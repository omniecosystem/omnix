//! Two-process A2A demonstration using the official Rust client and server.
//!
//! Intentionally bound to loopback. The default mode uses a copied demo token;
//! the opt-in paired-key mode pins peer keys for public Knowledge only. Neither
//! mode implements production pairing or transport. Answers are public demo
//! data, optionally served through Omnix Knowledge.

use std::{
    collections::HashMap,
    io::{BufRead, BufReader, Write},
    path::PathBuf,
    process::{Child, ChildStdin, ChildStdout, Command, Stdio},
    sync::{mpsc, Arc, Mutex},
    time::Duration,
};

use a2a::{
    AgentCapabilities, AgentCard, AgentInterface, AgentSkill, HttpAuthSecurityScheme, Message,
    Part, PartContent, Role, SecurityScheme, SendMessageRequest, SendMessageResponse,
    TRANSPORT_PROTOCOL_JSONRPC,
};
use a2a_client::{
    agent_card::AgentCardResolver, auth::AuthInterceptor, jsonrpc::JsonRpcTransportFactory,
    A2AClientFactory,
};
use a2a_server::{
    DefaultRequestHandler, InMemoryTaskStore, RequestAuthorizer, ServiceParams, StaticAgentCard,
};
use omnix::nexus::a2a::{
    demo_auth::DemoBearerAuthorizer,
    paired_auth::{PairedNodeAuthorizer, PeerRegistry, SigningIdentity},
    CallerVerifier, KnowledgeAgent, KnowledgeSource, VerifiedCaller,
};
use url::Url;

const BASE_URL: &str = "http://127.0.0.1:46137";

struct PublicKnowledge;

#[derive(Clone)]
enum ExampleAuth {
    Demo(DemoBearerAuthorizer),
    Paired(PairedNodeAuthorizer),
}

impl RequestAuthorizer for ExampleAuth {
    fn authorize(
        &self,
        params: &ServiceParams,
        task_id: Option<&str>,
    ) -> Result<(), a2a::A2AError> {
        match self {
            Self::Demo(auth) => auth.authorize(params, task_id),
            Self::Paired(auth) => auth.authorize(params, task_id),
        }
    }
}

impl CallerVerifier for ExampleAuth {
    fn verify(&self, params: &ServiceParams) -> Result<String, a2a::A2AError> {
        match self {
            Self::Demo(auth) => auth.verify(params),
            Self::Paired(auth) => auth.verify(params),
        }
    }
}

struct OmnixPublicKnowledge {
    bridge: Mutex<Option<DartBridge>>,
    example_dir: PathBuf,
    dart_executable: PathBuf,
}

struct DartBridge {
    child: Arc<Mutex<Child>>,
    input: ChildStdin,
    output: BufReader<ChildStdout>,
    next_id: u64,
}

struct KillTimer(mpsc::Sender<()>);

impl KillTimer {
    fn start(child: Arc<Mutex<Child>>, duration: Duration) -> Self {
        let (cancel, receiver) = mpsc::channel();
        std::thread::spawn(move || {
            if receiver.recv_timeout(duration).is_err() {
                if let Ok(mut child) = child.lock() {
                    let _ = child.kill();
                }
            }
        });
        Self(cancel)
    }
}

impl Drop for KillTimer {
    fn drop(&mut self) {
        let _ = self.0.send(());
    }
}

