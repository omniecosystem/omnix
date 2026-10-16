// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! CPU single-input, pooled-output LiteRT embedding adapter. Native handles and
//! the canonical SentencePiece processor stay on one worker thread.
use crate::{embedding::*, litert_embedding_bindings as ffi, CoreError};
use sha2::{Digest, Sha256};
use std::{
    alloc::{alloc_zeroed, dealloc, Layout},
    ffi::CString,
    io::Read,
    path::{Path, PathBuf},
    ptr,
    sync::mpsc,
    thread,
};

fn failure(message: impl Into<String>) -> CoreError {
    CoreError::BackendFailure(message.into())
}
fn check(status: i32, operation: &str) -> Result<(), CoreError> {
    if status == 0 {
        Ok(())
    } else {
        Err(failure(format!("{operation}:status-{status}")))
    }
}

/// Explicit model convention, not guessed from a filename or vocabulary size.
#[derive(Clone, Copy, Debug)]
pub enum LiteRtEmbeddingConvention {
    /// BOS=2, EOS=1, pad=0; task-specific retrieval prefixes; graph-pooled output.
    GemmaRetrieval,
    /// Explicit legacy Gecko compatibility: prepend ID 2 despite its disabled
    /// BOS metadata. Not interchangeable with a canonical Gecko preprocessing
    /// profile, and never inferred from dimensions or a filename.
    LegacyGeckoRetrieval,
}

enum Command {
    Embed(
        String,
        EmbeddingTask,
        mpsc::SyncSender<Result<Vec<f32>, CoreError>>,
    ),
    Close,
}

pub struct LiteRtEmbeddingModel {
    profile: EmbeddingProfile,
    sequence_length: usize,
    sender: mpsc::Sender<Command>,
    worker: Option<thread::JoinHandle<()>>,
}

impl LiteRtEmbeddingModel {
    /// Uses the selected build-time runtime; no inference-time acquisition.
    pub fn from_bundled(
        model: &Path,
        tokenizer: &Path,
        convention: LiteRtEmbeddingConvention,
    ) -> Result<Self, CoreError> {
        let runtime = crate::litertlm::LiteRtLmProvider::bundled_library_path()?
            .with_file_name("libLiteRt.dll");
        // This distribution is pinned by the existing Core acquisition hook.
        unsafe { Self::from_library(&runtime, model, tokenizer, convention) }
    }

    /// # Safety
    /// Library/dependencies must be trusted and implement the pinned LiteRT
    /// 9fe5be45 C ABI. Model/tokenizer must remain immutable while open.
    /// This adapter supports Windows x64 CPU with a single input and pooled
    /// output; it does not implement arbitrary TFLite graphs or GPU execution.
    pub unsafe fn from_library(
        runtime: &Path,
        model: &Path,
        tokenizer: &Path,
        convention: LiteRtEmbeddingConvention,
    ) -> Result<Self, CoreError> {
        for path in [runtime, model, tokenizer] {
            if !path.is_absolute() || !path.is_file() {
                return Err(CoreError::InvalidModelPath);
            }
        }
        let paths = (runtime.to_owned(), model.to_owned(), tokenizer.to_owned());
        let (sender, receiver) = mpsc::channel();
        let (initialized, ready) = mpsc::sync_channel(1);
        let worker = thread::Builder::new()
            .name("omnix-embedding".into())
            .spawn(move || {
                let result = unsafe { Worker::open(paths.0, paths.1, paths.2, convention) };
                match result {
                    Err(error) => {
                        let _ = initialized.send(Err(error));
                    }
                    Ok(mut worker) => {
                        if initialized
                            .send(Ok((worker.profile.clone(), worker.forward.seq)))
                            .is_err()
                        {
                            return;
                        }
                        while let Ok(command) = receiver.recv() {
                            match command {
                                Command::Embed(text, task, reply) => {
                                    let _ = reply.send(worker.embed(&text, task));
                                }
                                Command::Close => break,
                            }
                        }
                    }
                }
            })
            .map_err(|_| failure("embedding-worker-start"))?;
        match ready.recv() {
            Ok(Ok((profile, sequence_length))) => Ok(Self {
                profile,
                sequence_length,
                sender,
                worker: Some(worker),
            }),
            result => {
                let _ = worker.join();
                Err(match result {
                    Ok(Err(error)) => error,
                    _ => failure("embedding-worker-initialize"),
                })
            }
        }
    }

    pub fn input_sequence_length(&self) -> usize {
        self.sequence_length
    }
}

