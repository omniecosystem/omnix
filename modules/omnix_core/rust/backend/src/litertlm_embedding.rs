// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! EmbeddingGemma 2 through the official LiteRT-LM v0.18 C API.
//! The bundle owns tokenization, pooling and normalization. All native handles
//! and the library stay on one worker. No model or runtime is downloaded here.
use crate::{embedding::*, litertlm_embedding_bindings as ffi, CoreError};
use sha2::{Digest, Sha256};
use std::{ffi::CString, io::Read, path::Path, ptr, sync::mpsc, thread};

fn failure(message: impl Into<String>) -> CoreError {
    CoreError::BackendFailure(message.into())
}

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
        unsafe { (self.1)(self.0) };
    }
}

/// Model-card retrieval convention, versioned separately from legacy encoders.
fn retrieval_input(text: &str, task: EmbeddingTask) -> Result<String, CoreError> {
    let text = text.trim();
    if text.is_empty() || text.contains('\0') {
        return Err(CoreError::InvalidRequest);
    }
    Ok(match task {
        EmbeddingTask::RetrievalQuery => format!("task: search result | query: {text}"),
        EmbeddingTask::RetrievalDocument => format!("title: none | text: {text}"),
    })
}

enum Command {
    Embed(
        Vec<EmbeddingInput>,
        EmbeddingTask,
        mpsc::SyncSender<Result<Vec<f32>, CoreError>>,
    ),
    Close,
}

