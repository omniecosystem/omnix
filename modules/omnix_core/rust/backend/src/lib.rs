// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! Native inference provider boundary, independent of Flutter and other modules.
//!
//! No inference backend is registered implicitly. Provider descriptors declare
//! supported formats, targets and features; selection checks requested capabilities.

use std::{collections::BTreeSet, fmt, path::Path};

pub mod embedding;
pub mod execution;
#[cfg(feature = "history")]
pub mod history;
pub mod message;
pub mod ownership;
#[cfg(feature = "tools")]
pub mod tools;
pub mod working_context;
pub use message::{CoreMessage, MessagePart};
#[cfg(all(feature = "model-installation", not(target_arch = "wasm32")))]
pub mod installation;

#[cfg(all(feature = "litertlm-embedding-engine", not(target_arch = "wasm32")))]
pub mod litertlm_embedding;

#[cfg(all(feature = "litertlm-embedding-engine", not(target_arch = "wasm32")))]
#[allow(
    dead_code,
    non_camel_case_types,
    non_snake_case,
    non_upper_case_globals
)]
mod litertlm_embedding_bindings;

#[cfg(all(feature = "litertlm-embeddings", not(target_arch = "wasm32")))]
pub mod litert_embedding;

#[cfg(all(feature = "litertlm-embeddings", not(target_arch = "wasm32")))]
#[allow(
    dead_code,
    non_camel_case_types,
    non_snake_case,
    non_upper_case_globals,
    clippy::useless_transmute,
    clippy::ptr_offset_with_cast
)]
mod litert_embedding_bindings;

#[cfg(all(test, feature = "litertlm", windows))]
#[path = "../build_support/native_staging.rs"]
mod native_staging_tests;

#[cfg(not(any(feature = "litertlm", feature = "llamacpp")))]
compile_error!("Omnix Core requires an explicit runtime feature: litertlm and/or llamacpp");

#[cfg(all(feature = "litertlm", not(target_arch = "wasm32")))]
pub mod litertlm;

#[cfg(all(feature = "litertlm", not(target_arch = "wasm32")))]
mod bundled_runtime;

#[cfg(all(feature = "llamacpp", not(target_arch = "wasm32")))]
pub mod llamacpp;

/// Inspects a local container, independently of its filename extension.
/// This identifies the container only, not model validity or trust.
pub fn probe_model_format(path: &Path) -> Result<ModelFormat, CoreError> {
    use std::io::Read;
    if !path.is_absolute() {
        return Err(CoreError::InvalidModelPath);
    }
    let mut header = [0u8; 8];
    std::fs::File::open(path)
        .and_then(|mut file| file.read_exact(&mut header))
        .map_err(|_| CoreError::BackendFailure("model-header-unavailable".into()))?;
    if &header[..4] == b"GGUF" {
        // Support the current little-endian GGUF container, not older variants.
        if u32::from_le_bytes(header[4..8].try_into().unwrap()) != 3 {
            return Err(CoreError::BackendFailure("gguf-version-unsupported".into()));
        }
        Ok(ModelFormat::Gguf)
    } else if &header == b"LITERTLM" {
        Ok(ModelFormat::LiteRtLm)
    } else {
        Err(CoreError::BackendFailure("model-format-unknown".into()))
    }
}

