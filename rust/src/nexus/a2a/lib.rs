//! A first standards-based Omnixus experiment using the official A2A types.
//!
//! This is an experimental agent adapter, not a network listener. Use only
//! public or synthetic data: although the SDK does not propagate a verified
//! user, it does pass request headers to the executor. This adapter verifies
//! those headers again at the point of use and passes the resulting caller to
//! the host. The paired-key node API still depends on a host-provided secure
//! transport and local policy.

use a2a::event::StreamResponse;
use a2a::{new_artifact_id, A2AError, Artifact, Part, PartContent, Task, TaskState, TaskStatus};
use a2a_server::{AgentExecutor, ExecutorContext, ServiceParams};
use futures::{
    future::BoxFuture,
    stream::{self, BoxStream},
};
use std::sync::Arc;

pub mod demo_auth;
pub mod node;
pub mod paired_auth;

/// Caller identity produced by a verifier, not by the A2A message itself.
pub struct VerifiedCaller {
    id: String,
}

impl VerifiedCaller {
    /// The locally authenticated caller identifier.
    pub fn id(&self) -> &str {
        &self.id
    }
}

/// Validates a caller credential at the point a host request is used.
pub trait CallerVerifier: Send + Sync + 'static {
    /// Returns a stable local identifier only when the credential is valid.
    fn verify(&self, params: &ServiceParams) -> Result<String, A2AError>;
}

/// The local knowledge implementation behind an A2A-facing node.
///
/// This contract receives a verified caller so it can enforce resource-level
/// access. This prototype still only serves synthetic knowledge and never
/// receives device credentials or authority to execute actions.
pub trait KnowledgeSource: Send + Sync + 'static {
    /// Answers a natural-language question using permitted local knowledge.
    fn answer(&self, caller: &VerifiedCaller, question: &str) -> Result<String, String>;
}

/// A host's asynchronous text handler after peer verification.
///
/// Authentication is not authorization: the host remains responsible for
/// request-specific access checks and must not treat prose as action consent.
pub trait AsyncTextSource: Send + Sync + 'static {
    fn respond(
        &self,
        caller_id: String,
        text: String,
    ) -> BoxFuture<'static, Result<String, String>>;
}

/// Compatibility contract for the public Knowledge demo.
///
/// This boundary lets a Flutter host retrieve from its own Knowledge service
/// without blocking an HTTP worker while waiting for Dart.
pub trait AsyncKnowledgeSource: Send + Sync + 'static {
    fn answer(
        &self,
        caller_id: String,
        question: String,
    ) -> BoxFuture<'static, Result<String, String>>;
}

impl<T: AsyncKnowledgeSource> AsyncTextSource for T {
    fn respond(
        &self,
        caller_id: String,
        text: String,
    ) -> BoxFuture<'static, Result<String, String>> {
        self.answer(caller_id, text)
    }
}

/// Adapts a host-owned asynchronous text handler to an A2A task.
pub struct AsyncTextAgent<S> {
    source: Arc<S>,
    verifier: Box<dyn CallerVerifier>,
}

/// Compatibility name for the public Knowledge demo.
pub type AsyncKnowledgeAgent<S> = AsyncTextAgent<S>;

impl<S: AsyncTextSource> AsyncTextAgent<S> {
    pub fn new(source: S, verifier: impl CallerVerifier) -> Self {
        Self {
            source: Arc::new(source),
            verifier: Box::new(verifier),
        }
    }
}

