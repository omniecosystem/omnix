//! An actual HTTP boundary, confined to loopback and public synthetic data.
//! This is not a node-identity or private-knowledge security test.

use std::{
    collections::HashMap,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    },
};

use a2a::{
    AgentCapabilities, AgentCard, AgentInterface, AgentSkill, HttpAuthSecurityScheme, Message,
    Part, PartContent, Role, SecurityScheme, SendMessageRequest, SendMessageResponse, TaskState,
    TRANSPORT_PROTOCOL_JSONRPC,
};
use a2a_client::{agent_card::AgentCardResolver, auth::AuthInterceptor, A2AClientFactory};
use a2a_server::{DefaultRequestHandler, InMemoryTaskStore, StaticAgentCard};
use futures::future::BoxFuture;
use omnix::nexus::a2a::{
    demo_auth::DemoBearerAuthorizer,
    node::{
        paired_public_router, paired_public_router_async, paired_public_router_async_with_access,
        paired_text_router_async_with_access, query_public_knowledge, send_text, TextAgentInfo,
    },
    paired_auth::{PairedNodeAuthorizer, PeerRegistry, SigningIdentity},
    AsyncKnowledgeSource, AsyncTextSource, KnowledgeAgent, KnowledgeSource, VerifiedCaller,
};

struct PublicKnowledge(Arc<AtomicUsize>);

impl KnowledgeSource for PublicKnowledge {
    fn answer(&self, caller: &VerifiedCaller, question: &str) -> Result<String, String> {
        self.0.fetch_add(1, Ordering::SeqCst);
        if caller.id() != "test-client" || question == "private note" {
            return Err("knowledge access denied".into());
        }
        Ok(format!("Public answer to: {question}"))
    }
}

struct AsyncPairedKnowledge(Arc<AtomicUsize>);

impl AsyncKnowledgeSource for AsyncPairedKnowledge {
    fn answer(
        &self,
        caller_id: String,
        question: String,
    ) -> BoxFuture<'static, Result<String, String>> {
        self.0.fetch_add(1, Ordering::SeqCst);
        Box::pin(async move {
            if !caller_id.starts_with("ed25519:") || question == "private note" {
                return Err("knowledge unavailable".into());
            }
            Ok(format!("Async public: {question}"))
        })
    }
}

struct HostText;

impl AsyncTextSource for HostText {
    fn respond(
        &self,
        caller_id: String,
        text: String,
    ) -> BoxFuture<'static, Result<String, String>> {
        Box::pin(async move { Ok(format!("{caller_id} received: {text}")) })
    }
}

#[tokio::test]
async fn independent_host_can_advertise_non_knowledge_text_skill() {
    let server_dir = tempfile::tempdir().expect("server directory");
    let client_dir = tempfile::tempdir().expect("client directory");
    SigningIdentity::create_in(server_dir.path()).expect("server identity");
    let client = SigningIdentity::create_in(client_dir.path()).expect("client identity");
    let allowed_key = client.public_key_hex();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("listener");
    let origin = format!("http://{}", listener.local_addr().expect("address"));
    let router = paired_text_router_async_with_access(
        server_dir.path(),
        &origin,
        TextAgentInfo {
            name: "Independent text agent".into(),
            description: "A non-Omnix A2A host".into(),
            skill_id: "echo".into(),
            skill_name: "Echo".into(),
            skill_description: "Returns the input".into(),
        },
        HostText,
        move |key| key == allowed_key,
    )
    .expect("generic router");
    let server = tokio::spawn(async move { axum::serve(listener, router).await.expect("server") });
    let card = AgentCardResolver::new(None)
        .resolve(&origin)
        .await
        .expect("agent card");
    assert_eq!(card.name, "Independent text agent");
    assert_eq!(card.skills[0].id, "echo");
    let reply = send_text(client_dir.path(), &origin, "hello")
        .await
        .expect("text reply");
    assert_eq!(
        reply.texts,
        vec![format!(
            "ed25519:{} received: hello",
            client.public_key_hex()
        )]
    );
    server.abort();
}

#[tokio::test]
async fn asynchronous_node_invokes_host_only_after_peer_verification() {
    let server_dir = tempfile::tempdir().expect("server directory");
    let client_dir = tempfile::tempdir().expect("client directory");
    let unknown_dir = tempfile::tempdir().expect("unknown directory");
    SigningIdentity::create_in(server_dir.path()).expect("server identity");
    let client = SigningIdentity::create_in(client_dir.path()).expect("client identity");
    SigningIdentity::create_in(unknown_dir.path()).expect("unknown identity");
    PeerRegistry::allow_public(server_dir.path(), &client.public_key_hex()).expect("grant");
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("listener");
    let origin = format!("http://{}", listener.local_addr().expect("address"));
    let calls = Arc::new(AtomicUsize::new(0));
    let router = paired_public_router_async(
        server_dir.path(),
        &origin,
        AsyncPairedKnowledge(Arc::clone(&calls)),
    )
    .expect("router");
    let server = tokio::spawn(async move { axum::serve(listener, router).await.expect("server") });
    assert!(
        query_public_knowledge(unknown_dir.path(), &origin, "What is Omnixus?")
            .await
            .is_err()
    );
    assert_eq!(calls.load(Ordering::SeqCst), 0);
    let reply = query_public_knowledge(client_dir.path(), &origin, "What is Omnixus?")
        .await
        .expect("reply");
    assert_eq!(reply.texts, vec!["Async public: What is Omnixus?"]);
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    assert!(
        query_public_knowledge(client_dir.path(), &origin, "private note")
            .await
            .is_err()
    );
    assert_eq!(calls.load(Ordering::SeqCst), 2);
    server.abort();
}