impl DartBridge {
    fn start(
        example_dir: &PathBuf,
        dart_executable: &PathBuf,
    ) -> Result<Self, Box<dyn std::error::Error>> {
        // Keep one Dart process and one Omnix Knowledge service alive for the
        // entire A2A server lifetime. No shell sees the remote question.
        let mut child = Command::new(dart_executable)
            .args(["run", "bin/public_knowledge_node.dart", "--serve"])
            .current_dir(example_dir)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()?;
        let input = child.stdin.take().ok_or("Dart stdin unavailable")?;
        let output = BufReader::new(child.stdout.take().ok_or("Dart stdout unavailable")?);
        let mut bridge = Self {
            child: Arc::new(Mutex::new(child)),
            input,
            output,
            next_id: 1,
        };
        // A fresh SDK can spend minutes on native build hooks, but startup
        // must still have a finite bound.
        let _timer = KillTimer::start(Arc::clone(&bridge.child), Duration::from_secs(300));
        let mut ready = false;
        for _ in 0..128 {
            let mut line = String::new();
            if bridge.output.read_line(&mut line)? == 0 {
                break;
            }
            if line.trim() == "OMNIXUS_DEMO_READY_V1" {
                ready = true;
                break;
            }
        }
        if !ready {
            return Err("Omnix demo process did not become ready".into());
        }
        Ok(bridge)
    }

    fn ask(&mut self, caller: &str, question: &str) -> Result<String, String> {
        let _timer = KillTimer::start(Arc::clone(&self.child), Duration::from_secs(15));
        let id = self.next_id;
        self.next_id = self.next_id.wrapping_add(1);
        let request = serde_json::json!({"id": id, "caller": caller, "question": question});
        writeln!(self.input, "{request}")
            .and_then(|()| self.input.flush())
            .map_err(|_| "Omnix demo process is unavailable".to_string())?;
        for _ in 0..16 {
            let mut line = String::new();
            if self
                .output
                .read_line(&mut line)
                .map_err(|_| "Omnix response unavailable")?
                == 0
            {
                return Err("Omnix demo process exited".into());
            }
            let Some(payload) = line.trim().strip_prefix("OMNIXUS_DEMO_RESULT_V1 ") else {
                continue;
            };
            let response: serde_json::Value =
                serde_json::from_str(payload).map_err(|_| "Omnix returned invalid JSON")?;
            if response["id"].as_u64() != Some(id) {
                return Err("Omnix returned an unrelated answer".into());
            }
            if response["status"] != "ok" {
                return Err("resource not available to this caller".into());
            }
            let answer = response["answer"]
                .as_str()
                .ok_or("Omnix returned invalid text")?;
            if answer.trim().is_empty() || answer.len() > 4096 {
                return Err("Omnix returned an invalid answer".into());
            }
            return Ok(answer.to_string());
        }
        Err("Omnix answer marker missing".into())
    }
}

impl Drop for DartBridge {
    fn drop(&mut self) {
        if let Ok(mut child) = self.child.lock() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

impl KnowledgeSource for OmnixPublicKnowledge {
    fn answer(&self, caller: &VerifiedCaller, question: &str) -> Result<String, String> {
        if question.len() > 512 {
            return Err("question is too long for this demo".into());
        }
        println!("Omnix Knowledge query from {}: {question}", caller.id());
        let mut bridge = self
            .bridge
            .lock()
            .map_err(|_| "Omnix bridge unavailable".to_string())?;
        if bridge.is_none() {
            *bridge = Some(
                DartBridge::start(&self.example_dir, &self.dart_executable)
                    .map_err(|_| "Omnix bridge could not restart".to_string())?,
            );
        }
        let result = bridge
            .as_mut()
            .ok_or_else(|| "Omnix bridge unavailable".to_string())?
            .ask(caller.id(), question);
        if result
            .as_ref()
            .is_err_and(|error| error != "resource not available to this caller")
        {
            *bridge = None;
        }
        result
    }
}

fn dart_executable() -> Result<PathBuf, &'static str> {
    if cfg!(windows) {
        let path = std::env::var_os("PATH").ok_or("PATH is missing")?;
        for directory in std::env::split_paths(&path) {
            let direct = directory.join("dart.exe");
            if direct.is_file() {
                return Ok(direct);
            }
            if directory.join("dart.bat").is_file() {
                let sdk = directory.join("cache/dart-sdk/bin/dart.exe");
                if sdk.is_file() {
                    return Ok(sdk);
                }
            }
        }
        Err("Dart SDK executable not found on PATH")
    } else {
        Ok(PathBuf::from("dart"))
    }
}

impl KnowledgeSource for PublicKnowledge {
    fn answer(&self, caller: &VerifiedCaller, question: &str) -> Result<String, String> {
        println!(
            "Received A2A knowledge request from {}: {question}",
            caller.id()
        );
        // The A2A verifier has already established this caller. This source
        // only serves the same small public facts in either auth mode.
        let answer = match question.trim().to_ascii_lowercase().as_str() {
            "what is omnixus?" => {
                "Omnixus explores collaboration between independently controlled AI nodes.".into()
            }
            "what is a2a?" => {
                "Agent2Agent (A2A) defines how agents exchange messages, tasks, and results.".into()
            }
            _ => return Err("resource not available to this caller".into()),
        };
        Ok(answer)
    }
}

fn validated_base_url(input: &str) -> Result<Url, Box<dyn std::error::Error>> {
    let url = Url::parse(input)?;
    if url.as_str().trim_end_matches('/') != BASE_URL && url.scheme() != "https" {
        return Err("remote A2A URL must use HTTPS".into());
    }
    if url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.path() != "/"
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return Err("A2A URL must be an origin without path, query, or credentials".into());
    }
    Ok(url)
}

