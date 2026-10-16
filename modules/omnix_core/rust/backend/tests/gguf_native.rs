// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
#![cfg(all(feature = "llamacpp", target_os = "windows"))]
use omnix_core::{llamacpp::LlamaCppProvider, *};
use std::{
    path::PathBuf,
    sync::{atomic::AtomicBool, Arc},
};
#[test]
#[ignore = "requires trusted OMNIX_GGUF_MODEL"]
fn real_gguf_stream_stop_history_and_isolation() -> Result<(), Box<dyn std::error::Error>> {
    let path = PathBuf::from(std::env::var("OMNIX_GGUF_MODEL")?);
    let mut registry = RuntimeRegistry::default();
    registry.register(Box::new(LlamaCppProvider::new(2048)?))?;
    let request = ModelRequest {
        format: probe_model_format(&path)?,
        platform: TargetPlatform::Windows,
        input_modalities: [InputModality::Text].into(),
        thinking: false,
        tools: false,
        preferred_provider: None,
    };
    let model = registry.load(&request, &path)?;
    assert_eq!(model.provider_id(), "llamacpp-cpu");
    let mut unsupported = request.clone();
    unsupported.tools = true;
    assert!(registry.select(&unsupported).is_err());
    let options = ConversationOptions {
        thinking: false,
        system_prompt: Some("Answer briefly.".into()),
        max_output_tokens: 64,
        sampling: None,
    };
    assert!(model
        .start_conversation(ConversationOptions {
            thinking: false,
            max_output_tokens: 0,
            sampling: None,
            system_prompt: None
        })
        .is_err());
    let mut violet = model.start_conversation(options.clone())?;
    let mut orange = model.start_conversation(options)?;
    drop(model);
    assert_eq!(violet.send(" "), Err(CoreError::InvalidRequest));
    assert!(!violet
        .send("My favorite color is violet. Reply with just OK.")?
        .is_empty());
    assert!(!orange
        .send("My favorite color is orange. Reply with just OK.")?
        .is_empty());
    let recalled = violet.send("What is my favorite color? Answer with one word.")?;
    assert!(
        recalled.to_lowercase().contains("violet"),
        "Recall: {recalled}"
    );
    let captured = Arc::new(std::sync::Mutex::new(String::new()));
    let output = captured.clone();
    assert_eq!(
        violet.send_stream(
            "Count from one to one hundred, each number on its own line.",
            Box::new(move |delta| {
                output.lock().unwrap().push_str(&delta);
                false
            }),
            Arc::new(AtomicBool::new(false))
        )?,
        StreamOutcome::Cancelled
    );
    assert!(!captured.lock().unwrap().is_empty());
    let recalled = violet.send("What is my favorite color? Answer with one word.")?;
    assert!(
        recalled.to_lowercase().contains("violet"),
        "Stopped recall: {recalled}"
    );
    let recalled = orange.send("What is my favorite color? Answer with one word.")?;
    assert!(
        recalled.to_lowercase().contains("orange"),
        "Isolated recall: {recalled}"
    );
    // Overflow must not silently evict history; a subsequent small turn still works.
    assert!(violet.send(&"x ".repeat(4096)).is_err());
    assert!(!violet.send("Say hello.")?.is_empty());
    Ok(())
}
