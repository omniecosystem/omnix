//! C host bindings for the independent Omnix inference crate.
#![deny(unsafe_op_in_unsafe_fn)]

use omnix_core::litertlm::LiteRtLmProvider;
use omnix_core::{
    Conversation, ConversationOptions, CoreError, CoreMessage, InputModality, LoadedModel,
    MessagePart, ModelFormat, ModelRequest, RuntimeProvider, RuntimeRegistry, StreamOutcome,
};
use std::ffi::{c_char, c_void, CStr, CString};
use std::path::Path;
use std::ptr::null_mut;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};

pub struct OmnixModel(Box<dyn LoadedModel>);
pub struct OmnixConversation(Box<dyn Conversation>);
pub struct OmnixCancellation(Arc<AtomicBool>);

#[repr(C)]
pub struct OmnixPart {
    kind: u32,
    data: *const u8,
    size: usize,
}

type TextCallback = unsafe extern "C" fn(*mut c_void, *const u8, usize) -> bool;

unsafe fn utf8<'a>(text: *const c_char) -> Result<&'a str, CoreError> {
    if text.is_null() {
        return Err(CoreError::InvalidRequest);
    }
    unsafe { CStr::from_ptr(text) }
        .to_str()
        .map_err(|_| CoreError::InvalidRequest)
}

fn result<T>(
    error: *mut *mut c_char,
    fallback: T,
    run: impl FnOnce() -> Result<T, CoreError>,
) -> T {
    let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(run))
        .unwrap_or_else(|_| Err(CoreError::BackendFailure("host-binding-panic".into())));
    if let Some(error) = unsafe { error.as_mut() } {
        *error = match &outcome {
            Ok(_) => null_mut(),
            Err(cause) => CString::new(cause.to_string()).map_or(null_mut(), CString::into_raw),
        };
    }
    outcome.unwrap_or(fallback)
}

#[no_mangle]
pub unsafe extern "C" fn omnix_model_open(
    path: *const c_char,
    cache_dir: *const c_char,
    context_tokens: u32,
    images: bool,
    audio: bool,
    error: *mut *mut c_char,
) -> *mut OmnixModel {
    result(error, null_mut(), || {
        let path = Path::new(unsafe { utf8(path)? });
        let mut modalities = [InputModality::Text]
            .into_iter()
            .collect::<std::collections::BTreeSet<_>>();
        if images {
            modalities.insert(InputModality::Image);
        }
        if audio {
            modalities.insert(InputModality::Audio);
        }
        let mut provider =
            LiteRtLmProvider::from_bundled_with_modalities(context_tokens, modalities.clone())?;
        if !cache_dir.is_null() {
            provider = provider.with_cache_directory(Path::new(unsafe { utf8(cache_dir)? }))?;
        }
        let platform = provider
            .descriptor()
            .platforms
            .iter()
            .next()
            .copied()
            .ok_or(CoreError::NoCompatibleProvider)?;
        let mut registry = RuntimeRegistry::default();
        registry.register(Box::new(provider))?;
        let model = registry.load(
            &ModelRequest {
                format: ModelFormat::LiteRtLm,
                platform,
                input_modalities: modalities,
                thinking: false,
                tools: false,
                preferred_provider: None,
            },
            path,
        )?;
        Ok(Box::into_raw(Box::new(OmnixModel(model))))
    })
}

#[no_mangle]
pub unsafe extern "C" fn omnix_model_close(model: *mut OmnixModel) {
    if !model.is_null() {
        drop(unsafe { Box::from_raw(model) });
    }
}

#[no_mangle]
pub unsafe extern "C" fn omnix_conversation_open(
    model: *mut OmnixModel,
    system_prompt: *const c_char,
    output_tokens: u32,
    error: *mut *mut c_char,
) -> *mut OmnixConversation {
    result(error, null_mut(), || {
        let model = unsafe { model.as_ref() }.ok_or(CoreError::InvalidRequest)?;
        let conversation = model.0.start_conversation(ConversationOptions {
            thinking: false,
            system_prompt: if system_prompt.is_null() {
                None
            } else {
                Some(unsafe { utf8(system_prompt)? }.to_owned())
            },
            max_output_tokens: output_tokens,
            sampling: None,
        })?;
        Ok(Box::into_raw(Box::new(OmnixConversation(conversation))))
    })
}

#[no_mangle]
pub unsafe extern "C" fn omnix_conversation_close(conversation: *mut OmnixConversation) {
    if !conversation.is_null() {
        drop(unsafe { Box::from_raw(conversation) });
    }
}

#[no_mangle]
pub extern "C" fn omnix_cancellation_new() -> *mut OmnixCancellation {
    Box::into_raw(Box::new(OmnixCancellation(Arc::new(AtomicBool::new(
        false,
    )))))
}

#[no_mangle]
pub unsafe extern "C" fn omnix_cancel(cancel: *const OmnixCancellation) {
    if let Some(cancel) = unsafe { cancel.as_ref() } {
        cancel.0.store(true, Ordering::Release);
    }
}

#[no_mangle]
pub unsafe extern "C" fn omnix_cancellation_free(cancel: *mut OmnixCancellation) {
    if !cancel.is_null() {
        drop(unsafe { Box::from_raw(cancel) });
    }
}

#[no_mangle]
pub unsafe extern "C" fn omnix_conversation_send(
    conversation: *mut OmnixConversation,
    parts: *const OmnixPart,
    count: usize,
    cancel: *const OmnixCancellation,
    callback: Option<TextCallback>,
    user: *mut c_void,
    error: *mut *mut c_char,
) -> i32 {
    result(error, -1, || {
        let conversation = unsafe { conversation.as_mut() }.ok_or(CoreError::InvalidRequest)?;
        let cancel = unsafe { cancel.as_ref() }.ok_or(CoreError::InvalidRequest)?;
        let callback = callback.ok_or(CoreError::InvalidRequest)?;
        if parts.is_null() || !(1..=16).contains(&count) {
            return Err(CoreError::InvalidRequest);
        }
        let input = unsafe { std::slice::from_raw_parts(parts, count) };
        let mut owned = Vec::with_capacity(count);
        for part in input {
            let limit = match part.kind {
                0 => 1 << 20,
                1 => 8 << 20,
                2 => 2 << 20,
                _ => return Err(CoreError::InvalidRequest),
            };
            if part.data.is_null() || part.size == 0 || part.size > limit {
                return Err(CoreError::InvalidRequest);
            }
            let bytes = unsafe { std::slice::from_raw_parts(part.data, part.size) };
            owned.push(match part.kind {
                0 => MessagePart::Text(
                    std::str::from_utf8(bytes)
                        .map_err(|_| CoreError::InvalidRequest)?
                        .to_owned(),
                ),
                1 => MessagePart::Image(bytes.to_vec()),
                _ => MessagePart::Audio(bytes.to_vec()),
            });
        }
        let user = user as usize;
        let outcome = conversation.0.send_message_stream(
            &CoreMessage { parts: owned },
            Box::new(move |text| unsafe {
                callback(user as *mut c_void, text.as_ptr(), text.len())
            }),
            cancel.0.clone(),
        )?;
        Ok(match outcome {
            StreamOutcome::Completed => 0,
            StreamOutcome::Cancelled => 1,
        })
    })
}

#[no_mangle]
pub unsafe extern "C" fn omnix_string_free(string: *mut c_char) {
    if !string.is_null() {
        drop(unsafe { CString::from_raw(string) });
    }
}
