//! Binding-owned handles; no Flutter types enter the inference implementation.

#[derive(Debug, Clone, Copy)]
pub enum CoreInputKind {
    Text,
    Image,
    Audio,
}

#[derive(Debug, Clone)]
pub struct CoreInputPart {
    pub kind: CoreInputKind,
    pub text: Option<String>,
    pub bytes: Vec<u8>,
}

fn input_message(parts: Vec<CoreInputPart>) -> Result<omnix_core::CoreMessage, String> {
    use omnix_core::{CoreMessage, InputModality, MessagePart};
    let parts = parts
        .into_iter()
        .map(|part| match part.kind {
            CoreInputKind::Text if part.bytes.is_empty() => part
                .text
                .map(MessagePart::Text)
                .ok_or("Text input is missing"),
            CoreInputKind::Image if part.text.is_none() => Ok(MessagePart::Image(part.bytes)),
            CoreInputKind::Audio if part.text.is_none() => Ok(MessagePart::Audio(part.bytes)),
            _ => Err("Invalid input part"),
        })
        .collect::<Result<Vec<_>, _>>()?;
    let message = CoreMessage { parts };
    message
        .validate(
            &[
                InputModality::Text,
                InputModality::Image,
                InputModality::Audio,
            ]
            .into(),
        )
        .map_err(|e| e.to_string())?;
    Ok(message)
}

#[cfg(test)]
mod message_tests {
    use super::*;
    #[test]
    fn validates_parts_before_accessing_native_handles() {
        assert!(input_message(vec![]).is_err());
        assert!(input_message(vec![CoreInputPart {
            kind: CoreInputKind::Text,
            text: Some("hello".into()),
            bytes: vec![1]
        }])
        .is_err());
        assert!(input_message(vec![CoreInputPart {
            kind: CoreInputKind::Image,
            text: None,
            bytes: vec![1, 2, 3]
        }])
        .is_err());
        assert!(input_message(vec![CoreInputPart {
            kind: CoreInputKind::Text,
            text: Some("hello".into()),
            bytes: vec![]
        }])
        .is_ok());
    }
}

#[cfg(all(test, not(target_arch = "wasm32"), not(feature = "litertlm")))]
mod selection_tests {
    #[test]
    fn disabled_litertlm_fails_before_loading_native_code() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap();
        let error = runtime
            .block_on(super::core_load_trusted_model(
                "not-a-library".into(),
                "not-a-model".into(),
                2048,
            ))
            .unwrap_err();
        assert!(error.contains("runtime is not enabled"));
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn core_supported_platforms() -> Vec<String> {
    if cfg!(all(
        target_os = "windows",
        any(feature = "litertlm", feature = "llamacpp")
    )) {
        vec!["windows".into()]
    } else if cfg!(all(target_os = "android", feature = "litertlm")) {
        vec!["android".into()]
    } else {
        vec![]
    }
}

#[cfg(not(target_arch = "wasm32"))]
mod native {
    use omnix_core::{Conversation, LoadedModel};
    use std::sync::atomic::AtomicU64;
    use std::{
        collections::HashMap,
        sync::{
            atomic::{AtomicBool, Ordering},
            Arc, Mutex, OnceLock,
        },
    };

