// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
//! Private ownership boundary around the upstream C API; no runtime wrapper crate.
#![deny(unsafe_op_in_unsafe_fn)]
#[allow(
    dead_code,
    non_camel_case_types,
    non_snake_case,
    non_upper_case_globals
)]
#[path = "llamacpp_bindings.rs"]
mod ffi;
use super::error;
use crate::CoreError;
use std::{
    ffi::{CStr, CString},
    marker::PhantomData,
    path::Path,
    ptr::NonNull,
};

unsafe extern "C" fn quiet_log(
    _: ffi::ggml_log_level,
    _: *const std::ffi::c_char,
    _: *mut std::ffi::c_void,
) {
}
pub(super) fn initialize() {
    // SAFETY: OnceLock in the adapter serializes process-global initialization.
    // The callback is static, non-panicking, and retains no native pointers.
    unsafe {
        ffi::llama_log_set(Some(quiet_log), std::ptr::null_mut());
        ffi::llama_backend_init();
    }
}
pub(super) struct NativeModel(NonNull<ffi::llama_model>);
// SAFETY: model weights/vocabulary are immutable after loading. Each chat owns
// a separate mutable context, and Arc prevents freeing weights while in use.
unsafe impl Send for NativeModel {}
unsafe impl Sync for NativeModel {}
impl Drop for NativeModel {
    fn drop(&mut self) {
        unsafe {
            ffi::llama_model_free(self.0.as_ptr());
        }
    }
}
impl NativeModel {
    pub(super) fn load(path: &Path) -> Result<Self, CoreError> {
        let path = CString::new(path.to_str().ok_or(CoreError::InvalidRequest)?)
            .map_err(|_| CoreError::InvalidRequest)?;
        // SAFETY: CString lives through the call; default params match the pinned ABI.
        let raw = unsafe {
            let mut params = ffi::llama_model_default_params();
            params.n_gpu_layers = 0;
            ffi::llama_model_load_from_file(path.as_ptr(), params)
        };
        NonNull::new(raw)
            .map(Self)
            .ok_or_else(|| error("gguf-load"))
    }
    fn vocab(&self) -> Result<*const ffi::llama_vocab, CoreError> {
        let raw = unsafe { ffi::llama_model_get_vocab(self.0.as_ptr()) };
        if raw.is_null() {
            Err(error("vocabulary-unavailable"))
        } else {
            Ok(raw)
        }
    }
    pub(super) fn template(&self) -> Result<&CStr, CoreError> {
        let ptr = unsafe { ffi::llama_model_chat_template(self.0.as_ptr(), std::ptr::null()) };
        if ptr.is_null() {
            return Err(error("chat-template-missing"));
        }
        // SAFETY: upstream returns a NUL-terminated borrowed model metadata string.
        Ok(unsafe { CStr::from_ptr(ptr) })
    }
    pub(super) fn format(
        &self,
        messages: &[(String, String)],
        limit: usize,
    ) -> Result<Vec<u8>, CoreError> {
        let strings = messages
            .iter()
            .map(|(r, t)| {
                Ok((
                    CString::new(r.as_str()).map_err(|_| CoreError::InvalidRequest)?,
                    CString::new(t.as_str()).map_err(|_| CoreError::InvalidRequest)?,
                ))
            })
            .collect::<Result<Vec<_>, CoreError>>()?;
        let chat = strings
            .iter()
            .map(|(r, t)| ffi::llama_chat_message {
                role: r.as_ptr(),
                content: t.as_ptr(),
            })
            .collect::<Vec<_>>();
        let template = self.template()?;
        let apply = |buffer: &mut [u8]| unsafe {
            // SAFETY: all borrowed strings and message arrays outlive both calls;
            // buffer is writable for exactly its supplied length.
            ffi::llama_chat_apply_template(
                template.as_ptr(),
                chat.as_ptr(),
                chat.len(),
                true,
                buffer.as_mut_ptr().cast(),
                buffer.len() as i32,
            )
        };
        let mut buf = vec![0; 1024.min(limit)];
        let mut count = apply(&mut buf);
        if count < 0 {
            return Err(error("chat-template-unsupported"));
        }
        if count as usize > limit {
            return Err(error("context-capacity"));
        }
        if count as usize > buf.len() {
            buf.resize(count as usize, 0);
            count = apply(&mut buf);
        }
        if count < 0 || count as usize > buf.len() {
            return Err(error("chat-template-unsupported"));
        }
        buf.truncate(count as usize);
        Ok(buf)
    }
    pub(super) fn tokenize(&self, text: &[u8], limit: usize) -> Result<Vec<i32>, CoreError> {
        let len = i32::try_from(text.len()).map_err(|_| error("context-capacity"))?;
        let mut tokens = vec![0; limit];
        let n = unsafe {
            ffi::llama_tokenize(
                self.vocab()?,
                text.as_ptr().cast(),
                len,
                tokens.as_mut_ptr(),
                limit as i32,
                true,
                true,
            )
        };
        if n < 0 || n as usize > limit {
            return Err(error("context-capacity"));
        }
        tokens.truncate(n as usize);
        Ok(tokens)
    }
    pub(super) fn is_eog(&self, token: i32) -> bool {
        // Valid model vocab was checked before tokenization; no intervening free.
        unsafe { ffi::llama_vocab_is_eog(ffi::llama_model_get_vocab(self.0.as_ptr()), token) }
    }
    pub(super) fn piece(&self, token: i32) -> Result<Vec<u8>, CoreError> {
        let vocab = self.vocab()?;
        let mut buf = vec![0u8; 128];
        let mut n = unsafe {
            ffi::llama_token_to_piece(
                vocab,
                token,
                buf.as_mut_ptr().cast(),
                buf.len() as i32,
                0,
                false,
            )
        };
        if n < 0 {
            let size = n.checked_neg().ok_or_else(|| error("token-piece"))? as usize;
            if size > 1024 * 1024 {
                return Err(error("token-piece"));
            }
            buf.resize(size, 0);
            n = unsafe {
                ffi::llama_token_to_piece(
                    vocab,
                    token,
                    buf.as_mut_ptr().cast(),
                    buf.len() as i32,
                    0,
                    false,
                )
            };
        }
        if n < 0 || n as usize > buf.len() {
            return Err(error("token-piece"));
        }
        buf.truncate(n as usize);
        Ok(buf)
    }
}
pub(super) struct NativeContext<'a> {
    raw: NonNull<ffi::llama_context>,
    _model: PhantomData<&'a NativeModel>,
}
impl Drop for NativeContext<'_> {
    fn drop(&mut self) {
        unsafe {
            ffi::llama_free(self.raw.as_ptr());
        }
    }
}
impl<'a> NativeContext<'a> {
    pub(super) fn new(
        model: &'a NativeModel,
        tokens: u32,
        threads: i32,
    ) -> Result<Self, CoreError> {
        let raw = unsafe {
            let mut p = ffi::llama_context_default_params();
            p.n_ctx = tokens;
            p.n_batch = 512;
            p.n_ubatch = 512;
            p.n_threads = threads;
            p.n_threads_batch = threads;
            ffi::llama_init_from_model(model.0.as_ptr(), p)
        };
        Ok(Self {
            raw: NonNull::new(raw).ok_or_else(|| error("context-create"))?,
            _model: PhantomData,
        })
    }
    pub(super) fn decode(&mut self, batch: &mut NativeBatch) -> Result<(), CoreError> {
        if unsafe { ffi::llama_decode(self.raw.as_ptr(), batch.0) } != 0 {
            Err(error("decode"))
        } else {
            Ok(())
        }
    }
}
pub(super) struct NativeBatch(ffi::llama_batch);
impl Drop for NativeBatch {
    fn drop(&mut self) {
        unsafe {
            ffi::llama_batch_free(self.0);
        }
    }
}
impl NativeBatch {
    pub(super) fn new() -> Result<Self, CoreError> {
        let batch = Self(unsafe { ffi::llama_batch_init(512, 0, 1) });
        if batch.0.token.is_null()
            || batch.0.pos.is_null()
            || batch.0.n_seq_id.is_null()
            || batch.0.seq_id.is_null()
            || batch.0.logits.is_null()
        {
            return Err(error("batch-create"));
        }
        Ok(batch)
    }
    pub(super) fn clear(&mut self) {
        self.0.n_tokens = 0;
    }
    pub(super) fn add(
        &mut self,
        token: i32,
        position: i32,
        seq: &[i32],
        logits: bool,
    ) -> Result<(), CoreError> {
        let i = self.0.n_tokens as usize;
        if i >= 512 || seq != [0] {
            return Err(error("batch-add"));
        }
        // SAFETY: batch_init allocated 512 slots, one sequence per token;
        // this index is bounded, and decode sees only initialized slots.
        unsafe {
            let sequence = *self.0.seq_id.add(i);
            if sequence.is_null() {
                return Err(error("batch-add"));
            }
            *self.0.token.add(i) = token;
            *self.0.pos.add(i) = position;
            *self.0.n_seq_id.add(i) = 1;
            *sequence = 0;
            *self.0.logits.add(i) = i8::from(logits);
        }
        self.0.n_tokens += 1;
        Ok(())
    }
}
pub(super) struct NativeSampler(NonNull<ffi::llama_sampler>);
impl Drop for NativeSampler {
    fn drop(&mut self) {
        unsafe {
            ffi::llama_sampler_free(self.0.as_ptr());
        }
    }
}
impl NativeSampler {
    pub(super) fn configured(options: Option<&crate::SamplingOptions>) -> Result<Self, CoreError> {
        let Some(options) = options else {
            return Self::greedy();
        };
        options.validate()?;
        if options.temperature == 0.0 {
            return Self::greedy();
        }
        let chain = NonNull::new(unsafe {
            ffi::llama_sampler_chain_init(ffi::llama_sampler_chain_default_params())
        })
        .map(Self)
        .ok_or_else(|| error("sampler-create"))?;
        unsafe {
            let add = |part| -> Result<(), CoreError> {
                let part = NonNull::new(part).ok_or_else(|| error("sampler-create"))?;
                ffi::llama_sampler_chain_add(chain.0.as_ptr(), part.as_ptr());
                Ok(())
            };
            add(ffi::llama_sampler_init_top_k(options.top_k as i32))?;
            add(ffi::llama_sampler_init_top_p(options.top_p, 1))?;
            add(ffi::llama_sampler_init_temp(options.temperature))?;
            add(ffi::llama_sampler_init_dist(options.seed))?;
        }
        Ok(chain)
    }
    pub(super) fn greedy() -> Result<Self, CoreError> {
        NonNull::new(unsafe { ffi::llama_sampler_init_greedy() })
            .map(Self)
            .ok_or_else(|| error("sampler-create"))
    }
    pub(super) fn sample(&mut self, ctx: &NativeContext<'_>) -> i32 {
        unsafe { ffi::llama_sampler_sample(self.0.as_ptr(), ctx.raw.as_ptr(), -1) }
    }
}

#[cfg(test)]
mod sampler_tests {
    use super::*;

    #[test]
    fn native_sampler_chain_and_greedy_paths_create_and_release() {
        let options = crate::SamplingOptions {
            temperature: 0.8,
            top_k: 40,
            top_p: 0.95,
            seed: 42,
        };
        drop(NativeSampler::configured(Some(&options)).unwrap());
        drop(
            NativeSampler::configured(Some(&crate::SamplingOptions {
                temperature: 0.0,
                ..options.clone()
            }))
            .unwrap(),
        );
        drop(NativeSampler::configured(None).unwrap());
        assert!(NativeSampler::configured(Some(&crate::SamplingOptions {
            top_k: 0,
            ..options
        }))
        .is_err());
    }
}
