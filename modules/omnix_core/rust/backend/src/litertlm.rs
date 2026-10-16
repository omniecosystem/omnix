// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! Opt-in conversation adapter for the LiteRT-LM C ABI.
//! Windows pins v0.17.1; Android v0.18 preserves this conversation API.
//! Media encoders and accelerators require compatible models and native binaries.
//! All engine/conversation calls run on one owning thread. No raw native pointer
//! is sent between threads, and the library outlives every native allocation.

use crate::litertlm_bindings as ffi;
use crate::tools::{ToolCall, ToolConversation, ToolDefinition, ToolResult, ToolTurn};
use crate::*;
use base64::Engine;
use std::{
    collections::BTreeMap,
    ffi::{CStr, CString},
    ptr,
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Arc,
    },
    thread,
    time::Duration,
};

// The generated table retains the library and typed upstream function pointers.
// Symbol presence alone still does NOT establish ABI compatibility.
struct Api(ffi::LiteRtLm);

// Android's runtime contains process-wide Rust TLS keys and native callbacks.
// Keep the library mapped until process exit, not merely until engine deletion.
// This does not retain model weights or live engines.
#[cfg(any(target_os = "android", test))]
fn resident_library<T>(
    cache: &std::sync::Mutex<BTreeMap<std::path::PathBuf, Arc<T>>>,
    path: &Path,
    load: impl FnOnce() -> Result<T, CoreError>,
) -> Result<Arc<T>, CoreError> {
    let mut cache = cache
        .lock()
        .map_err(|_| failure("native-library-registry"))?;
    if let Some(api) = cache.get(path) {
        return Ok(api.clone());
    }
    // Runtime replacement requires an app restart; bound trusted override paths.
    if cache.len() >= 4 {
        return Err(failure("native-library-resident-limit"));
    }
    let api = Arc::new(load()?);
    cache.insert(path.to_owned(), api.clone());
    Ok(api)
}

fn failure(code: &str) -> CoreError {
    CoreError::BackendFailure(code.into())
}

fn library_error(error: libloading::Error) -> CoreError {
    use std::error::Error;
    let code = error
        .source()
        .and_then(|source| source.downcast_ref::<std::io::Error>())
        .and_then(std::io::Error::raw_os_error);
    failure(&match code {
        Some(code) => format!("native-library-load:os-{code}"),
        None => "native-library-load".into(),
    })
}

impl Api {
    unsafe fn shared(path: &Path) -> Result<Arc<Self>, CoreError> {
        #[cfg(target_os = "android")]
        {
            static APIS: std::sync::OnceLock<
                std::sync::Mutex<BTreeMap<std::path::PathBuf, Arc<Api>>>,
            > = std::sync::OnceLock::new();
            resident_library(APIS.get_or_init(Default::default), path, || {
                Self::load(path)
            })
        }
        #[cfg(not(target_os = "android"))]
        {
            Ok(Arc::new(Self::load(path)?))
        }
    }
    unsafe fn load(path: &Path) -> Result<Self, CoreError> {
        #[cfg(windows)]
        let library: libloading::Library = libloading::os::windows::Library::load_with_flags(
            path,
            // Search dependencies beside this library and in default trusted
            // directories, not in the process current working directory.
            0x00000100 | 0x00001000,
        )
        .map_err(library_error)?
        .into();
        #[cfg(not(windows))]
        let library = libloading::Library::new(path).map_err(library_error)?;
        Ok(Self(
            ffi::LiteRtLm::from_library(library).map_err(|_| failure("native-symbol-missing"))?,
        ))
    }
}

/// Native allocation confined to its owner thread; the Api lives outside it.
struct Resource<T>(*mut T, unsafe extern "C" fn(*mut T));
impl<T> Resource<T> {
    fn new(
        handle: *mut T,
        delete: unsafe extern "C" fn(*mut T),
        code: &str,
    ) -> Result<Self, CoreError> {
        if handle.is_null() {
            Err(failure(code))
        } else {
            Ok(Self(handle, delete))
        }
    }
}
impl<T> Drop for Resource<T> {
    fn drop(&mut self) {
        unsafe { (self.1)(self.0) }
    }
}

/// LiteRT-LM provider for Windows and Android with explicit encoder/backend selection.
/// Runtime initialization validates the selected model and native configuration.
pub struct LiteRtLmProvider {
    api: Arc<Api>,
    descriptor: ProviderDescriptor,
    context_tokens: u32,
    cache_directory: Option<CString>,
    backend: LiteRtLmBackend,
    dispatch_directory: Option<CString>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum LiteRtLmBackend {
    #[default]
    Cpu,
    Gpu,
    Npu,
}

impl LiteRtLmBackend {
    pub fn parse(name: &str) -> Result<Self, CoreError> {
        match name {
            "cpu" => Ok(Self::Cpu),
            "gpu" => Ok(Self::Gpu),
            "npu" => Ok(Self::Npu),
            _ => Err(failure("invalid-litertlm-backend")),
        }
    }
    fn native_name(self) -> &'static CStr {
        match self {
            Self::Cpu => c"cpu",
            Self::Gpu => c"gpu",
            Self::Npu => c"npu",
        }
    }
}

impl LiteRtLmProvider {
    /// Resolves the build-time distribution beside the executable or Core DLL.
    /// No working-directory or PATH search, and no inference-time download.
    pub fn bundled_library_path() -> Result<std::path::PathBuf, CoreError> {
        crate::bundled_runtime::litertlm_path()
            .map(std::path::PathBuf::from)
            .map_err(CoreError::BackendFailure)
    }

    /// Loads the pinned distribution installed by Cargo or the Flutter build hook.
    /// The deployment must preserve the DLLs beside the executable/Core library.
    pub fn from_bundled(context_tokens: u32) -> Result<Self, CoreError> {
        let path = Self::bundled_library_path()?;
        // Build-time acquisition verifies the pinned C-ABI distribution.
        unsafe { Self::from_library(&path, context_tokens) }
    }

    /// Load an explicitly selected trusted native runtime, without downloading.
    ///
    /// # Safety
    /// The caller must verify this library and its dependencies are trusted and
    /// implement the pinned platform's compatible LiteRT-LM C ABI (v0.17.1 on
    /// Windows, v0.18.0 on Android). Loading arbitrary or ABI-incompatible
    /// native code can execute malicious code or cause undefined behavior.
    pub unsafe fn from_library(path: &Path, context_tokens: u32) -> Result<Self, CoreError> {
        Self::from_library_with_modalities(path, context_tokens, [InputModality::Text].into())
    }

    /// Enables requested encoders for a host-approved model containing them.
    /// Engine initialization must succeed; this is not model capability discovery.
    ///
    /// # Safety
    /// The runtime must meet the same trust and ABI requirements as `from_library`.
    pub unsafe fn from_library_with_modalities(
        path: &Path,
        context_tokens: u32,
        modalities: std::collections::BTreeSet<InputModality>,
    ) -> Result<Self, CoreError> {
        if !path.is_absolute()
            || !path.is_file()
            || !(128..=i32::MAX as u32).contains(&context_tokens)
            || !modalities.contains(&InputModality::Text)
        {
            return Err(CoreError::InvalidRequest);
        }
        Ok(Self {
            api: Api::shared(&path.canonicalize().map_err(|_| CoreError::InvalidRequest)?)?,
            descriptor: ProviderDescriptor {
                id: "litertlm-cpu".into(),
                priority: 0,
                formats: [ModelFormat::LiteRtLm].into(),
                platforms: [current_platform()?].into(),
                input_modalities: modalities,
                thinking: true,
                tools: false,
            },
            context_tokens: context_tokens.max(1024),
            cache_directory: None,
            backend: LiteRtLmBackend::Cpu,
            dispatch_directory: None,
        })
    }

    // Selection is not hardware discovery. A missing driver, incompatible
    // compiled model or unsupported device is reported by native creation.
    pub fn with_backend(
        mut self,
        backend: LiteRtLmBackend,
        dispatch_directory: Option<&Path>,
    ) -> Result<Self, CoreError> {
        if backend == LiteRtLmBackend::Npu && dispatch_directory.is_none() {
            return Err(failure("npu-dispatch-directory-required"));
        }
        if backend != LiteRtLmBackend::Npu && dispatch_directory.is_some() {
            return Err(failure("dispatch-directory-requires-npu"));
        }
        self.dispatch_directory = dispatch_directory.map(cache_directory).transpose()?;
        self.backend = backend;
        self.descriptor.id = format!("litertlm-{}", backend.native_name().to_string_lossy());
        Ok(self)
    }

    /// Selects an existing host-owned directory for native optimized caches.
    /// Does not create, clean or move files; existing default caches stay intact.
    pub fn with_cache_directory(mut self, directory: &Path) -> Result<Self, CoreError> {
        self.cache_directory = Some(cache_directory(directory)?);
        Ok(self)
    }
}

impl RuntimeProvider for LiteRtLmProvider {
    fn descriptor(&self) -> &ProviderDescriptor {
        &self.descriptor
    }
    fn load(&self, request: &ModelRequest, path: &Path) -> Result<Box<dyn LoadedModel>, CoreError> {
        if !self.descriptor.supports(request) || request.platform != current_platform()? {
            return Err(CoreError::NoCompatibleProvider);
        }
        if !path.is_absolute() || !path.is_file() {
            return Err(CoreError::InvalidModelPath);
        }
        let path = path.to_str().ok_or(CoreError::InvalidModelPath)?;
        let path = CString::new(path).map_err(|_| CoreError::InvalidModelPath)?;
        let api = self.api.clone();
        let tokens = self.context_tokens;
        let cache_directory = self.cache_directory.clone();
        let backend = self.backend;
        let dispatch_directory = self.dispatch_directory.clone();
        // Advertised capabilities bound routing, while the request controls
        // which encoders this model actually initializes. A text-only model
        // must not be forced to contain image/audio encoders.
        let modalities = model_modalities(request);
        let (sender, receiver) = mpsc::channel();
        let (ready_tx, ready_rx) = mpsc::channel();
        let join = thread::Builder::new()
            .name("omnix-core-litertlm".into())
            .spawn(move || {
                let engine = unsafe {
                    (|| {
                        let settings = Resource::new(
                            (api.0.litert_lm_engine_settings_create)(
                                path.as_ptr(),
                                backend.native_name().as_ptr(),
                                encoder_backend(&modalities, InputModality::Image),
                                encoder_backend(&modalities, InputModality::Audio),
                            ),
                            api.0.litert_lm_engine_settings_delete,
                            "engine-settings-create",
                        )?;
                        (api.0.litert_lm_engine_settings_set_max_num_tokens)(
                            settings.0,
                            tokens as i32,
                        );
                        if let Some(directory) = &cache_directory {
                            (api.0.litert_lm_engine_settings_set_cache_dir)(
                                settings.0,
                                directory.as_ptr(),
                            );
                        }
                        if let Some(directory) = &dispatch_directory {
                            (api.0.litert_lm_engine_settings_set_litert_dispatch_lib_dir)(
                                settings.0,
                                directory.as_ptr(),
                            );
                        }
                        Resource::new(
                            (api.0.litert_lm_engine_create)(settings.0),
                            api.0.litert_lm_engine_delete,
                            match backend {
                                LiteRtLmBackend::Cpu => "engine-create:cpu",
                                LiteRtLmBackend::Gpu => "engine-create:gpu",
                                LiteRtLmBackend::Npu => "engine-create:npu",
                            },
                        )
                    })()
                };
                match engine {
                    Ok(engine) => {
                        if ready_tx.send(Ok(())).is_ok() {
                            run_worker(&api, &engine, tokens, receiver);
                        }
                        // All conversations are destroyed before engine, then Api.
                    }
                    Err(error) => {
                        let _ = ready_tx.send(Err(error));
                    }
                }
            })
            .map_err(|_| failure("worker-start"))?;
        match ready_rx.recv().map_err(|_| failure("worker-stopped"))? {
            Ok(()) => Ok(Box::new(Model(Arc::new(Worker {
                sender,
                join: Some(join),
                modalities: model_modalities(request),
                provider_id: self.descriptor.id.clone(),
            })))),
            Err(error) => {
                let _ = join.join();
                Err(error)
            }
        }
    }
}

fn model_modalities(request: &ModelRequest) -> std::collections::BTreeSet<InputModality> {
    request.input_modalities.clone()
}

fn cache_directory(directory: &Path) -> Result<CString, CoreError> {
    if !directory.is_absolute() || !directory.is_dir() {
        return Err(failure("cache-directory-must-exist-and-be-absolute"));
    }
    // Keep the host spelling: Windows canonicalization introduces an extended
    // path prefix that some native file APIs do not accept.
    CString::new(directory.to_str().ok_or(CoreError::InvalidModelPath)?)
        .map_err(|_| CoreError::InvalidModelPath)
}

fn current_platform() -> Result<TargetPlatform, CoreError> {
    if cfg!(target_os = "windows") {
        Ok(TargetPlatform::Windows)
    } else if cfg!(target_os = "android") {
        Ok(TargetPlatform::Android)
    } else {
        Err(CoreError::NoCompatibleProvider)
    }
}