    type Model = Arc<Mutex<Option<Box<dyn LoadedModel>>>>;
    struct ChatState {
        slot: Mutex<Option<Box<dyn Conversation>>>,
        cancel: Arc<AtomicBool>,
        streaming: Mutex<bool>,
    }
    type Chat = Arc<ChatState>;
    struct StreamLease(Chat);
    impl Drop for StreamLease {
        fn drop(&mut self) {
            if let Ok(mut active) = self.0.streaming.lock() {
                *active = false;
            }
        }
    }
    static MODELS: OnceLock<Mutex<HashMap<u64, Model>>> = OnceLock::new();
    static CHATS: OnceLock<Mutex<HashMap<u64, Chat>>> = OnceLock::new();
    static NEXT: AtomicU64 = AtomicU64::new(1);
    type ArtifactIdentity = (std::path::PathBuf, u64, Option<std::time::SystemTime>);
    #[derive(Debug, PartialEq, Eq, PartialOrd, Ord)]
    struct LoadKey {
        model: ArtifactIdentity,
        runtime: Option<ArtifactIdentity>,
        context: u32,
        media: (bool, bool),
        cache: Option<std::path::PathBuf>,
    }
    static SHARED: OnceLock<omnix_core::ownership::ModelPool<LoadKey>> = OnceLock::new();
    fn pool() -> &'static omnix_core::ownership::ModelPool<LoadKey> {
        SHARED.get_or_init(Default::default)
    }
    fn artifact(path: &str) -> Result<ArtifactIdentity, String> {
        let path = std::path::Path::new(path);
        if !path.is_absolute() || !path.is_file() {
            return Err("An existing absolute artifact path is required".into());
        }
        let path = path
            .canonicalize()
            .map_err(|_| "Artifact identity unavailable")?;
        let metadata = path
            .metadata()
            .map_err(|_| "Artifact identity unavailable")?;
        Ok((path, metadata.len(), metadata.modified().ok()))
    }
    fn load_key(
        model: &str,
        runtime: Option<&str>,
        context: u32,
        images: bool,
        audio: bool,
        cache: Option<&str>,
    ) -> Result<LoadKey, String> {
        let cache = cache
            .map(|value| {
                let path = std::path::Path::new(value);
                if !path.is_absolute() || !path.is_dir() {
                    return Err("Cache directory must exist and be absolute");
                }
                path.canonicalize()
                    .map_err(|_| "Cache identity unavailable")
            })
            .transpose()?;
        Ok(LoadKey {
            model: artifact(model)?,
            runtime: runtime.map(artifact).transpose()?,
            context,
            media: (images, audio),
            cache,
        })
    }
    #[flutter_rust_bridge::frb(ignore)]
    pub fn shared_count() -> Result<u32, String> {
        pool()
            .live_models()
            .map(|count| count as u32)
            .map_err(|error| error.to_string())
    }

    #[cfg(test)]
    mod ownership_key_tests {
        use super::*;
        #[test]
        fn all_current_engine_settings_participate_in_shared_identity() {
            let file = std::env::current_exe().unwrap();
            let path = file.to_str().unwrap();
            let key = load_key(path, Some(path), 1024, false, false, None).unwrap();
            assert_eq!(
                key,
                load_key(path, Some(path), 1024, false, false, None).unwrap()
            );
            assert_ne!(
                key,
                load_key(path, Some(path), 2048, false, false, None).unwrap()
            );
            assert_ne!(
                key,
                load_key(path, Some(path), 1024, true, false, None).unwrap()
            );
            assert_ne!(
                key,
                load_key(path, Some(path), 1024, false, true, None).unwrap()
            );
            assert_ne!(key, load_key(path, None, 1024, false, false, None).unwrap());
            assert_ne!(
                key,
                load_key(
                    path,
                    Some(path),
                    1024,
                    false,
                    false,
                    file.parent().unwrap().to_str()
                )
                .unwrap()
            );
            assert!(load_key("relative", None, 1024, false, false, None).is_err());
            assert!(load_key(path, Some(path), 1024, false, false, Some("relative")).is_err());
        }
    }

