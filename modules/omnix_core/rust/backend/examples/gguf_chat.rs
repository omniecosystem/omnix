// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
use omnix_core::{llamacpp::LlamaCppProvider, *};
use std::{
    path::PathBuf,
    sync::{atomic::AtomicBool, Arc},
};
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = PathBuf::from(
        std::env::args()
            .nth(1)
            .ok_or("Provide an absolute trusted GGUF path")?,
    );
    let mut registry = RuntimeRegistry::default();
    registry.register(Box::new(LlamaCppProvider::new(2048)?))?;
    let model = registry.load(
        &ModelRequest {
            format: probe_model_format(&path)?,
            platform: TargetPlatform::Windows,
            input_modalities: [InputModality::Text].into(),
            thinking: false,
            tools: false,
            preferred_provider: None,
        },
        &path,
    )?;
    let mut chat = model.start_conversation(ConversationOptions {
        thinking: false,
        system_prompt: None,
        max_output_tokens: 96,
        sampling: None,
    })?;
    drop(model);
    chat.send_stream(
        "Explain what a rainbow is in one short sentence.",
        Box::new(|text| {
            print!("{text}");
            true
        }),
        Arc::new(AtomicBool::new(false)),
    )?;
    println!();
    Ok(())
}