impl EmbeddingModel for LiteRtEmbeddingModel {
    fn profile(&self) -> &EmbeddingProfile {
        &self.profile
    }
    fn generate_embedding(
        &mut self,
        text: &str,
        task: EmbeddingTask,
    ) -> Result<Vec<f32>, CoreError> {
        if text.trim().is_empty() {
            return Err(CoreError::InvalidRequest);
        }
        let (reply, result) = mpsc::sync_channel(1);
        self.sender
            .send(Command::Embed(text.into(), task, reply))
            .map_err(|_| failure("embedding-worker-closed"))?;
        result
            .recv()
            .map_err(|_| failure("embedding-worker-closed"))?
    }
}
impl Drop for LiteRtEmbeddingModel {
    fn drop(&mut self) {
        let _ = self.sender.send(Command::Close);
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
    }
}

struct Worker {
    forward: Forward,
    tokenizer: sentencepiece::SentencePieceProcessor,
    profile: EmbeddingProfile,
}
impl Worker {
    unsafe fn open(
        runtime: PathBuf,
        model: PathBuf,
        tokenizer: PathBuf,
        convention: LiteRtEmbeddingConvention,
    ) -> Result<Self, CoreError> {
        let tokenizer_bytes =
            std::fs::read(&tokenizer).map_err(|_| failure("embedding-tokenizer-read"))?;
        let tokenizer =
            sentencepiece::SentencePieceProcessor::from_serialized_proto(&tokenizer_bytes)
                .map_err(|e| failure(format!("embedding-tokenizer:{e}")))?;
        // Reject a vocabulary that cannot satisfy the explicitly selected rule.
        let bos_matches = match convention {
            LiteRtEmbeddingConvention::GemmaRetrieval => tokenizer.bos_id() == Some(2),
            LiteRtEmbeddingConvention::LegacyGeckoRetrieval => {
                tokenizer.bos_id().is_none() && tokenizer.unk_id() == 2
            }
        };
        if !bos_matches || tokenizer.eos_id() != Some(1) || tokenizer.pad_id() != Some(0) {
            return Err(failure(format!(
                "embedding-tokenizer-convention-mismatch:bos={:?},eos={:?},pad={:?}",
                tokenizer.bos_id(),
                tokenizer.eos_id(),
                tokenizer.pad_id()
            )));
        }
        let forward = Forward::open(&runtime, &model)?;
        let mut hash = Sha256::new();
        hash.update(b"omnix-litert-cpu-gemma-retrieval-v1\0");
        hash.update(match convention {
            LiteRtEmbeddingConvention::GemmaRetrieval => b"gemma".as_slice(),
            LiteRtEmbeddingConvention::LegacyGeckoRetrieval => b"legacy-gecko".as_slice(),
        });
        hash.update((tokenizer_bytes.len() as u64).to_le_bytes());
        hash.update(&tokenizer_bytes);
        hash.update((forward.seq as u64).to_le_bytes());
        hash.update((forward.dim as u64).to_le_bytes());
        let mut file = std::fs::File::open(&model).map_err(|_| failure("embedding-model-read"))?;
        let mut buffer = [0u8; 65536];
        loop {
            let size = file
                .read(&mut buffer)
                .map_err(|_| failure("embedding-model-read"))?;
            if size == 0 {
                break;
            }
            hash.update(&buffer[..size]);
        }
        let profile = EmbeddingProfile {
            id: format!("litert-retrieval-v1:{:x}", hash.finalize()),
            dimension: forward.dim,
        };
        Ok(Self {
            forward,
            tokenizer,
            profile,
        })
    }
    fn embed(&mut self, text: &str, task: EmbeddingTask) -> Result<Vec<f32>, CoreError> {
        let prefix = match task {
            EmbeddingTask::RetrievalQuery => "task: search result | query: ",
            EmbeddingTask::RetrievalDocument => "title: none | text: ",
        };
        let pieces = self
            .tokenizer
            .encode(&format!("{prefix}{text}"))
            .map_err(|e| failure(format!("embedding-tokenize:{e}")))?;
        let tokens = pieces
            .into_iter()
            .map(|p| i32::try_from(p.id).map_err(|_| CoreError::InvalidRequest))
            .collect::<Result<Vec<_>, _>>()?;
        let tokens = prepare_tokens(&tokens, self.forward.seq)?;
        let vector = self.forward.run(&tokens)?;
        validate_final(&vector, self.profile.dimension)?;
        Ok(vector)
    }
}

// Reject overflow rather than silently truncate content or drop its EOS.
// Callers must size their chunks for this model's input width.
fn prepare_tokens(content: &[i32], width: usize) -> Result<Vec<i32>, CoreError> {
    if width < 2 || content.len() > width - 2 || content.iter().any(|id| *id < 0) {
        return Err(CoreError::InvalidRequest);
    }
    let mut result = vec![0; width];
    result[0] = 2;
    result[1..content.len() + 1].copy_from_slice(content);
    result[content.len() + 1] = 1;
    Ok(result)
}