enum Command {
    ContextPolicy(
        u64,
        Option<working_context::SharedContextPolicy>,
        mpsc::Sender<Result<(), CoreError>>,
    ),
    ContextUsage(
        u64,
        mpsc::Sender<Result<Option<working_context::ContextUsage>, CoreError>>,
    ),
    ImportChat(
        u64,
        Vec<serde_json::Value>,
        mpsc::Sender<Result<(), CoreError>>,
    ),
    ToolsEnabled(u64, bool, mpsc::Sender<Result<(), CoreError>>),
    Thinking(u64, bool, mpsc::Sender<Result<(), CoreError>>),
    Reconfigure(
        u64,
        u32,
        Option<SamplingOptions>,
        mpsc::Sender<Result<(), CoreError>>,
    ),
    ToolCheckpoint(
        u64,
        Option<String>,
        Option<bool>,
        mpsc::Sender<Result<String, CoreError>>,
    ),
    History(u64, mpsc::Sender<Result<Vec<(String, String)>, CoreError>>),
    Restore(
        u64,
        Vec<(String, String)>,
        Option<bool>,
        mpsc::Sender<Result<(), CoreError>>,
    ),
    Open(
        ConversationOptions,
        Vec<ToolDefinition>,
        mpsc::Sender<Result<u64, CoreError>>,
    ),
    Tool(u64, ToolInput, mpsc::Sender<Result<ToolTurn, CoreError>>),
    ToolStream(
        u64,
        ToolInput,
        Box<dyn FnMut(ConversationDelta) -> bool + Send>,
        Arc<AtomicBool>,
        mpsc::Sender<Result<ToolTurn, CoreError>>,
    ),
    Send(u64, CoreMessage, mpsc::Sender<Result<String, CoreError>>),
    Stream(
        u64,
        CoreMessage,
        Box<dyn FnMut(ConversationDelta) -> bool + Send>,
        Arc<AtomicBool>,
        mpsc::Sender<Result<StreamOutcome, CoreError>>,
    ),
    Close(u64),
    Shutdown,
}
struct Worker {
    sender: mpsc::Sender<Command>,
    join: Option<thread::JoinHandle<()>>,
    modalities: std::collections::BTreeSet<InputModality>,
    provider_id: String,
}
impl Drop for Worker {
    fn drop(&mut self) {
        let _ = self.sender.send(Command::Shutdown);
        if let Some(join) = self.join.take() {
            let _ = join.join();
        }
    }
}
struct Model(Arc<Worker>);
enum ToolInput {
    User(CoreMessage),
    Results(Vec<ToolResult>),
}
impl LoadedModel for Model {
    fn provider_id(&self) -> &str {
        &self.0.provider_id
    }
    fn start_conversation(
        &self,
        options: ConversationOptions,
    ) -> Result<Box<dyn Conversation>, CoreError> {
        let (tx, rx) = mpsc::channel();
        self.0
            .sender
            .send(Command::Open(options, vec![], tx))
            .map_err(|_| failure("worker-stopped"))?;
        let id = rx.recv().map_err(|_| failure("worker-stopped"))??;
        Ok(Box::new(Chat {
            worker: self.0.clone(),
            id,
        }))
    }
    fn start_tool_conversation(
        &self,
        options: ConversationOptions,
        tools: Vec<ToolDefinition>,
    ) -> Result<Box<dyn ToolConversation>, CoreError> {
        crate::tools::validate_definitions(&tools)?;
        let (tx, rx) = mpsc::channel();
        self.0
            .sender
            .send(Command::Open(options.clone(), tools.clone(), tx))
            .map_err(|_| failure("worker-stopped"))?;
        let id = rx.recv().map_err(|_| failure("worker-stopped"))??;
        Ok(Box::new(ToolChat(
            Chat {
                worker: self.0.clone(),
                id,
            },
            options,
            tools,
        )))
    }
}
struct ToolChat(Chat, ConversationOptions, Vec<ToolDefinition>);
impl ToolChat {
    fn import_chat(&mut self, history: Vec<serde_json::Value>) -> Result<(), CoreError> {
        for message in &history {
            if let Some(parts) = message["content"].as_array() {
                for part in parts {
                    let modality = match part["type"].as_str() {
                        Some("image") => Some(InputModality::Image),
                        Some("audio") => Some(InputModality::Audio),
                        _ => None,
                    };
                    if modality.is_some_and(|m| !self.0.worker.modalities.contains(&m)) {
                        return Err(failure("input-modality-not-enabled"));
                    }
                }
            }
        }
        let (tx, rx) = mpsc::channel();
        self.0
            .worker
            .sender
            .send(Command::ImportChat(self.0.id, history, tx))
            .map_err(|_| failure("worker-stopped"))?;
        rx.recv().map_err(|_| failure("worker-stopped"))?
    }
    fn checkpoint(&mut self, snapshot: Option<String>) -> Result<String, CoreError> {
        let (tx, rx) = mpsc::channel();
        self.0
            .worker
            .sender
            .send(Command::ToolCheckpoint(self.0.id, snapshot, None, tx))
            .map_err(|_| failure("worker-stopped"))?;
        rx.recv().map_err(|_| failure("worker-stopped"))?
    }
    fn turn(&mut self, input: ToolInput) -> Result<ToolTurn, CoreError> {
        let (tx, rx) = mpsc::channel();
        self.0
            .worker
            .sender
            .send(Command::Tool(self.0.id, input, tx))
            .map_err(|_| failure("worker-stopped"))?;
        rx.recv().map_err(|_| failure("worker-stopped"))?
    }
    fn stream(
        &mut self,
        input: ToolInput,
        consumer: Box<dyn FnMut(ConversationDelta) -> bool + Send>,
        cancel: Arc<AtomicBool>,
    ) -> Result<ToolTurn, CoreError> {
        let (tx, rx) = mpsc::channel();
        self.0
            .worker
            .sender
            .send(Command::ToolStream(self.0.id, input, consumer, cancel, tx))
            .map_err(|_| failure("worker-stopped"))?;
        rx.recv().map_err(|_| failure("worker-stopped"))?
    }
}
impl ToolConversation for ToolChat {
    fn import_portable_history(
        &mut self,
        history: Vec<crate::history::HistoryTurn>,
    ) -> Result<(), CoreError> {
        self.import_chat(portable_native_history(
            &history,
            &self.0.worker.modalities,
        )?)
    }
    fn restore_checkpoint_with_thinking(
        &mut self,
        checkpoint: &str,
        enabled: bool,
    ) -> Result<(), CoreError> {
        self.0
            .restore_checkpoint_with_thinking(checkpoint, enabled)?;
        self.1.thinking = enabled;
        Ok(())
    }
    fn set_thinking(&mut self, enabled: bool) -> Result<(), CoreError> {
        self.0.set_thinking(enabled)?;
        self.1.thinking = enabled;
        Ok(())
    }
    fn restore_interrupted_turn(
        &mut self,
        checkpoint: &str,
        message: &CoreMessage,
        partial: &str,
    ) -> Result<(), CoreError> {
        let history = tool_checkpoint_history(checkpoint, &self.2, &self.1)?;
        let mut snapshot: serde_json::Value =
            serde_json::from_str(checkpoint).map_err(|_| CoreError::InvalidRequest)?;
        let mut messages = history;
        messages.push(encode_input(message));
        messages.push(
            serde_json::json!({"role":"assistant", "content":[{"type":"text", "text":partial}]}),
        );
        snapshot["messages"] = serde_json::Value::Array(messages);
        self.restore_checkpoint(&snapshot.to_string())
    }
    fn restart(&mut self) -> Result<Box<dyn ToolConversation>, CoreError> {
        Model(self.0.worker.clone()).start_tool_conversation(self.1.clone(), self.2.clone())
    }
    fn configure_context(
        &mut self,
        policy: Option<working_context::SharedContextPolicy>,
    ) -> Result<(), CoreError> {
        self.0.configure_context(policy)
    }
    fn context_usage(&mut self) -> Result<Option<working_context::ContextUsage>, CoreError> {
        self.0.context_usage()
    }
    fn import_chat_history(&mut self, history: Vec<(String, String)>) -> Result<(), CoreError> {
        crate::validate_history(&history)?;
        self.import_chat(history.into_iter().map(|(role, text)|
            serde_json::json!({"role": role, "content": [{"type":"text", "text":text}]})).collect())
    }
    fn import_chat_checkpoint(&mut self, context: &str) -> Result<(), CoreError> {
        self.import_chat(ordinary_checkpoint_history(context)?)
    }
    fn set_tools_enabled(&mut self, enabled: bool) -> Result<(), CoreError> {
        let (tx, rx) = mpsc::channel();
        self.0
            .worker
            .sender
            .send(Command::ToolsEnabled(self.0.id, enabled, tx))
            .map_err(|_| failure("worker-stopped"))?;
        rx.recv().map_err(|_| failure("worker-stopped"))?
    }
    fn reconfigure(
        &mut self,
        tokens: u32,
        sampling: Option<SamplingOptions>,
    ) -> Result<(), CoreError> {
        self.0.reconfigure(tokens, sampling.clone())?;
        self.1.max_output_tokens = tokens;
        self.1.sampling = sampling;
        Ok(())
    }
    fn export_checkpoint(&mut self) -> Result<String, CoreError> {
        self.checkpoint(None)
    }
    fn restore_checkpoint(&mut self, checkpoint: &str) -> Result<(), CoreError> {
        self.checkpoint(Some(checkpoint.to_owned())).map(|_| ())
    }
    fn send(&mut self, text: &str) -> Result<ToolTurn, CoreError> {
        self.send_message(&CoreMessage::text(text))
    }
    fn send_message(&mut self, message: &CoreMessage) -> Result<ToolTurn, CoreError> {
        message.validate(&self.0.worker.modalities)?;
        self.turn(ToolInput::User(message.clone()))
    }
    fn respond(&mut self, results: Vec<ToolResult>) -> Result<ToolTurn, CoreError> {
        self.turn(ToolInput::Results(results))
    }
    fn send_stream(
        &mut self,
        text: &str,
        consumer: Box<dyn FnMut(String) -> bool + Send>,
        cancel: Arc<AtomicBool>,
    ) -> Result<ToolTurn, CoreError> {
        self.send_message_stream(&CoreMessage::text(text), consumer, cancel)
    }
    fn send_message_stream(
        &mut self,
        message: &CoreMessage,
        mut consumer: Box<dyn FnMut(String) -> bool + Send>,
        cancel: Arc<AtomicBool>,
    ) -> Result<ToolTurn, CoreError> {
        self.send_message_events(
            message,
            Box::new(move |event| match event {
                ConversationDelta::Text(text) => consumer(text),
                ConversationDelta::Reasoning(_) => true,
            }),
            cancel,
        )
    }
    fn send_message_events(
        &mut self,
        message: &CoreMessage,
        consumer: Box<dyn FnMut(ConversationDelta) -> bool + Send>,
        cancel: Arc<AtomicBool>,
    ) -> Result<ToolTurn, CoreError> {
        message.validate(&self.0.worker.modalities)?;
        self.stream(ToolInput::User(message.clone()), consumer, cancel)
    }
    fn respond_stream(
        &mut self,
        results: Vec<ToolResult>,
        mut consumer: Box<dyn FnMut(String) -> bool + Send>,
        cancel: Arc<AtomicBool>,
    ) -> Result<ToolTurn, CoreError> {
        self.respond_events(
            results,
            Box::new(move |event| match event {
                ConversationDelta::Text(text) => consumer(text),
                ConversationDelta::Reasoning(_) => true,
            }),
            cancel,
        )
    }
    fn respond_events(
        &mut self,
        results: Vec<ToolResult>,
        consumer: Box<dyn FnMut(ConversationDelta) -> bool + Send>,
        cancel: Arc<AtomicBool>,
    ) -> Result<ToolTurn, CoreError> {
        self.stream(ToolInput::Results(results), consumer, cancel)
    }
}
struct Chat {
    worker: Arc<Worker>,
    id: u64,
}
impl Conversation for Chat {
    fn import_portable_history(
        &mut self,
        history: Vec<crate::history::HistoryTurn>,
    ) -> Result<(), CoreError> {
        let history = portable_native_history(&history, &self.worker.modalities)?;
        let (tx, rx) = mpsc::channel();
        self.worker
            .sender
            .send(Command::ImportChat(self.id, history, tx))
            .map_err(|_| failure("worker-stopped"))?;
        rx.recv().map_err(|_| failure("worker-stopped"))?
    }
    fn restore_checkpoint_with_thinking(
        &mut self,
        checkpoint: &str,
        enabled: bool,
    ) -> Result<(), CoreError> {
        let (tx, rx) = mpsc::channel();
        self.worker
            .sender
            .send(Command::ToolCheckpoint(
                self.id,
                Some(checkpoint.to_owned()),
                Some(enabled),
                tx,
            ))
            .map_err(|_| failure("worker-stopped"))?;
        rx.recv()
            .map_err(|_| failure("worker-stopped"))?
            .map(|_| ())
    }
    fn restore_history_with_thinking(
        &mut self,
        messages: Vec<(String, String)>,
        enabled: bool,
    ) -> Result<(), CoreError> {
        crate::validate_history(&messages)?;
        let (tx, rx) = mpsc::channel();
        self.worker
            .sender
            .send(Command::Restore(self.id, messages, Some(enabled), tx))
            .map_err(|_| failure("worker-stopped"))?;
        rx.recv().map_err(|_| failure("worker-stopped"))?
    }
    fn set_thinking(&mut self, enabled: bool) -> Result<(), CoreError> {
        let (tx, rx) = mpsc::channel();
        self.worker
            .sender
            .send(Command::Thinking(self.id, enabled, tx))
            .map_err(|_| failure("worker-stopped"))?;
        rx.recv().map_err(|_| failure("worker-stopped"))?
    }
    fn configure_context(
        &mut self,
        policy: Option<working_context::SharedContextPolicy>,
    ) -> Result<(), CoreError> {
        let (tx, rx) = mpsc::channel();
        self.worker
            .sender
            .send(Command::ContextPolicy(self.id, policy, tx))
            .map_err(|_| failure("worker-stopped"))?;
        rx.recv().map_err(|_| failure("worker-stopped"))?
    }
    fn context_usage(&mut self) -> Result<Option<working_context::ContextUsage>, CoreError> {
        let (tx, rx) = mpsc::channel();
        self.worker
            .sender
            .send(Command::ContextUsage(self.id, tx))
            .map_err(|_| failure("worker-stopped"))?;
        rx.recv().map_err(|_| failure("worker-stopped"))?
    }
    fn export_checkpoint(&mut self) -> Result<String, CoreError> {
        let (tx, rx) = mpsc::channel();
        self.worker
            .sender
            .send(Command::ToolCheckpoint(self.id, None, None, tx))
            .map_err(|_| failure("worker-stopped"))?;
        rx.recv().map_err(|_| failure("worker-stopped"))?
    }
    fn restore_checkpoint(&mut self, checkpoint: &str) -> Result<(), CoreError> {
        let (tx, rx) = mpsc::channel();
        self.worker
            .sender
            .send(Command::ToolCheckpoint(
                self.id,
                Some(checkpoint.to_owned()),
                None,
                tx,
            ))
            .map_err(|_| failure("worker-stopped"))?;
        rx.recv()
            .map_err(|_| failure("worker-stopped"))?
            .map(|_| ())
    }
    fn reconfigure(
        &mut self,
        tokens: u32,
        sampling: Option<SamplingOptions>,
    ) -> Result<(), CoreError> {
        let (tx, rx) = mpsc::channel();
        self.worker
            .sender
            .send(Command::Reconfigure(self.id, tokens, sampling, tx))
            .map_err(|_| failure("worker-stopped"))?;
        rx.recv().map_err(|_| failure("worker-stopped"))?
    }
    fn history(&mut self) -> Result<Vec<(String, String)>, CoreError> {
        let (tx, rx) = mpsc::channel();
        self.worker
            .sender
            .send(Command::History(self.id, tx))
            .map_err(|_| failure("worker-stopped"))?;
        rx.recv().map_err(|_| failure("worker-stopped"))?
    }

    fn restore_history(&mut self, messages: Vec<(String, String)>) -> Result<(), CoreError> {
        crate::validate_history(&messages)?;
        let (tx, rx) = mpsc::channel();
        self.worker
            .sender
            .send(Command::Restore(self.id, messages, None, tx))
            .map_err(|_| failure("worker-stopped"))?;
        rx.recv().map_err(|_| failure("worker-stopped"))?
    }
    fn send(&mut self, text: &str) -> Result<String, CoreError> {
        self.send_message(&CoreMessage::text(text))
    }

    fn send_message(&mut self, message: &CoreMessage) -> Result<String, CoreError> {
        message.validate(&self.worker.modalities)?;
        let (tx, rx) = mpsc::channel();
        self.worker
            .sender
            .send(Command::Send(self.id, message.clone(), tx))
            .map_err(|_| failure("worker-stopped"))?;
        rx.recv().map_err(|_| failure("worker-stopped"))?
    }

    fn send_stream(
        &mut self,
        text: &str,
        consumer: Box<dyn FnMut(String) -> bool + Send>,
        cancel: Arc<AtomicBool>,
    ) -> Result<StreamOutcome, CoreError> {
        self.send_message_stream(&CoreMessage::text(text), consumer, cancel)
    }

    fn send_message_stream(
        &mut self,
        message: &CoreMessage,
        mut consumer: Box<dyn FnMut(String) -> bool + Send>,
        cancel: Arc<AtomicBool>,
    ) -> Result<StreamOutcome, CoreError> {
        self.send_message_events(
            message,
            Box::new(move |event| match event {
                ConversationDelta::Text(text) => consumer(text),
                ConversationDelta::Reasoning(_) => true,
            }),
            cancel,
        )
    }

    fn send_message_events(
        &mut self,
        message: &CoreMessage,
        consumer: Box<dyn FnMut(ConversationDelta) -> bool + Send>,
        cancel: Arc<AtomicBool>,
    ) -> Result<StreamOutcome, CoreError> {
        message.validate(&self.worker.modalities)?;
        let (tx, rx) = mpsc::channel();
        self.worker
            .sender
            .send(Command::Stream(
                self.id,
                message.clone(),
                consumer,
                cancel,
                tx,
            ))
            .map_err(|_| failure("worker-stopped"))?;
        rx.recv().map_err(|_| failure("worker-stopped"))?
    }
}
impl Drop for Chat {
    fn drop(&mut self) {
        let _ = self.worker.sender.send(Command::Close(self.id));
    }
}