#[cfg(all(feature = "litertlm", not(target_arch = "wasm32")))]
#[allow(
    dead_code,
    non_camel_case_types,
    non_snake_case,
    non_upper_case_globals
)]
mod litertlm_bindings;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum ModelFormat {
    LiteRtLm,
    Gguf,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum InputModality {
    Text,
    Image,
    Audio,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum TargetPlatform {
    Android,
    Ios,
    Macos,
    Windows,
    Linux,
    Web,
}

/// Requirements for one model use. Actual file-format probing belongs to the
/// backend; a declared format never substitutes for validating the artifact.
#[derive(Debug, Clone)]
pub struct ModelRequest {
    pub format: ModelFormat,
    pub platform: TargetPlatform,
    pub input_modalities: BTreeSet<InputModality>,
    pub thinking: bool,
    pub tools: bool,
    /// An explicit provider choice is binding; no silent provider fallback.
    pub preferred_provider: Option<String>,
}

/// Capabilities available for the request, not a claim about every model.
#[derive(Debug, Clone)]
pub struct ProviderDescriptor {
    pub id: String,
    pub priority: i32,
    pub formats: BTreeSet<ModelFormat>,
    pub platforms: BTreeSet<TargetPlatform>,
    pub input_modalities: BTreeSet<InputModality>,
    pub thinking: bool,
    pub tools: bool,
}

impl ProviderDescriptor {
    fn supports(&self, request: &ModelRequest) -> bool {
        self.formats.contains(&request.format)
            && self.platforms.contains(&request.platform)
            && request.input_modalities.is_subset(&self.input_modalities)
            && (!request.thinking || self.thinking)
            && (!request.tools || self.tools)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CoreError {
    InvalidProvider,
    DuplicateProvider,
    InvalidRequest,
    NoCompatibleProvider,
    PreferredProviderUnavailable,
    InvalidModelPath,
    /// Backends supply a non-sensitive diagnostic code, not prompt content.
    BackendFailure(String),
}

impl fmt::Display for CoreError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidProvider => write!(f, "Invalid provider registration"),
            Self::DuplicateProvider => write!(f, "Provider already registered"),
            Self::InvalidRequest => write!(f, "Invalid model requirements"),
            Self::NoCompatibleProvider => write!(f, "No compatible inference provider"),
            Self::PreferredProviderUnavailable => write!(f, "Preferred provider unavailable"),
            Self::InvalidModelPath => write!(f, "An absolute model file path is required"),
            Self::BackendFailure(code) => write!(f, "Inference backend failed: {code}"),
        }
    }
}

impl std::error::Error for CoreError {}

/// Settings for a text conversation. Limits are enforced by the backend.
#[derive(Debug, Clone)]
pub struct ConversationOptions {
    /// Explicit native reasoning configuration. Unsupported runtimes reject it.
    pub thinking: bool,
    pub system_prompt: Option<String>,
    pub max_output_tokens: u32,
    pub sampling: Option<SamplingOptions>,
}

/// Explicit sampler configuration shared by runtime adapters.
/// `None` on a conversation preserves the runtime's existing default behavior.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SamplingOptions {
    pub temperature: f32,
    pub top_k: u32,
    pub top_p: f32,
    pub seed: u32,
}

impl SamplingOptions {
    pub fn validate(&self) -> Result<(), CoreError> {
        if !self.temperature.is_finite()
            || !(0.0..=2.0).contains(&self.temperature)
            || !(1..=10000).contains(&self.top_k)
            || !self.top_p.is_finite()
            || self.top_p <= 0.0
            || self.top_p > 1.0
            || self.seed > i32::MAX as u32
        {
            return Err(CoreError::InvalidRequest);
        }
        Ok(())
    }
}

/// Whether a streaming turn reached its normal end or was stopped.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StreamOutcome {
    Completed,
    Cancelled,
}

/// Runtime-reported output channels; reasoning is never inferred from prose.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConversationDelta {
    Text(String),
    Reasoning(String),
}

/// A stateful text conversation with optional streaming support.
pub trait Conversation: Send {
    /// Imports host-recorded semantic context, not native state or executable calls.
    #[cfg(feature = "history")]
    fn import_portable_history(
        &mut self,
        history: Vec<history::HistoryTurn>,
    ) -> Result<(), CoreError> {
        self.restore_history(history::text_pairs(&history)?)
    }
    /// Restores validated context and explicitly selects future reasoning output.
    fn restore_checkpoint_with_thinking(
        &mut self,
        _checkpoint: &str,
        _enabled: bool,
    ) -> Result<(), CoreError> {
        Err(CoreError::BackendFailure(
            "thinking-restoration-unsupported".into(),
        ))
    }
    fn restore_history_with_thinking(
        &mut self,
        _messages: Vec<(String, String)>,
        _enabled: bool,
    ) -> Result<(), CoreError> {
        Err(CoreError::BackendFailure(
            "thinking-restoration-unsupported".into(),
        ))
    }
    /// Changes future reasoning output between completed turns without erasing context.
    fn set_thinking(&mut self, _enabled: bool) -> Result<(), CoreError> {
        Err(CoreError::BackendFailure(
            "thinking-reconfiguration-unsupported".into(),
        ))
    }
    fn configure_context(
        &mut self,
        _policy: Option<working_context::SharedContextPolicy>,
    ) -> Result<(), CoreError> {
        Err(CoreError::BackendFailure(
            "context-policy-unsupported".into(),
        ))
    }
    fn context_usage(&mut self) -> Result<Option<working_context::ContextUsage>, CoreError> {
        Ok(None)
    }
    fn reconfigure(
        &mut self,
        _max_output_tokens: u32,
        _sampling: Option<SamplingOptions>,
    ) -> Result<(), CoreError> {
        Err(CoreError::BackendFailure(
            "reconfiguration-unsupported".into(),
        ))
    }
    fn send(&mut self, text: &str) -> Result<String, CoreError>;