    fn next_id() -> Result<u64, String> {
        NEXT.fetch_update(Ordering::Relaxed, Ordering::Relaxed, |id| id.checked_add(1))
            .map_err(|_| "Core handle space exhausted".into())
    }
    fn models() -> &'static Mutex<HashMap<u64, Model>> {
        MODELS.get_or_init(|| Mutex::new(HashMap::new()))
    }
    fn chats() -> &'static Mutex<HashMap<u64, Chat>> {
        CHATS.get_or_init(|| Mutex::new(HashMap::new()))
    }

    #[flutter_rust_bridge::frb(ignore)]
    #[cfg(feature = "litertlm")]
    pub async fn load(
        library_path: String,
        model_path: String,
        context_tokens: u32,
    ) -> Result<u64, String> {
        load_with_media(library_path, model_path, context_tokens, false, false).await
    }

    #[flutter_rust_bridge::frb(ignore)]
    #[cfg(feature = "litertlm")]
    pub async fn load_with_media(
        library_path: String,
        model_path: String,
        context_tokens: u32,
        images: bool,
        audio: bool,
    ) -> Result<u64, String> {
        load_configured(
            library_path,
            model_path,
            context_tokens,
            images,
            audio,
            None,
        )
        .await
    }

    #[flutter_rust_bridge::frb(ignore)]
    #[cfg(feature = "litertlm")]
    pub async fn load_configured(
        library_path: String,
        model_path: String,
        context_tokens: u32,
        images: bool,
        audio: bool,
        cache_directory: Option<String>,
    ) -> Result<u64, String> {
        load_configured_owned(
            library_path,
            model_path,
            context_tokens,
            images,
            audio,
            cache_directory,
            false,
        )
        .await
    }
    #[flutter_rust_bridge::frb(ignore)]
    #[cfg(feature = "litertlm")]
    async fn load_configured_owned(
        library_path: String,
        model_path: String,
        context_tokens: u32,
        images: bool,
        audio: bool,
        cache_directory: Option<String>,
        shared: bool,
    ) -> Result<u64, String> {
        if !cfg!(any(target_os = "windows", target_os = "android")) {
            return Err("LiteRT-LM CPU/text is available on Windows and Android arm64".into());
        }
        tokio::task::spawn_blocking(move || {
            use omnix_core::{
                litertlm::LiteRtLmProvider, InputModality, ModelFormat, ModelRequest,
                RuntimeRegistry, TargetPlatform,
            };
            use std::path::Path;
            let key = if shared {
                Some(load_key(
                    &model_path,
                    Some(&library_path),
                    context_tokens.max(1024),
                    images,
                    audio,
                    cache_directory.as_deref(),
                )?)
            } else {
                None
            };
            // This API explicitly requires the host-approved pinned platform C-ABI
            // artifacts. Path validation is not ABI or provenance verification.
            let mut modalities = [InputModality::Text]
                .into_iter()
                .collect::<std::collections::BTreeSet<_>>();
            if images {
                modalities.insert(InputModality::Image);
            }
            if audio {
                modalities.insert(InputModality::Audio);
            }
            let provider = unsafe {
                LiteRtLmProvider::from_library_with_modalities(
                    Path::new(&library_path),
                    context_tokens,
                    modalities.clone(),
                )
            }
            .map_err(|error| error.to_string())?;
            let provider = match cache_directory {
                Some(directory) => provider
                    .with_cache_directory(Path::new(&directory))
                    .map_err(|error| error.to_string())?,
                None => provider,
            };
            let mut registry = RuntimeRegistry::default();
            registry
                .register(Box::new(provider))
                .map_err(|error| error.to_string())?;
            let load = || {
                registry.load(
                    &ModelRequest {
                        format: ModelFormat::LiteRtLm,
                        platform: if cfg!(target_os = "android") {
                            TargetPlatform::Android
                        } else {
                            TargetPlatform::Windows
                        },
                        input_modalities: modalities,
                        thinking: false,
                        tools: false,
                        preferred_provider: None,
                    },
                    Path::new(&model_path),
                )
            };
            let model: Box<dyn LoadedModel> = match key {
                Some(key) => Box::new(
                    pool()
                        .acquire(key, load)
                        .map_err(|error| error.to_string())?,
                ),
                None => load().map_err(|error| error.to_string())?,
            };
            let id = next_id()?;
            models()
                .lock()
                .map_err(|_| "Core registry unavailable")?
                .insert(id, Arc::new(Mutex::new(Some(model))));
            Ok(id)
        })
        .await
        .map_err(|_| "Core worker failed")?
    }

    #[flutter_rust_bridge::frb(ignore)]
    #[cfg(not(feature = "litertlm"))]
    pub async fn load(
        _library_path: String,
        _model_path: String,
        _context_tokens: u32,
    ) -> Result<u64, String> {
        Err("LiteRT-LM runtime is not enabled; enable the litertlm Core feature".into())
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub async fn load_routed(
        model_path: String,
        library_path: Option<String>,
        context_tokens: u32,
    ) -> Result<u64, String> {
        load_routed_with_media(model_path, library_path, context_tokens, false, false).await
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub async fn load_routed_with_media(
        model_path: String,
        library_path: Option<String>,
        context_tokens: u32,
        images: bool,
        audio: bool,
    ) -> Result<u64, String> {
        load_routed_configured(
            model_path,
            library_path,
            context_tokens,
            images,
            audio,
            None,
        )
        .await
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub async fn load_routed_configured(
        model_path: String,
        library_path: Option<String>,
        context_tokens: u32,
        images: bool,
        audio: bool,
        cache_directory: Option<String>,
    ) -> Result<u64, String> {
        load_routed_owned(
            model_path,
            library_path,
            context_tokens,
            images,
            audio,
            cache_directory,
            false,
        )
        .await
    }
    #[flutter_rust_bridge::frb(ignore)]
    pub async fn load_routed_owned(
        model_path: String,
        library_path: Option<String>,
        context_tokens: u32,
        images: bool,
        audio: bool,
        cache_directory: Option<String>,
        shared: bool,
    ) -> Result<u64, String> {
        use omnix_core::{probe_model_format, ModelFormat};
        let path = std::path::Path::new(&model_path);
        let format = probe_model_format(path).map_err(|e| e.to_string())?;
        if format == ModelFormat::LiteRtLm {
            if !cfg!(feature = "litertlm") {
                return Err(
                    "LiteRT-LM runtime is not enabled; enable the litertlm Core feature".into(),
                );
            }
            let library_path = match library_path {
                Some(path) => path,
                None => {
                    #[cfg(feature = "litertlm")]
                    {
                        omnix_core::litertlm::LiteRtLmProvider::bundled_library_path()
                            .map_err(|e| e.to_string())?
                            .to_str()
                            .ok_or("Runtime path is not UTF-8")?
                            .to_owned()
                    }
                    #[cfg(not(feature = "litertlm"))]
                    return Err("LiteRT-LM runtime is not enabled".into());
                }
            };
            #[cfg(feature = "litertlm")]
            return load_configured_owned(
                library_path,
                model_path,
                context_tokens,
                images,
                audio,
                cache_directory,
                shared,
            )
            .await;
            #[cfg(not(feature = "litertlm"))]
            return load(library_path, model_path, context_tokens).await;
        }
        if cache_directory.is_some() {
            return Err(
                "Explicit optimized cache directories are supported only by LiteRT-LM".into(),
            );
        }
        if images || audio {
            return Err(
                "GGUF media input requires an mtmd adapter and matching projector; not implemented"
                    .into(),
            );
        }
        if library_path.is_some() {
            return Err("GGUF uses the compiled runtime; do not supply a LiteRT-LM library".into());
        }
        #[cfg(feature = "llamacpp")]
        {
            if !cfg!(target_os = "windows") {
                return Err("GGUF CPU/text is qualified only on Windows".into());
            }
            tokio::task::spawn_blocking(move || {
                use omnix_core::{
                    llamacpp::LlamaCppProvider, InputModality, ModelRequest, RuntimeRegistry,
                    TargetPlatform,
                };
                let key = if shared {
                    Some(load_key(
                        &model_path,
                        None,
                        context_tokens,
                        false,
                        false,
                        None,
                    )?)
                } else {
                    None
                };
                let mut registry = RuntimeRegistry::default();
                registry
                    .register(Box::new(
                        LlamaCppProvider::new(context_tokens).map_err(|e| e.to_string())?,
                    ))
                    .map_err(|e| e.to_string())?;
                let load = || {
                    registry.load(
                        &ModelRequest {
                            format,
                            platform: TargetPlatform::Windows,
                            input_modalities: [InputModality::Text].into(),
                            thinking: false,
                            tools: false,
                            preferred_provider: None,
                        },
                        std::path::Path::new(&model_path),
                    )
                };
                let model: Box<dyn LoadedModel> = match key {
                    Some(key) => Box::new(
                        pool()
                            .acquire(key, load)
                            .map_err(|error| error.to_string())?,
                    ),
                    None => load().map_err(|error| error.to_string())?,
                };
                let id = next_id()?;
                models()
                    .lock()
                    .map_err(|_| "Core registry unavailable")?
                    .insert(id, Arc::new(Mutex::new(Some(model))));
                Ok(id)
            })
            .await
            .map_err(|_| "Core worker failed")?
        }
        #[cfg(not(feature = "llamacpp"))]
        Err("GGUF runtime is not compiled; enable the llamacpp Core feature".into())
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub async fn start(
        id: u64,
        system_prompt: Option<String>,
        max_output_tokens: u32,
        sampling: Option<omnix_core::SamplingOptions>,
        thinking: bool,
    ) -> Result<u64, String> {
        let model = models()
            .lock()
            .map_err(|_| "Core registry unavailable")?
            .get(&id)
            .cloned()
            .ok_or("Model is closed")?;
        tokio::task::spawn_blocking(move || {
            let guard = model.lock().map_err(|_| "Model unavailable")?;
            let chat = guard
                .as_ref()
                .ok_or("Model is closed")?
                .start_conversation(omnix_core::ConversationOptions {
                    thinking,
                    system_prompt,
                    max_output_tokens,
                    sampling,
                })
                .map_err(|error| error.to_string())?;
            let id = next_id()?;
            chats()
                .lock()
                .map_err(|_| "Core registry unavailable")?
                .insert(
                    id,
                    Arc::new(ChatState {
                        slot: Mutex::new(Some(chat)),
                        cancel: Arc::new(AtomicBool::new(false)),
                        streaming: Mutex::new(false),
                    }),
                );
            Ok(id)
        })
        .await
        .map_err(|_| "Core worker failed")?
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub async fn send(id: u64, text: String) -> Result<String, String> {
        send_message(id, omnix_core::CoreMessage::text(text)).await
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub async fn send_message(id: u64, message: omnix_core::CoreMessage) -> Result<String, String> {
        let chat = chats()
            .lock()
            .map_err(|_| "Core registry unavailable")?
            .get(&id)
            .cloned()
            .ok_or("Conversation is closed")?;
        tokio::task::spawn_blocking(move || {
            let mut guard = chat.slot.lock().map_err(|_| "Conversation unavailable")?;
            guard
                .as_mut()
                .ok_or("Conversation is closed")?
                .send_message(&message)
                .map_err(|error| error.to_string())
        })
        .await
        .map_err(|_| "Core worker failed")?
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub async fn history(
        id: u64,
        snapshot: Option<String>,
        thinking: Option<bool>,
    ) -> Result<String, String> {
        if snapshot.is_none() && thinking.is_some() {
            return Err("Thinking transition requires a checkpoint".into());
        }
        let chat = chats()
            .lock()
            .map_err(|_| "Core registry unavailable")?
            .get(&id)
            .cloned()
            .ok_or("Conversation is closed")?;
        tokio::task::spawn_blocking(move || {
            let mut guard = chat.slot.lock().map_err(|_| "Conversation unavailable")?;
            let conversation = guard.as_mut().ok_or("Conversation is closed")?;
            if let Some(snapshot) = snapshot {
                if snapshot.len() > 20 * 1024 * 1024 {
                    return Err("History snapshot too large".into());
                }
                let value: serde_json::Value =
                    serde_json::from_str(&snapshot).map_err(|_| "Invalid history JSON")?;
                match value["version"].as_u64() {
                    Some(3) => {
                        if thinking.is_some() { return Err("Portable history uses the fresh session's configured thinking setting".into()); }
                        conversation.import_portable_history(omnix_core::history::parse_document(&snapshot).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
                    }
                    Some(1) => {
                        if snapshot.len() > 2_097_152 {
                            return Err("History snapshot too large".into());
                        }
                        let messages: Vec<(String, String)> =
                            serde_json::from_value(value["messages"].clone())
                                .map_err(|_| "Invalid history messages")?;
                        match thinking {
                            Some(enabled) => conversation.restore_history_with_thinking(messages, enabled),
                            None => conversation.restore_history(messages),
                        }.map_err(|e| e.to_string())?;
                    }
                    Some(2) => {
                        let context = value["context"].as_str().ok_or("Invalid native context")?;
                        match thinking {
                            Some(enabled) => conversation.restore_checkpoint_with_thinking(context, enabled),
                            None => conversation.restore_checkpoint(context),
                        }.map_err(|e| e.to_string())?;
                    },
                    _ => return Err("Unsupported history version".into()),
                }
            }
            let value = match conversation.history() {
                Ok(messages) => {
                    omnix_core::validate_history(&messages).map_err(|e| e.to_string())?;
                    serde_json::json!({"version":1,"messages":messages})
                }
                Err(omnix_core::CoreError::BackendFailure(reason))
                    if reason == "media-history-export-unsupported" =>
                {
                    let context = conversation
                        .export_checkpoint()
                        .map_err(|e| e.to_string())?;
                    serde_json::json!({"version":2,"context":context})
                }
                Err(error) => return Err(error.to_string()),
            };
            serde_json::to_string(&value).map_err(|e| e.to_string())
        })
        .await
        .map_err(|_| "Core worker failed")?
    }
    #[flutter_rust_bridge::frb(ignore)]
    pub async fn reconfigure(
        id: u64,
        tokens: u32,
        sampling: Option<omnix_core::SamplingOptions>,
    ) -> Result<(), String> {
        let chat = chats()
            .lock()
            .map_err(|_| "Core registry unavailable")?
            .get(&id)
            .cloned()
            .ok_or("Conversation closed")?;
        tokio::task::spawn_blocking(move || {
            let mut guard = chat.slot.try_lock().map_err(|_| "Conversation busy")?;
            guard
                .as_mut()
                .ok_or("Conversation closed")?
                .reconfigure(tokens, sampling)
                .map_err(|e| e.to_string())
        })
        .await
        .map_err(|_| "Core worker failed")?
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub async fn set_thinking(id: u64, enabled: bool) -> Result<(), String> {
        let chat = chats()
            .lock()
            .map_err(|_| "Core registry unavailable")?
            .get(&id)
            .cloned()
            .ok_or("Conversation closed")?;
        tokio::task::spawn_blocking(move || {
            let mut guard = chat.slot.try_lock().map_err(|_| "Conversation busy")?;
            guard
                .as_mut()
                .ok_or("Conversation closed")?
                .set_thinking(enabled)
                .map_err(|e| e.to_string())
        })
        .await
        .map_err(|_| "Core worker failed")?
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub async fn stream(
        id: u64,
        text: String,
        sink: crate::frb_generated::StreamSink<String>,
    ) -> Result<(), String> {
        stream_message(id, omnix_core::CoreMessage::text(text), sink).await
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub async fn stream_message(
        id: u64,
        message: omnix_core::CoreMessage,
        sink: crate::frb_generated::StreamSink<String>,
    ) -> Result<(), String> {
        stream_output(id, message, sink, false).await
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub async fn stream_output(
        id: u64,
        message: omnix_core::CoreMessage,
        sink: crate::frb_generated::StreamSink<String>,
        structured: bool,
    ) -> Result<(), String> {
        let chat = chats()
            .lock()
            .map_err(|_| "Core registry unavailable")?
            .get(&id)
            .cloned()
            .ok_or("Conversation is closed")?;
        {
            let mut active = chat
                .streaming
                .lock()
                .map_err(|_| "Conversation unavailable")?;
            if *active {
                return Err("A streaming turn is already active".into());
            }
            chat.cancel.store(false, Ordering::Release);
            *active = true;
        }
        let lease = StreamLease(chat.clone());
        tokio::task::spawn_blocking(move || {
            let _lease = lease;
            let mut guard = chat.slot.lock().map_err(|_| "Conversation unavailable")?;
            let updates = sink.clone();
            let outcome = guard
                .as_mut()
                .ok_or("Conversation is closed")?
                .send_message_events(
                    &message,
                    Box::new(move |delta| {
                        let (kind, text) = match delta {
                            omnix_core::ConversationDelta::Text(text) => ("text", text),
                            omnix_core::ConversationDelta::Reasoning(text) => ("reasoning", text),
                        };
                        if structured {
                            updates
                                .add(serde_json::json!({"kind":kind,"text":text}).to_string())
                                .is_ok()
                        } else if kind == "text" {
                            updates.add(text).is_ok()
                        } else {
                            true
                        }
                    }),
                    chat.cancel.clone(),
                )
                .map_err(|error| error.to_string())?;
            if structured {
                let kind = if outcome == omnix_core::StreamOutcome::Completed {
                    "completed"
                } else {
                    "cancelled"
                };
                sink.add(serde_json::json!({"kind":kind}).to_string())
                    .map_err(|_| "Stream closed")?;
            }
            Ok(())
        })
        .await
        .map_err(|_| "Core worker failed")?
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub fn cancel(id: u64) -> Result<(), String> {
        if let Some(chat) = chats()
            .lock()
            .map_err(|_| "Core registry unavailable")?
            .get(&id)
        {
            if *chat
                .streaming
                .lock()
                .map_err(|_| "Conversation unavailable")?
            {
                chat.cancel.store(true, Ordering::Release);
            }
        }
        Ok(())
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub async fn close_model(id: u64) -> Result<(), String> {
        let model = models()
            .lock()
            .map_err(|_| "Core registry unavailable")?
            .remove(&id);
        tokio::task::spawn_blocking(move || {
            if let Some(model) = model {
                model.lock().map_err(|_| "Model unavailable")?.take();
            }
            Ok(())
        })
        .await
        .map_err(|_| "Core worker failed")?
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub async fn close_chat(id: u64) -> Result<(), String> {
        let chat = chats()
            .lock()
            .map_err(|_| "Core registry unavailable")?
            .remove(&id);
        tokio::task::spawn_blocking(move || {
            if let Some(chat) = chat {
                chat.cancel.store(true, Ordering::Release);
                chat.slot
                    .lock()
                    .map_err(|_| "Conversation unavailable")?
                    .take();
            }
            Ok(())
        })
        .await
        .map_err(|_| "Core worker failed")?
    }
}

pub async fn core_load_trusted_model(
    library_path: String,
    model_path: String,
    context_tokens: u32,
) -> Result<u64, String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        native::load(library_path, model_path, context_tokens).await
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (library_path, model_path, context_tokens);
        Err("Native Core is unavailable on web".into())
    }
}
pub async fn core_start_conversation(
    model_id: u64,
    system_prompt: Option<String>,
    max_output_tokens: u32,
) -> Result<u64, String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        native::start(model_id, system_prompt, max_output_tokens, None, false).await
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (model_id, system_prompt, max_output_tokens);
        Err("Native Core is unavailable on web".into())
    }
}

pub async fn core_start_sampled_conversation(
    model_id: u64,
    system_prompt: Option<String>,
    max_output_tokens: u32,
    sampling_json: Option<String>,
    thinking: bool,
) -> Result<u64, String> {
    let sampling: Option<omnix_core::SamplingOptions> = sampling_json
        .as_deref()
        .map(|json| serde_json::from_str(json).map_err(|_| "Invalid sampling configuration"))
        .transpose()?;
    if let Some(sampling) = &sampling {
        sampling.validate().map_err(|e| e.to_string())?;
    }
    #[cfg(not(target_arch = "wasm32"))]
    {
        native::start(
            model_id,
            system_prompt,
            max_output_tokens,
            sampling,
            thinking,
        )
        .await
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (
            model_id,
            system_prompt,
            max_output_tokens,
            sampling,
            thinking,
        );
        Err("Native Core is unavailable on web".into())
    }
}

/// Routes a host-approved local container to its compiled/trusted runtime.
pub async fn core_load_configured_model(
    model_path: String,
    library_path: Option<String>,
    context_tokens: u32,
    images: bool,
    audio: bool,
    cache_directory: String,
) -> Result<u64, String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        native::load_routed_configured(
            model_path,
            library_path,
            context_tokens,
            images,
            audio,
            Some(cache_directory),
        )
        .await
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (
            model_path,
            library_path,
            context_tokens,
            images,
            audio,
            cache_directory,
        );
        Err("Native Core is unavailable on web".into())
    }
}

/// Acquires an independent handle to a compatible shared native engine.
pub async fn core_load_shared_model(
    model_path: String,
    library_path: Option<String>,
    context_tokens: u32,
    images: bool,
    audio: bool,
    cache_directory: Option<String>,
) -> Result<u64, String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        native::load_routed_owned(
            model_path,
            library_path,
            context_tokens,
            images,
            audio,
            cache_directory,
            true,
        )
        .await
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (
            model_path,
            library_path,
            context_tokens,
            images,
            audio,
            cache_directory,
        );
        Err("Native Core is unavailable on web".into())
    }
}

/// Reports shared engines retained by this binding's owners and conversations.
#[flutter_rust_bridge::frb(sync)]
pub fn core_shared_model_count() -> Result<u32, String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        native::shared_count()
    }
    #[cfg(target_arch = "wasm32")]
    {
        Ok(0)
    }
}

/// Routes a host-approved local container to its compiled/trusted runtime.
pub async fn core_load_routed_model(
    model_path: String,
    library_path: Option<String>,
    context_tokens: u32,
) -> Result<u64, String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        native::load_routed(model_path, library_path, context_tokens).await
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (model_path, library_path, context_tokens);
        Err("Native Core is unavailable on web".into())
    }
}
pub async fn core_send(conversation_id: u64, text: String) -> Result<String, String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        native::send(conversation_id, text).await
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (conversation_id, text);
        Err("Native Core is unavailable on web".into())
    }
}

