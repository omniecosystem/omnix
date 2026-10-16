// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
//! Opt-in CPU/text llama.cpp adapter. Model weights are shared; each turn
//! replays the conversation into a fresh context. No self-referential handles,
//! runtime downloads, generic-template fallback, or implicit context eviction.

use crate::*;
#[path = "llamacpp_native.rs"]
mod native;
use native::{NativeBatch, NativeContext, NativeModel, NativeSampler};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex, OnceLock,
};

fn error(code: &str) -> CoreError {
    CoreError::BackendFailure(code.into())
}

// llama.cpp initialization is process-global. Never free it while another
// provider/model can still use it. This singleton lives for the process lifetime.
fn backend() {
    static BACKEND: OnceLock<()> = OnceLock::new();
    BACKEND.get_or_init(native::initialize);
}

pub struct LlamaCppProvider {
    descriptor: ProviderDescriptor,
    context_tokens: u32,
}
impl LlamaCppProvider {
    /// Constructs a CPU/text provider for Windows. Other targets are not
    /// accepted by this adapter, even if the native sources compile there.
    pub fn new(context_tokens: u32) -> Result<Self, CoreError> {
        if !(128..=32768).contains(&context_tokens) {
            return Err(CoreError::InvalidRequest);
        }
        Ok(Self {
            context_tokens,
            descriptor: ProviderDescriptor {
                id: "llamacpp-cpu".into(),
                priority: 0,
                formats: [ModelFormat::Gguf].into(),
                platforms: [TargetPlatform::Windows].into(),
                input_modalities: [InputModality::Text].into(),
                thinking: false,
                tools: false,
            },
        })
    }
}
impl RuntimeProvider for LlamaCppProvider {
    fn descriptor(&self) -> &ProviderDescriptor {
        &self.descriptor
    }
    fn load(&self, request: &ModelRequest, path: &Path) -> Result<Box<dyn LoadedModel>, CoreError> {
        if !cfg!(target_os = "windows") || !self.descriptor.supports(request) {
            return Err(CoreError::NoCompatibleProvider);
        }
        if probe_model_format(path)? != ModelFormat::Gguf {
            return Err(error("model-format-mismatch"));
        }
        backend();
        let model = NativeModel::load(path)?;
        // Missing/unsupported templates fail explicitly, never guess ChatML.
        model.template()?;
        Ok(Box::new(Model {
            model: Arc::new(model),
            context_tokens: self.context_tokens,
        }))
    }
}
struct Model {
    model: Arc<NativeModel>,
    context_tokens: u32,
}
impl LoadedModel for Model {
    fn provider_id(&self) -> &str {
        "llamacpp-cpu"
    }
    fn start_conversation(
        &self,
        options: ConversationOptions,
    ) -> Result<Box<dyn Conversation>, CoreError> {
        if options.thinking {
            return Err(error("reasoning-channels-unsupported:llamacpp"));
        }
        if let Some(sampling) = &options.sampling {
            sampling.validate()?;
        }
        if options.max_output_tokens == 0 || options.max_output_tokens >= self.context_tokens {
            return Err(CoreError::InvalidRequest);
        }
        let mut history = vec![];
        if let Some(system) = &options.system_prompt {
            if system.contains('\0') {
                return Err(CoreError::InvalidRequest);
            }
            history.push(("system".into(), system.clone()));
        }
        Ok(Box::new(Chat {
            model: self.model.clone(),
            context_tokens: self.context_tokens,
            options,
            history,
        }))
    }
}
struct Chat {
    model: Arc<NativeModel>,
    context_tokens: u32,
    options: ConversationOptions,
    history: Vec<(String, String)>,
}
impl Conversation for Chat {
    fn reconfigure(
        &mut self,
        tokens: u32,
        sampling: Option<SamplingOptions>,
    ) -> Result<(), CoreError> {
        if tokens == 0 || tokens > self.context_tokens {
            return Err(CoreError::InvalidRequest);
        }
        if let Some(settings) = &sampling {
            settings.validate()?;
        }
        self.options.max_output_tokens = tokens;
        self.options.sampling = sampling;
        Ok(())
    }
    fn history(&mut self) -> Result<Vec<(String, String)>, CoreError> {
        Ok(self
            .history
            .iter()
            .filter(|(role, _)| role != "system")
            .cloned()
            .collect())
    }