fn agent_card(public_url: &Url, paired: bool) -> AgentCard {
    let scheme_name = if paired { "pairedProof" } else { "demoBearer" };
    let scheme_description = if paired {
        "Short-lived signed proof from an explicitly allowed peer key."
    } else {
        "Local demo credential only; not durable node identity."
    };
    AgentCard {
        name: "Omnixus public knowledge demo".into(),
        description: "Answers public demo questions through A2A.".into(),
        version: a2a::VERSION.into(),
        provider: None,
        capabilities: AgentCapabilities {
            streaming: Some(false),
            push_notifications: Some(false),
            extensions: None,
            extended_agent_card: None,
        },
        skills: vec![AgentSkill {
            id: "public_knowledge".into(),
            name: "Public knowledge".into(),
            description: "Answers public demo questions about Omnixus and A2A.".into(),
            tags: vec!["knowledge".into()],
            examples: Some(vec!["What is Omnixus?".into()]),
            input_modes: None,
            output_modes: None,
            security_requirements: None,
        }],
        default_input_modes: vec!["text/plain".into()],
        default_output_modes: vec!["text/plain".into()],
        supported_interfaces: vec![AgentInterface::new(
            format!("{}/jsonrpc", public_url.as_str().trim_end_matches('/')),
            TRANSPORT_PROTOCOL_JSONRPC,
        )],
        security_schemes: Some(HashMap::from([(
            scheme_name.into(),
            SecurityScheme::HttpAuth(HttpAuthSecurityScheme {
                scheme: "bearer".into(),
                description: Some(scheme_description.into()),
                bearer_format: None,
            }),
        )])),
        security_requirements: Some(vec![HashMap::from([(scheme_name.into(), vec![])])]),
        documentation_url: None,
        icon_url: None,
        signatures: None,
    }
}

fn validate_card_origin(card: &AgentCard, base_url: &Url) -> Result<(), &'static str> {
    let has_jsonrpc = card.supported_interfaces.iter().any(|interface| {
        interface.protocol_binding == TRANSPORT_PROTOCOL_JSONRPC
            && Url::parse(&interface.url).is_ok_and(|url| url.origin() == base_url.origin())
    });
    let all_same_origin = card.supported_interfaces.iter().all(|interface| {
        Url::parse(&interface.url).is_ok_and(|url| url.origin() == base_url.origin())
    });
    if has_jsonrpc && all_same_origin {
        Ok(())
    } else {
        Err("Agent Card points to an unexpected origin; refusing to send token")
    }
}

