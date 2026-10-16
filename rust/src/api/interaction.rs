// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
//! Root binding owns its handles; companion handles never cross library boundaries.

// Validate the bridge envelope before loading runtime libraries or providers.
fn execution_config(raw: &str) -> Result<(usize, usize, u64), String> {
    if raw.len() > 256 {
        return Err("Invalid execution admission configuration".into());
    }
    let value: serde_json::Value =
        serde_json::from_str(raw).map_err(|_| "Invalid execution admission configuration")?;
    let fields = value
        .as_object()
        .ok_or("Invalid execution admission configuration")?;
    if fields.len() != 3 {
        return Err("Invalid execution admission configuration".into());
    }
    let slots = value["maxActive"]
        .as_u64()
        .filter(|n| (1..=16).contains(n))
        .ok_or("Invalid execution active limit")?;
    let queue = value["maxWaiting"]
        .as_u64()
        .filter(|n| *n <= 256)
        .ok_or("Invalid execution waiting limit")?;
    let wait = value["waitMilliseconds"]
        .as_u64()
        .filter(|n| *n <= 300_000)
        .ok_or("Invalid execution waiting duration")?;
    if (queue == 0) != (wait == 0) {
        return Err("Queue capacity and wait duration must both be zero or both positive".into());
    }
    Ok((slots as usize, queue as usize, wait))
}

fn runtime_config(raw: &str) -> Result<serde_json::Value, String> {
    if raw.len() > 16384 {
        return Err("Runtime configuration too large".into());
    }
    let value: serde_json::Value =
        serde_json::from_str(raw).map_err(|_| "Invalid runtime configuration")?;
    let object = value.as_object().ok_or("Invalid runtime configuration")?;
    if object
        .keys()
        .any(|key| !["backend", "cacheDirectory", "dispatchDirectory"].contains(&key.as_str()))
    {
        return Err("Unknown runtime configuration field".into());
    }
    if !matches!(value["backend"].as_str(), Some("cpu" | "gpu" | "npu")) {
        return Err("Invalid LiteRT-LM backend".into());
    }
    for key in ["cacheDirectory", "dispatchDirectory"] {
        if let Some(path) = object.get(key) {
            let path = path
                .as_str()
                .filter(|path| !path.contains('\0'))
                .ok_or("Invalid runtime directory")?;
            if !std::path::Path::new(path).is_absolute() || !std::path::Path::new(path).is_dir() {
                return Err("Runtime directory must exist and be absolute".into());
            }
        }
    }
    if object.contains_key("dispatchDirectory") && value["backend"] != "npu" {
        return Err("Dispatch directory requires NPU".into());
    }
    Ok(value)
}

/// Point-in-time inference admission counts for this root engine.
pub fn interaction_execution_snapshot(engine_id: u64) -> Result<String, String> {
    #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
    {
        let snapshot = native::engine(engine_id)?
            .execution_snapshot()
            .map_err(|e| e.to_string())?;
        Ok(serde_json::json!({"active":snapshot.active,"waiting":snapshot.waiting}).to_string())
    }
    #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
    {
        let _ = engine_id;
        Err("Native Core is not selected".into())
    }
}