impl<S: AsyncTextSource> AgentExecutor for AsyncTextAgent<S> {
    fn execute(
        &self,
        ctx: ExecutorContext,
    ) -> BoxStream<'static, Result<StreamResponse, A2AError>> {
        let caller = self.verifier.verify(&ctx.service_params);
        let question = ctx.message.as_ref().and_then(|message| {
            message.parts.iter().find_map(|part| match &part.content {
                PartContent::Text(text) if !text.trim().is_empty() => Some(text.clone()),
                _ => None,
            })
        });
        let source = Arc::clone(&self.source);
        Box::pin(stream::once(async move {
            let caller = caller?;
            let question = question.ok_or_else(A2AError::content_type_not_supported)?;
            if question.len() > 512 {
                return Err(A2AError::invalid_request("question too long"));
            }
            let answer = source
                .respond(caller, question)
                .await
                .map_err(A2AError::invalid_request)?;
            if answer.trim().is_empty() || answer.len() > 16_384 {
                return Err(A2AError::invalid_request("response unavailable"));
            }
            Ok(completed_task(ctx.task_id, ctx.context_id, answer))
        }))
    }

    fn cancel(&self, ctx: ExecutorContext) -> BoxStream<'static, Result<StreamResponse, A2AError>> {
        Box::pin(stream::once(async move {
            Ok(StreamResponse::Task(Task {
                id: ctx.task_id,
                context_id: ctx.context_id,
                status: TaskStatus {
                    state: TaskState::Canceled,
                    message: None,
                    timestamp: None,
                },
                artifacts: None,
                history: None,
                metadata: None,
            }))
        }))
    }
}

fn completed_task(task_id: String, context_id: String, answer: String) -> StreamResponse {
    StreamResponse::Task(Task {
        id: task_id,
        context_id,
        status: TaskStatus {
            state: TaskState::Completed,
            message: None,
            timestamp: None,
        },
        artifacts: Some(vec![Artifact {
            artifact_id: new_artifact_id(),
            name: Some("Text response".into()),
            description: None,
            parts: vec![Part::text(answer)],
            metadata: None,
            extensions: None,
        }]),
        history: None,
        metadata: None,
    })
}

impl<T: KnowledgeSource + ?Sized> KnowledgeSource for Box<T> {
    fn answer(&self, caller: &VerifiedCaller, question: &str) -> Result<String, String> {
        (**self).answer(caller, question)
    }
}

/// Adapts a read-only knowledge source to the official A2A task lifecycle.
pub struct KnowledgeAgent<S> {
    source: S,
    verifier: Box<dyn CallerVerifier>,
}

impl<S: KnowledgeSource> KnowledgeAgent<S> {
    /// Creates a knowledge agent without starting a network listener.
    pub fn new(source: S, verifier: impl CallerVerifier) -> Self {
        Self {
            source,
            verifier: Box::new(verifier),
        }
    }
}