struct Resource<T>(*mut T, unsafe extern "C" fn(*mut T));
impl<T> Resource<T> {
    fn new(handle: *mut T, destroy: unsafe extern "C" fn(*mut T)) -> Result<Self, CoreError> {
        if handle.is_null() {
            Err(failure("embedding-null-handle"))
        } else {
            Ok(Self(handle, destroy))
        }
    }
}
impl<T> Drop for Resource<T> {
    fn drop(&mut self) {
        unsafe { (self.1)(self.0) }
    }
}

struct Forward {
    // Declaration order is cleanup order. Library must outlive all handles.
    compiled: Resource<ffi::LiteRtCompiledModelT>,
    _options: Resource<ffi::LiteRtOptionsT>,
    _model: Resource<ffi::LiteRtModelT>,
    _environment: Resource<ffi::LiteRtEnvironmentT>,
    api: ffi::LiteRtEmbeddingApi,
    input: ffi::LiteRtRankedTensorType,
    output: ffi::LiteRtRankedTensorType,
    seq: usize,
    dim: usize,
}

fn width(
    tensor: &ffi::LiteRtRankedTensorType,
    element: i32,
    maximum: usize,
) -> Result<usize, CoreError> {
    let layout = &tensor.layout;
    if tensor.element_type != element
        || layout.rank() != 2
        || layout.has_strides() != 0
        || layout.dimensions[0] != 1
        || layout.dimensions[1] <= 0
        || layout.dimensions[1] as usize > maximum
    {
        return Err(failure("embedding-tensor-type-or-shape-unsupported"));
    }
    Ok(layout.dimensions[1] as usize)
}