fn run_worker(
    api: &Arc<Api>,
    engine: &Resource<ffi::LiteRtLmEngine>,
    tokens: u32,
    receiver: mpsc::Receiver<Command>,
) {
    let mut chats: BTreeMap<u64, ChatState> = BTreeMap::new();
    let mut next_id = 0u64;
    while let Ok(command) = receiver.recv() {
        let (command, stream) = match command {
            Command::ToolStream(id, input, consumer, cancel, reply) => {
                (Command::Tool(id, input, reply), Some((consumer, cancel)))
            }
            other => (other, None),
        };
        match command {
            Command::ContextPolicy(id, policy, reply) => {
                let result = chats
                    .get_mut(&id)
                    .ok_or_else(|| failure("conversation-closed"))
                    .and_then(|chat| {
                        if chat.stopped || !chat.pending.is_empty() {
                            return Err(failure("context-policy-requires-completed-turn"));
                        }
                        require_context_accounting(policy.as_ref())?;
                        Ok(())
                    });
                let _ = reply.send(result);
            }
            Command::ContextUsage(id, reply) => {
                let _ = reply.send(
                    chats
                        .get(&id)
                        .ok_or_else(|| failure("conversation-closed"))
                        .and_then(|_| Err(failure("context-accounting-unsupported:litertlm"))),
                );
            }
            Command::ImportChat(id, history, reply) => {
                let result = chats
                    .get_mut(&id)
                    .ok_or_else(|| failure("conversation-closed"))
                    .and_then(|chat| import_chat_state(chat, history));
                let _ = reply.send(result);
            }
            Command::ToolsEnabled(id, enabled, reply) => {
                let result = chats
                    .get(&id)
                    .ok_or_else(|| failure("conversation-closed"))
                    .and_then(|chat| validate_tool_switch(chat, enabled))
                    .map(|()| {
                        let chat = chats.get_mut(&id).unwrap();
                        if chat.tools_enabled == enabled {
                            return;
                        }
                        // Defer native replay until the next inference request.
                        suspend_other_chats(&mut chats, id);
                        let chat = chats.get_mut(&id).unwrap();
                        chat.live.take();
                        chat.tools_enabled = enabled;
                    });
                let _ = reply.send(result);
            }
            Command::Reconfigure(id, output_tokens, sampling, reply) => {
                let result = chats
                    .get(&id)
                    .ok_or_else(|| failure("conversation-closed"))
                    .and_then(|chat| reconfiguration_options(chat, tokens, output_tokens, sampling))
                    .map(|options| {
                        suspend_other_chats(&mut chats, id);
                        let chat = chats.get_mut(&id).unwrap();
                        // Reopen with the new settings on the next request.
                        chat.live.take();
                        chat.options = options;
                    });
                let _ = reply.send(result);
            }
            Command::Thinking(id, enabled, reply) => {
                let result = chats
                    .get_mut(&id)
                    .ok_or_else(|| failure("conversation-closed"))
                    .and_then(|chat| {
                        let options = thinking_options(chat, enabled)?;
                        if chat.options.thinking == enabled {
                            return Ok(());
                        }
                        // The native setter applies at conversation creation.
                        // Preserve owned history and the loaded model; reopen
                        // only this native conversation on its next turn.
                        chat.live.take();
                        chat.options = options;
                        Ok(())
                    });
                let _ = reply.send(result);
            }
            Command::ToolStream(..) => unreachable!("normalized above"),
            Command::ToolCheckpoint(id, snapshot, thinking, reply) => {
                let result = chats
                    .get_mut(&id)
                    .ok_or_else(|| failure("conversation-closed"))
                    .and_then(|chat| {
                        if !chat.pending.is_empty() || chat.stopped {
                            return Err(failure("tool-history-unbalanced"));
                        }
                        if let Some(snapshot) = snapshot {
                            if !chat.history.is_empty() {
                                return Err(CoreError::InvalidRequest);
                            }
                            // Validate completely before changing native state. Replay is
                            // deferred to recover(), never to an executor callback.
                            let history = if thinking.is_some() {
                                thinking_checkpoint_history(&snapshot, &chat.tools, &chat.options)?
                            } else {
                                tool_checkpoint_history(&snapshot, &chat.tools, &chat.options)?
                            };
                            let enabled = checkpoint_tools_enabled(&snapshot)?;
                            chat.live.take();
                            chat.history_bytes = history.iter().map(|m| m.to_string().len()).sum();
                            chat.history = history;
                            chat.tools_enabled = enabled;
                            if let Some(thinking) = thinking {
                                chat.options.thinking = thinking;
                            }
                            Ok(String::new())
                        } else {
                            let snapshot = tool_checkpoint_enabled(
                                &chat.history,
                                &chat.tools,
                                &chat.options,
                                chat.tools_enabled,
                            );
                            tool_checkpoint_history(&snapshot, &chat.tools, &chat.options)?;
                            Ok(snapshot)
                        }
                    });
                // An invalid snapshot must not destroy a fresh usable conversation.
                let _ = reply.send(result);
            }
            Command::History(id, reply) => {
                let result = chats
                    .get(&id)
                    .ok_or_else(|| failure("conversation-closed"))
                    .and_then(|chat| {
                        if !chat.tools.is_empty()
                            || chat.options.thinking
                            || chat.history.iter().any(|message| {
                                message.get("reasoning_content").is_some()
                                    || message["content"].as_array().is_some_and(|parts| {
                                        parts.iter().any(|part| part["type"] != "text")
                                    })
                            })
                        {
                            return Err(failure("media-history-export-unsupported"));
                        }
                        Ok(chat
                            .history
                            .iter()
                            .map(|message| {
                                (
                                    message["role"].as_str().unwrap_or_default().to_string(),
                                    message["content"]
                                        .as_array()
                                        .unwrap()
                                        .iter()
                                        .map(|part| part["text"].as_str().unwrap_or_default())
                                        .collect::<String>(),
                                )
                            })
                            .collect())
                    });
                let _ = reply.send(result);
            }
            Command::Restore(id, messages, thinking, reply) => {
                suspend_other_chats(&mut chats, id);
                let result = chats.get_mut(&id).ok_or_else(|| failure("conversation-closed"))
                    .and_then(|chat| {
                        if !chat.history.is_empty() { return Err(CoreError::InvalidRequest); }
                        let history: Vec<_> = messages.into_iter().map(|(role, text)|
                            serde_json::json!({"role":role,"content":[{"type":"text","text":text}]})).collect();
                        // The engine permits one live chat. A failed replay must
                        // be reported to the caller, which invalidates this handle.
                        chat.live.take();
                        // Selection needs the next input's cost. Do not replay an
                        // oversized full transcript while restoring a checkpoint.
                        chat.history_bytes = history.iter().map(|message| message.to_string().len()).sum();
                        chat.history = history;
                        chat.stopped = false;
                        if let Some(thinking) = thinking { chat.options.thinking = thinking; }
                        Ok(())
                    });
                let _ = reply.send(result);
            }
            Command::Open(options, tools, reply) => {
                let result = validate_open(chats.len(), tokens, &options)
                    .and_then(|()| unsafe {
                        suspend_other_chats(&mut chats, u64::MAX);
                        let live = open_chat(api, engine, tokens, options.clone(), &[], &tools)?;
                        Ok(ChatState {
                            live: Some(live),
                            options,
                            history: vec![],
                            stopped: false,
                            history_bytes: 0,
                            tools,
                            tools_enabled: true,
                            pending: vec![],
                        })
                    })
                    .and_then(|chat| {
                        next_id = next_id
                            .checked_add(1)
                            .ok_or_else(|| failure("conversation-id-exhausted"))?;
                        chats.insert(next_id, chat);
                        Ok(next_id)
                    });
                let _ = reply.send(result);
            }
            Command::Tool(id, input, reply) => {
                suspend_other_chats(&mut chats, id);
                let result = chats
                    .get_mut(&id)
                    .ok_or_else(|| failure("conversation-closed"))
                    .and_then(|chat| unsafe {
                        let completing_tools = matches!(&input, ToolInput::Results(_));
                        let input = encode_tool_input(&input, &chat.pending)?;
                        chat.admit(&input)?;
                        chat.recover(api, engine, tokens)?;
                        let live = chat
                            .live
                            .as_ref()
                            .ok_or_else(|| failure("conversation-closed"))?;
                        let raw = match stream {
                            Some((consumer, cancel)) => {
                                stream_tool_input(api, live, &input, consumer, &cancel)?
                            }
                            None => send_raw(api, live, &input)?,
                        };
                        let turn = parse_tool_turn_with_completion(
                            &raw,
                            chat.active_tools(),
                            chat.history.len(),
                            completing_tools,
                        )?;
                        if chat.history.len() + 2 > 200
                            || chat
                                .history_bytes
                                .saturating_add(input.to_string().len())
                                .saturating_add(raw.to_string().len())
                                > 64 * 1024 * 1024
                        {
                            return Err(failure("conversation-history-limit"));
                        }
                        chat.history_bytes += input.to_string().len() + raw.to_string().len();
                        // Preserve complete native assistant calls and role=tool results for replay.
                        chat.history.push(input);
                        chat.history.push(raw);
                        chat.pending = turn.calls.clone();
                        Ok(turn)
                    });
                // No reuse after an unbalanced or failed native turn.
                if result.is_err() {
                    chats.remove(&id);
                }
                let _ = reply.send(result);
            }
            Command::Send(id, message, reply) => {
                suspend_other_chats(&mut chats, id);
                let result = chats
                    .get_mut(&id)
                    .ok_or_else(|| failure("conversation-closed"))
                    .and_then(|chat| unsafe {
                        let input = encode_input(&message);
                        chat.admit(&input)?;
                        chat.recover(api, engine, tokens)?;
                        let raw = send_raw(
                            api,
                            chat.live
                                .as_ref()
                                .ok_or_else(|| failure("conversation-closed"))?,
                            &input,
                        )?;
                        let reply = parse_reply(&raw.to_string())?;
                        let content = response_content(&raw, false)?;
                        chat.record_content(input, &content);
                        Ok(reply)
                    });
                // Native failure may have partially mutated history. Fail closed:
                // do not allow another turn on a possibly inconsistent session.
                if result.is_err() {
                    chats.remove(&id);
                }
                let _ = reply.send(result);
            }
            Command::Stream(id, message, mut consumer, cancel, reply) => {
                if !cancel.load(Ordering::Acquire) {
                    suspend_other_chats(&mut chats, id);
                }
                let result = chats
                    .get_mut(&id)
                    .ok_or_else(|| failure("conversation-closed"))
                    .and_then(|chat| unsafe {
                        if cancel.load(Ordering::Acquire) {
                            return Ok(StreamOutcome::Cancelled);
                        }
                        let input = encode_input(&message);
                        chat.admit(&input)?;
                        chat.recover(api, engine, tokens)?;
                        let (outcome, output) = stream_input_events(
                            api,
                            chat.live
                                .as_ref()
                                .ok_or_else(|| failure("conversation-closed"))?,
                            &input,
                            &mut consumer,
                            &cancel,
                        )?;
                        chat.record_content(input, &output);
                        chat.stopped = outcome == StreamOutcome::Cancelled;
                        Ok(outcome)
                    });
                if result.is_err() {
                    chats.remove(&id);
                }
                let _ = reply.send(result);
            }
            Command::Close(id) => {
                chats.remove(&id);
            }
            Command::Shutdown => break,
        }
    }
}

// Called only on the engine's owning thread, between completed native turns.
// Logical histories (including owned media) survive, but at most one native
// conversation occupies the engine. Replay never mixes two chat histories.
fn suspend_other_chats(chats: &mut BTreeMap<u64, ChatState>, selected: u64) {
    for (id, chat) in chats.iter_mut() {
        if *id != selected {
            chat.live.take();
        }
    }
}

fn validate_open(
    active: usize,
    tokens: u32,
    options: &ConversationOptions,
) -> Result<(), CoreError> {
    if let Some(sampling) = &options.sampling {
        sampling.validate()?;
    }
    if options.max_output_tokens == 0 || options.max_output_tokens > tokens {
        return Err(CoreError::InvalidRequest);
    }
    // Bound retained logical histories. This is not a hardware memory budget.
    if active >= 16 {
        return Err(failure("conversation-count-limit"));
    }
    Ok(())
}

#[cfg(test)]
fn message(role: &str, text: &str) -> CString {
    CString::new(
        serde_json::json!({"role":role,"content":[{"type":"text","text":text}]}).to_string(),
    )
    .expect("JSON escapes embedded NUL bytes")
}

fn system_message(text: &str) -> CString {
    // The C API wraps this content in its own system-role message.
    CString::new(serde_json::to_string(text).expect("strings serialize as JSON"))
        .expect("JSON escapes embedded NUL bytes")
}

fn encoder_backend(
    modalities: &std::collections::BTreeSet<InputModality>,
    modality: InputModality,
) -> *const std::ffi::c_char {
    if modalities.contains(&modality) {
        c"cpu".as_ptr()
    } else {
        ptr::null()
    }
}

fn encode_input(message: &CoreMessage) -> serde_json::Value {
    let parts: Vec<_> = message.parts.iter().map(|part| match part {
        MessagePart::Text(text) => serde_json::json!({"type":"text", "text":text}),
        MessagePart::Image(bytes) => serde_json::json!({"type":"image", "blob":base64::engine::general_purpose::STANDARD.encode(bytes)}),
        MessagePart::Audio(bytes) => serde_json::json!({"type":"audio", "blob":base64::engine::general_purpose::STANDARD.encode(bytes)}),
    }).collect();
    serde_json::json!({"role":"user", "content":parts})
}

unsafe fn open_chat(
    api: &Api,
    engine: &Resource<ffi::LiteRtLmEngine>,
    tokens: u32,
    options: ConversationOptions,
    history: &[serde_json::Value],
    tools: &[ToolDefinition],
) -> Result<Resource<ffi::LiteRtLmConversation>, CoreError> {
    if let Some(sampling) = &options.sampling {
        sampling.validate()?;
    }
    if options.max_output_tokens == 0 || options.max_output_tokens > tokens {
        return Err(CoreError::InvalidRequest);
    }
    let session = Resource::new(
        (api.0.litert_lm_session_config_create)(),
        api.0.litert_lm_session_config_delete,
        "session-config-create",
    )?;
    (api.0.litert_lm_session_config_set_max_output_tokens)(
        session.0,
        options.max_output_tokens as i32,
    );
    let sampler = if let Some(sampling) = &options.sampling {
        let params = Resource::new(
            (api.0.litert_lm_sampler_params_create)(if sampling.temperature == 0.0 {
                3
            } else {
                2
            }),
            api.0.litert_lm_sampler_params_delete,
            "sampler-create",
        )?;
        (api.0.litert_lm_sampler_params_set_temperature)(params.0, sampling.temperature);
        (api.0.litert_lm_sampler_params_set_top_k)(params.0, sampling.top_k as i32);
        (api.0.litert_lm_sampler_params_set_top_p)(params.0, sampling.top_p);
        (api.0.litert_lm_sampler_params_set_seed)(params.0, sampling.seed as i32);
        (api.0.litert_lm_session_config_set_sampler_params)(session.0, params.0);
        Some(params)
    } else {
        None
    };
    // Keep sampler parameters alive until native configuration/conversation
    // creation has consumed them, rather than assuming a borrowed C lifetime.
    let _sampler = sampler;
    let config = Resource::new(
        (api.0.litert_lm_conversation_config_create)(),
        api.0.litert_lm_conversation_config_delete,
        "conversation-config-create",
    )?;
    (api.0.litert_lm_conversation_config_set_session_config)(config.0, session.0);
    if !tools.is_empty() {
        let declarations: Vec<_> = tools.iter().map(|tool| serde_json::json!({"type":"function","function":{"name":tool.name,"description":tool.description,"parameters":tool.parameters}})).collect();
        let json = CString::new(serde_json::to_string(&declarations).unwrap()).unwrap();
        (api.0.litert_lm_conversation_config_set_tools)(config.0, json.as_ptr());
    }
    // Native tool conversations constrain generation; host validation and
    // authorization remain independent checks before execution.
    (api.0
        .litert_lm_conversation_config_set_enable_constrained_decoding)(
        config.0,
        constrained_tool_decoding(tools),
    );
    let thinking = Resource::new(
        (api.0.litert_lm_thinking_config_create)(),
        api.0.litert_lm_thinking_config_delete,
        "thinking-config-create",
    )?;
    (api.0.litert_lm_thinking_config_set_enable_thinking)(thinking.0, options.thinking);
    (api.0.litert_lm_conversation_config_set_thinking_config)(config.0, thinking.0);
    if let Some(system) = options.system_prompt {
        (api.0.litert_lm_conversation_config_set_system_message)(
            config.0,
            system_message(&system).as_ptr(),
        );
    }
    if !history.is_empty() {
        let messages = CString::new(serde_json::Value::Array(history.to_vec()).to_string())
            .expect("JSON escapes NUL");
        (api.0.litert_lm_conversation_config_set_messages)(config.0, messages.as_ptr());
    }
    Resource::new(
        (api.0.litert_lm_conversation_create)(engine.0, config.0),
        api.0.litert_lm_conversation_delete,
        "conversation-create",
    )
}