impl<S: KnowledgeSource> AgentExecutor for KnowledgeAgent<S> {
    fn execute(
        &self,
        ctx: ExecutorContext,
    ) -> BoxStream<'static, Result<StreamResponse, A2AError>> {
        let result = (|| {
            // The SDK currently sets ctx.user to None. Verify the raw headers
            // here rather than assuming a handler-level check already ran.
            let caller = VerifiedCaller {
                id: self.verifier.verify(&ctx.service_params)?,
            };
            let message = ctx
                .message
                .as_ref()
                .ok_or_else(A2AError::invalid_agent_response)?;
            let question = message
                .parts
                .iter()
                .find_map(|part| match &part.content {
                    PartContent::Text(text) if !text.trim().is_empty() => Some(text.as_str()),
                    _ => None,
                })
                .ok_or_else(A2AError::content_type_not_supported)?;
            let answer = self
                .source
                .answer(&caller, question)
                .map_err(A2AError::invalid_request)?;
            Ok(StreamResponse::Task(Task {
                id: ctx.task_id,
                context_id: ctx.context_id,
                status: TaskStatus {
                    state: TaskState::Completed,
                    message: None,
                    timestamp: None,
                },
                artifacts: Some(vec![Artifact {
                    artifact_id: new_artifact_id(),
                    name: Some("Knowledge answer".into()),
                    description: None,
                    parts: vec![Part::text(answer)],
                    metadata: None,
                    extensions: None,
                }]),
                history: None,
                metadata: None,
            }))
        })();
        Box::pin(stream::once(async move { result }))
    }

    fn cancel(&self, ctx: ExecutorContext) -> BoxStream<'static, Result<StreamResponse, A2AError>> {
        Box::pin(stream::once(async move {
            Ok(StreamResponse::Task(Task {
                id: ctx.task_id,
                context_id: ctx.context_id,
                status: TaskStatus {
                    state: TaskState::Canceled,
                    message: None,
                    timestamp: None,
                },
                artifacts: None,
                history: None,
                metadata: None,
            }))
        }))
    }
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use std::sync::Arc;

    use a2a::{Message, Part, Role, SendMessageRequest, SendMessageResponse, TaskState};
    use a2a_server::{
        DefaultRequestHandler, InMemoryTaskStore, RequestAuthorizer, RequestHandler, ServiceParams,
    };
    use futures::StreamExt;

    use super::*;

    struct ExampleKnowledge(Arc<AtomicUsize>);

    impl KnowledgeSource for ExampleKnowledge {
        fn answer(&self, caller: &VerifiedCaller, question: &str) -> Result<String, String> {
            assert_eq!(caller.id(), "test-client");
            self.0.fetch_add(1, Ordering::SeqCst);
            Ok(format!("Answer to: {question}"))
        }
    }

    struct DemoAuthorizer(Arc<AtomicBool>);

    impl RequestAuthorizer for DemoAuthorizer {
        fn authorize(
            &self,
            _params: &ServiceParams,
            _task_id: Option<&str>,
        ) -> Result<(), A2AError> {
            if self.0.load(Ordering::SeqCst) {
                Ok(())
            } else {
                Err(A2AError::invalid_request("knowledge access denied"))
            }
        }
    }

    #[tokio::test]
    async fn official_handler_checks_grant_before_knowledge_execution() {
        let calls = Arc::new(AtomicUsize::new(0));
        let grant = Arc::new(AtomicBool::new(false));
        let handler = DefaultRequestHandler::new(
            KnowledgeAgent::new(
                ExampleKnowledge(Arc::clone(&calls)),
                demo_auth::DemoBearerAuthorizer::new(
                    "test-secret".into(),
                    "test-client".into(),
                    true,
                ),
            ),
            InMemoryTaskStore::new(),
        )
        .with_authorizer(DemoAuthorizer(Arc::clone(&grant)));
        let request = || SendMessageRequest {
            message: Message::new(Role::User, vec![Part::text("What is Omnixus?")]),
            configuration: None,
            metadata: None,
            tenant: None,
        };

        let params =
            ServiceParams::from([("authorization".into(), vec!["Bearer test-secret".into()])]);
        assert!(handler.send_message(&params, request()).await.is_err());
        assert_eq!(calls.load(Ordering::SeqCst), 0);

        grant.store(true, Ordering::SeqCst);
        let response = handler
            .send_message(&params, request())
            .await
            .expect("granted request");
        let SendMessageResponse::Task(task) = response else {
            panic!("expected an A2A task");
        };
        assert_eq!(task.status.state, TaskState::Completed);
        let answer = task.artifacts.expect("result artifact")[0].parts[0].clone();
        assert_eq!(
            answer.content,
            PartContent::Text("Answer to: What is Omnixus?".into())
        );
        assert_eq!(calls.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn executor_reverifies_caller_without_a_handler_check() {
        let calls = Arc::new(AtomicUsize::new(0));
        let agent = KnowledgeAgent::new(
            ExampleKnowledge(Arc::clone(&calls)),
            demo_auth::DemoBearerAuthorizer::new("test-secret".into(), "test-client".into(), true),
        );
        let context = |service_params| ExecutorContext {
            message: Some(Message::new(
                Role::User,
                vec![Part::text("What is Omnixus?")],
            )),
            task_id: "task".into(),
            stored_task: None,
            context_id: "context".into(),
            metadata: None,
            user: None,
            service_params,
            tenant: None,
        };
        assert!(agent
            .execute(context(ServiceParams::new()))
            .next()
            .await
            .expect("executor result")
            .is_err());
        assert_eq!(calls.load(Ordering::SeqCst), 0);
        let allowed =
            ServiceParams::from([("authorization".into(), vec!["Bearer test-secret".into()])]);
        assert!(agent
            .execute(context(allowed))
            .next()
            .await
            .expect("executor result")
            .is_ok());
        assert_eq!(calls.load(Ordering::SeqCst), 1);
    }
}
