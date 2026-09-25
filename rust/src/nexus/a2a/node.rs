//! Reusable, public-knowledge-only A2A node operations.
//!
//! Hosts provide Knowledge and a listener. This module does not own app
//! lifecycle, discovery, private documents, or remote action authority.

use std::{collections::HashMap, path::Path, sync::Arc, time::Duration};

use a2a::{
    AgentCapabilities, AgentCard, AgentInterface, AgentSkill, HttpAuthSecurityScheme, Message,
    Part, PartContent, Role, SecurityScheme, SendMessageRequest, SendMessageResponse, TaskState,
    TRANSPORT_PROTOCOL_JSONRPC,
};
use a2a_client::{
    agent_card::AgentCardResolver, auth::AuthInterceptor, jsonrpc::JsonRpcTransportFactory,
    A2AClientFactory,
};
use a2a_server::{DefaultRequestHandler, InMemoryTaskStore, StaticAgentCard};
use url::Url;

use super::{
    paired_auth::{PairedNodeAuthorizer, PeerRegistry, SigningIdentity},
    AsyncKnowledgeSource, AsyncTextAgent, AsyncTextSource, KnowledgeAgent, KnowledgeSource,
};

/// The text artifacts returned by a completed A2A task.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TextReply {
    pub task_id: Option<String>,
    pub texts: Vec<String>,
}

/// Compatibility name for the public Knowledge demo.
pub type KnowledgeReply = TextReply;

fn origin(input: &str) -> Result<Url, String> {
    let url = Url::parse(input).map_err(|_| "invalid A2A origin")?;
    let local = url.scheme() == "http" && url.host_str() == Some("127.0.0.1");
    if (url.scheme() != "https" && !local)
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.path() != "/"
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return Err("A2A endpoint must be an HTTPS origin (or IPv4 loopback for tests)".into());
    }
    Ok(url)
}

/// Host-provided presentation of one text-capable A2A endpoint.
pub struct TextAgentInfo {
    pub name: String,
    pub description: String,
    pub skill_id: String,
    pub skill_name: String,
    pub skill_description: String,
}

fn public_knowledge_info() -> TextAgentInfo {
    TextAgentInfo {
        name: "Omnixus public knowledge node".into(),
        description: "Answers authorized public Knowledge requests through A2A.".into(),
        skill_id: "public_knowledge".into(),
        skill_name: "Public knowledge".into(),
        skill_description: "Requests public Knowledge from this node.".into(),
    }
}

fn paired_card(endpoint: &Url, info: TextAgentInfo) -> AgentCard {
    AgentCard {
        name: info.name,
        description: info.description,
        version: a2a::VERSION.into(),
        provider: None,
        capabilities: AgentCapabilities {
            streaming: Some(false),
            push_notifications: Some(false),
            extensions: None,
            extended_agent_card: None,
        },
        skills: vec![AgentSkill {
            id: info.skill_id,
            name: info.skill_name,
            description: info.skill_description,
            tags: vec!["text".into()],
            examples: None,
            input_modes: None,
            output_modes: None,
            security_requirements: None,
        }],
        default_input_modes: vec!["text/plain".into()],
        default_output_modes: vec!["text/plain".into()],
        supported_interfaces: vec![AgentInterface::new(
            format!("{}/jsonrpc", endpoint.as_str().trim_end_matches('/')),
            TRANSPORT_PROTOCOL_JSONRPC,
        )],
        security_schemes: Some(HashMap::from([(
            "pairedProof".into(),
            SecurityScheme::HttpAuth(HttpAuthSecurityScheme {
                scheme: "bearer".into(),
                description: Some("Short-lived proof from an allowed peer key".into()),
                bearer_format: None,
            }),
        )])),
        security_requirements: Some(vec![HashMap::from([("pairedProof".into(), vec![])])]),
        documentation_url: None,
        icon_url: None,
        signatures: None,
    }
}

/// Constructs an A2A router for a host-provided public Knowledge source.
///
/// The host owns the listener and must advertise the origin clients actually
/// reach. HTTPS is required off-device. Peer grants are loaded at creation;
/// restart/rebuild the router after changing them. The in-memory task store
/// does not expose task history to remote peers.
pub fn paired_public_router<S: KnowledgeSource>(
    node_dir: &Path,
    advertised_origin: &str,
    source: S,
) -> Result<axum::Router, String> {
    let endpoint = origin(advertised_origin)?;
    SigningIdentity::load_from(node_dir).map_err(|_| "node identity unavailable")?;
    let grants = PeerRegistry::load_from(node_dir).map_err(|_| "peer grants unavailable")?;
    let auth = PairedNodeAuthorizer::new(endpoint.as_str().trim_end_matches('/').into(), grants);
    let handler = Arc::new(
        DefaultRequestHandler::new(
            KnowledgeAgent::new(source, auth.clone()),
            InMemoryTaskStore::new(),
        )
        .with_authorizer(auth),
    );
    Ok(axum::Router::new()
        .nest("/jsonrpc", a2a_server::jsonrpc::jsonrpc_router(handler))
        .merge(a2a_server::agent_card::agent_card_router(Arc::new(
            StaticAgentCard::new(paired_card(&endpoint, public_knowledge_info())),
        ))))
}

/// Constructs the same paired A2A router for an asynchronous host lookup.
///
/// A Flutter host can supply a bridge to its Knowledge service. The transport
/// still verifies the peer before the callback is invoked. Grants are loaded
/// when the router is created and require a listener restart to change.
pub fn paired_public_router_async<S: AsyncKnowledgeSource>(
    node_dir: &Path,
    advertised_origin: &str,
    source: S,
) -> Result<axum::Router, String> {
    let grants = PeerRegistry::load_from(node_dir).map_err(|_| "peer grants unavailable")?;
    let allowed = grants
        .peers
        .into_iter()
        .filter(|peer| peer.public_knowledge)
        .map(|peer| peer.public_key)
        .collect::<std::collections::HashSet<_>>();
    paired_public_router_async_with_access(node_dir, advertised_origin, source, move |key| {
        allowed.contains(key)
    })
}