    fn restore_history(&mut self, messages: Vec<(String, String)>) -> Result<(), CoreError> {
        crate::validate_history(&messages)?;
        if self.history.iter().any(|(role, _)| role != "system") {
            return Err(CoreError::InvalidRequest);
        }
        self.history.extend(messages);
        Ok(())
    }
    fn send(&mut self, text: &str) -> Result<String, CoreError> {
        let output = Arc::new(Mutex::new(String::new()));
        let collected = output.clone();
        self.send_stream(
            text,
            Box::new(move |delta| {
                collected.lock().unwrap().push_str(&delta);
                true
            }),
            Arc::new(AtomicBool::new(false)),
        )?;
        let result = output
            .lock()
            .map_err(|_| error("response-unavailable"))?
            .clone();
        Ok(result)
    }
    fn send_stream(
        &mut self,
        text: &str,
        mut consumer: Box<dyn FnMut(String) -> bool + Send>,
        cancel: Arc<AtomicBool>,
    ) -> Result<StreamOutcome, CoreError> {
        if text.trim().is_empty() || text.contains('\0') {
            return Err(CoreError::InvalidRequest);
        }
        if cancel.load(Ordering::Acquire) {
            return Ok(StreamOutcome::Cancelled);
        }
        let mut messages = self.history.clone();
        messages.push(("user".into(), text.into()));
        // Bound input before the C template/tokenizer APIs allocate buffers.
        if messages.iter().map(|(_, s)| s.len()).sum::<usize>() > self.context_tokens as usize * 128
        {
            return Err(error("context-capacity"));
        }
        let prompt = self
            .model
            .format(&messages, self.context_tokens as usize * 256)?;
        let tokens = self.model.tokenize(&prompt, self.context_tokens as usize)?;
        if tokens.is_empty()
            || tokens.len() + self.options.max_output_tokens as usize > self.context_tokens as usize
        {
            return Err(error("context-capacity"));
        }
        let threads = std::thread::available_parallelism().map_or(2, |n| n.get().min(8)) as i32;
        let mut context = NativeContext::new(&self.model, self.context_tokens, threads)?;
        let mut batch = NativeBatch::new()?;
        let mut position = 0i32;
        for chunk in tokens.chunks(512) {
            if cancel.load(Ordering::Acquire) {
                return Ok(StreamOutcome::Cancelled);
            }
            batch.clear();
            for token in chunk {
                batch
                    .add(
                        *token,
                        position,
                        &[0],
                        position as usize == tokens.len() - 1,
                    )
                    .map_err(|_| error("batch-add"))?;
                position += 1;
            }
            context
                .decode(&mut batch)
                .map_err(|_| error("prompt-decode"))?;
        }
        let mut sampler = NativeSampler::configured(self.options.sampling.as_ref())?;
        let mut decoder = Utf8Pieces::default();
        let mut answer = String::new();
        let mut outcome = StreamOutcome::Completed;
        for _ in 0..self.options.max_output_tokens {
            if cancel.load(Ordering::Acquire) {
                outcome = StreamOutcome::Cancelled;
                break;
            }
            let token = sampler.sample(&context);
            if self.model.is_eog(token) {
                break;
            }
            let delta = decoder.push(&self.model.piece(token)?)?;
            answer.push_str(&delta);
            if !delta.is_empty() && !consumer(delta) {
                outcome = StreamOutcome::Cancelled;
                break;
            }
            batch.clear();
            batch
                .add(token, position, &[0], true)
                .map_err(|_| error("batch-add"))?;
            context
                .decode(&mut batch)
                .map_err(|_| error("token-decode"))?;
            position += 1;
        }
        // A cancelled byte sequence may be partial; never emit replacement text.
        if outcome == StreamOutcome::Completed && !decoder.pending.is_empty() {
            return Err(error("response-incomplete-utf8"));
        }
        if answer.is_empty() && outcome == StreamOutcome::Completed {
            return Err(error("response-empty"));
        }
        messages.push(("assistant".into(), answer));
        self.history = messages; // Commit only successful/completed or stopped turns.
        Ok(outcome)
    }
}

#[derive(Default)]
struct Utf8Pieces {
    pending: Vec<u8>,
}
impl Utf8Pieces {
    fn push(&mut self, bytes: &[u8]) -> Result<String, CoreError> {
        self.pending.extend_from_slice(bytes);
        let length = match std::str::from_utf8(&self.pending) {
            Ok(_) => self.pending.len(),
            Err(e) if e.error_len().is_none() => e.valid_up_to(),
            Err(_) => return Err(error("response-invalid-utf8")),
        };
        let text = std::str::from_utf8(&self.pending[..length])
            .unwrap()
            .to_owned();
        self.pending.drain(..length);
        Ok(text)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn preserves_split_unicode_without_inserted_spaces() {
        let mut decoder = Utf8Pieces::default();
        assert_eq!(decoder.push(&[b'A', 0xe2]).unwrap(), "A");
        assert_eq!(decoder.push(&[0x82]).unwrap(), "");
        assert_eq!(decoder.push(&[0xac, b'B']).unwrap(), "€B");
        assert!(decoder.push(&[0xff]).is_err());
    }
    #[test]
    fn rejects_invalid_context_limits() {
        assert!(LlamaCppProvider::new(127).is_err());
        assert!(LlamaCppProvider::new(32769).is_err());
    }
}