async fn serve() -> Result<(), Box<dyn std::error::Error>> {
    let public_url = validated_base_url(
        &std::env::var("OMNIXUS_DEMO_PUBLIC_URL").unwrap_or_else(|_| BASE_URL.into()),
    )?;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:46137").await?;
    let node_dir = std::env::var_os("OMNIXUS_NODE_DIR");
    let paired = node_dir.is_some();
    let (auth, demo_token) = if let Some(node_dir) = node_dir {
        let node_dir = PathBuf::from(node_dir);
        let identity = SigningIdentity::load_from(&node_dir)?;
        let peers = PeerRegistry::load_from(&node_dir)?;
        println!("Paired node public key: {}", identity.public_key_hex());
        (
            ExampleAuth::Paired(PairedNodeAuthorizer::new(
                public_url.as_str().trim_end_matches('/').to_owned(),
                peers,
            )),
            None,
        )
    } else {
        let token = format!("{}{}", uuid::Uuid::new_v4(), uuid::Uuid::new_v4());
        (
            ExampleAuth::Demo(DemoBearerAuthorizer::new(
                token.clone(),
                "paired-demo-client".into(),
                true,
            )),
            Some(token),
        )
    };
    let source: Box<dyn KnowledgeSource> =
        if let Ok(example_dir) = std::env::var("OMNIXUS_DEMO_OMNIX_EXAMPLE") {
            let example_dir = PathBuf::from(example_dir);
            if !example_dir.join("bin/public_knowledge_node.dart").is_file()
                || !example_dir.join("public_knowledge.json").is_file()
            {
                return Err(
                    "OMNIXUS_DEMO_OMNIX_EXAMPLE must point to the Omnix example directory".into(),
                );
            }
            println!(
                "Using public Omnix Knowledge from {}",
                example_dir.display()
            );
            let bridge = DartBridge::start(&example_dir, &dart_executable()?)?;
            Box::new(OmnixPublicKnowledge {
                bridge: Mutex::new(Some(bridge)),
                example_dir,
                dart_executable: dart_executable()?,
            })
        } else {
            println!("Using static public demonstration answers");
            Box::new(PublicKnowledge)
        };
    let handler = Arc::new(
        DefaultRequestHandler::new(
            KnowledgeAgent::new(source, auth.clone()),
            InMemoryTaskStore::new(),
        )
        .with_authorizer(auth),
    );
    let app = axum::Router::new()
        .nest("/jsonrpc", a2a_server::jsonrpc::jsonrpc_router(handler))
        .merge(a2a_server::agent_card::agent_card_router(Arc::new(
            StaticAgentCard::new(agent_card(&public_url, paired)),
        )));
    println!("A2A agent listening at {BASE_URL}");
    println!("Advertised Agent Card: {public_url}.well-known/agent-card.json");
    if let Some(token) = demo_token {
        println!("Local demo token (copy to second terminal): {token}");
    } else {
        println!("Paired-key mode: only explicitly allowed public keys may query.");
    }
    println!("Public demo data only. Press Ctrl+C to stop.");
    axum::serve(listener, app).await?;
    Ok(())
}