struct ChatState {
    live: Option<Resource<ffi::LiteRtLmConversation>>,
    options: ConversationOptions,
    history: Vec<serde_json::Value>,
    stopped: bool,
    history_bytes: usize,
    tools: Vec<ToolDefinition>,
    tools_enabled: bool,
    pending: Vec<ToolCall>,
}

fn portable_native_history(
    turns: &[crate::history::HistoryTurn],
    supported: &BTreeSet<InputModality>,
) -> Result<Vec<serde_json::Value>, CoreError> {
    crate::history::validate(turns, supported)?;
    Ok(turns.iter().flat_map(|turn| [encode_input(&turn.input), serde_json::json!({
        "role": "assistant", "content": [{"type":"text", "text":turn.assistant_context()}]
    })]).collect())
}

fn import_chat_state(
    chat: &mut ChatState,
    history: Vec<serde_json::Value>,
) -> Result<(), CoreError> {
    // Nonempty imports belong to a fresh conversation. An explicit empty
    // transcript clears completed context while preserving settings/catalog.
    if (!chat.history.is_empty() && !history.is_empty()) || !chat.pending.is_empty() || chat.stopped
    {
        return Err(failure("chat-import-requires-fresh-conversation"));
    }
    let snapshot = tool_checkpoint_enabled(&history, &[], &chat.options, true);
    let history = tool_checkpoint_history(&snapshot, &[], &chat.options)?;
    chat.live.take();
    chat.history_bytes = history.iter().map(|m| m.to_string().len()).sum();
    chat.history = history;
    Ok(())
}

fn require_context_accounting(
    policy: Option<&working_context::SharedContextPolicy>,
) -> Result<(), CoreError> {
    if policy.is_some() {
        return Err(failure("context-accounting-unsupported:litertlm"));
    }
    Ok(())
}
fn validate_tool_switch(chat: &ChatState, enabled: bool) -> Result<(), CoreError> {
    if chat.stopped || !chat.pending.is_empty() {
        return Err(failure("tool-switching-requires-completed-turn"));
    }
    if enabled && chat.tools.is_empty() {
        return Err(failure("tool-switching-requires-supplied-catalog"));
    }
    let snapshot = tool_checkpoint_enabled(
        &chat.history,
        &chat.tools,
        &chat.options,
        chat.tools_enabled,
    );
    tool_checkpoint_history(&snapshot, &chat.tools, &chat.options)?;
    Ok(())
}
fn reconfiguration_options(
    chat: &ChatState,
    context: u32,
    output: u32,
    sampling: Option<SamplingOptions>,
) -> Result<ConversationOptions, CoreError> {
    if !chat.pending.is_empty() || chat.stopped {
        return Err(failure("reconfiguration-requires-completed-turn"));
    }
    let mut options = chat.options.clone();
    options.max_output_tokens = output;
    options.sampling = sampling;
    validate_open(0, context, &options)?;
    Ok(options)
}
fn thinking_options(chat: &ChatState, enabled: bool) -> Result<ConversationOptions, CoreError> {
    if !chat.pending.is_empty() || chat.stopped {
        return Err(failure("thinking-reconfiguration-requires-completed-turn"));
    }
    let mut options = chat.options.clone();
    options.thinking = enabled;
    Ok(options)
}
impl ChatState {
    fn active_tools(&self) -> &[ToolDefinition] {
        if self.tools_enabled {
            &self.tools
        } else {
            &[]
        }
    }
    unsafe fn recover(
        &mut self,
        api: &Api,
        engine: &Resource<ffi::LiteRtLmEngine>,
        tokens: u32,
    ) -> Result<(), CoreError> {
        if self.stopped || self.live.is_none() {
            // Delete before recreating: upstream supports one native conversation.
            self.live.take();
            self.live = Some(open_chat(
                api,
                engine,
                tokens,
                self.options.clone(),
                &self.history,
                self.active_tools(),
            )?);
            self.stopped = false;
        }
        Ok(())
    }
    fn admit(&self, input: &serde_json::Value) -> Result<(), CoreError> {
        if self.history.len() >= 200
            || self.history_bytes.saturating_add(input.to_string().len()) > 64 * 1024 * 1024
        {
            return Err(failure("conversation-history-limit"));
        }
        Ok(())
    }
    #[cfg(test)]
    fn record(&mut self, input: serde_json::Value, output: &str) {
        self.record_content(
            input,
            &ResponseContent {
                text: output.to_owned(),
                reasoning: String::new(),
            },
        );
    }
    fn record_content(&mut self, input: serde_json::Value, output: &ResponseContent) {
        let mut response =
            serde_json::json!({"role":"assistant","content":[{"type":"text","text":output.text}]});
        if !output.reasoning.is_empty() {
            response["reasoning_content"] = serde_json::json!(output.reasoning);
        }
        self.history_bytes = self
            .history_bytes
            .saturating_add(input.to_string().len())
            .saturating_add(response.to_string().len());
        self.history.push(input);
        self.history.push(response);
    }
}

struct CallbackState {
    api: Arc<Api>,
    chunks: mpsc::SyncSender<Result<String, CoreError>>,
    terminal: mpsc::Sender<Result<(), CoreError>>,
    overflow: Arc<AtomicBool>,
    raw: bool,
}

fn stream_generation_failure(message: &CStr) -> CoreError {
    let detail: String = message.to_string_lossy().chars().take(2048).collect();
    if detail.trim().is_empty() {
        failure("stream-generation-failed")
    } else {
        failure(&format!("stream-generation-failed: {detail}"))
    }
}

// The pinned upstream callback ABI borrows both chunk and text only for this
// call. Own the callback state locally and copy text before handing it off.
unsafe extern "C" fn stream_callback(
    data: *mut std::ffi::c_void,
    chunk: *const ffi::LiteRtLmStreamChunk,
) {
    let pointer = data.cast::<CallbackState>();
    Arc::increment_strong_count(pointer);
    let state = Arc::from_raw(pointer);
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if chunk.is_null() {
            let _ = state.chunks.try_send(Err(failure("stream-chunk-missing")));
            state.overflow.store(true, Ordering::Release);
            return;
        }
        let native_error = (state.api.0.litert_lm_stream_chunk_get_error)(chunk);
        if !native_error.is_null() {
            // The error is borrowed only during this callback, just like text.
            // Copy its diagnostic before forwarding the terminal/chunk result.
            let error = stream_generation_failure(CStr::from_ptr(native_error));
            if (state.api.0.litert_lm_stream_chunk_is_final)(chunk) {
                let _ = state.terminal.send(Err(error));
            } else {
                let _ = state.chunks.try_send(Err(error));
                state.overflow.store(true, Ordering::Release);
            }
            return;
        }
        let text = (state.api.0.litert_lm_stream_chunk_get_text)(chunk);
        if !text.is_null() {
            let owned = CStr::from_ptr(text)
                .to_str()
                .map_err(|_| failure("response-encoding"))
                .and_then(|json| {
                    if state.raw {
                        Ok(json.to_owned())
                    } else {
                        parse_reply_inner(json, true)
                    }
                });
            if state.chunks.try_send(owned).is_err() {
                state.overflow.store(true, Ordering::Release);
            }
        }
        if (state.api.0.litert_lm_stream_chunk_is_final)(chunk) {
            let _ = state.terminal.send(Ok(()));
        }
    }));
    if result.is_err() {
        let _ = state
            .chunks
            .try_send(Err(failure("stream-callback-failed")));
        state.overflow.store(true, Ordering::Release);
        if !chunk.is_null() && (state.api.0.litert_lm_stream_chunk_is_final)(chunk) {
            let _ = state.terminal.send(Err(failure("stream-callback-failed")));
        }
    }
}

unsafe fn stream_input_events(
    api: &Arc<Api>,
    chat: &Resource<ffi::LiteRtLmConversation>,
    input: &serde_json::Value,
    consumer: &mut Box<dyn FnMut(ConversationDelta) -> bool + Send>,
    cancel: &Arc<AtomicBool>,
) -> Result<(StreamOutcome, ResponseContent), CoreError> {
    let state = Arc::new(std::sync::Mutex::new(ContentStreamAccumulator::default()));
    let collected = state.clone();
    // The existing callback bridge owns native lifetime/cancellation. Decode
    // copied JSON on the engine thread, not inside the borrowed C callback.
    let mut delivery = std::mem::replace(consumer, Box::new(|_| false));
    let mut accepting = true;
    let mut raw_consumer: Box<dyn FnMut(String) -> bool + Send> = Box::new(move |json| {
        if !accepting {
            return false;
        }
        let events = {
            let mut state = collected.lock().expect("content stream lock");
            match state.push(&json) {
                Ok(events) => events,
                Err(error) => {
                    state.error = Some(error);
                    return false;
                }
            }
        };
        accepting = events.into_iter().all(&mut delivery);
        accepting
    });
    let (outcome, _) = stream_input_mode(api, chat, input, &mut raw_consumer, cancel, true)?;
    let mut state = state
        .lock()
        .map_err(|_| failure("stream-consumer-failed"))?;
    if let Some(error) = state.error.take() {
        return Err(error);
    }
    if outcome == StreamOutcome::Completed && state.content.text.is_empty() {
        return Err(failure("response-empty"));
    }
    Ok((outcome, std::mem::take(&mut state.content)))
}

#[derive(Default)]
struct ContentStreamAccumulator {
    content: ResponseContent,
    bytes: usize,
    error: Option<CoreError>,
}
impl ContentStreamAccumulator {
    fn push(&mut self, json: &str) -> Result<Vec<ConversationDelta>, CoreError> {
        self.bytes = self.bytes.saturating_add(json.len());
        if self.bytes > 1_048_576 {
            return Err(failure("response-size-limit"));
        }
        let value: serde_json::Value =
            serde_json::from_str(json).map_err(|_| failure("response-json"))?;
        if value["role"] != "assistant" {
            return Err(failure("response-role"));
        }
        if value.get("tool_calls").is_some_and(|calls| {
            !calls.is_null() && calls.as_array().is_none_or(|calls| !calls.is_empty())
        }) {
            return Err(failure("tool-response-requires-tool-conversation"));
        }
        let delta = response_content(&value, true)?;
        let mut events = Vec::with_capacity(2);
        if !delta.reasoning.is_empty() {
            self.content.reasoning.push_str(&delta.reasoning);
            events.push(ConversationDelta::Reasoning(delta.reasoning));
        }
        if !delta.text.is_empty() {
            self.content.text.push_str(&delta.text);
            events.push(ConversationDelta::Text(delta.text));
        }
        Ok(events)
    }
}

unsafe fn stream_input_mode(
    api: &Arc<Api>,
    chat: &Resource<ffi::LiteRtLmConversation>,
    input: &serde_json::Value,
    consumer: &mut Box<dyn FnMut(String) -> bool + Send>,
    cancel: &Arc<AtomicBool>,
    raw: bool,
) -> Result<(StreamOutcome, String), CoreError> {
    let (tx, chunks) = mpsc::sync_channel(64);
    let (terminal_tx, terminal) = mpsc::channel();
    let overflow = Arc::new(AtomicBool::new(false));
    let state = Arc::new(CallbackState {
        api: api.clone(),
        chunks: tx,
        terminal: terminal_tx,
        overflow: overflow.clone(),
        raw,
    });
    let pointer = Arc::into_raw(state);
    let encoded = CString::new(input.to_string()).expect("JSON escapes NUL");
    let status = (api.0.litert_lm_conversation_send_message_stream)(
        chat.0,
        encoded.as_ptr(),
        ptr::null(),
        ptr::null(),
        Some(stream_callback),
        pointer.cast_mut().cast(),
    );
    if status != 0 {
        drop(Arc::from_raw(pointer));
        return Err(failure("stream-start-failed"));
    }
    let mut stopped = false;
    let mut output = String::new();
    let mut parse_error = None;
    // Never release callback state/conversation merely on timeout. Only an
    // upstream terminal callback establishes the end of callback delivery.
    let result = loop {
        for item in chunks.try_iter() {
            match item {
                Ok(delta) => {
                    if !raw {
                        output.push_str(&delta);
                    }
                    if !stopped && !delta.is_empty() {
                        match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                            consumer(delta)
                        })) {
                            Ok(true) => {}
                            Ok(false) => cancel.store(true, Ordering::Release),
                            Err(_) => {
                                parse_error = Some(failure("stream-consumer-failed"));
                                cancel.store(true, Ordering::Release);
                            }
                        }
                    }
                }
                Err(error) => {
                    parse_error = Some(error);
                    cancel.store(true, Ordering::Release);
                }
            }
        }
        match terminal.try_recv() {
            Ok(result) => break result,
            Err(mpsc::TryRecvError::Disconnected) => break Err(failure("stream-terminal-missing")),
            Err(mpsc::TryRecvError::Empty) => {}
        }
        if !stopped && (cancel.load(Ordering::Acquire) || overflow.load(Ordering::Acquire)) {
            stopped = true;
            (api.0.litert_lm_conversation_cancel_process)(chat.0);
        }
        thread::sleep(Duration::from_millis(2));
    };
    // Drain chunks produced just before the terminal notification.
    for item in chunks.try_iter() {
        match item {
            Ok(delta) => {
                if !raw {
                    output.push_str(&delta);
                }
                if !stopped && !delta.is_empty() {
                    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| consumer(delta)))
                    {
                        Ok(true) => {}
                        Ok(false) => {
                            cancel.store(true, Ordering::Release);
                            stopped = true;
                        }
                        Err(_) => {
                            parse_error = Some(failure("stream-consumer-failed"));
                        }
                    }
                }
            }
            Err(error) => {
                parse_error = Some(error);
            }
        }
    }
    drop(Arc::from_raw(pointer));
    if overflow.load(Ordering::Acquire) {
        return Err(failure("stream-consumer-too-slow"));
    }
    if let Some(error) = parse_error {
        return Err(error);
    }
    if stopped {
        return Ok((StreamOutcome::Cancelled, output));
    }
    result?;
    if output.is_empty() && !raw {
        return Err(failure("response-empty"));
    }
    Ok((StreamOutcome::Completed, output))
}