    fn send_message(&mut self, message: &CoreMessage) -> Result<String, CoreError> {
        self.send(&message.text_only()?)
    }

    fn send_message_stream(
        &mut self,
        message: &CoreMessage,
        consumer: Box<dyn FnMut(String) -> bool + Send>,
        cancel: std::sync::Arc<std::sync::atomic::AtomicBool>,
    ) -> Result<StreamOutcome, CoreError> {
        self.send_stream(&message.text_only()?, consumer, cancel)
    }

    /// Streams distinct output channels. Text-only backends emit only text.
    /// Returning false requests cancellation with the same lifetime guarantees
    /// as `send_message_stream`.
    fn send_message_events(
        &mut self,
        message: &CoreMessage,
        mut consumer: Box<dyn FnMut(ConversationDelta) -> bool + Send>,
        cancel: std::sync::Arc<std::sync::atomic::AtomicBool>,
    ) -> Result<StreamOutcome, CoreError> {
        self.send_message_stream(
            message,
            Box::new(move |text| consumer(ConversationDelta::Text(text))),
            cancel,
        )
    }

    fn history(&mut self) -> Result<Vec<(String, String)>, CoreError> {
        Err(CoreError::BackendFailure("history-unsupported".into()))
    }

    fn restore_history(&mut self, _messages: Vec<(String, String)>) -> Result<(), CoreError> {
        Err(CoreError::BackendFailure("history-unsupported".into()))
    }

    /// A bounded runtime-owned snapshot for context that text history cannot represent.
    fn export_checkpoint(&mut self) -> Result<String, CoreError> {
        Err(CoreError::BackendFailure("checkpoint-unsupported".into()))
    }
    fn restore_checkpoint(&mut self, _checkpoint: &str) -> Result<(), CoreError> {
        Err(CoreError::BackendFailure("checkpoint-unsupported".into()))
    }

    /// Runs a streaming turn. Returning false from the consumer requests stop.
    /// Native callback data must be copied before delivering owned text here.
    fn send_stream(
        &mut self,
        _text: &str,
        _consumer: Box<dyn FnMut(String) -> bool + Send>,
        _cancel: std::sync::Arc<std::sync::atomic::AtomicBool>,
    ) -> Result<StreamOutcome, CoreError> {
        Err(CoreError::BackendFailure("streaming-unsupported".into()))
    }
}

pub fn validate_history(messages: &[(String, String)]) -> Result<(), CoreError> {
    if messages.len() > 10000
        || !messages.len().is_multiple_of(2)
        || messages
            .iter()
            .try_fold(0usize, |size, (_, text)| size.checked_add(text.len()))
            .unwrap_or(usize::MAX)
            > 1_048_576
        || messages.iter().enumerate().any(|(i, (role, text))| {
            role != if i % 2 == 0 { "user" } else { "assistant" } || text.contains('\0')
        })
    {
        return Err(CoreError::InvalidRequest);
    }
    Ok(())
}

#[cfg(test)]
mod conversation_events_tests {
    use super::*;
    #[test]
    fn text_only_implementations_keep_streaming_and_consumer_cancellation() {
        struct Chat;
        impl Conversation for Chat {
            fn send(&mut self, _: &str) -> Result<String, CoreError> {
                unreachable!()
            }
            fn send_stream(
                &mut self,
                text: &str,
                mut consumer: Box<dyn FnMut(String) -> bool + Send>,
                _: std::sync::Arc<std::sync::atomic::AtomicBool>,
            ) -> Result<StreamOutcome, CoreError> {
                Ok(if consumer(text.to_owned()) {
                    StreamOutcome::Completed
                } else {
                    StreamOutcome::Cancelled
                })
            }
        }
        let events = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
        let received = events.clone();
        assert_eq!(
            Chat.send_message_events(
                &CoreMessage::text("plain"),
                Box::new(move |event| {
                    received.lock().unwrap().push(event);
                    false
                }),
                std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false))
            )
            .unwrap(),
            StreamOutcome::Cancelled
        );
        assert_eq!(
            *events.lock().unwrap(),
            vec![ConversationDelta::Text("plain".into())]
        );
    }
}