#[tokio::test]
async fn host_policy_can_allow_a_verified_peer_without_omnixus_grants() {
    let server_dir = tempfile::tempdir().expect("server directory");
    let client_dir = tempfile::tempdir().expect("client directory");
    SigningIdentity::create_in(server_dir.path()).expect("server identity");
    let client = SigningIdentity::create_in(client_dir.path()).expect("client identity");
    let allowed_key = client.public_key_hex();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("listener");
    let origin = format!("http://{}", listener.local_addr().expect("address"));
    let calls = Arc::new(AtomicUsize::new(0));
    let router = paired_public_router_async_with_access(
        server_dir.path(),
        &origin,
        AsyncPairedKnowledge(Arc::clone(&calls)),
        move |key| key == allowed_key,
    )
    .expect("router without demo grants");
    let server = tokio::spawn(async move { axum::serve(listener, router).await.expect("server") });
    let reply = query_public_knowledge(client_dir.path(), &origin, "What is Omnixus?")
        .await
        .expect("host-authorized reply");
    assert_eq!(reply.texts, vec!["Async public: What is Omnixus?"]);
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    server.abort();
}

fn agent_card(endpoint: String) -> AgentCard {
    AgentCard {
        name: "Omnixus public knowledge demo".into(),
        description: "Answers one synthetic public knowledge question.".into(),
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
            description: "Returns a synthetic answer for protocol testing.".into(),
            tags: vec!["knowledge".into()],
            examples: None,
            input_modes: None,
            output_modes: None,
            security_requirements: None,
        }],
        default_input_modes: vec!["text/plain".into()],
        default_output_modes: vec!["text/plain".into()],
        supported_interfaces: vec![AgentInterface::new(endpoint, TRANSPORT_PROTOCOL_JSONRPC)],
        security_schemes: Some(HashMap::from([(
            "demoBearer".into(),
            SecurityScheme::HttpAuth(HttpAuthSecurityScheme {
                scheme: "bearer".into(),
                description: None,
                bearer_format: None,
            }),
        )])),
        security_requirements: Some(vec![HashMap::from([("demoBearer".into(), vec![])])]),
        documentation_url: None,
        icon_url: None,
        signatures: None,
    }
}

#[tokio::test]
async fn official_a2a_client_discovers_card_and_receives_public_artifact() {
    let calls = Arc::new(AtomicUsize::new(0));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("loopback listener");
    let address = listener.local_addr().expect("listener address");
    let card = agent_card(format!("http://{address}/jsonrpc"));
    let auth = DemoBearerAuthorizer::new("test-secret".into(), "test-client".into(), true);
    let handler = Arc::new(
        DefaultRequestHandler::new(
            KnowledgeAgent::new(PublicKnowledge(Arc::clone(&calls)), auth.clone()),
            InMemoryTaskStore::new(),
        )
        .with_authorizer(auth),
    );
    let app = axum::Router::new()
        .nest("/jsonrpc", a2a_server::jsonrpc::jsonrpc_router(handler))
        .merge(a2a_server::agent_card::agent_card_router(Arc::new(
            StaticAgentCard::new(card.clone()),
        )));
    let server = tokio::spawn(async move {
        axum::serve(listener, app).await.expect("A2A server");
    });

    let discovered = AgentCardResolver::new(None)
        .resolve(&format!("http://{address}"))
        .await
        .expect("discover Agent Card over HTTP");
    assert_eq!(discovered.name, card.name);
    assert!(discovered
        .security_schemes
        .as_ref()
        .expect("Agent Card must declare authentication")
        .contains_key("demoBearer"));
    let request = || SendMessageRequest {
        message: Message::new(Role::User, vec![Part::text("What is Omnixus?")]),
        configuration: None,
        metadata: None,
        tenant: None,
    };
    let unauthenticated = A2AClientFactory::builder()
        .build()
        .create_from_card(&discovered)
        .await
        .expect("official A2A client");
    assert!(unauthenticated.send_message(&request()).await.is_err());
    assert_eq!(calls.load(Ordering::SeqCst), 0);

    let wrong_credential = A2AClientFactory::builder()
        .with_interceptor(Arc::new(AuthInterceptor::bearer("wrong-secret")))
        .build()
        .create_from_card(&discovered)
        .await
        .expect("wrong-credential client");
    assert!(wrong_credential.send_message(&request()).await.is_err());
    assert_eq!(calls.load(Ordering::SeqCst), 0);

    let client = A2AClientFactory::builder()
        .with_interceptor(Arc::new(AuthInterceptor::bearer("test-secret")))
        .build()
        .create_from_card(&discovered)
        .await
        .expect("paired A2A client");
    let response = client.send_message(&request()).await.expect("A2A response");
    let SendMessageResponse::Task(task) = response else {
        panic!("expected A2A task");
    };
    assert_eq!(task.status.state, TaskState::Completed);
    assert_eq!(
        task.artifacts.expect("artifact")[0].parts[0].content,
        PartContent::Text("Public answer to: What is Omnixus?".into())
    );
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    let private_request = SendMessageRequest {
        message: Message::new(Role::User, vec![Part::text("private note")]),
        configuration: None,
        metadata: None,
        tenant: None,
    };
    assert!(client.send_message(&private_request).await.is_err());
    assert_eq!(calls.load(Ordering::SeqCst), 2);
    server.abort();
}