// Upstream emits parsed tool calls alongside ordinary content deltas.
// Accumulate complete calls for the finished turn; never execute fragments.
#[derive(Default)]
struct ToolStreamAccumulator {
    text: String,
    reasoning: String,
    calls: Vec<serde_json::Value>,
    bytes: usize,
    error: Option<CoreError>,
}
impl ToolStreamAccumulator {
    #[cfg(test)]
    fn push(&mut self, json: &str) -> Result<String, CoreError> {
        Ok(self
            .push_events(json)?
            .into_iter()
            .filter_map(|event| match event {
                ConversationDelta::Text(text) => Some(text),
                ConversationDelta::Reasoning(_) => None,
            })
            .collect())
    }
    fn push_events(&mut self, json: &str) -> Result<Vec<ConversationDelta>, CoreError> {
        self.bytes = self.bytes.saturating_add(json.len());
        if self.bytes > 1_048_576 {
            return Err(failure("response-size-limit"));
        }
        let value: serde_json::Value =
            serde_json::from_str(json).map_err(|_| failure("response-json"))?;
        if value["role"] != "assistant" {
            return Err(failure("response-role"));
        }
        let delta = response_content(&value, true)?;
        if let Some(calls) = value.get("tool_calls").filter(|v| !v.is_null()) {
            self.calls.extend(
                calls
                    .as_array()
                    .ok_or_else(|| failure("response-tool-calls"))?
                    .iter()
                    .cloned(),
            );
            if self.calls.len() > 16 {
                return Err(failure("tool-call-count-limit"));
            }
        }
        let mut events = Vec::with_capacity(2);
        if !delta.reasoning.is_empty() {
            self.reasoning.push_str(&delta.reasoning);
            events.push(ConversationDelta::Reasoning(delta.reasoning));
        }
        if !delta.text.is_empty() {
            self.text.push_str(&delta.text);
            events.push(ConversationDelta::Text(delta.text));
        }
        Ok(events)
    }
    fn message(&self) -> serde_json::Value {
        let mut message = serde_json::json!({"role":"assistant", "content":[{"type":"text","text":self.text}], "tool_calls":self.calls});
        if !self.reasoning.is_empty() {
            message["reasoning_content"] = serde_json::json!(self.reasoning);
        }
        message
    }
}
unsafe fn stream_tool_input(
    api: &Arc<Api>,
    chat: &Resource<ffi::LiteRtLmConversation>,
    input: &serde_json::Value,
    mut consumer: Box<dyn FnMut(ConversationDelta) -> bool + Send>,
    cancel: &Arc<AtomicBool>,
) -> Result<serde_json::Value, CoreError> {
    let accumulator = Arc::new(std::sync::Mutex::new(ToolStreamAccumulator::default()));
    let shared = accumulator.clone();
    let mut accepting = true;
    let mut raw_consumer: Box<dyn FnMut(String) -> bool + Send> = Box::new(move |chunk| {
        if !accepting {
            return false;
        }
        let events = {
            let mut state = shared.lock().expect("single streaming consumer");
            match state.push_events(&chunk) {
                Ok(events) => events,
                Err(error) => {
                    state.error = Some(error);
                    accepting = false;
                    return false;
                }
            }
        };
        accepting = events.into_iter().all(&mut consumer);
        accepting
    });
    let (outcome, _) = stream_input_mode(api, chat, input, &mut raw_consumer, cancel, true)?;
    let mut state = accumulator
        .lock()
        .map_err(|_| failure("stream-consumer-failed"))?;
    if let Some(error) = state.error.take() {
        return Err(error);
    }
    if outcome == StreamOutcome::Cancelled || cancel.load(Ordering::Acquire) {
        return Err(failure("generation-cancelled"));
    }
    Ok(state.message())
}

unsafe fn send_raw(
    api: &Api,
    chat: &Resource<ffi::LiteRtLmConversation>,
    input: &serde_json::Value,
) -> Result<serde_json::Value, CoreError> {
    let response = Resource::new(
        (api.0.litert_lm_conversation_send_message)(
            chat.0,
            CString::new(input.to_string())
                .expect("JSON escapes NUL")
                .as_ptr(),
            ptr::null(),
            ptr::null(),
        ),
        api.0.litert_lm_json_response_delete,
        "generation-failed",
    )?;
    let string = (api.0.litert_lm_json_response_get_string)(response.0);
    if string.is_null() {
        return Err(failure("response-missing"));
    }
    let json = CStr::from_ptr(string)
        .to_str()
        .map_err(|_| failure("response-encoding"))?;
    if json.len() > 1_048_576 {
        return Err(failure("response-size-limit"));
    }
    serde_json::from_str(json).map_err(|_| failure("response-json"))
}

fn checkpoint_catalog(tools: &[ToolDefinition]) -> serde_json::Value {
    serde_json::json!(tools
        .iter()
        .map(|t| serde_json::json!({
            "name": t.name, "description": t.description, "parameters": t.parameters
        }))
        .collect::<Vec<_>>())
}

#[cfg(test)]
fn tool_checkpoint(
    history: &[serde_json::Value],
    tools: &[ToolDefinition],
    options: &ConversationOptions,
) -> String {
    tool_checkpoint_enabled(history, tools, options, true)
}

fn tool_checkpoint_enabled(
    history: &[serde_json::Value],
    tools: &[ToolDefinition],
    options: &ConversationOptions,
    enabled: bool,
) -> String {
    serde_json::json!({
        "version": 1, "runtime": "litertlm", "tools": checkpoint_catalog(tools),
        "toolsEnabled": enabled,
        "systemPrompt": options.system_prompt, "maxOutputTokens": options.max_output_tokens,
        "sampling": options.sampling,
        "thinking": options.thinking,
        "messages": history.iter().map(|m| {
            let mut message = serde_json::json!({
                "role": m["role"], "content": m["content"], "tool_calls": m["tool_calls"]
            });
            if let Some(reasoning) = m.get("reasoning_content") {
                message["reasoning_content"] = reasoning.clone();
            }
            message
        }).collect::<Vec<_>>()
    })
    .to_string()
}

fn checkpoint_tools_enabled(snapshot: &str) -> Result<bool, CoreError> {
    let value: serde_json::Value =
        serde_json::from_str(snapshot).map_err(|_| CoreError::InvalidRequest)?;
    match value.get("toolsEnabled") {
        None => Ok(true), // Existing checkpoints predate availability switching.
        Some(value) => value.as_bool().ok_or(CoreError::InvalidRequest),
    }
}

fn checkpoint_thinking(value: &serde_json::Value) -> Result<bool, CoreError> {
    match value.get("thinking") {
        None => Ok(false), // Old checkpoints were generated with thinking disabled.
        Some(value) => value.as_bool().ok_or(CoreError::InvalidRequest),
    }
}

// Validate the saved configuration before explicitly changing only the future
// reasoning setting. Model/system/sampler/tool catalog checks remain binding.
fn thinking_checkpoint_history(
    snapshot: &str,
    tools: &[ToolDefinition],
    options: &ConversationOptions,
) -> Result<Vec<serde_json::Value>, CoreError> {
    if snapshot.len() > 16 * 1024 * 1024 {
        return Err(failure("tool-history-size-limit"));
    }
    let value: serde_json::Value =
        serde_json::from_str(snapshot).map_err(|_| CoreError::InvalidRequest)?;
    let mut saved = options.clone();
    saved.thinking = checkpoint_thinking(&value)?;
    tool_checkpoint_history(snapshot, tools, &saved)
}

fn ordinary_checkpoint_history(snapshot: &str) -> Result<Vec<serde_json::Value>, CoreError> {
    if snapshot.len() > 16 * 1024 * 1024 {
        return Err(failure("tool-history-size-limit"));
    }
    let value: serde_json::Value =
        serde_json::from_str(snapshot).map_err(|_| CoreError::InvalidRequest)?;
    if value["tools"] != serde_json::json!([]) {
        return Err(failure("chat-import-requires-ordinary-context"));
    }
    let options = ConversationOptions {
        thinking: checkpoint_thinking(&value)?,
        system_prompt: serde_json::from_value(value["systemPrompt"].clone())
            .map_err(|_| CoreError::InvalidRequest)?,
        max_output_tokens: serde_json::from_value(value["maxOutputTokens"].clone())
            .map_err(|_| CoreError::InvalidRequest)?,
        sampling: serde_json::from_value(value["sampling"].clone())
            .map_err(|_| CoreError::InvalidRequest)?,
    };
    tool_checkpoint_history(snapshot, &[], &options)
}

/// Accepts completed native exchanges with bounded, validated owned media.
/// A checkpoint is context,
/// never authority: current declarations/settings must match; grants are absent.
fn tool_checkpoint_history(
    snapshot: &str,
    tools: &[ToolDefinition],
    options: &ConversationOptions,
) -> Result<Vec<serde_json::Value>, CoreError> {
    if snapshot.len() > 16 * 1024 * 1024 {
        return Err(failure("tool-history-size-limit"));
    }
    let value: serde_json::Value =
        serde_json::from_str(snapshot).map_err(|_| CoreError::InvalidRequest)?;
    checkpoint_tools_enabled(snapshot)?;
    let thinking = checkpoint_thinking(&value)?;
    if value["version"] != 1
        || value["runtime"] != "litertlm"
        || value["tools"] != checkpoint_catalog(tools)
        || value["systemPrompt"] != serde_json::json!(options.system_prompt)
        || value["maxOutputTokens"] != options.max_output_tokens
        || value["sampling"] != serde_json::json!(options.sampling)
        || thinking != options.thinking
    {
        return Err(failure("tool-history-configuration-mismatch"));
    }
    let messages = value["messages"]
        .as_array()
        .ok_or(CoreError::InvalidRequest)?;
    if messages.len() > 10000 {
        return Err(failure("conversation-history-limit"));
    }
    let mut expected = "user";
    let mut pending = vec![];
    for (index, message) in messages.iter().enumerate() {
        if message["role"] != expected {
            return Err(failure("tool-history-unbalanced"));
        }
        if expected != "assistant"
            && (!message["tool_calls"].is_null() || message.get("reasoning_content").is_some())
        {
            return Err(CoreError::InvalidRequest);
        }
        match expected {
            "assistant" => {
                let turn =
                    parse_tool_turn_with_completion(message, tools, index, !pending.is_empty())?;
                pending = turn.calls;
                expected = if pending.is_empty() { "user" } else { "tool" };
            }
            "user" => {
                let parts = message["content"]
                    .as_array()
                    .ok_or(CoreError::InvalidRequest)?;
                if parts.is_empty() || parts.len() > 16 {
                    return Err(CoreError::InvalidRequest);
                }
                let mut decoded = Vec::with_capacity(parts.len());
                for part in parts {
                    if part.as_object().is_none_or(|p| p.len() != 2) {
                        return Err(CoreError::InvalidRequest);
                    }
                    decoded.push(match part["type"].as_str() {
                        Some("text") => MessagePart::Text(
                            part["text"]
                                .as_str()
                                .ok_or(CoreError::InvalidRequest)?
                                .to_owned(),
                        ),
                        Some(kind @ ("image" | "audio")) => {
                            let blob = part["blob"].as_str().ok_or(CoreError::InvalidRequest)?;
                            let bytes = base64::engine::general_purpose::STANDARD
                                .decode(blob)
                                .map_err(|_| CoreError::InvalidRequest)?;
                            if kind == "image" {
                                MessagePart::Image(bytes)
                            } else {
                                MessagePart::Audio(bytes)
                            }
                        }
                        _ => return Err(CoreError::InvalidRequest),
                    });
                }
                CoreMessage { parts: decoded }.validate(
                    &[
                        InputModality::Text,
                        InputModality::Image,
                        InputModality::Audio,
                    ]
                    .into(),
                )?;
                expected = "assistant";
            }
            "tool" => {
                let parts = message["content"]
                    .as_array()
                    .ok_or(CoreError::InvalidRequest)?;
                if parts.len() != pending.len()
                    || parts.iter().zip(&pending).any(|(p, c)| {
                        p["type"] != "tool_response"
                            || p["name"] != c.name
                            || p.get("response").is_none()
                            || p["response"].to_string().len() > 65536
                    })
                {
                    return Err(failure("tool-history-unbalanced"));
                }
                expected = "assistant";
            }
            _ => unreachable!(),
        }
    }
    if expected != "user" {
        return Err(failure("tool-history-unbalanced"));
    }
    Ok(messages.clone())
}

fn constrained_tool_decoding(tools: &[ToolDefinition]) -> bool {
    !tools.is_empty()
}

fn encode_tool_input(
    input: &ToolInput,
    pending: &[ToolCall],
) -> Result<serde_json::Value, CoreError> {
    match input {
        ToolInput::User(message) => {
            if !pending.is_empty() {
                return Err(CoreError::InvalidRequest);
            }
            message.validate(
                &[
                    InputModality::Text,
                    InputModality::Image,
                    InputModality::Audio,
                ]
                .into(),
            )?;
            Ok(encode_input(message))
        }
        ToolInput::Results(results) => {
            crate::tools::validate_results(pending, results)?;
            let content: Vec<_> = pending.iter().zip(results).map(|(call, result)| serde_json::json!({"type":"tool_response","name":call.name,"response":result.value})).collect();
            Ok(serde_json::json!({"role":"tool","content":content}))
        }
    }
}

#[cfg(test)]
fn parse_tool_turn(
    raw: &serde_json::Value,
    tools: &[ToolDefinition],
    turn: usize,
) -> Result<ToolTurn, CoreError> {
    parse_tool_turn_with_completion(raw, tools, turn, false)
}

fn parse_tool_turn_with_completion(
    raw: &serde_json::Value,
    tools: &[ToolDefinition],
    turn: usize,
    completing_tools: bool,
) -> Result<ToolTurn, CoreError> {
    if raw["role"] != "assistant" {
        return Err(failure("response-role"));
    }
    let text = response_content(raw, true)?.text;
    let mut calls = vec![];
    if let Some(value) = raw.get("tool_calls").filter(|v| !v.is_null()) {
        let native = value
            .as_array()
            .ok_or_else(|| failure("response-tool-calls"))?;
        if native.len() > 16 {
            return Err(failure("tool-call-count-limit"));
        }
        for (index, call) in native.iter().enumerate() {
            let function = &call["function"];
            let name = function["name"]
                .as_str()
                .ok_or_else(|| failure("tool-name"))?;
            let arguments = function["arguments"].clone();
            if call["type"] != "function"
                || !arguments.is_object()
                || arguments.to_string().len() > 65536
                || !tools.iter().any(|tool| tool.name == name)
            {
                return Err(failure("tool-call-invalid"));
            }
            calls.push(ToolCall {
                id: format!("{turn}:{index}"),
                name: name.into(),
                arguments,
            });
        }
    }
    // A successfully completed native continuation can end with the tool's
    // structured result and no additional prose. Initial user turns cannot.
    if text.is_empty() && calls.is_empty() && !completing_tools {
        return Err(failure("response-empty"));
    }
    Ok(ToolTurn { text, calls })
}

fn parse_reply(json: &str) -> Result<String, CoreError> {
    parse_reply_inner(json, false)
}

// Upstream channel_util.cc emits reasoning_content separately from content.
// Never infer a reasoning channel from prose, tags or arbitrary channel names.
#[derive(Debug, Default, PartialEq, Eq)]
struct ResponseContent {
    text: String,
    reasoning: String,
}

fn response_content(
    value: &serde_json::Value,
    allow_missing_content: bool,
) -> Result<ResponseContent, CoreError> {
    let reasoning = match value.get("reasoning_content") {
        None | Some(serde_json::Value::Null) => String::new(),
        Some(serde_json::Value::String(text)) => text.clone(),
        _ => return Err(failure("response-reasoning")),
    };
    let parts = match value.get("content").filter(|value| !value.is_null()) {
        None if allow_missing_content => &[][..],
        Some(serde_json::Value::Array(parts)) => parts.as_slice(),
        _ => return Err(failure("response-content")),
    };
    let mut text = String::new();
    for part in parts {
        if part["type"] != "text" {
            return Err(failure(if allow_missing_content {
                "response-part-unsupported"
            } else {
                "response-modality-unsupported"
            }));
        }
        text.push_str(
            part["text"]
                .as_str()
                .ok_or_else(|| failure("response-text"))?,
        );
    }
    if text.len().saturating_add(reasoning.len()) > 1_048_576 {
        return Err(failure("response-size-limit"));
    }
    Ok(ResponseContent { text, reasoning })
}