pub async fn core_load_media_model(
    model_path: String,
    library_path: Option<String>,
    context_tokens: u32,
    images: bool,
    audio: bool,
) -> Result<u64, String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        native::load_routed_with_media(model_path, library_path, context_tokens, images, audio)
            .await
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (model_path, library_path, context_tokens, images, audio);
        Err("Native Core is unavailable on web".into())
    }
}

pub async fn core_send_message(
    conversation_id: u64,
    parts: Vec<CoreInputPart>,
) -> Result<String, String> {
    let message = input_message(parts)?;
    #[cfg(not(target_arch = "wasm32"))]
    {
        native::send_message(conversation_id, message).await
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (conversation_id, message);
        Err("Native Core is unavailable on web".into())
    }
}

pub async fn core_send_message_stream(
    conversation_id: u64,
    parts: Vec<CoreInputPart>,
    sink: crate::frb_generated::StreamSink<String>,
) -> Result<(), String> {
    let message = input_message(parts)?;
    #[cfg(not(target_arch = "wasm32"))]
    {
        native::stream_message(conversation_id, message, sink).await
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (conversation_id, message, sink);
        Err("Native Core is unavailable on web".into())
    }
}

/// Streams distinct runtime output channels with explicit terminal events.
pub async fn core_send_message_events(
    conversation_id: u64,
    parts: Vec<CoreInputPart>,
    sink: crate::frb_generated::StreamSink<String>,
) -> Result<(), String> {
    let result = async {
        let message = input_message(parts)?;
        #[cfg(not(target_arch = "wasm32"))]
        {
            native::stream_output(conversation_id, message, sink.clone(), true).await
        }
        #[cfg(target_arch = "wasm32")]
        {
            let _ = (conversation_id, message);
            Err::<(), String>("Native Core is unavailable on web".into())
        }
    }
    .await;
    if let Err(error) = result {
        let _ = sink.add(serde_json::json!({"kind":"failed", "text":error}).to_string());
    }
    Ok(())
}