impl Forward {
    unsafe fn open(runtime: &Path, model_path: &Path) -> Result<Self, CoreError> {
        #[cfg(windows)]
        let library: libloading::Library =
            libloading::os::windows::Library::load_with_flags(runtime, 0x100 | 0x1000)
                .map_err(|e| failure(format!("embedding-native-library:{e}")))?
                .into();
        #[cfg(not(windows))]
        let library = libloading::Library::new(runtime)
            .map_err(|e| failure(format!("embedding-native-library:{e}")))?;
        let api = ffi::LiteRtEmbeddingApi::from_library(library)
            .map_err(|e| failure(format!("embedding-native-symbol:{e}")))?;
        let mut environment = ptr::null_mut();
        check(
            (api.LiteRtCreateEnvironment)(0, ptr::null(), &mut environment),
            "embedding-environment",
        )?;
        let environment = Resource::new(environment, api.LiteRtDestroyEnvironment)?;
        let path = CString::new(model_path.to_str().ok_or(CoreError::InvalidModelPath)?)
            .map_err(|_| CoreError::InvalidModelPath)?;
        let mut model = ptr::null_mut();
        check(
            (api.LiteRtCreateModelFromFile)(environment.0, path.as_ptr(), &mut model),
            "embedding-model",
        )?;
        let model = Resource::new(model, api.LiteRtDestroyModel)?;
        let mut signature = ptr::null_mut();
        check(
            (api.LiteRtGetModelSignature)(model.0, 0, &mut signature),
            "embedding-signature",
        )?;
        let (mut inputs, mut outputs) = (0, 0);
        check(
            (api.LiteRtGetNumSignatureInputs)(signature, &mut inputs),
            "embedding-input-count",
        )?;
        check(
            (api.LiteRtGetNumSignatureOutputs)(signature, &mut outputs),
            "embedding-output-count",
        )?;
        if inputs != 1 || outputs != 1 {
            return Err(failure("embedding-requires-single-input-pooled-output"));
        }
        let (mut input_tensor, mut output_tensor) = (ptr::null_mut(), ptr::null_mut());
        check(
            (api.LiteRtGetSignatureInputTensorByIndex)(signature, 0, &mut input_tensor),
            "embedding-input",
        )?;
        check(
            (api.LiteRtGetSignatureOutputTensorByIndex)(signature, 0, &mut output_tensor),
            "embedding-output",
        )?;
        let (mut input, mut output): (ffi::LiteRtRankedTensorType, ffi::LiteRtRankedTensorType) =
            (std::mem::zeroed(), std::mem::zeroed());
        check(
            (api.LiteRtGetRankedTensorType)(input_tensor, &mut input),
            "embedding-input-type",
        )?;
        check(
            (api.LiteRtGetRankedTensorType)(output_tensor, &mut output),
            "embedding-output-type",
        )?;
        let seq = width(&input, 2, 8192)?;
        let dim = width(&output, 1, 65536)?;
        let mut options = ptr::null_mut();
        check((api.LiteRtCreateOptions)(&mut options), "embedding-options")?;
        let options = Resource::new(options, api.LiteRtDestroyOptions)?;
        check(
            (api.LiteRtSetOptionsHardwareAccelerators)(options.0, 1),
            "embedding-cpu",
        )?;
        let mut compiled = ptr::null_mut();
        check(
            (api.LiteRtCreateCompiledModel)(environment.0, model.0, options.0, &mut compiled),
            "embedding-compile",
        )?;
        let compiled = Resource::new(compiled, api.LiteRtDestroyCompiledModel)?;
        check(
            (api.LiteRtGetCompiledModelInputTensorLayout)(compiled.0, 0, 0, &mut input.layout),
            "embedding-input-layout",
        )?;
        check(
            (api.LiteRtGetCompiledModelOutputTensorLayouts)(
                compiled.0,
                0,
                1,
                &mut output.layout,
                false,
            ),
            "embedding-output-layout",
        )?;
        if width(&input, 2, 8192)? != seq || width(&output, 1, 65536)? != dim {
            return Err(failure("embedding-compiled-shape-changed"));
        }
        Ok(Self {
            compiled,
            _options: options,
            _model: model,
            _environment: environment,
            api,
            input,
            output,
            seq,
            dim,
        })
    }
    fn run(&mut self, tokens: &[i32]) -> Result<Vec<f32>, CoreError> {
        if tokens.len() != self.seq {
            return Err(CoreError::InvalidRequest);
        }
        let input_memory = Aligned::new(self.seq * 4)?;
        let output_memory = Aligned::new(self.dim * 4)?;
        unsafe {
            ptr::copy_nonoverlapping(
                tokens.as_ptr(),
                input_memory.pointer.cast::<i32>(),
                tokens.len(),
            );
            let (mut input, mut output) = (ptr::null_mut(), ptr::null_mut());
            check(
                (self.api.LiteRtCreateTensorBufferFromHostMemory)(
                    &self.input,
                    input_memory.pointer.cast(),
                    self.seq * 4,
                    None,
                    &mut input,
                ),
                "embedding-input-buffer",
            )?;
            let input = Resource::new(input, self.api.LiteRtDestroyTensorBuffer)?;
            check(
                (self.api.LiteRtCreateTensorBufferFromHostMemory)(
                    &self.output,
                    output_memory.pointer.cast(),
                    self.dim * 4,
                    None,
                    &mut output,
                ),
                "embedding-output-buffer",
            )?;
            let output = Resource::new(output, self.api.LiteRtDestroyTensorBuffer)?;
            let (mut input_handle, mut output_handle) = (input.0, output.0);
            check(
                (self.api.LiteRtRunCompiledModel)(
                    self.compiled.0,
                    0,
                    1,
                    &mut input_handle,
                    1,
                    &mut output_handle,
                ),
                "embedding-forward",
            )?;
            let mut locked = ptr::null_mut();
            check(
                (self.api.LiteRtLockTensorBuffer)(output.0, &mut locked, 0),
                "embedding-lock-output",
            )?;
            // Always unlock after a successful lock, including an invalid pointer.
            let vector = if locked.is_null() {
                Err(failure("embedding-null-output"))
            } else {
                Ok(std::slice::from_raw_parts(locked.cast::<f32>(), self.dim).to_vec())
            };
            check(
                (self.api.LiteRtUnlockTensorBuffer)(output.0),
                "embedding-unlock-output",
            )?;
            vector
        }
    }
}
struct Aligned {
    pointer: *mut u8,
    layout: Layout,
}
impl Aligned {
    fn new(bytes: usize) -> Result<Self, CoreError> {
        let layout = Layout::from_size_align(bytes, 64).map_err(|_| CoreError::InvalidRequest)?;
        let pointer = unsafe { alloc_zeroed(layout) };
        if pointer.is_null() {
            return Err(failure("embedding-buffer-allocation"));
        }
        Ok(Self { pointer, layout })
    }
}
impl Drop for Aligned {
    fn drop(&mut self) {
        unsafe { dealloc(self.pointer, self.layout) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn explicit_terminators_padding_and_overflow() {
        assert_eq!(prepare_tokens(&[10, 11], 6).unwrap(), [2, 10, 11, 1, 0, 0]);
        assert_eq!(prepare_tokens(&[10, 11], 4).unwrap(), [2, 10, 11, 1]);
        assert!(prepare_tokens(&[10, 11, 12], 4).is_err());
        assert!(prepare_tokens(&[-1], 4).is_err());
    }
    #[test]
    fn generated_windows_x64_tensor_layout() {
        assert_eq!(std::mem::size_of::<ffi::LiteRtLayout>(), 68);
        assert_eq!(std::mem::size_of::<ffi::LiteRtRankedTensorType>(), 72);
        assert_eq!(std::mem::offset_of!(ffi::LiteRtLayout, dimensions), 4);
    }
}