fn parse_reply_inner(json: &str, allow_empty: bool) -> Result<String, CoreError> {
    let value: serde_json::Value =
        serde_json::from_str(json).map_err(|_| failure("response-json"))?;
    if value["role"] != "assistant" {
        return Err(failure("response-role"));
    }
    if value.get("tool_calls").is_some_and(|calls| {
        !calls.is_null() && calls.as_array().is_none_or(|calls| !calls.is_empty())
    }) {
        return Err(failure("tool-response-requires-tool-conversation"));
    }
    let text = response_content(&value, false)?.text;
    if text.is_empty() && !allow_empty {
        return Err(failure("response-empty"));
    }
    Ok(text)
}

#[cfg(test)]
mod tests {
    #[test]
    fn stream_failure_preserves_bounded_native_details() {
        assert!(
            matches!(stream_generation_failure(c"native context exhausted"),
            CoreError::BackendFailure(message) if message == "stream-generation-failed: native context exhausted")
        );
        assert!(matches!(stream_generation_failure(c""),
            CoreError::BackendFailure(message) if message == "stream-generation-failed"));
        let long = CString::new("é".repeat(3000)).unwrap();
        assert!(matches!(stream_generation_failure(&long),
            CoreError::BackendFailure(message) if message.chars().count() == "stream-generation-failed: ".len() + 2048));
    }
    #[test]
    fn thinking_transition_preserves_history_and_rejects_unbalanced_context() {
        let mut chat = ChatState {
            live: None,
            options: checkpoint_options(),
            history: completed_tool_history(),
            stopped: false,
            history_bytes: 77,
            tools: vec![tool()],
            tools_enabled: true,
            pending: vec![],
        };
        let original = chat.history.clone();
        let changed = thinking_options(&chat, true).unwrap();
        assert!(changed.thinking);
        assert_eq!(changed.system_prompt, chat.options.system_prompt);
        assert_eq!(changed.max_output_tokens, chat.options.max_output_tokens);
        assert_eq!(changed.sampling, chat.options.sampling);
        assert_eq!(chat.history, original);
        assert_eq!(chat.history_bytes, 77);
        chat.pending.push(ToolCall {
            id: "pending".into(),
            name: tool().name,
            arguments: serde_json::json!({}),
        });
        assert!(thinking_options(&chat, true).is_err());
        assert!(thinking_options(&chat, false).is_err());
        chat.pending.clear();
        chat.stopped = true;
        assert!(thinking_options(&chat, true).is_err());
        assert!(!chat.options.thinking);
        assert_eq!(chat.history, original);
    }
    #[test]
    fn explicit_thinking_restore_validates_saved_context_without_relaxing_other_settings() {
        let saved = checkpoint_options();
        let mut future = saved.clone();
        future.thinking = true;
        let snapshot = tool_checkpoint(&completed_tool_history(), &[tool()], &saved);
        assert!(tool_checkpoint_history(&snapshot, &[tool()], &future).is_err());
        let restored = thinking_checkpoint_history(&snapshot, &[tool()], &future).unwrap();
        assert_eq!(
            restored[1]["tool_calls"],
            completed_tool_history()[1]["tool_calls"]
        );
        future.system_prompt = Some("changed".into());
        assert!(thinking_checkpoint_history(&snapshot, &[tool()], &future).is_err());
        future = saved.clone();
        future.max_output_tokens += 1;
        assert!(thinking_checkpoint_history(&snapshot, &[tool()], &future).is_err());
        assert!(thinking_checkpoint_history(&snapshot, &[], &saved).is_err());
        let mut value: serde_json::Value = serde_json::from_str(&snapshot).unwrap();
        value["thinking"] = serde_json::json!("false");
        assert!(thinking_checkpoint_history(&value.to_string(), &[tool()], &saved).is_err());
        assert!(!saved.thinking);
    }
    #[test]
    fn tool_stream_reasoning_stays_separate_from_calls_and_visible_content() {
        let mut stream = ToolStreamAccumulator::default();
        assert_eq!(
            stream
                .push_events(r#"{"role":"assistant","reasoning_content":"choose a tool"}"#)
                .unwrap(),
            vec![ConversationDelta::Reasoning("choose a tool".into())]
        );
        let call = serde_json::json!({"role":"assistant","content":[],"tool_calls":[{"type":"function","function":{"name":tool().name,"arguments":{}}}]});
        assert!(stream.push_events(&call.to_string()).unwrap().is_empty());
        let message = stream.message();
        assert_eq!(message["reasoning_content"], "choose a tool");
        assert_eq!(message["content"][0]["text"], "");
        assert_eq!(
            parse_tool_turn(&message, &[tool()], 0).unwrap().calls.len(),
            1
        );
        assert!(ToolStreamAccumulator::default()
            .push_events(r#"{"role":"assistant","reasoning_content":17}"#)
            .is_err());
    }

    #[test]
    fn thinking_checkpoint_configuration_is_explicit_and_old_snapshots_are_disabled() {
        let mut options = checkpoint_options();
        let mut history = completed_tool_history();
        history[1]["reasoning_content"] = serde_json::json!("consider tool");
        options.thinking = true;
        let snapshot = tool_checkpoint(&history, &[tool()], &options);
        assert!(tool_checkpoint_history(&snapshot, &[tool()], &options).is_ok());
        options.thinking = false;
        assert!(tool_checkpoint_history(&snapshot, &[tool()], &options).is_err());
        let mut value: serde_json::Value = serde_json::from_str(&tool_checkpoint(
            &completed_tool_history(),
            &[tool()],
            &options,
        ))
        .unwrap();
        value.as_object_mut().unwrap().remove("thinking");
        assert!(tool_checkpoint_history(&value.to_string(), &[tool()], &options).is_ok());
        value["thinking"] = serde_json::json!("true");
        assert!(tool_checkpoint_history(&value.to_string(), &[tool()], &options).is_err());
    }
    #[test]
    fn content_stream_emits_canonical_channels_without_guessing_or_duplication() {
        let mut stream = ContentStreamAccumulator::default();
        assert_eq!(stream.push(r#"{"role":"assistant","reasoning_content":"Think","channels":{"thought":"duplicate"}}"#).unwrap(),
            vec![ConversationDelta::Reasoning("Think".into())]);
        assert_eq!(stream.push(r#"{"role":"assistant","content":[{"type":"text","text":"<think>literal</think>"}],"reasoning_content":" more"}"#).unwrap(),
            vec![ConversationDelta::Reasoning(" more".into()), ConversationDelta::Text("<think>literal</think>".into())]);
        assert_eq!(
            stream.content,
            ResponseContent {
                text: "<think>literal</think>".into(),
                reasoning: "Think more".into()
            }
        );
    }

    #[test]
    fn content_stream_rejects_invalid_channels_calls_roles_and_total_size() {
        for input in [
            r#"{"role":"assistant","reasoning_content":42}"#,
            r#"{"role":"user","content":[]}"#,
            r#"{"role":"assistant","tool_calls":[{}]}"#,
            r#"{"role":"assistant","content":[{"type":"audio"}]}"#,
            "not JSON",
        ] {
            assert!(ContentStreamAccumulator::default().push(input).is_err());
        }
        let mut stream = ContentStreamAccumulator {
            bytes: 1_048_576,
            ..Default::default()
        };
        assert!(
            matches!(stream.push(r#"{"role":"assistant","content":[]}"#), Err(CoreError::BackendFailure(code)) if code == "response-size-limit")
        );
    }

    #[test]
    fn content_stream_preserves_delta_boundaries_and_empty_terminal_content() {
        let mut stream = ContentStreamAccumulator::default();
        for text in ["Hello", " ", "world"] {
            let message =
                serde_json::json!({"role":"assistant","content":[{"type":"text","text":text}]});
            assert_eq!(
                stream.push(&message.to_string()).unwrap(),
                vec![ConversationDelta::Text(text.into())]
            );
        }
        assert!(stream
            .push(r#"{"role":"assistant","content":[]}"#)
            .unwrap()
            .is_empty());
        assert_eq!(stream.content.text, "Hello world");
        assert!(stream.content.reasoning.is_empty());
    }

    #[test]
    #[ignore = "requires existing trusted runtime/model/cache paths; no downloads"]
    fn real_model_reports_native_structured_reasoning() {
        let library = std::env::var("OMNIX_REASONING_LIBRARY").unwrap();
        let model = CString::new(std::env::var("OMNIX_REASONING_MODEL").unwrap()).unwrap();
        let cache =
            cache_directory(Path::new(&std::env::var("OMNIX_REASONING_CACHE").unwrap())).unwrap();
        unsafe {
            // Probe structured reasoning through the bound official C API
            // and the same event decoder used by conversation streaming.
            let api = Api::shared(Path::new(&library)).unwrap();
            let settings = Resource::new(
                (api.0.litert_lm_engine_settings_create)(
                    model.as_ptr(),
                    c"cpu".as_ptr(),
                    ptr::null(),
                    ptr::null(),
                ),
                api.0.litert_lm_engine_settings_delete,
                "probe-settings",
            )
            .unwrap();
            (api.0.litert_lm_engine_settings_set_max_num_tokens)(settings.0, 4096);
            (api.0.litert_lm_engine_settings_set_cache_dir)(settings.0, cache.as_ptr());
            let engine = Resource::new(
                (api.0.litert_lm_engine_create)(settings.0),
                api.0.litert_lm_engine_delete,
                "probe-engine",
            )
            .unwrap();
            let session = Resource::new(
                (api.0.litert_lm_session_config_create)(),
                api.0.litert_lm_session_config_delete,
                "probe-session",
            )
            .unwrap();
            (api.0.litert_lm_session_config_set_max_output_tokens)(session.0, 512);
            let thinking = Resource::new(
                (api.0.litert_lm_thinking_config_create)(),
                api.0.litert_lm_thinking_config_delete,
                "probe-thinking",
            )
            .unwrap();
            (api.0.litert_lm_thinking_config_set_enable_thinking)(thinking.0, true);
            let config = Resource::new(
                (api.0.litert_lm_conversation_config_create)(),
                api.0.litert_lm_conversation_config_delete,
                "probe-config",
            )
            .unwrap();
            (api.0.litert_lm_conversation_config_set_session_config)(config.0, session.0);
            (api.0.litert_lm_conversation_config_set_thinking_config)(config.0, thinking.0);
            let chat = Resource::new(
                (api.0.litert_lm_conversation_create)(engine.0, config.0),
                api.0.litert_lm_conversation_delete,
                "probe-chat",
            )
            .unwrap();
            let events = Arc::new(std::sync::Mutex::new(Vec::new()));
            let delivered = events.clone();
            let mut consumer: Box<dyn FnMut(ConversationDelta) -> bool + Send> =
                Box::new(move |event| {
                    delivered.lock().unwrap().push(event);
                    true
                });
            let (outcome, response) = stream_input_events(
                &api,
                &chat,
                &encode_input(&CoreMessage::text(
                    "What is 17 multiplied by 19? Answer with the number.",
                )),
                &mut consumer,
                &Arc::new(AtomicBool::new(false)),
            )
            .unwrap();
            assert_eq!(outcome, StreamOutcome::Completed);
            let events = events.lock().unwrap();
            assert!(events
                .iter()
                .any(|event| matches!(event, ConversationDelta::Reasoning(_))));
            assert!(events
                .iter()
                .any(|event| matches!(event, ConversationDelta::Text(_))));
            println!(
                "Native reasoning bytes={}, answer bytes={}",
                response.reasoning.len(),
                response.text.len()
            );
            assert!(
                !response.reasoning.is_empty(),
                "Runtime did not report structured reasoning"
            );
            assert!(
                response.text.contains("323"),
                "Runtime did not produce the expected visible answer"
            );
        }
    }

    #[test]
    fn structured_reasoning_is_separate_and_never_inferred_from_visible_text() {
        let message = serde_json::json!({
            "role": "assistant",
            "content": [{"type":"text","text":"<think>literal example</think> Answer"}],
            "reasoning_content": "Runtime-reported reasoning",
            "channels": {"thought":"Do not duplicate this channel"}
        });
        assert_eq!(
            response_content(&message, false).unwrap(),
            ResponseContent {
                text: "<think>literal example</think> Answer".into(),
                reasoning: "Runtime-reported reasoning".into(),
            }
        );
        assert_eq!(
            parse_reply(&message.to_string()).unwrap(),
            "<think>literal example</think> Answer"
        );
        let plain = serde_json::json!({"content":[{"type":"text","text":"I am thinking aloud"}]});
        assert_eq!(response_content(&plain, false).unwrap().reasoning, "");
    }

    #[test]
    fn reasoning_only_stream_chunks_do_not_become_visible_answers() {
        let message = serde_json::json!({"role":"assistant","content":[],"reasoning_content":"Consider the facts"});
        assert_eq!(
            response_content(&message, false).unwrap().reasoning,
            "Consider the facts"
        );
        assert_eq!(parse_reply_inner(&message.to_string(), true).unwrap(), "");
        assert_eq!(
            parse_reply(&message.to_string()),
            Err(failure("response-empty"))
        );
    }

    #[test]
    fn malformed_or_oversized_reasoning_is_rejected_for_chat_and_tools() {
        for reasoning in [
            serde_json::json!(7),
            serde_json::json!(false),
            serde_json::json!({"text":"invalid"}),
        ] {
            let message = serde_json::json!({"role":"assistant","content":[{"type":"text","text":"Answer"}],"reasoning_content":reasoning});
            assert_eq!(
                response_content(&message, false),
                Err(failure("response-reasoning"))
            );
            assert_eq!(
                parse_tool_turn(&message, &[], 0),
                Err(failure("response-reasoning"))
            );
        }
        let message = serde_json::json!({"content":[],"reasoning_content":"x".repeat(1_048_577)});
        assert_eq!(
            response_content(&message, false),
            Err(failure("response-size-limit"))
        );
    }

    #[test]
    fn context_selection_requires_verified_accounting_and_never_calls_a_policy() {
        struct Never;
        impl working_context::WorkingContextPolicy for Never {
            fn select(
                &self,
                _: &[usize],
                _: usize,
                _: usize,
                _: usize,
            ) -> Result<working_context::WorkingSelection, CoreError> {
                panic!("unsupported accounting must not invoke selection");
            }
        }
        let policy: working_context::SharedContextPolicy = Arc::new(Never);
        assert!(require_context_accounting(Some(&policy))
            .unwrap_err()
            .to_string()
            .contains("context-accounting-unsupported:litertlm"));
        require_context_accounting(None).unwrap();
    }
    #[test]
    fn resident_library_survives_owner_release() {
        use std::sync::atomic::AtomicUsize;
        struct Marker(Arc<AtomicUsize>);
        impl Drop for Marker {
            fn drop(&mut self) {
                self.0.fetch_add(1, Ordering::SeqCst);
            }
        }
        let drops = Arc::new(AtomicUsize::new(0));
        let cache = std::sync::Mutex::new(BTreeMap::new());
        let path = Path::new("trusted-runtime");
        let first = resident_library(&cache, path, || Ok(Marker(drops.clone()))).unwrap();
        let weak = Arc::downgrade(&first);
        drop(first);
        assert_eq!(drops.load(Ordering::SeqCst), 0);
        let second = resident_library(&cache, path, || panic!("must not reload")).unwrap();
        assert!(Arc::ptr_eq(&weak.upgrade().unwrap(), &second));
        drop(second);
        drop(cache);
        assert_eq!(drops.load(Ordering::SeqCst), 1);
    }
    #[test]
    fn resident_library_failed_load_is_retryable_and_paths_are_bounded() {
        let cache = std::sync::Mutex::new(BTreeMap::new());
        let path = Path::new("failed-runtime");
        assert!(resident_library::<u8>(&cache, path, || Err(failure("load-failed"))).is_err());
        assert!(cache.lock().unwrap().is_empty());
        assert_eq!(*resident_library(&cache, path, || Ok(1)).unwrap(), 1);
        for name in ["second", "third", "fourth"] {
            resident_library(&cache, Path::new(name), || Ok(2)).unwrap();
        }
        assert!(resident_library(&cache, Path::new("fifth"), || panic!(
            "must reject before loading"
        ))
        .is_err());
        assert_eq!(
            *resident_library(&cache, path, || panic!("existing remains usable")).unwrap(),
            1
        );
    }
    fn checkpoint_options() -> ConversationOptions {
        ConversationOptions {
            thinking: false,
            system_prompt: Some("Host instructions".into()),
            max_output_tokens: 128,
            sampling: None,
        }
    }
    fn completed_tool_history() -> Vec<serde_json::Value> {
        vec![
            serde_json::json!({"role":"user","content":[{"type":"text","text":"read clock"}]}),
            serde_json::json!({"role":"assistant","content":[],"tool_calls":[{"type":"function","function":{"name":tool().name,"arguments":{}}}]}),
            serde_json::json!({"role":"tool","content":[{"type":"tool_response","name":tool().name,"response":{"status":"ok","time":"12:00"}}]}),
            serde_json::json!({"role":"assistant","content":[]}),
        ]
    }
    #[test]
    fn completed_tool_checkpoints_preserve_calls_results_and_empty_continuation() {
        let snapshot = tool_checkpoint(&completed_tool_history(), &[tool()], &checkpoint_options());
        let restored =
            tool_checkpoint_history(&snapshot, &[tool()], &checkpoint_options()).unwrap();
        assert_eq!(
            restored[1]["tool_calls"][0]["function"]["name"],
            tool().name
        );
        assert_eq!(restored[2]["content"][0]["response"]["time"], "12:00");
        assert_eq!(restored.len(), 4);
    }
    #[test]
    fn checkpoints_preserve_reasoning_separately_and_validate_its_role_and_type() {
        let options = checkpoint_options();
        let mut chat = ChatState {
            live: None,
            options: options.clone(),
            history: vec![],
            stopped: false,
            history_bytes: 0,
            tools: vec![],
            tools_enabled: true,
            pending: vec![],
        };
        chat.record_content(
            encode_input(&CoreMessage::text("question")),
            &ResponseContent {
                text: "answer".into(),
                reasoning: "native reasoning".into(),
            },
        );
        let snapshot = tool_checkpoint(&chat.history, &[], &options);
        let restored = ordinary_checkpoint_history(&snapshot).unwrap();
        assert_eq!(restored[1]["reasoning_content"], "native reasoning");
        assert_eq!(restored[1]["content"][0]["text"], "answer");
        let mut value: serde_json::Value = serde_json::from_str(&snapshot).unwrap();
        value["messages"][1]["reasoning_content"] = serde_json::json!(17);
        assert!(ordinary_checkpoint_history(&value.to_string()).is_err());
        value["messages"][1]["reasoning_content"] = serde_json::json!("valid");
        value["messages"][0]["reasoning_content"] = serde_json::json!("wrong role");
        assert!(ordinary_checkpoint_history(&value.to_string()).is_err());

        let mut tools = completed_tool_history();
        tools[1]["reasoning_content"] = serde_json::json!("choose a declared tool");
        let snapshot = tool_checkpoint(&tools, &[tool()], &options);
        assert_eq!(
            tool_checkpoint_history(&snapshot, &[tool()], &options).unwrap()[1]
                ["reasoning_content"],
            "choose a declared tool"
        );
    }
    #[test]
    fn tool_availability_preserves_completed_context_and_removes_declarations() {
        let mut chat = ChatState {
            live: None,
            options: checkpoint_options(),
            history: completed_tool_history(),
            stopped: false,
            history_bytes: 0,
            tools: vec![tool()],
            tools_enabled: true,
            pending: vec![],
        };
        let before = chat.history.clone();
        validate_tool_switch(&chat, false).unwrap();
        chat.tools_enabled = false;
        assert!(chat.active_tools().is_empty());
        let snapshot = tool_checkpoint_enabled(&chat.history, &chat.tools, &chat.options, false);
        assert!(!checkpoint_tools_enabled(&snapshot).unwrap());
        let restored = tool_checkpoint_history(&snapshot, &chat.tools, &chat.options).unwrap();
        assert_eq!(restored[1]["tool_calls"], before[1]["tool_calls"]);
        assert_eq!(restored[2]["content"], before[2]["content"]);
        // Historical calls are context, but a new call while disabled is invalid.
        assert!(parse_tool_turn(&before[1], chat.active_tools(), 4).is_err());
        validate_tool_switch(&chat, true).unwrap();
        chat.tools_enabled = true;
        assert_eq!(chat.active_tools().len(), 1);
        assert_eq!(chat.history, before);
        chat.pending.push(ToolCall {
            id: "pending".into(),
            name: tool().name,
            arguments: serde_json::json!({}),
        });
        assert!(validate_tool_switch(&chat, false).is_err());
        assert!(chat.tools_enabled);
        chat.pending.clear();
        chat.stopped = true;
        assert!(validate_tool_switch(&chat, false).is_err());
        chat.stopped = false;
        chat.tools.clear();
        assert!(validate_tool_switch(&chat, true).is_err());
    }
    #[test]
    fn explicit_empty_import_clears_context_without_regranting_tools() {
        let mut chat = ChatState {
            live: None,
            options: checkpoint_options(),
            history: completed_tool_history(),
            stopped: false,
            history_bytes: 1234,
            tools: vec![tool()],
            tools_enabled: false,
            pending: vec![],
        };
        chat.options.thinking = true;
        let old_history = chat.history.clone();
        assert!(
            import_chat_state(&mut chat, vec![encode_input(&CoreMessage::text("replace"))])
                .is_err()
        );
        assert_eq!(chat.history, old_history);
        import_chat_state(&mut chat, vec![]).unwrap();
        assert!(chat.history.is_empty());
        assert_eq!(chat.history_bytes, 0);
        assert!(!chat.tools_enabled);
        assert!(chat.active_tools().is_empty());
        assert_eq!(chat.tools.len(), 1);
        assert!(chat.options.thinking);
        chat.pending.push(ToolCall {
            id: "pending".into(),
            name: tool().name,
            arguments: serde_json::json!({}),
        });
        assert!(import_chat_state(&mut chat, vec![]).is_err());
        assert_eq!(chat.pending.len(), 1);
        chat.pending.clear();
        chat.stopped = true;
        assert!(import_chat_state(&mut chat, vec![]).is_err());
    }
    #[test]
    fn portable_observations_import_as_text_without_pending_calls_or_new_grants() {
        let turns = crate::history::parse_document(r#"{"version":3,"turns":[{"input":[{"type":"text","text":"Run an action"}],"answer":null,"observations":[{"kind":"call","name":"unregistered-old-action","text":"{}"},{"kind":"result","name":"unregistered-old-action","text":"failed"}]}]}"#).unwrap();
        let messages = portable_native_history(&turns, &[InputModality::Text].into()).unwrap();
        assert!(messages.iter().all(|m| m.get("tool_calls").is_none()));
        let mut chat = ChatState {
            live: None,
            options: checkpoint_options(),
            history: vec![],
            stopped: false,
            history_bytes: 0,
            tools: vec![tool()],
            tools_enabled: false,
            pending: vec![],
        };
        import_chat_state(&mut chat, messages.clone()).unwrap();
        for (actual, expected) in chat.history.iter().zip(&messages) {
            assert_eq!(actual["role"], expected["role"]);
            assert_eq!(actual["content"], expected["content"]);
            assert!(actual["tool_calls"].is_null());
        }
        assert!(chat.pending.is_empty());
        assert!(!chat.tools_enabled);
        assert_eq!(chat.tools.len(), 1);
        let old = chat.history.clone();
        assert!(import_chat_state(&mut chat, messages).is_err());
        assert_eq!(chat.history, old);
    }
    #[test]
    fn checkpoint_availability_is_strict_and_old_checkpoints_remain_readable() {
        let snapshot = tool_checkpoint(&completed_tool_history(), &[tool()], &checkpoint_options());
        let mut value: serde_json::Value = serde_json::from_str(&snapshot).unwrap();
        value.as_object_mut().unwrap().remove("toolsEnabled");
        assert!(checkpoint_tools_enabled(&value.to_string()).unwrap());
        assert!(
            tool_checkpoint_history(&value.to_string(), &[tool()], &checkpoint_options()).is_ok()
        );
        for invalid in [
            serde_json::json!("false"),
            serde_json::json!(null),
            serde_json::json!(1),
        ] {
            value["toolsEnabled"] = invalid;
            assert!(
                tool_checkpoint_history(&value.to_string(), &[tool()], &checkpoint_options())
                    .is_err()
            );
        }
    }
    #[test]
    fn ordinary_import_preserves_owned_context_but_rejects_agent_calls() {
        let ordinary = vec![
            encode_input(&CoreMessage::text("Remember cobalt")),
            serde_json::json!({"role":"assistant","content":[{"type":"text","text":"Remembered"}]}),
        ];
        let snapshot = tool_checkpoint(&ordinary, &[], &checkpoint_options());
        let imported = ordinary_checkpoint_history(&snapshot).unwrap();
        assert_eq!(imported[0]["content"], ordinary[0]["content"]);
        assert!(ordinary_checkpoint_history(&tool_checkpoint(
            &completed_tool_history(),
            &[tool()],
            &checkpoint_options()
        ))
        .is_err());
        assert!(ordinary_checkpoint_history(&tool_checkpoint(
            &ordinary[..1],
            &[],
            &checkpoint_options()
        ))
        .is_err());
        // Catalog-stripping cannot make tool-bearing history ordinary.
        assert!(ordinary_checkpoint_history(&tool_checkpoint(
            &completed_tool_history(),
            &[],
            &checkpoint_options()
        ))
        .is_err());
    }
    #[test]
    fn reconfiguration_validates_before_mutation_and_preserves_tool_history() {
        let mut chat = ChatState {
            live: None,
            options: checkpoint_options(),
            history: completed_tool_history(),
            stopped: false,
            history_bytes: 0,
            tools: vec![tool()],
            tools_enabled: true,
            pending: vec![],
        };
        let before = chat.history.clone();
        let changed = reconfiguration_options(
            &chat,
            2048,
            512,
            Some(SamplingOptions {
                temperature: 0.8,
                top_k: 40,
                top_p: 0.9,
                seed: 42,
            }),
        )
        .unwrap();
        assert_eq!(changed.max_output_tokens, 512);
        assert_eq!(changed.system_prompt, chat.options.system_prompt);
        assert_eq!(chat.history, before);
        assert!(reconfiguration_options(&chat, 2048, 0, None).is_err());
        assert!(reconfiguration_options(&chat, 2048, 2049, None).is_err());
        chat.stopped = true;
        assert!(reconfiguration_options(&chat, 2048, 512, None).is_err());
        chat.stopped = false;
        chat.pending.push(ToolCall {
            id: "pending".into(),
            name: tool().name,
            arguments: serde_json::json!({}),
        });
        assert!(reconfiguration_options(&chat, 2048, 512, None).is_err());
        assert_eq!(chat.history, before);
    }
    #[test]
    #[ignore = "requires an existing host-provided model; no downloads"]
    fn real_model_live_settings_preserve_completed_context() {
        let path = std::env::var("OMNIX_RECONFIGURATION_MODEL").expect("provide an existing model");
        let provider = LiteRtLmProvider::from_bundled(4096).unwrap();
        let request = ModelRequest {
            format: ModelFormat::LiteRtLm,
            platform: current_platform().unwrap(),
            input_modalities: [InputModality::Text].into(),
            thinking: false,
            tools: false,
            preferred_provider: None,
        };
        let model = provider.load(&request, Path::new(&path)).unwrap();
        let mut chat = model
            .start_conversation(ConversationOptions {
                thinking: false,
                system_prompt: Some("Answer briefly. Remember facts given by the user.".into()),
                max_output_tokens: 64,
                sampling: None,
            })
            .unwrap();
        assert!(!chat
            .send("Remember my project code: cobalt-731. Acknowledge briefly.")
            .unwrap()
            .is_empty());
        let previous = chat.history().unwrap();
        chat.reconfigure(
            128,
            Some(SamplingOptions {
                temperature: 0.5,
                top_k: 40,
                top_p: 0.95,
                seed: 42,
            }),
        )
        .unwrap();
        assert_eq!(chat.history().unwrap(), previous);
        assert!(chat.reconfigure(0, None).is_err());
        let answer = chat.send("What is my project code?").unwrap();
        println!("After live settings update: {answer}");
        assert!(answer.contains("731"));
        assert_eq!(chat.history().unwrap().len(), previous.len() + 2);
    }
    #[test]
    fn tool_checkpoints_preserve_sampling_and_reject_changed_sampler() {
        let mut options = checkpoint_options();
        options.sampling = Some(SamplingOptions {
            temperature: 0.7,
            top_k: 40,
            top_p: 0.95,
            seed: 42,
        });
        let snapshot = tool_checkpoint(&completed_tool_history(), &[tool()], &options);
        assert!(tool_checkpoint_history(&snapshot, &[tool()], &options).is_ok());
        options.sampling.as_mut().unwrap().seed = 43;
        assert!(tool_checkpoint_history(&snapshot, &[tool()], &options).is_err());
        options.sampling = None;
        assert!(tool_checkpoint_history(&snapshot, &[tool()], &options).is_err());
        let old = tool_checkpoint(&completed_tool_history(), &[tool()], &options);
        let mut value: serde_json::Value = serde_json::from_str(&old).unwrap();
        value.as_object_mut().unwrap().remove("sampling");
        assert!(tool_checkpoint_history(&value.to_string(), &[tool()], &options).is_ok());
    }
    #[test]
    fn tool_checkpoints_preserve_valid_audio_and_reject_external_or_invalid_media() {
        let mut wav = b"RIFF".to_vec();
        wav.extend(38u32.to_le_bytes());
        wav.extend(b"WAVEfmt ");
        wav.extend(16u32.to_le_bytes());
        wav.extend([1, 0, 1, 0]);
        wav.extend(16000u32.to_le_bytes());
        wav.extend(32000u32.to_le_bytes());
        wav.extend([2, 0, 16, 0]);
        wav.extend(b"data");
        wav.extend(2u32.to_le_bytes());
        wav.extend([0, 0]);
        let mut history = completed_tool_history();
        history[0] = encode_input(&CoreMessage {
            parts: vec![
                MessagePart::Text("Use the recording.".into()),
                MessagePart::Audio(wav),
            ],
        });
        let snapshot = tool_checkpoint(&history, &[tool()], &checkpoint_options());
        let restored =
            tool_checkpoint_history(&snapshot, &[tool()], &checkpoint_options()).unwrap();
        assert_eq!(restored[0]["content"], history[0]["content"]);
        assert_eq!(restored[2]["content"], history[2]["content"]);
        // Ordinary conversations use the same owned media context, without a tool catalog.
        let ordinary = vec![
            history[0].clone(),
            serde_json::json!({
                "role":"assistant", "content":[{"type":"text", "text":"Heard your recording."}]
            }),
        ];
        let snapshot = tool_checkpoint(&ordinary, &[], &checkpoint_options());
        let restored = tool_checkpoint_history(&snapshot, &[], &checkpoint_options()).unwrap();
        for (restored, original) in restored.iter().zip(&ordinary) {
            assert_eq!(restored["role"], original["role"]);
            assert_eq!(restored["content"], original["content"]);
        }
        assert!(tool_checkpoint_history(&snapshot, &[tool()], &checkpoint_options()).is_err());
        for invalid in [
            serde_json::json!({"type":"audio","blob":"AAAA"}),
            serde_json::json!({"type":"audio","path":"/private/recording.wav"}),
            serde_json::json!({"type":"audio","blob":"%%%"}),
            serde_json::json!({"type":"image","blob":"AAAA"}),
        ] {
            history[0]["content"] = serde_json::json!([invalid]);
            assert!(tool_checkpoint_history(
                &tool_checkpoint(&history, &[tool()], &checkpoint_options()),
                &[tool()],
                &checkpoint_options()
            )
            .is_err());
        }
        assert!(tool_checkpoint_history(
            &" ".repeat(16 * 1024 * 1024 + 1),
            &[tool()],
            &checkpoint_options()
        )
        .is_err());
    }
    #[test]
    fn tool_checkpoints_reject_incomplete_changed_and_media_context() {
        let history = completed_tool_history();
        for length in 1..history.len() {
            let snapshot = tool_checkpoint(&history[..length], &[tool()], &checkpoint_options());
            assert!(tool_checkpoint_history(&snapshot, &[tool()], &checkpoint_options()).is_err());
        }
        let snapshot = tool_checkpoint(&history, &[tool()], &checkpoint_options());
        let mut changed = tool();
        changed.parameters =
            serde_json::json!({"type":"object","properties":{"changed":{"type":"string"}}});
        assert!(tool_checkpoint_history(&snapshot, &[changed], &checkpoint_options()).is_err());
        let mut options = checkpoint_options();
        options.system_prompt = None;
        assert!(tool_checkpoint_history(&snapshot, &[tool()], &options).is_err());
        let mut history = history;
        history[0]["content"] = serde_json::json!([{"type":"audio","data":"AAAA"}]);
        let snapshot = tool_checkpoint(&history, &[tool()], &checkpoint_options());
        assert!(tool_checkpoint_history(&snapshot, &[tool()], &checkpoint_options()).is_err());
    }
    #[test]
    fn tool_checkpoints_reject_wrong_result_name_role_version_and_oversized_data() {
        let snapshot = tool_checkpoint(&completed_tool_history(), &[tool()], &checkpoint_options());
        for (field, value) in [
            ("version", serde_json::json!(2)),
            ("runtime", serde_json::json!("other")),
        ] {
            let mut invalid: serde_json::Value = serde_json::from_str(&snapshot).unwrap();
            invalid[field] = value;
            assert!(tool_checkpoint_history(
                &invalid.to_string(),
                &[tool()],
                &checkpoint_options()
            )
            .is_err());
        }
        for role in ["system", "user"] {
            let mut history = completed_tool_history();
            history[2]["role"] = serde_json::json!(role);
            assert!(tool_checkpoint_history(
                &tool_checkpoint(&history, &[tool()], &checkpoint_options()),
                &[tool()],
                &checkpoint_options()
            )
            .is_err());
        }
        let mut history = completed_tool_history();
        history[2]["content"][0]["name"] = serde_json::json!("other");
        assert!(tool_checkpoint_history(
            &tool_checkpoint(&history, &[tool()], &checkpoint_options()),
            &[tool()],
            &checkpoint_options()
        )
        .is_err());
        assert!(
            tool_checkpoint_history(&" ".repeat(1_048_577), &[tool()], &checkpoint_options())
                .is_err()
        );
    }
    #[test]
    fn native_constraints_are_enabled_only_for_tool_conversations() {
        assert!(!constrained_tool_decoding(&[]));
        assert!(constrained_tool_decoding(&[tool()]));
    }

    #[test]
    fn tool_stream_accumulates_text_and_complete_calls_without_exposing_arguments() {
        let mut stream = ToolStreamAccumulator::default();
        assert_eq!(
            stream
                .push(r#"{"role":"assistant","content":[{"type":"text","text":"Checking "}]}"#)
                .unwrap(),
            "Checking "
        );
        assert_eq!(stream.push(r#"{"role":"assistant","tool_calls":[{"type":"function","function":{"name":"search_knowledge","arguments":{"query":"reset"}}}]}"#).unwrap(), "");
        let turn = parse_tool_turn(&stream.message(), &[tool()], 0).unwrap();
        assert_eq!(turn.text, "Checking ");
        assert_eq!(turn.calls.len(), 1);
        assert!(stream
            .push(r#"{"role":"assistant","content":[{"type":"audio","data":"x"}]}"#)
            .is_err());
        assert!(stream.push(r#"{"role":"tool"}"#).is_err());
    }
    fn tool() -> ToolDefinition {
        ToolDefinition {
            name: "search_knowledge".into(),
            description: "Search".into(),
            parameters: serde_json::json!({"type":"object"}),
        }
    }
    #[test]
    fn typed_tools_preserve_arguments_and_balance_native_result_messages() {
        let raw = serde_json::json!({"role":"assistant", "tool_calls":[{"type":"function","function":{"name":"search_knowledge","arguments":{"query":"reset"}}}]});
        let turn = parse_tool_turn(&raw, &[tool()], 2).unwrap();
        assert_eq!(turn.calls[0].id, "2:0");
        assert_eq!(turn.calls[0].arguments["query"], "reset");
        assert!(encode_tool_input(
            &ToolInput::User(CoreMessage::text("interrupt")),
            &turn.calls
        )
        .is_err());
        assert!(encode_tool_input(&ToolInput::Results(vec![]), &turn.calls).is_err());
        let input = encode_tool_input(
            &ToolInput::Results(vec![ToolResult {
                call_id: "2:0".into(),
                value: serde_json::json!({"answer":"blue"}),
            }]),
            &turn.calls,
        )
        .unwrap();
        assert_eq!(input["role"], "tool");
        assert_eq!(input["content"][0]["type"], "tool_response");
        assert_eq!(input["content"][0]["name"], "search_knowledge");
    }
    #[test]
    fn refuses_undeclared_calls_and_nonobject_arguments() {
        for function in [
            serde_json::json!({"name":"control_device","arguments":{}}),
            serde_json::json!({"name":"search_knowledge","arguments":"{}"}),
        ] {
            let raw = serde_json::json!({"role":"assistant","tool_calls":[{"type":"function","function":function}]});
            assert!(parse_tool_turn(&raw, &[tool()], 0).is_err());
        }
        assert!(parse_tool_turn(&serde_json::json!({"role":"assistant"}), &[tool()], 0).is_err());
    }
    #[test]
    fn empty_completion_is_allowed_only_after_balanced_tool_results() {
        let raw = serde_json::json!({"role":"assistant","content":[]});
        assert!(parse_tool_turn_with_completion(&raw, &[tool()], 0, false).is_err());
        let completed = parse_tool_turn_with_completion(&raw, &[tool()], 1, true).unwrap();
        assert!(completed.text.is_empty());
        assert!(completed.calls.is_empty());
        assert!(parse_tool_turn_with_completion(
            &serde_json::json!({"role":"tool","content":[]}),
            &[tool()],
            1,
            true
        )
        .is_err());
        assert!(encode_tool_input(&ToolInput::Results(vec![]), &[]).is_err());
    }
    #[test]
    fn system_message_encodes_content_not_a_nested_chat_message() {
        let content = system_message("Reply with JSON only.\n\"quoted\"\0");
        let decoded: serde_json::Value = serde_json::from_slice(content.as_bytes()).unwrap();
        assert_eq!(
            decoded.as_str(),
            Some("Reply with JSON only.\n\"quoted\"\0")
        );
    }
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    static DELETED: AtomicUsize = AtomicUsize::new(0);
    #[test]
    fn media_serialization_keeps_order_and_encoded_content_for_replay() {
        let input = CoreMessage {
            parts: vec![
                MessagePart::Text("describe ".into()),
                MessagePart::Image(vec![1, 2, 3]),
                MessagePart::Text(" then listen ".into()),
                MessagePart::Audio(vec![4, 5, 6]),
            ],
        };
        let encoded = encode_input(&input);
        assert_eq!(encoded["content"][0]["text"], "describe ");
        assert_eq!(encoded["content"][1]["type"], "image");
        assert_eq!(encoded["content"][1]["blob"], "AQID");
        assert_eq!(encoded["content"][2]["text"], " then listen ");
        assert_eq!(encoded["content"][3]["blob"], "BAUG");
        let mut chat = ChatState {
            live: None,
            options: ConversationOptions {
                thinking: false,
                system_prompt: None,
                max_output_tokens: 8,
                sampling: None,
            },
            history: vec![],
            stopped: true,
            history_bytes: 0,
            tools: vec![],
            tools_enabled: true,
            pending: vec![],
        };
        chat.record(encoded.clone(), "answer");
        assert_eq!(chat.history[0], encoded);
        assert_eq!(chat.history[1]["role"], "assistant");
        assert!(chat.history_bytes > 0);
        chat.history_bytes = 64 * 1024 * 1024;
        assert!(chat.admit(&encoded).is_err());
    }

    #[test]
    fn encoder_backends_are_disabled_unless_explicitly_requested() {
        let text = [InputModality::Text].into();
        assert!(encoder_backend(&text, InputModality::Image).is_null());
        assert!(encoder_backend(&text, InputModality::Audio).is_null());
        let media = [
            InputModality::Text,
            InputModality::Image,
            InputModality::Audio,
        ]
        .into();
        assert_eq!(
            unsafe { CStr::from_ptr(encoder_backend(&media, InputModality::Image)) }.to_bytes(),
            b"cpu"
        );
        assert_eq!(
            unsafe { CStr::from_ptr(encoder_backend(&media, InputModality::Audio)) }.to_bytes(),
            b"cpu"
        );
    }
    #[test]
    fn model_encoders_follow_the_request_not_all_provider_capabilities() {
        let descriptor = ProviderDescriptor {
            id: "media".into(),
            priority: 0,
            formats: [ModelFormat::LiteRtLm].into(),
            platforms: [TargetPlatform::Android].into(),
            input_modalities: [
                InputModality::Text,
                InputModality::Image,
                InputModality::Audio,
            ]
            .into(),
            thinking: false,
            tools: false,
        };
        let mut request = ModelRequest {
            format: ModelFormat::LiteRtLm,
            platform: TargetPlatform::Android,
            input_modalities: [InputModality::Text].into(),
            thinking: false,
            tools: false,
            preferred_provider: None,
        };
        assert!(descriptor.supports(&request));
        assert!(encoder_backend(&model_modalities(&request), InputModality::Audio).is_null());
        request.input_modalities.insert(InputModality::Audio);
        assert!(descriptor.supports(&request));
        assert!(!encoder_backend(&model_modalities(&request), InputModality::Audio).is_null());
        assert!(encoder_backend(&model_modalities(&request), InputModality::Image).is_null());
    }
    #[test]
    fn bounds_logical_conversations_and_validates_limits() {
        let options = ConversationOptions {
            thinking: false,
            system_prompt: None,
            max_output_tokens: 128,
            sampling: None,
        };
        assert_eq!(validate_open(0, 2048, &options), Ok(()));
        assert_eq!(
            validate_open(16, 2048, &options),
            Err(failure("conversation-count-limit"))
        );
        assert_eq!(validate_open(1, 2048, &options), Ok(()));
        assert_eq!(
            validate_open(0, 64, &options),
            Err(CoreError::InvalidRequest)
        );
    }
    unsafe extern "C" fn delete_test_resource(pointer: *mut u8) {
        drop(Box::from_raw(pointer));
        DELETED.fetch_add(1, Ordering::SeqCst);
    }
    #[test]
    fn handoff_releases_only_other_native_handles_and_preserves_owned_history() {
        unsafe extern "C" fn delete(pointer: *mut ffi::LiteRtLmConversation) {
            drop(Box::from_raw(pointer.cast::<u8>()));
        }
        let mut chats = BTreeMap::new();
        for id in [1, 2] {
            chats.insert(
                id,
                ChatState {
                    live: Some(
                        Resource::new(Box::into_raw(Box::new(0u8)).cast(), delete, "test").unwrap(),
                    ),
                    options: ConversationOptions {
                        thinking: false,
                        system_prompt: Some(format!("system-{id}")),
                        max_output_tokens: 16,
                        sampling: None,
                    },
                    history: vec![encode_input(&CoreMessage::text(format!("private-{id}")))],
                    stopped: false,
                    history_bytes: 10,
                    tools: vec![],
                    tools_enabled: true,
                    pending: vec![],
                },
            );
        }
        suspend_other_chats(&mut chats, 2);
        assert!(chats[&1].live.is_none());
        assert!(chats[&2].live.is_some());
        assert_eq!(chats[&1].history[0]["content"][0]["text"], "private-1");
        assert_eq!(chats[&2].options.system_prompt.as_deref(), Some("system-2"));
        suspend_other_chats(&mut chats, 1);
        assert!(chats.values().all(|chat| chat.live.is_none()));
        assert_eq!(chats[&2].history[0]["content"][0]["text"], "private-2");
    }
    #[test]
    fn native_guard_deletes_once_and_rejects_null_without_deleting() {
        assert!(Resource::new(ptr::null_mut(), delete_test_resource, "null").is_err());
        assert_eq!(DELETED.load(Ordering::SeqCst), 0);
        let resource = Resource::new(
            Box::into_raw(Box::new(1u8)).cast(),
            delete_test_resource,
            "allocation",
        )
        .unwrap();
        drop(resource);
        assert_eq!(DELETED.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn library_validation_rejects_relative_paths_and_unbounded_context() {
        for tokens in [0, 127, u32::MAX] {
            assert!(matches!(
                unsafe { LiteRtLmProvider::from_library(Path::new("runtime.dll"), tokens) },
                Err(CoreError::InvalidRequest)
            ));
        }
    }
    #[test]
    fn preserves_text_boundaries_without_inserting_newlines() {
        assert_eq!(parse_reply(r#"{"role":"assistant","content":[{"type":"text","text":"hello "},{"type":"text","text":"world"}]}"#).unwrap(), "hello world");
    }
    #[test]
    fn cpu_context_has_a_safe_minimum_without_reducing_larger_requests() {
        let artifact = LiteRtLmProvider::bundled_library_path().unwrap();
        for (requested, expected) in [(128, 1024), (1024, 1024), (4096, 4096)] {
            let provider = unsafe { LiteRtLmProvider::from_library(&artifact, requested) }.unwrap();
            assert_eq!(provider.context_tokens, expected);
            assert!(provider.cache_directory.is_none());
        }
    }

    #[test]
    fn cache_paths_must_be_existing_absolute_directories() {
        let artifact = std::env::current_exe().unwrap();
        let directory = artifact.parent().unwrap();
        assert_eq!(
            cache_directory(directory).unwrap().to_str().unwrap(),
            directory.to_str().unwrap()
        );
        assert!(cache_directory(Path::new("cache")).is_err());
        assert!(cache_directory(&artifact).is_err());
        assert!(cache_directory(&directory.join("omnix-cache-missing-test-directory")).is_err());
        let provider = LiteRtLmProvider::from_bundled(2048).unwrap();
        assert!(provider
            .with_cache_directory(directory)
            .unwrap()
            .cache_directory
            .is_some());
    }
    #[test]
    fn refuses_unexpected_payloads_without_leaking_them() {
        for json in [
            "secret prompt",
            r#"{"role":"user"}"#,
            r#"{"role":"assistant","content":[]}"#,
            r#"{"role":"assistant","content":[{"type":"tool_call","text":"secret"}]}"#,
        ] {
            let error = parse_reply(json).unwrap_err().to_string();
            assert!(!error.contains("secret"));
        }
    }
    #[test]
    fn allows_empty_stream_deltas_but_rejects_empty_final_answers() {
        let json = r#"{"role":"assistant","content":[]}"#;
        assert_eq!(parse_reply_inner(json, true), Ok(String::new()));
        assert_eq!(parse_reply(json), Err(failure("response-empty")));
    }
    #[test]
    fn serializes_unicode_quotes_and_nuls_as_text() {
        let encoded = message("user", "héllo \"\0\n");
        let value: serde_json::Value = serde_json::from_str(encoded.to_str().unwrap()).unwrap();
        assert_eq!(value["content"][0]["text"], "héllo \"\0\n");
    }
}