async fn ask(question: String) -> Result<(), Box<dyn std::error::Error>> {
    let base_url =
        validated_base_url(&std::env::var("OMNIXUS_DEMO_URL").unwrap_or_else(|_| BASE_URL.into()))?;
    // No automatic redirects: neither card discovery nor the authenticated
    // request may silently move to a different endpoint.
    let http = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(std::time::Duration::from_secs(20))
        .build()?;
    let card = AgentCardResolver::new(Some(http.clone()))
        .resolve(base_url.as_str())
        .await?;
    validate_card_origin(&card, &base_url)?;
    println!("Discovered agent: {}", card.name);
    let token = if let Some(node_dir) = std::env::var_os("OMNIXUS_NODE_DIR") {
        let identity = SigningIdentity::load_from(&PathBuf::from(node_dir))?;
        identity.bearer_for(base_url.as_str().trim_end_matches('/'))?
    } else {
        let token = std::env::var("OMNIXUS_DEMO_TOKEN")
            .map_err(|_| "set OMNIXUS_DEMO_TOKEN to the token printed by the server")?;
        if token.trim().is_empty() {
            return Err("OMNIXUS_DEMO_TOKEN must not be empty".into());
        }
        token
    };
    let client = A2AClientFactory::builder()
        .no_defaults()
        .register(Arc::new(JsonRpcTransportFactory::new(Some(http))))
        .with_interceptor(Arc::new(AuthInterceptor::bearer(token)))
        .build()
        .create_from_card(&card)
        .await?;
    let response = match client
        .send_message(&SendMessageRequest {
            message: Message::new(Role::User, vec![Part::text(question)]),
            configuration: None,
            metadata: None,
            tenant: None,
        })
        .await
    {
        Ok(response) => response,
        Err(error) if error.message == "resource not available to this caller" => {
            println!("Access refused: {}", error.message);
            return Ok(());
        }
        Err(error) => return Err(error.into()),
    };
    match response {
        SendMessageResponse::Task(task) => {
            println!("A2A task: {} ({:?})", task.id, task.status.state);
            for artifact in task.artifacts.unwrap_or_default() {
                for part in artifact.parts {
                    if let PartContent::Text(text) = part.content {
                        println!("Answer artifact: {text}");
                    }
                }
            }
        }
        SendMessageResponse::Message(message) => {
            for part in message.parts {
                if let PartContent::Text(text) = part.content {
                    println!("A2A message: {text}");
                }
            }
        }
    }
    Ok(())
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1);
    match args.next().as_deref() {
        Some("identity") => {
            let dir = std::env::var_os("OMNIXUS_NODE_DIR")
                .ok_or("set OMNIXUS_NODE_DIR to a private directory outside the repository")?;
            let dir = PathBuf::from(dir);
            match (args.next().as_deref(), args.next(), args.next()) {
                (Some("init"), None, None) => {
                    let identity = SigningIdentity::create_in(&dir)?;
                    println!("Node public key: {}", identity.public_key_hex());
                    Ok(())
                }
                (Some("show"), None, None) => {
                    let identity = SigningIdentity::load_from(&dir)?;
                    println!("Node public key: {}", identity.public_key_hex());
                    Ok(())
                }
                (Some("allow"), Some(public_key), None) => {
                    PeerRegistry::allow_public(&dir, &public_key)?;
                    println!("Granted public Knowledge to {public_key}");
                    Ok(())
                }
                (Some("deny"), Some(public_key), None) => {
                    PeerRegistry::deny_public(&dir, &public_key)?;
                    println!("Revoked public Knowledge from {public_key}; restart serve to apply");
                    Ok(())
                }
                _ => Err("usage: two_agents identity init | show | allow <peer-public-key> | deny <peer-public-key>".into()),
            }
        }
        Some("serve") if args.next().is_none() => serve().await,
        Some("ask") => {
            let question = args.collect::<Vec<_>>().join(" ");
            if question.trim().is_empty() {
                return Err("provide a question after ask".into());
            }
            ask(question).await
        }
        _ => Err("usage: two_agents identity <command> | serve | ask <question>".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn remote_demo_requires_https_and_simple_origin() {
        assert!(validated_base_url(BASE_URL).is_ok());
        assert!(validated_base_url("https://node.example.ts.net").is_ok());
        assert!(validated_base_url("http://node.example.ts.net").is_err());
        assert!(validated_base_url("https://node.example.ts.net/path").is_err());
        assert!(validated_base_url("https://user@node.example.ts.net").is_err());
    }

    #[test]
    fn agent_card_cannot_redirect_credential_to_another_origin() {
        let base = validated_base_url("https://node.example.ts.net").expect("valid base URL");
        let mut card = agent_card(&base, false);
        assert!(validate_card_origin(&card, &base).is_ok());
        card.supported_interfaces[0].url = "https://other.example.ts.net/jsonrpc".into();
        assert!(validate_card_origin(&card, &base).is_err());
    }
}