#[cfg(test)]
mod admission_tests {
    use super::execution_config;
    #[test]
    fn runtime_options_validate_backend_and_paths_without_native_loading() {
        for backend in ["cpu", "gpu", "npu"] {
            assert_eq!(
                super::runtime_config(&format!(r#"{{"backend":"{backend}"}}"#)).unwrap()["backend"],
                backend
            );
        }
        for raw in [
            "null",
            "{}",
            r#"{"backend":"auto"}"#,
            r#"{"backend":"gpu","unknown":1}"#,
            r#"{"backend":"cpu","cacheDirectory":"relative"}"#,
            r#"{"backend":"npu","dispatchDirectory":null}"#,
        ] {
            assert!(super::runtime_config(raw).is_err(), "{raw}");
        }
        let directory = tempfile::tempdir().unwrap();
        let options = serde_json::json!({"backend":"npu","dispatchDirectory":directory.path(),"cacheDirectory":directory.path()});
        super::runtime_config(&options.to_string()).unwrap();
        let mut invalid = options;
        invalid["backend"] = "cpu".into();
        assert!(super::runtime_config(&invalid.to_string()).is_err());
    }
    #[test]
    fn bridge_limits_are_explicit_and_validated_before_engine_creation() {
        assert_eq!(
            execution_config(r#"{"maxActive":1,"maxWaiting":2,"waitMilliseconds":100}"#).unwrap(),
            (1, 2, 100)
        );
        for raw in [
            "{}",
            "null",
            r#"{"maxActive":0,"maxWaiting":0,"waitMilliseconds":0}"#,
            r#"{"maxActive":1,"maxWaiting":1,"waitMilliseconds":0}"#,
            r#"{"maxActive":1,"maxWaiting":0,"waitMilliseconds":1}"#,
            r#"{"maxActive":17,"maxWaiting":0,"waitMilliseconds":0}"#,
            r#"{"maxActive":1,"maxWaiting":257,"waitMilliseconds":1}"#,
            r#"{"maxActive":1,"maxWaiting":1,"waitMilliseconds":300001}"#,
            r#"{"maxActive":1,"maxWaiting":0,"waitMilliseconds":0,"extra":false}"#,
        ] {
            assert!(execution_config(raw).is_err(), "{raw}");
        }
    }
}

/// Releases idle provider resources without interrupting conversations or embeddings.
pub fn interaction_release_idle_resources(engine_id: u64) -> Result<String, String> {
    #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
    {
        let report = native::engine(engine_id)?
            .release_idle_resources()
            .map_err(|e| e.to_string())?;
        Ok(serde_json::json!({"knowledge": format!("{:?}", report.knowledge), "retainedChatModels": report.retained_chat_models}).to_string())
    }
    #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
    {
        let _ = engine_id;
        Err("Native Core is not selected".into())
    }
}

pub fn interaction_configure_context(
    session_id: u64,
    enabled: bool,
    safety_margin: u32,
) -> Result<(), String> {
    #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
    {
        let entry = native::entry(session_id)?;
        let mut session = entry.session.try_lock().map_err(|_| "Session busy")?;
        session
            .as_mut()
            .ok_or("Session closed")?
            .configure_context(enabled.then_some(crate::context::RecentContextPolicy {
                safety_margin: safety_margin as usize,
            }))
            .map_err(|e| e.to_string())
    }
    #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
    {
        let _ = (session_id, enabled, safety_margin);
        Err("Native Core is not selected".into())
    }
}

pub fn interaction_context_usage(session_id: u64) -> Result<String, String> {
    #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
    {
        let entry = native::entry(session_id)?;
        let mut session = entry.session.try_lock().map_err(|_| "Session busy")?;
        let usage = session
            .as_mut()
            .ok_or("Session closed")?
            .context_usage()
            .map_err(|e| e.to_string())?;
        serde_json::to_string(&usage).map_err(|_| "Context encoding failed".into())
    }
    #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
    {
        let _ = session_id;
        Err("Native Core is not selected".into())
    }
}

#[allow(clippy::too_many_arguments)] // Keep the existing generated bridge signature stable.
pub fn interaction_open_sampled(
    engine_id: u64,
    model_path: String,
    system_prompt: Option<String>,
    max_output_tokens: u32,
    images: bool,
    audio: bool,
    sampling_json: Option<String>,
    thinking: bool,
) -> Result<u64, String> {
    #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
    {
        let sampling: Option<crate::core::SamplingOptions> = sampling_json
            .as_deref()
            .map(|json| serde_json::from_str(json).map_err(|_| "Invalid sampling configuration"))
            .transpose()?;
        if let Some(sampling) = &sampling {
            sampling.validate().map_err(|e| e.to_string())?;
        }
        native::open_sampled(
            engine_id,
            model_path,
            system_prompt,
            max_output_tokens,
            images,
            audio,
            sampling,
            thinking,
        )
    }
    #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
    {
        let _ = (
            engine_id,
            model_path,
            system_prompt,
            max_output_tokens,
            images,
            audio,
            sampling_json,
            thinking,
        );
        Err("Native Core is not selected".into())
    }
}

#[cfg(all(feature = "core", not(target_arch = "wasm32")))]
pub(super) mod native {
    use crate::{
        core::*,
        session::{Omnix, Session},
    };
    use std::{
        collections::HashMap,
        path::Path,
        sync::{
            atomic::{AtomicBool, AtomicU64, Ordering},
            Arc, Mutex, OnceLock,
        },
    };
    pub(super) struct Entry {
        pub session: Mutex<Option<Session>>,
        pub cancel: Arc<AtomicBool>,
        pub sources: Mutex<Vec<crate::session::ContextSource>>,
    }
    static NEXT: AtomicU64 = AtomicU64::new(1);
    static ENGINES: OnceLock<Mutex<HashMap<u64, Arc<Omnix>>>> = OnceLock::new();
    static SESSIONS: OnceLock<Mutex<HashMap<u64, Arc<Entry>>>> = OnceLock::new();
    fn engines() -> &'static Mutex<HashMap<u64, Arc<Omnix>>> {
        ENGINES.get_or_init(Default::default)
    }
    pub(in crate::api) fn engine(id: u64) -> Result<Arc<Omnix>, String> {
        engines()
            .lock()
            .map_err(|_| "Engine registry unavailable")?
            .get(&id)
            .cloned()
            .ok_or("Engine closed".into())
    }
    fn sessions() -> &'static Mutex<HashMap<u64, Arc<Entry>>> {
        SESSIONS.get_or_init(Default::default)
    }
    pub(in crate::api) fn id() -> Result<u64, String> {
        NEXT.fetch_update(Ordering::Relaxed, Ordering::Relaxed, |n| n.checked_add(1))
            .map_err(|_| "Handle space exhausted".into())
    }
    pub(super) fn entry(id: u64) -> Result<Arc<Entry>, String> {
        sessions()
            .lock()
            .map_err(|_| "Session registry unavailable")?
            .get(&id)
            .cloned()
            .ok_or("Session closed".into())
    }
    pub(super) type ContextFactory =
        Box<dyn FnOnce(&Omnix) -> Result<Box<dyn crate::session::ContextProvider>, String>>;
    pub(super) fn create(
        runtimes: Vec<String>,
        library: Option<String>,
        tokens: u32,
        context: Option<ContextFactory>,
        execution_json: Option<String>,
        runtime_json: Option<String>,
    ) -> Result<u64, String> {
        let runtime_options = runtime_json
            .as_deref()
            .map(super::runtime_config)
            .transpose()?;
        if runtime_options.is_some() && !runtimes.iter().any(|r| r == "litertlm") {
            return Err("LiteRT-LM configuration requires the litertlm runtime".into());
        }
        let execution = execution_json
            .as_deref()
            .map(super::execution_config)
            .transpose()?;
        if runtimes.is_empty()
            || !(128..=32768).contains(&tokens)
            || runtimes
                .iter()
                .enumerate()
                .any(|(i, r)| runtimes[..i].contains(r))
        {
            return Err("Select at least one runtime".into());
        }
        let mut registry = RuntimeRegistry::default();
        for runtime in runtimes {
            match runtime.as_str() {
                #[cfg(feature = "core-litertlm")]
                "litertlm" => {
                    // Provider capability is not a request to enable every
                    // encoder. Each model load selects its requested modalities.
                    let modalities = [
                        InputModality::Text,
                        InputModality::Image,
                        InputModality::Audio,
                    ]
                    .into();
                    let path = match &library {
                        Some(path) => std::path::PathBuf::from(path),
                        None => litertlm::LiteRtLmProvider::bundled_library_path()
                            .map_err(|e| e.to_string())?,
                    };
                    let mut provider = unsafe {
                        litertlm::LiteRtLmProvider::from_library_with_modalities(
                            &path, tokens, modalities,
                        )
                    }
                    .map_err(|e| e.to_string())?;
                    if let Some(options) = &runtime_options {
                        let backend =
                            litertlm::LiteRtLmBackend::parse(options["backend"].as_str().unwrap())
                                .map_err(|e| e.to_string())?;
                        let dispatch = if backend == litertlm::LiteRtLmBackend::Npu {
                            options["dispatchDirectory"]
                                .as_str()
                                .map(Path::new)
                                .or_else(|| path.parent())
                        } else {
                            None
                        };
                        provider = provider
                            .with_backend(backend, dispatch)
                            .map_err(|e| e.to_string())?;
                        if let Some(directory) = options["cacheDirectory"].as_str() {
                            provider = provider
                                .with_cache_directory(Path::new(directory))
                                .map_err(|e| e.to_string())?;
                        }
                    }
                    registry
                        .register(Box::new(provider))
                        .map_err(|e| e.to_string())?;
                }
                #[cfg(feature = "core-llamacpp")]
                "llamacpp" => registry
                    .register(Box::new(
                        llamacpp::LlamaCppProvider::new(tokens).map_err(|e| e.to_string())?,
                    ))
                    .map_err(|e| e.to_string())?,
                _ => return Err("Requested runtime is not compiled into Omnix".into()),
            }
        }
        let mut engine = Omnix::new(registry);
        if let Some((slots, queue, wait)) = execution {
            engine = engine.with_execution_admission(
                execution::ExecutionAdmission::new(slots, queue).map_err(|e| e.to_string())?,
                std::time::Duration::from_millis(wait),
            );
        }
        if let Some(context) = context {
            let provider = context(&engine)?;
            engine = engine.with_knowledge(SharedContext(provider));
        }
        let id = id()?;
        engines()
            .lock()
            .map_err(|_| "Engine registry unavailable")?
            .insert(id, Arc::new(engine));
        Ok(id)
    }
    pub(super) fn open(
        engine: u64,
        path: String,
        system: Option<String>,
        limit: u32,
    ) -> Result<u64, String> {
        open_media(engine, path, system, limit, false, false)
    }
    pub(super) fn open_media(
        engine: u64,
        path: String,
        system: Option<String>,
        limit: u32,
        images: bool,
        audio: bool,
    ) -> Result<u64, String> {
        open_sampled(engine, path, system, limit, images, audio, None, false)
    }
    #[allow(clippy::too_many_arguments)] // Mirrors the bridge's explicit session configuration.
    pub(super) fn open_sampled(
        engine: u64,
        path: String,
        system: Option<String>,
        limit: u32,
        images: bool,
        audio: bool,
        sampling: Option<SamplingOptions>,
        thinking: bool,
    ) -> Result<u64, String> {
        if let Some(sampling) = &sampling {
            sampling.validate().map_err(|e| e.to_string())?;
        }
        let engine = engines()
            .lock()
            .map_err(|_| "Engine registry unavailable")?
            .get(&engine)
            .cloned()
            .ok_or("Engine closed")?;
        let platform = if cfg!(target_os = "windows") {
            TargetPlatform::Windows
        } else if cfg!(target_os = "android") {
            TargetPlatform::Android
        } else {
            return Err("Target not qualified".into());
        };
        let request = ModelRequest {
            format: probe_model_format(Path::new(&path)).map_err(|e| e.to_string())?,
            platform,
            input_modalities: [
                Some(InputModality::Text),
                images.then_some(InputModality::Image),
                audio.then_some(InputModality::Audio),
            ]
            .into_iter()
            .flatten()
            .collect(),
            thinking,
            tools: false,
            preferred_provider: None,
        };
        let model = engine
            .load_model(&request, Path::new(&path))
            .map_err(|e| e.to_string())?;
        let session = engine
            .start_session(
                &model,
                ConversationOptions {
                    thinking,
                    system_prompt: system,
                    max_output_tokens: limit,
                    sampling,
                },
            )
            .map_err(|e| e.to_string())?;
        let id = id()?;
        sessions()
            .lock()
            .map_err(|_| "Session registry unavailable")?
            .insert(
                id,
                Arc::new(Entry {
                    session: Mutex::new(Some(session)),
                    cancel: Arc::new(AtomicBool::new(false)),
                    sources: Mutex::new(vec![]),
                }),
            );
        Ok(id)
    }
    struct SharedContext(Box<dyn crate::session::ContextProvider>);
    impl crate::session::ContextProvider for SharedContext {
        fn release_idle(
            &self,
        ) -> Result<crate::session::IdleRelease, crate::session::SessionError> {
            self.0.release_idle()
        }
        fn index(
            &self,
            document: crate::session::KnowledgeDocument,
        ) -> Result<(), crate::session::SessionError> {
            self.0.index(document)
        }
        fn retrieve(
            &self,
            query: &str,
        ) -> Result<Vec<crate::session::ContextSource>, crate::session::SessionError> {
            self.0.retrieve(query)
        }
    }
    pub(super) fn close_session(id: u64) -> Result<(), String> {
        let entry = sessions()
            .lock()
            .map_err(|_| "Session registry unavailable")?
            .remove(&id);
        if let Some(entry) = entry {
            entry.cancel.store(true, Ordering::Release);
            entry
                .session
                .lock()
                .map_err(|_| "Session unavailable")?
                .take();
        }
        Ok(())
    }
    pub(super) fn close_engine(id: u64) -> Result<(), String> {
        engines()
            .lock()
            .map_err(|_| "Engine registry unavailable")?
            .remove(&id);
        Ok(())
    }
}

pub fn interaction_create(
    runtimes: Vec<String>,
    library_path: Option<String>,
    context_tokens: u32,
    execution_json: Option<String>,
    runtime_json: Option<String>,
) -> Result<u64, String> {
    #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
    {
        native::create(
            runtimes,
            library_path,
            context_tokens,
            None,
            execution_json,
            runtime_json,
        )
    }
    #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
    {
        let _ = (
            runtimes,
            library_path,
            context_tokens,
            execution_json,
            runtime_json,
        );
        Err("Native Core is not selected in the root Omnix build".into())
    }
}
pub fn interaction_open(
    engine_id: u64,
    model_path: String,
    system_prompt: Option<String>,
    max_output_tokens: u32,
) -> Result<u64, String> {
    #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
    {
        native::open(engine_id, model_path, system_prompt, max_output_tokens)
    }
    #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
    {
        let _ = (engine_id, model_path, system_prompt, max_output_tokens);
        Err("Native Core is not selected".into())
    }
}
/// Opens an existing profile-bound index and owns its encoder in the root library.
/// The trusted host must release other owners of this shard before calling.
// Keep the existing generated bridge signature stable; configuration is
// represented as an object in the public Dart facade.
#[allow(clippy::too_many_arguments)]
pub fn interaction_create_with_knowledge(
    runtimes: Vec<String>,
    library_path: Option<String>,
    context_tokens: u32,
    embedding_model: String,
    store_path: String,
    top_k: u32,
    threshold: f32,
    public_only: bool,
    execution_json: Option<String>,
    create_store: bool,
    runtime_json: Option<String>,
) -> Result<u64, String> {
    if top_k == 0 || top_k > 16 || !threshold.is_finite() || !(-1.0..=1.0).contains(&threshold) {
        return Err("Invalid retrieval limits".into());
    }
    if let Some(raw) = execution_json.as_deref() {
        execution_config(raw)?;
    }
    #[cfg(all(feature = "knowledge-local", not(target_arch = "wasm32")))]
    {
        use crate::knowledge::{AccessScope, SearchOptions};
        use std::path::Path;
        let provider: native::ContextFactory = Box::new(move |engine| {
            let open = if create_store {
                crate::local_knowledge::NativeLocalKnowledge::create_with_engine
            } else {
                crate::local_knowledge::NativeLocalKnowledge::open_with_engine
            };
            let provider = open(
                Path::new(&embedding_model),
                Path::new(&store_path),
                SearchOptions {
                    top_k: top_k as usize,
                    threshold,
                    scope: if public_only {
                        AccessScope::PublicOnly
                    } else {
                        AccessScope::LocalAll
                    },
                },
                engine,
            )
            .map_err(|e| e.to_string())?;
            Ok(Box::new(provider))
        });
        return native::create(
            runtimes,
            library_path,
            context_tokens,
            Some(provider),
            execution_json,
            runtime_json,
        );
    }
    #[cfg(not(all(feature = "knowledge-local", not(target_arch = "wasm32"))))]
    {
        let _ = (
            runtimes,
            library_path,
            context_tokens,
            embedding_model,
            store_path,
            public_only,
            execution_json,
            create_store,
            runtime_json,
        );
        Err("Local Knowledge is not compiled into root Omnix".into())
    }
}

/// Indexes and flushes a host-supplied document in the root-owned Knowledge store.
pub fn interaction_knowledge_index(engine_id: u64, record_json: String) -> Result<(), String> {
    #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
    {
        if record_json.len() > 262144 {
            return Err("Invalid Knowledge document".into());
        }
        let value: serde_json::Value =
            serde_json::from_str(&record_json).map_err(|_| "Invalid Knowledge document")?;
        let object = value.as_object().ok_or("Invalid Knowledge document")?;
        if object.len() != 5 {
            return Err("Invalid Knowledge document".into());
        }
        let text = |key: &str| -> Result<String, String> {
            let value = object
                .get(key)
                .and_then(|v| v.as_str())
                .filter(|v| !v.trim().is_empty())
                .ok_or("Invalid Knowledge document")?;
            Ok(value.into())
        };
        let document = crate::session::KnowledgeDocument {
            id: text("id")?,
            document_id: text("documentId")?,
            title: text("title")?,
            content: text("content")?,
            public: object
                .get("public")
                .and_then(|v| v.as_bool())
                .ok_or("Invalid Knowledge document")?,
        };
        native::engine(engine_id)?
            .index_document(document)
            .map_err(|e| e.to_string())
    }
    #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
    {
        let _ = (engine_id, record_json);
        Err("Native Core is not selected".into())
    }
}

/// Retrieves authorized sources through the root-owned encoder and store.
pub fn interaction_knowledge_search(engine_id: u64, query: String) -> Result<String, String> {
    #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
    {
        let sources = native::engine(engine_id)?
            .retrieve_sources(&query)
            .map_err(|e| e.to_string())?;
        serde_json::to_string(
            &sources
                .iter()
                .map(|s| serde_json::json!({"title":s.title,"content":s.content}))
                .collect::<Vec<_>>(),
        )
        .map_err(|e| e.to_string())
    }
    #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
    {
        let _ = (engine_id, query);
        Err("Native Core is not selected".into())
    }
}

pub fn interaction_grounded_stream(
    session_id: u64,
    text: String,
    knowledge: String,
    sink: crate::frb_generated::StreamSink<String>,
) -> Result<(), String> {
    #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
    {
        let policy = match knowledge.as_str() {
            "disabled" => crate::session::KnowledgeUse::Disabled,
            "ifAvailable" => crate::session::KnowledgeUse::IfAvailable,
            "required" => crate::session::KnowledgeUse::Required,
            _ => return Err("Invalid Knowledge policy".into()),
        };
        let entry = native::entry(session_id)?;
        let mut session = entry.session.try_lock().map_err(|_| "Session busy")?;
        entry
            .sources
            .lock()
            .map_err(|_| "Sources unavailable")?
            .clear();
        let result = session
            .as_mut()
            .ok_or("Session closed")?
            .send_grounded_stream(
                &text,
                policy,
                Box::new(move |delta| sink.add(delta).is_ok()),
                entry.cancel.clone(),
            );
        match result {
            Ok((crate::core::StreamOutcome::Completed, sources)) => {
                *entry.sources.lock().map_err(|_| "Sources unavailable")? = sources;
                Ok(())
            }
            Ok(_) => Ok(()),
            Err(error) => {
                session.take();
                Err(error.to_string())
            }
        }
    }
    #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
    {
        let _ = (session_id, text, knowledge, sink);
        Err("Native Core is not selected".into())
    }
}

pub fn interaction_sources(session_id: u64) -> Result<String, String> {
    #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
    {
        let entry = native::entry(session_id)?;
        let _session = entry.session.try_lock().map_err(|_| "Session busy")?;
        if _session.is_none() {
            return Err("Session closed".into());
        }
        let sources = entry.sources.lock().map_err(|_| "Sources unavailable")?;
        serde_json::to_string(
            &sources
                .iter()
                .map(|s| serde_json::json!({"title": s.title, "content": s.content}))
                .collect::<Vec<_>>(),
        )
        .map_err(|_| "Source encoding failed".into())
    }
    #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
    {
        let _ = session_id;
        Err("Native Core is not selected".into())
    }
}
pub fn interaction_history(session_id: u64) -> Result<String, String> {
    #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
    {
        let entry = native::entry(session_id)?;
        let mut session = entry.session.lock().map_err(|_| "Session unavailable")?;
        let session = session.as_mut().ok_or("Session closed")?;
        let value = match session.history() {
            Ok(history) => serde_json::json!({"version":1,"messages":history}),
            Err(crate::session::SessionError::Core(crate::core::CoreError::BackendFailure(
                reason,
            ))) if reason == "media-history-export-unsupported" => {
                let context = session.export_checkpoint().map_err(|e| e.to_string())?;
                serde_json::json!({"version":2,"context":context})
            }
            Err(error) => return Err(error.to_string()),
        };
        serde_json::to_string(&value).map_err(|_| "History encoding failed".into())
    }
    #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
    {
        let _ = session_id;
        Err("Native Core is not selected".into())
    }
}
pub fn interaction_reconfigure(
    session_id: u64,
    max_output_tokens: u32,
    sampling_json: Option<String>,
) -> Result<(), String> {
    #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
    {
        let sampling = sampling_json
            .map(|json| serde_json::from_str::<crate::core::SamplingOptions>(&json))
            .transpose()
            .map_err(|_| "Invalid sampling configuration")?;
        let entry = native::entry(session_id)?;
        let mut session = entry.session.try_lock().map_err(|_| "Session busy")?;
        session
            .as_mut()
            .ok_or("Session closed")?
            .reconfigure(max_output_tokens, sampling)
            .map_err(|e| e.to_string())
    }
    #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
    {
        let _ = (session_id, max_output_tokens, sampling_json);
        Err("Native Core is not selected".into())
    }
}
pub fn interaction_set_thinking(session_id: u64, enabled: bool) -> Result<(), String> {
    #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
    {
        let entry = native::entry(session_id)?;
        let mut session = entry.session.try_lock().map_err(|_| "Session busy")?;
        session
            .as_mut()
            .ok_or("Session closed")?
            .set_thinking(enabled)
            .map_err(|e| e.to_string())
    }
    #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
    {
        let _ = (session_id, enabled);
        Err("Native Core is not selected".into())
    }
}
pub fn interaction_restore(
    session_id: u64,
    history: String,
    thinking: Option<bool>,
) -> Result<(), String> {
    #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
    {
        if history.len() > 20 * 1024 * 1024 {
            return Err("History exceeds limit".into());
        }
        let value: serde_json::Value =
            serde_json::from_str(&history).map_err(|_| "Invalid history")?;
        let entry = native::entry(session_id)?;
        let mut session = entry.session.lock().map_err(|_| "Session unavailable")?;
        let session = session.as_mut().ok_or("Session closed")?;
        match value["version"].as_u64() {
            Some(3) => {
                if thinking.is_some() {
                    return Err(
                        "Portable history uses the fresh session's configured thinking setting"
                            .into(),
                    );
                }
                session
                    .import_portable_history(
                        crate::core::history::parse_document(&history)
                            .map_err(|e| e.to_string())?,
                    )
                    .map_err(|e| e.to_string())
            }
            Some(1) => {
                if history.len() > 1_048_576 {
                    return Err("History exceeds limit".into());
                }
                let pairs = serde_json::from_value(value["messages"].clone())
                    .map_err(|_| "Invalid history messages")?;
                match thinking {
                    Some(enabled) => session.restore_history_with_thinking(pairs, enabled),
                    None => session.restore_history(pairs),
                }
                .map_err(|e| e.to_string())
            }
            Some(2) => {
                let context = value["context"].as_str().ok_or("Invalid native context")?;
                match thinking {
                    Some(enabled) => session.restore_checkpoint_with_thinking(context, enabled),
                    None => session.restore_checkpoint(context),
                }
                .map_err(|e| e.to_string())
            }
            _ => Err("Unsupported history version".into()),
        }
    }
    #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
    {
        let _ = (session_id, history, thinking);
        Err("Native Core is not selected".into())
    }
}
pub fn interaction_stream(
    session_id: u64,
    text: String,
    sink: crate::frb_generated::StreamSink<String>,
) -> Result<(), String> {
    #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
    {
        let entry = native::entry(session_id)?;
        let mut session = entry.session.try_lock().map_err(|_| "Session busy")?;
        entry
            .sources
            .lock()
            .map_err(|_| "Sources unavailable")?
            .clear();
        let result = session
            .as_mut()
            .ok_or("Session closed")?
            .send_stream(
                &text,
                Box::new(move |delta| sink.add(delta).is_ok()),
                entry.cancel.clone(),
            )
            .map_err(|e| e.to_string());
        if result.is_err() {
            session.take();
        }
        result.map(|_| ())
    }
    #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
    {
        let _ = (session_id, text, sink);
        Err("Native Core is not selected".into())
    }
}
pub fn interaction_open_media(
    engine_id: u64,
    model_path: String,
    system_prompt: Option<String>,
    max_output_tokens: u32,
    images: bool,
    audio: bool,
) -> Result<u64, String> {
    #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
    {
        native::open_media(
            engine_id,
            model_path,
            system_prompt,
            max_output_tokens,
            images,
            audio,
        )
    }
    #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
    {
        let _ = (
            engine_id,
            model_path,
            system_prompt,
            max_output_tokens,
            images,
            audio,
        );
        Err("Native Core is not selected".into())
    }
}
pub fn interaction_message_stream(
    session_id: u64,
    parts: Vec<super::input::InteractionInputPart>,
    knowledge: String,
    sink: crate::frb_generated::StreamSink<String>,
) -> Result<(), String> {
    // Structured terminal events avoid FRB's unobserved stream-task errors.
    let result = (|| -> Result<(), String> {
        #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
        {
            let input = super::input::message(parts)?;
            let knowledge = match knowledge.as_str() {
                "disabled" => crate::session::KnowledgeUse::Disabled,
                "ifAvailable" => crate::session::KnowledgeUse::IfAvailable,
                "required" => crate::session::KnowledgeUse::Required,
                _ => return Err("Invalid Knowledge policy".into()),
            };
            let entry = native::entry(session_id)?;
            let mut session = entry.session.try_lock().map_err(|_| "Session busy")?;
            entry
                .sources
                .lock()
                .map_err(|_| "Sources unavailable")?
                .clear();
            let updates = sink.clone();
            let result = session
                .as_mut()
                .ok_or("Session closed")?
                .send_message_events(
                    &input,
                    knowledge,
                    Box::new(move |event| {
                        let (kind, text) = match event {
                            crate::core::ConversationDelta::Text(text) => ("text", text),
                            crate::core::ConversationDelta::Reasoning(text) => ("reasoning", text),
                        };
                        updates
                            .add(serde_json::json!({"kind":kind,"text":text}).to_string())
                            .is_ok()
                    }),
                    entry.cancel.clone(),
                );
            match result {
                Ok((crate::core::StreamOutcome::Completed, sources)) => {
                    *entry.sources.lock().map_err(|_| "Sources unavailable")? = sources;
                    sink.add(serde_json::json!({"kind":"completed"}).to_string())
                        .map_err(|_| "Stream closed")?;
                }
                Ok(_) => {
                    session.take();
                    let _ = sink.add(serde_json::json!({"kind":"cancelled"}).to_string());
                }
                Err(error) => {
                    session.take();
                    return Err(error.to_string());
                }
            }
            Ok(())
        }
        #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
        {
            let _ = (session_id, parts, knowledge);
            Err("Native Core is not selected".into())
        }
    })();
    if let Err(error) = result {
        let _ = sink.add(serde_json::json!({"kind":"failed","text":error}).to_string());
    }
    Ok(())
}
#[flutter_rust_bridge::frb(sync)]
pub fn interaction_prepare(session_id: u64) -> Result<(), String> {
    #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
    {
        let entry = native::entry(session_id)?;
        let session = entry.session.try_lock().map_err(|_| "Session busy")?;
        if session.is_none() {
            return Err("Session closed".into());
        }
        entry
            .cancel
            .store(false, std::sync::atomic::Ordering::Release);
        return Ok(());
    }
    #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
    {
        let _ = session_id;
        Err("Native Core is not selected".into())
    }
}
#[flutter_rust_bridge::frb(sync)]
pub fn interaction_cancel(session_id: u64) -> Result<(), String> {
    #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
    {
        native::entry(session_id)?
            .cancel
            .store(true, std::sync::atomic::Ordering::Release);
        return Ok(());
    }
    #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
    {
        let _ = session_id;
        Err("Native Core is not selected".into())
    }
}
pub fn interaction_close_session(session_id: u64) -> Result<(), String> {
    #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
    {
        native::close_session(session_id)
    }
    #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
    {
        let _ = session_id;
        Ok(())
    }
}
pub fn interaction_close_engine(engine_id: u64) -> Result<(), String> {
    #[cfg(all(feature = "core", not(target_arch = "wasm32")))]
    {
        native::close_engine(engine_id)
    }
    #[cfg(not(all(feature = "core", not(target_arch = "wasm32"))))]
    {
        let _ = engine_id;
        Ok(())
    }
}

#[cfg(test)]
mod knowledge_tests {
    #[cfg(feature = "core")]
    #[test]
    fn invalid_documents_are_rejected_before_engine_lookup() {
        for raw in [
            "not json",
            "{}",
            r#"{"id":"id","documentId":"doc","title":"Title","content":"","public":true}"#,
            r#"{"id":"id","documentId":"doc","title":"Title","content":"Content","public":"true"}"#,
        ] {
            assert_eq!(
                super::interaction_knowledge_index(u64::MAX, raw.into()).unwrap_err(),
                "Invalid Knowledge document"
            );
        }
    }
    use super::*;
    #[test]
    fn invalid_retrieval_settings_fail_before_loading_native_resources() {
        for (top_k, threshold) in [(0, 0.7), (17, 0.7), (3, f32::NAN), (3, 1.1)] {
            let error = interaction_create_with_knowledge(
                vec!["litertlm".into()],
                None,
                2048,
                "missing-model".into(),
                "missing-index".into(),
                top_k,
                threshold,
                true,
                None,
                false,
                None,
            )
            .unwrap_err();
            assert_eq!(error, "Invalid retrieval limits");
        }
    }
    #[cfg(feature = "knowledge-local")]
    #[test]
    fn invalid_paths_fail_without_creating_an_index_or_loading_a_model() {
        assert!(matches!(
            crate::local_knowledge::NativeLocalKnowledge::open(
                std::path::Path::new("relative-model"),
                std::path::Path::new("relative-index"),
                crate::knowledge::SearchOptions {
                    top_k: 3,
                    threshold: 0.7,
                    scope: crate::knowledge::AccessScope::PublicOnly
                }
            ),
            Err(crate::session::SessionError::InvalidRequest)
        ));
    }
}