/// Builds the demo A2A Knowledge endpoint with access decided by the host.
///
/// Omnixus authenticates the signed peer key; the host-supplied predicate
/// decides whether that key may reach this particular endpoint. This does not
/// give the caller access to any other host resource or action.
pub fn paired_public_router_async_with_access<S: AsyncKnowledgeSource>(
    node_dir: &Path,
    advertised_origin: &str,
    source: S,
    permits: impl Fn(&str) -> bool + Send + Sync + 'static,
) -> Result<axum::Router, String> {
    paired_text_router_async_with_access(
        node_dir,
        advertised_origin,
        public_knowledge_info(),
        source,
        permits,
    )
}

/// Hosts one paired A2A text task with host-owned policy and presentation.
///
/// The authenticated public key is passed to the host; the host must decide
/// which data and effects, if any, are permitted. No action semantics are
/// inferred from the incoming text by this transport adapter.
pub fn paired_text_router_async_with_access<S: AsyncTextSource>(
    node_dir: &Path,
    advertised_origin: &str,
    info: TextAgentInfo,
    source: S,
    permits: impl Fn(&str) -> bool + Send + Sync + 'static,
) -> Result<axum::Router, String> {
    let endpoint = origin(advertised_origin)?;
    SigningIdentity::load_from(node_dir).map_err(|_| "node identity unavailable")?;
    let auth =
        PairedNodeAuthorizer::with_access(endpoint.as_str().trim_end_matches('/').into(), permits);
    let handler = Arc::new(
        DefaultRequestHandler::new(
            AsyncTextAgent::new(source, auth.clone()),
            InMemoryTaskStore::new(),
        )
        .with_authorizer(auth),
    );
    Ok(axum::Router::new()
        .nest("/jsonrpc", a2a_server::jsonrpc::jsonrpc_router(handler))
        .merge(a2a_server::agent_card::agent_card_router(Arc::new(
            StaticAgentCard::new(paired_card(&endpoint, info)),
        ))))
}

/// Sends one signed text request through the official A2A client.
///
/// The private key remains local. The Agent Card must advertise JSON-RPC only
/// on the origin we contacted; redirects are disabled to avoid leaking a
/// signed proof to another endpoint. Each call signs a fresh request.
pub async fn send_text(
    node_dir: &Path,
    remote_origin: &str,
    text: &str,
) -> Result<TextReply, String> {
    if text.trim().is_empty() || text.len() > 512 {
        return Err("text must contain 1 to 512 characters".into());
    }
    let endpoint = origin(remote_origin)?;
    let http = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(20))
        .build()
        .map_err(|_| "A2A HTTP client unavailable")?;
    let card = AgentCardResolver::new(Some(http.clone()))
        .resolve(endpoint.as_str())
        .await
        .map_err(|_| "could not discover the remote Agent Card")?;
    let same_origin = card.supported_interfaces.iter().all(|interface| {
        Url::parse(&interface.url).is_ok_and(|url| url.origin() == endpoint.origin())
    });
    let has_jsonrpc = card.supported_interfaces.iter().any(|interface| {
        interface.protocol_binding == TRANSPORT_PROTOCOL_JSONRPC
            && Url::parse(&interface.url).is_ok_and(|url| url.origin() == endpoint.origin())
    });
    if !same_origin || !has_jsonrpc {
        return Err("Agent Card points to an unexpected origin".into());
    }
    let identity = SigningIdentity::load_from(node_dir).map_err(|_| "node identity unavailable")?;
    let proof = identity
        .bearer_for(endpoint.as_str().trim_end_matches('/'))
        .map_err(|_| "could not sign A2A request")?;
    let client = A2AClientFactory::builder()
        .no_defaults()
        .register(Arc::new(JsonRpcTransportFactory::new(Some(http))))
        .with_interceptor(Arc::new(AuthInterceptor::bearer(proof)))
        .build()
        .create_from_card(&card)
        .await
        .map_err(|_| "could not connect to the A2A node")?;
    let response = client
        .send_message(&SendMessageRequest {
            message: Message::new(Role::User, vec![Part::text(text.to_owned())]),
            configuration: None,
            metadata: None,
            tenant: None,
        })
        .await
        .map_err(|error| format!("A2A request failed: {}", error.message))?;
    let (task_id, parts) = match response {
        SendMessageResponse::Task(task) if task.status.state == TaskState::Completed => (
            Some(task.id),
            task.artifacts
                .unwrap_or_default()
                .into_iter()
                .flat_map(|artifact| artifact.parts)
                .collect::<Vec<_>>(),
        ),
        SendMessageResponse::Message(message) => (None, message.parts),
        SendMessageResponse::Task(_) => return Err("A2A task did not complete".into()),
    };
    let texts = parts
        .into_iter()
        .filter_map(|part| match part.content {
            PartContent::Text(text) if !text.trim().is_empty() => Some(text),
            _ => None,
        })
        .collect::<Vec<_>>();
    if texts.is_empty() {
        return Err("A2A response contains no text".into());
    }
    Ok(TextReply { task_id, texts })
}

/// Compatibility entry point for the public Knowledge demo.
pub async fn query_public_knowledge(
    node_dir: &Path,
    remote_origin: &str,
    question: &str,
) -> Result<KnowledgeReply, String> {
    send_text(node_dir, remote_origin, question).await
}
