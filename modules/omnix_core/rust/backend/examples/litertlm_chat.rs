// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! Standalone text conversation with a host-provided model.

#[cfg(not(target_arch = "wasm32"))]
fn main() -> Result<(), Box<dyn std::error::Error>> {
    use omnix_core::{
        litertlm::{LiteRtLmBackend, LiteRtLmProvider},
        *,
    };
    use std::path::Path;
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() < 2 {
        return Err("Usage: litertlm_chat <absolute-model> <prompt> [follow-up ...]".into());
    }
    let platform = if cfg!(target_os = "android") {
        TargetPlatform::Android
    } else if cfg!(target_os = "windows") {
        TargetPlatform::Windows
    } else {
        return Err("This LiteRT-LM example supports Windows and Android only".into());
    };
    let provider = match std::env::var_os("OMNIX_LITERTLM_LIBRARY") {
        Some(path) => unsafe { LiteRtLmProvider::from_library(Path::new(&path), 2048)? },
        None => LiteRtLmProvider::from_bundled(2048)?,
    };
    let backend = LiteRtLmBackend::parse(
        &std::env::var("OMNIX_LITERTLM_BACKEND").unwrap_or_else(|_| "cpu".into()),
    )?;
    let dispatch = std::env::var_os("OMNIX_LITERTLM_DISPATCH_DIR");
    let provider = provider.with_backend(backend, dispatch.as_deref().map(Path::new))?;
    println!("Selected backend: {backend:?}");
    let provider = match std::env::var_os("OMNIX_LITERTLM_CACHE_DIR") {
        Some(directory) => provider.with_cache_directory(Path::new(&directory))?,
        None => provider,
    };
    let mut registry = RuntimeRegistry::default();
    registry.register(Box::new(provider))?;
    let model = registry.load(
        &ModelRequest {
            format: ModelFormat::LiteRtLm,
            platform,
            input_modalities: [InputModality::Text].into(),
            thinking: false,
            tools: false,
            preferred_provider: None,
        },
        Path::new(&args[0]),
    )?;
    let mut chat = model.start_conversation(ConversationOptions {
        thinking: false,
        system_prompt: Some("Answer briefly and clearly.".into()),
        max_output_tokens: 128,
        sampling: None,
    })?;
    // Demonstrates that a conversation safely retains its engine after model drop.
    drop(model);
    for (turn, prompt) in args[1..].iter().enumerate() {
        println!("Turn {}: {}", turn + 1, chat.send(prompt)?);
    }
    drop(chat);
    println!("Conversation and engine released.");
    Ok(())
}

#[cfg(target_arch = "wasm32")]
fn main() {
    eprintln!("The dynamic-library backend is not a web implementation.");
}