/// A backend-owned loaded model. Conversations retain the engine they use.
pub trait LoadedModel: Send {
    fn provider_id(&self) -> &str;
    /// Opens an explicitly tool-enabled conversation; unsupported providers fail closed.
    #[cfg(feature = "tools")]
    fn start_tool_conversation(
        &self,
        _options: ConversationOptions,
        _tools: Vec<tools::ToolDefinition>,
    ) -> Result<Box<dyn tools::ToolConversation>, CoreError> {
        Err(CoreError::BackendFailure(
            "tool-conversations-unsupported".into(),
        ))
    }
    fn start_conversation(
        &self,
        _options: ConversationOptions,
    ) -> Result<Box<dyn Conversation>, CoreError> {
        Err(CoreError::BackendFailure(
            "conversations-unsupported".into(),
        ))
    }
}

/// Core chooses a provider; the provider owns native runtime integration.
pub trait RuntimeProvider: Send + Sync {
    fn descriptor(&self) -> &ProviderDescriptor;
    fn load(&self, request: &ModelRequest, path: &Path) -> Result<Box<dyn LoadedModel>, CoreError>;
}

/// Explicitly registered runtime providers with deterministic selection.
#[derive(Default)]
pub struct RuntimeRegistry {
    providers: Vec<Box<dyn RuntimeProvider>>,
}

impl RuntimeRegistry {
    pub fn register(&mut self, provider: Box<dyn RuntimeProvider>) -> Result<(), CoreError> {
        let descriptor = provider.descriptor();
        if descriptor.id.trim().is_empty()
            || descriptor.formats.is_empty()
            || descriptor.platforms.is_empty()
            || descriptor.input_modalities.is_empty()
        {
            return Err(CoreError::InvalidProvider);
        }
        if self
            .providers
            .iter()
            .any(|p| p.descriptor().id == descriptor.id)
        {
            return Err(CoreError::DuplicateProvider);
        }
        self.providers.push(provider);
        Ok(())
    }

    pub fn select(&self, request: &ModelRequest) -> Result<&dyn RuntimeProvider, CoreError> {
        if request.input_modalities.is_empty()
            || request
                .preferred_provider
                .as_ref()
                .is_some_and(|id| id.trim().is_empty())
        {
            return Err(CoreError::InvalidRequest);
        }
        let mut selected: Option<&dyn RuntimeProvider> = None;
        for provider in &self.providers {
            let descriptor = provider.descriptor();
            if request
                .preferred_provider
                .as_ref()
                .is_some_and(|id| id != &descriptor.id)
                || !descriptor.supports(request)
            {
                continue;
            }
            // Strictly greater preserves registration order on priority ties.
            if selected.is_none_or(|p| descriptor.priority > p.descriptor().priority) {
                selected = Some(provider.as_ref());
            }
        }
        selected.ok_or(if request.preferred_provider.is_some() {
            CoreError::PreferredProviderUnavailable
        } else {
            CoreError::NoCompatibleProvider
        })
    }