struct PairedKnowledge(Arc<AtomicUsize>);

impl KnowledgeSource for PairedKnowledge {
    fn answer(&self, caller: &VerifiedCaller, question: &str) -> Result<String, String> {
        assert!(caller.id().starts_with("ed25519:"));
        self.0.fetch_add(1, Ordering::SeqCst);
        Ok(format!("Public: {question}"))
    }
}

#[tokio::test]
async fn reusable_node_api_queries_host_knowledge_over_a2a() {
    let server_dir = tempfile::tempdir().expect("server directory");
    let client_dir = tempfile::tempdir().expect("client directory");
    SigningIdentity::create_in(server_dir.path()).expect("server identity");
    let client = SigningIdentity::create_in(client_dir.path()).expect("client identity");
    PeerRegistry::allow_public(server_dir.path(), &client.public_key_hex()).expect("grant");
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("listener");
    let origin = format!("http://{}", listener.local_addr().expect("address"));
    let calls = Arc::new(AtomicUsize::new(0));
    let app = paired_public_router(
        server_dir.path(),
        &origin,
        PairedKnowledge(Arc::clone(&calls)),
    )
    .expect("paired router");
    let server = tokio::spawn(async move { axum::serve(listener, app).await.expect("server") });
    let reply = query_public_knowledge(client_dir.path(), &origin, "What is Omnixus?")
        .await
        .expect("A2A reply");
    assert!(reply.task_id.is_some());
    assert_eq!(reply.texts, vec!["Public: What is Omnixus?"]);
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    let missing_identity = tempfile::tempdir().expect("unknown node");
    assert!(
        query_public_knowledge(missing_identity.path(), &origin, "What is Omnixus?")
            .await
            .is_err()
    );
    assert!(query_public_knowledge(client_dir.path(), &origin, " ")
        .await
        .is_err());
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    server.abort();
}

#[tokio::test]
async fn pinned_peer_sends_one_signed_a2a_request_without_a_shared_secret() {
    let server_dir = tempfile::tempdir().expect("server directory");
    let client_dir = tempfile::tempdir().expect("client directory");
    let _server_identity = SigningIdentity::create_in(server_dir.path()).expect("server identity");
    let client_identity = SigningIdentity::create_in(client_dir.path()).expect("client identity");
    PeerRegistry::allow_public(server_dir.path(), &client_identity.public_key_hex())
        .expect("grant");

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("listener");
    let address = listener.local_addr().expect("address");
    let origin = format!("http://{address}");
    let calls = Arc::new(AtomicUsize::new(0));
    let auth = PairedNodeAuthorizer::new(
        origin.clone(),
        PeerRegistry::load_from(server_dir.path()).expect("registry"),
    );
    let handler = Arc::new(
        DefaultRequestHandler::new(
            KnowledgeAgent::new(PairedKnowledge(Arc::clone(&calls)), auth.clone()),
            InMemoryTaskStore::new(),
        )
        .with_authorizer(auth),
    );
    let app = axum::Router::new()
        .nest("/jsonrpc", a2a_server::jsonrpc::jsonrpc_router(handler))
        .merge(a2a_server::agent_card::agent_card_router(Arc::new(
            StaticAgentCard::new(agent_card(format!("{origin}/jsonrpc"))),
        )));
    let server = tokio::spawn(async move { axum::serve(listener, app).await.expect("server") });
    let discovered = AgentCardResolver::new(None)
        .resolve(&origin)
        .await
        .expect("card");
    let token = client_identity.bearer_for(&origin).expect("proof");
    let client = A2AClientFactory::builder()
        .with_interceptor(Arc::new(AuthInterceptor::bearer(token)))
        .build()
        .create_from_card(&discovered)
        .await
        .expect("client");
    let request = || SendMessageRequest {
        message: Message::new(Role::User, vec![Part::text("What is Omnixus?")]),
        configuration: None,
        metadata: None,
        tenant: None,
    };
    let response = client
        .send_message(&request())
        .await
        .expect("first request");
    assert!(matches!(response, SendMessageResponse::Task(_)));
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    assert!(
        client.send_message(&request()).await.is_err(),
        "replayed proof"
    );
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    server.abort();
}