pub struct LiteRtLmEmbeddingModel {
    profile: EmbeddingProfile,
    sender: mpsc::Sender<Command>,
    worker: Option<thread::JoinHandle<()>>,
    multimodal: bool,
}
impl LiteRtLmEmbeddingModel {
    /// Opens the pinned v0.18 runtime (separate on Windows, shared on Android).
    pub fn from_bundled(model: &Path) -> Result<Self, CoreError> {
        let library = crate::bundled_runtime::embedding_path().map_err(failure)?;
        // Native Assets acquisition verifies the pinned v0.18 distribution.
        unsafe { Self::from_library(&library, model) }
    }
    pub fn from_bundled_multimodal(model: &Path) -> Result<Self, CoreError> {
        let library = crate::bundled_runtime::embedding_path().map_err(failure)?;
        unsafe { Self::from_library_multimodal(&library, model) }
    }
    /// # Safety
    /// The caller must supply a trusted LiteRT-LM v0.18.0 library and dependencies.
    /// The model must be a trusted, immutable EmbeddingGemma 2 text bundle.
    /// Symbol presence is not a substitute for ABI/artifact qualification.
    pub unsafe fn from_library(library: &Path, model: &Path) -> Result<Self, CoreError> {
        Self::open_library(library, model, false)
    }
    /// # Safety
    /// Requires trusted v0.18.0 runtime binaries and an immutable full bundle.
    pub unsafe fn from_library_multimodal(library: &Path, model: &Path) -> Result<Self, CoreError> {
        Self::open_library(library, model, true)
    }
    unsafe fn open_library(
        library: &Path,
        model: &Path,
        multimodal: bool,
    ) -> Result<Self, CoreError> {
        if !library.is_absolute() || !library.is_file() || !model.is_absolute() || !model.is_file()
        {
            return Err(CoreError::InvalidModelPath);
        }
        if crate::probe_model_format(model)? != crate::ModelFormat::LiteRtLm {
            return Err(CoreError::InvalidRequest);
        }
        let mut digest = Sha256::new();
        digest.update(b"omnix-embeddinggemma2-text-v1:litertlm-0.18:cpu-f32:search:768:normalized:overflow-error\0");
        if multimodal {
            digest.update(b"multimodal-v1:ordered-text-image-audio:cpu-encoders\0");
        }
        let mut file = std::fs::File::open(model).map_err(|_| failure("embedding-bundle-read"))?;
        let mut buffer = [0u8; 65536];
        loop {
            let count = file
                .read(&mut buffer)
                .map_err(|_| failure("embedding-bundle-read"))?;
            if count == 0 {
                break;
            }
            digest.update(&buffer[..count]);
        }
        let profile = EmbeddingProfile {
            id: format!("embeddinggemma2:{digest:x}", digest = digest.finalize()),
            dimension: 768,
        };
        let library = library.to_owned();
        let model = model.to_owned();
        let (sender, receiver) = mpsc::channel();
        let (initialized, ready) = mpsc::sync_channel(1);
        let worker = thread::Builder::new()
            .name("omnix-embeddinggemma2".into())
            .spawn(move || match Worker::open(&library, &model, multimodal) {
                Err(error) => {
                    let _ = initialized.send(Err(error));
                }
                Ok(mut worker) => {
                    if initialized.send(Ok(())).is_err() {
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
            })
            .map_err(|_| failure("embedding-engine-worker-start"))?;
        match ready.recv() {
            Ok(Ok(())) => Ok(Self {
                profile,
                sender,
                worker: Some(worker),
                multimodal,
            }),
            result => {
                let _ = worker.join();
                Err(match result {
                    Ok(Err(e)) => e,
                    _ => failure("embedding-engine-worker-initialize"),
                })
            }
        }
    }
}
impl EmbeddingModel for LiteRtLmEmbeddingModel {
    fn profile(&self) -> &EmbeddingProfile {
        &self.profile
    }
    fn generate_embedding(
        &mut self,
        text: &str,
        task: EmbeddingTask,
    ) -> Result<Vec<f32>, CoreError> {
        retrieval_input(text, task)?;
        self.generate_multimodal_embedding(&[EmbeddingInput::Text(text.into())], task)
    }
    fn generate_multimodal_embedding(
        &mut self,
        inputs: &[EmbeddingInput],
        task: EmbeddingTask,
    ) -> Result<Vec<f32>, CoreError> {
        validate_embedding_inputs(inputs)?;
        if !self.multimodal
            && inputs
                .iter()
                .any(|part| !matches!(part, EmbeddingInput::Text(_)))
        {
            return Err(failure("multimodal-embedding-not-enabled"));
        }
        let (reply, result) = mpsc::sync_channel(1);
        self.sender
            .send(Command::Embed(inputs.to_vec(), task, reply))
            .map_err(|_| failure("embedding-engine-closed"))?;
        result
            .recv()
            .map_err(|_| failure("embedding-engine-closed"))?
    }
}
impl Drop for LiteRtLmEmbeddingModel {
    fn drop(&mut self) {
        let _ = self.sender.send(Command::Close);
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
    }
}

struct Worker {
    // Drop handles before the dynamic library containing their destructors.
    engine: Resource<ffi::LiteRtLmEmbeddingEngine>,
    options: Resource<ffi::LiteRtLmEmbeddingOptions>,
    api: ffi::LiteRtLmEmbeddingApi,
}
impl Worker {
    unsafe fn open(library: &Path, model: &Path, multimodal: bool) -> Result<Self, CoreError> {
        #[cfg(windows)]
        let library: libloading::Library =
            libloading::os::windows::Library::load_with_flags(library, 0x00000100 | 0x00001000)
                .map_err(|e| failure(format!("embedding-engine-library:{e}")))?
                .into();
        #[cfg(not(windows))]
        let library = libloading::Library::new(library)
            .map_err(|e| failure(format!("embedding-engine-library:{e}")))?;
        let api = ffi::LiteRtLmEmbeddingApi::from_library(library)
            .map_err(|e| failure(format!("embedding-engine-requires-litertlm-0.18:{e}")))?;
        let path = CString::new(model.to_str().ok_or(CoreError::InvalidModelPath)?)
            .map_err(|_| CoreError::InvalidModelPath)?;
        let settings = Resource::new(
            (api.litert_lm_embedding_engine_settings_create)(
                path.as_ptr(),
                c"cpu".as_ptr(),
                if multimodal {
                    c"cpu".as_ptr()
                } else {
                    ptr::null()
                },
                if multimodal {
                    c"cpu".as_ptr()
                } else {
                    ptr::null()
                },
            ),
            api.litert_lm_embedding_engine_settings_delete,
            "embedding-engine-settings",
        )?;
        (api.litert_lm_embedding_engine_settings_set_activation_data_type)(
            settings.0,
            ffi::LiteRtLmActivationDataType_kLiteRtLmActivationDataTypeFloat32,
        );
        (api.litert_lm_embedding_engine_settings_set_max_input_length)(settings.0, 8192);
        let engine = Resource::new(
            (api.litert_lm_embedding_engine_create)(settings.0),
            api.litert_lm_embedding_engine_delete,
            "embedding-engine-create",
        )?;
        let options = Resource::new(
            (api.litert_lm_embedding_options_create)(),
            api.litert_lm_embedding_options_delete,
            "embedding-engine-options",
        )?;
        (api.litert_lm_embedding_options_set_normalize)(options.0, true);
        (api.litert_lm_embedding_options_set_insert_special_tokens)(options.0, true);
        (api.litert_lm_embedding_options_set_output_size)(options.0, 768);
        (api.litert_lm_embedding_options_set_input_overflow_strategy)(
            options.0,
            ffi::LiteRtLmInputOverflowStrategy_kLiteRtLmInputOverflowStrategyError,
        );
        Ok(Self {
            engine,
            options,
            api,
        })
    }
    fn embed(
        &mut self,
        parts: &[EmbeddingInput],
        task: EmbeddingTask,
    ) -> Result<Vec<f32>, CoreError> {
        validate_embedding_inputs(parts)?;
        // Apply a task prefix once, preserving input order. The runtime inserts
        // BOS/EOS and image/audio special tokens itself.
        let prefix = match task {
            EmbeddingTask::RetrievalQuery => "task: search result | query: ",
            EmbeddingTask::RetrievalDocument => "title: none | text: ",
        };
        let mut ordered = vec![EmbeddingInput::Text(prefix.into())];
        ordered.extend(parts.iter().cloned());
        if let [EmbeddingInput::Text(text)] = parts {
            ordered = vec![EmbeddingInput::Text(retrieval_input(text, task)?)];
        }
        unsafe {
            let resources: Result<Vec<_>, _> = ordered
                .iter()
                .map(|part| {
                    let (kind, data): (_, &[u8]) = match part {
                        EmbeddingInput::Text(text) => (
                            ffi::LiteRtLmInputDataType_kLiteRtLmInputDataTypeText,
                            text.as_bytes(),
                        ),
                        EmbeddingInput::Image(data) => (
                            ffi::LiteRtLmInputDataType_kLiteRtLmInputDataTypeImage,
                            data.as_slice(),
                        ),
                        EmbeddingInput::Audio(data) => (
                            ffi::LiteRtLmInputDataType_kLiteRtLmInputDataTypeAudio,
                            data.as_slice(),
                        ),
                    };
                    Resource::new(
                        (self.api.litert_lm_input_data_create)(
                            kind,
                            data.as_ptr().cast(),
                            data.len(),
                        ),
                        self.api.litert_lm_input_data_delete,
                        "embedding-engine-input",
                    )
                })
                .collect();
            let resources = resources?;
            let inputs: Vec<_> = resources
                .iter()
                .map(|input| input.0 as *const ffi::LiteRtLmInputData)
                .collect();
            let response = Resource::new(
                (self.api.litert_lm_embedding_engine_compute_embedding)(
                    self.engine.0,
                    inputs.as_ptr(),
                    inputs.len(),
                    self.options.0,
                ),
                self.api.litert_lm_embedding_response_delete,
                "embedding-engine-compute",
            )?;
            let length = (self.api.litert_lm_embedding_response_get_size)(response.0);
            let values = (self.api.litert_lm_embedding_response_get_values)(response.0);
            if length != 768 || values.is_null() {
                return Err(failure("embedding-engine-output-shape"));
            }
            let vector = std::slice::from_raw_parts(values, length).to_vec();
            validate_final(&vector, 768)?;
            Ok(vector)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn model_card_prefixes_and_invalid_input() {
        assert_eq!(
            retrieval_input(" bonjour ", EmbeddingTask::RetrievalQuery).unwrap(),
            "task: search result | query: bonjour"
        );
        assert_eq!(
            retrieval_input("guide", EmbeddingTask::RetrievalDocument).unwrap(),
            "title: none | text: guide"
        );
        for text in ["", " \n ", "hello\0world"] {
            assert_eq!(
                retrieval_input(text, EmbeddingTask::RetrievalQuery),
                Err(CoreError::InvalidRequest)
            );
        }
    }
}