    pub fn load(
        &self,
        request: &ModelRequest,
        path: &Path,
    ) -> Result<Box<dyn LoadedModel>, CoreError> {
        if !path.is_absolute() || path.file_name().is_none() {
            return Err(CoreError::InvalidModelPath);
        }
        // A selected backend failure is returned, never hidden by retrying a
        // different backend that might discard required capabilities.
        self.select(request)?.load(request, path)
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn sampling_rejects_nonfinite_and_out_of_range_values() {
        let valid = super::SamplingOptions {
            temperature: 0.8,
            top_k: 40,
            top_p: 0.95,
            seed: 0,
        };
        assert!(valid.validate().is_ok());
        assert!(super::SamplingOptions {
            temperature: 0.0,
            ..valid.clone()
        }
        .validate()
        .is_ok());
        for temperature in [f32::NAN, f32::INFINITY, -0.1, 2.1] {
            assert!(super::SamplingOptions {
                temperature,
                ..valid.clone()
            }
            .validate()
            .is_err());
        }
        for top_p in [f32::NAN, 0.0, 1.1] {
            assert!(super::SamplingOptions {
                top_p,
                ..valid.clone()
            }
            .validate()
            .is_err());
        }
        for top_k in [0, 10001] {
            assert!(super::SamplingOptions {
                top_k,
                ..valid.clone()
            }
            .validate()
            .is_err());
        }
        assert!(super::SamplingOptions {
            seed: u32::MAX,
            ..valid
        }
        .validate()
        .is_err());
    }
    use super::*;
    struct TestProvider(ProviderDescriptor);
    impl RuntimeProvider for TestProvider {
        fn descriptor(&self) -> &ProviderDescriptor {
            &self.0
        }
        fn load(&self, _: &ModelRequest, _: &Path) -> Result<Box<dyn LoadedModel>, CoreError> {
            Err(CoreError::BackendFailure("test-load-failure".into()))
        }
    }
    fn descriptor(id: &str, priority: i32, format: ModelFormat) -> ProviderDescriptor {
        ProviderDescriptor {
            id: id.into(),
            priority,
            formats: [format].into(),
            platforms: [TargetPlatform::Windows].into(),
            input_modalities: [InputModality::Text].into(),
            thinking: false,
            tools: false,
        }
    }
    fn request() -> ModelRequest {
        ModelRequest {
            format: ModelFormat::LiteRtLm,
            platform: TargetPlatform::Windows,
            input_modalities: [InputModality::Text].into(),
            thinking: false,
            tools: false,
            preferred_provider: None,
        }
    }
    #[test]
    fn empty_registry_fails_explicitly() {
        assert!(matches!(
            RuntimeRegistry::default().select(&request()),
            Err(CoreError::NoCompatibleProvider)
        ));
    }
    #[test]
    fn selects_format_priority_then_registration_order() {
        let mut registry = RuntimeRegistry::default();
        for d in [
            descriptor("wrong-format", 99, ModelFormat::Gguf),
            descriptor("first", 1, ModelFormat::LiteRtLm),
            descriptor("tie", 1, ModelFormat::LiteRtLm),
        ] {
            registry.register(Box::new(TestProvider(d))).unwrap();
        }
        assert_eq!(
            registry.select(&request()).unwrap().descriptor().id,
            "first"
        );
        registry
            .register(Box::new(TestProvider(descriptor(
                "higher",
                2,
                ModelFormat::LiteRtLm,
            ))))
            .unwrap();
        assert_eq!(
            registry.select(&request()).unwrap().descriptor().id,
            "higher"
        );
    }
    #[test]
    fn rejects_duplicate_or_incomplete_registration() {
        let mut registry = RuntimeRegistry::default();
        registry
            .register(Box::new(TestProvider(descriptor(
                "provider",
                0,
                ModelFormat::LiteRtLm,
            ))))
            .unwrap();
        assert_eq!(
            registry.register(Box::new(TestProvider(descriptor(
                "provider",
                1,
                ModelFormat::LiteRtLm
            )))),
            Err(CoreError::DuplicateProvider)
        );
        assert_eq!(
            registry.register(Box::new(TestProvider(descriptor(
                "",
                0,
                ModelFormat::LiteRtLm
            )))),
            Err(CoreError::InvalidProvider)
        );
    }
    #[test]
    fn never_drops_requested_capabilities() {
        let mut registry = RuntimeRegistry::default();
        registry
            .register(Box::new(TestProvider(descriptor(
                "text-only",
                0,
                ModelFormat::LiteRtLm,
            ))))
            .unwrap();
        for changed in 0..4 {
            let mut r = request();
            match changed {
                0 => {
                    r.input_modalities.insert(InputModality::Image);
                }
                1 => r.tools = true,
                2 => r.thinking = true,
                _ => r.platform = TargetPlatform::Android,
            }
            assert!(matches!(
                registry.select(&r),
                Err(CoreError::NoCompatibleProvider)
            ));
        }
    }
    #[test]
    fn explicit_preference_is_binding() {
        let mut registry = RuntimeRegistry::default();
        registry
            .register(Box::new(TestProvider(descriptor(
                "available",
                0,
                ModelFormat::LiteRtLm,
            ))))
            .unwrap();
        let mut r = request();
        r.preferred_provider = Some("missing".into());
        assert!(matches!(
            registry.select(&r),
            Err(CoreError::PreferredProviderUnavailable)
        ));
        r.preferred_provider = Some("available".into());
        assert_eq!(registry.select(&r).unwrap().descriptor().id, "available");
    }
    #[test]
    fn validates_requirements_and_path_without_loading() {
        let registry = RuntimeRegistry::default();
        let mut r = request();
        r.input_modalities.clear();
        assert!(matches!(
            registry.select(&r),
            Err(CoreError::InvalidRequest)
        ));
        assert!(matches!(
            registry.load(&request(), Path::new("relative.litertlm")),
            Err(CoreError::InvalidModelPath)
        ));
    }
    #[test]
    fn preserves_backend_failure_without_fallback() {
        let mut registry = RuntimeRegistry::default();
        registry
            .register(Box::new(TestProvider(descriptor(
                "selected",
                0,
                ModelFormat::LiteRtLm,
            ))))
            .unwrap();
        let absolute = std::env::current_dir().unwrap().join("model.litertlm");
        assert!(
            matches!(registry.load(&request(), &absolute), Err(CoreError::BackendFailure(code)) if code == "test-load-failure")
        );
    }
}