/// Exports native text history, or restores a versioned snapshot into a fresh conversation.
pub async fn core_conversation_history(
    conversation_id: u64,
    snapshot: Option<String>,
    thinking: Option<bool>,
) -> Result<String, String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        native::history(conversation_id, snapshot, thinking).await
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (conversation_id, snapshot, thinking);
        Err("Native Core is unavailable on web".into())
    }
}
pub async fn core_reconfigure_conversation(
    conversation_id: u64,
    max_output_tokens: u32,
    sampling_json: Option<String>,
) -> Result<(), String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        let sampling = sampling_json
            .map(|json| serde_json::from_str::<omnix_core::SamplingOptions>(&json))
            .transpose()
            .map_err(|_| "Invalid sampling configuration")?;
        native::reconfigure(conversation_id, max_output_tokens, sampling).await
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (conversation_id, max_output_tokens, sampling_json);
        Err("Native Core is unavailable on web".into())
    }
}

pub async fn core_set_thinking(conversation_id: u64, enabled: bool) -> Result<(), String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        native::set_thinking(conversation_id, enabled).await
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (conversation_id, enabled);
        Err("Native Core is unavailable on web".into())
    }
}

pub async fn core_send_stream(
    conversation_id: u64,
    text: String,
    sink: crate::frb_generated::StreamSink<String>,
) -> Result<(), String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        native::stream(conversation_id, text, sink).await
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (conversation_id, text, sink);
        Err("Native Core is unavailable on web".into())
    }
}

pub fn core_cancel_generation(conversation_id: u64) -> Result<(), String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        native::cancel(conversation_id)
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = conversation_id;
        Ok(())
    }
}
pub async fn core_close_model(model_id: u64) -> Result<(), String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        native::close_model(model_id).await
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = model_id;
        Ok(())
    }
}
pub async fn core_close_conversation(conversation_id: u64) -> Result<(), String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        native::close_chat(conversation_id).await
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = conversation_id;
        Ok(())
    }
}
