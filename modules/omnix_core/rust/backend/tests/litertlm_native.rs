// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

#![cfg(all(feature = "litertlm", target_os = "windows"))]

use omnix_core::{litertlm::LiteRtLmProvider, *};
use std::path::PathBuf;

/// Operator supplies trusted ABI-compatible artifacts. No downloads.
#[test]
#[ignore = "requires trusted OMNIX_LITERTLM_LIBRARY and OMNIX_LITERTLM_MODEL"]
fn real_history_reopen_and_model_lifetime() -> Result<(), Box<dyn std::error::Error>> {
    let library = PathBuf::from(std::env::var("OMNIX_LITERTLM_LIBRARY")?);
    let artifact = PathBuf::from(std::env::var("OMNIX_LITERTLM_MODEL")?);
    let provider = unsafe { LiteRtLmProvider::from_library(&library, 2048)? };
    let mut registry = RuntimeRegistry::default();
    registry.register(Box::new(provider))?;
    let model = registry.load(
        &ModelRequest {
            format: ModelFormat::LiteRtLm,
            platform: TargetPlatform::Windows,
            input_modalities: [InputModality::Text].into(),
            thinking: false,
            tools: false,
            preferred_provider: None,
        },
        &artifact,
    )?;
    assert!(matches!(
        model.start_conversation(ConversationOptions {
            thinking: false,
            system_prompt: None,
            max_output_tokens: 0,
            sampling: None,
        }),
        Err(CoreError::InvalidRequest)
    ));
    let options = ConversationOptions {
        thinking: false,
        system_prompt: Some("Answer briefly and clearly.".into()),
        max_output_tokens: 128,
        sampling: None,
    };
    let mut first = model.start_conversation(options.clone())?;
    // Logical conversations share an engine, but retain separate histories.
    // Sending to the first after using the second exercises native handoff.
    let mut second = model.start_conversation(options.clone())?;
    second.send("My favorite color is green. Reply with just OK.")?;
    assert_eq!(first.send("  "), Err(CoreError::InvalidRequest));
    first.send("My favorite color is violet. Reply with just OK.")?;
    let second_answer = second.send("What is my favorite color? Answer with one word.")?;
    assert!(
        second_answer.to_lowercase().contains("green"),
        "Unexpected second-conversation recall: {second_answer}"
    );
    let answer = first.send("What is my favorite color? Answer with one word.")?;
    assert!(
        answer.to_lowercase().contains("violet"),
        "Unexpected recall: {answer}"
    );
    drop(second);
    drop(first);
    let mut reopened = model.start_conversation(options)?;
    drop(model);
    reopened.send("My favorite color is orange. Reply with just OK.")?;
    let answer = reopened.send("What is my favorite color? Answer with one word.")?;
    assert!(
        answer.to_lowercase().contains("orange"),
        "Unexpected fresh context: {answer}"
    );
    let chunks = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
    let captured = chunks.clone();
    assert_eq!(
        reopened.send_stream(
            "Count slowly from one to one hundred, each number on its own line.",
            Box::new(move |delta| {
                captured.lock().unwrap().push(delta);
                false
            }),
            std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false)),
        )?,
        StreamOutcome::Cancelled
    );
    assert!(!chunks.lock().unwrap().is_empty());
    let answer = reopened.send("What is my favorite color? Answer with one word.")?;
    assert!(
        answer.to_lowercase().contains("orange"),
        "History lost after stop: {answer}"
    );
    let chunks = std::sync::Arc::new(std::sync::Mutex::new(String::new()));
    let captured = chunks.clone();
    assert_eq!(
        reopened.send_stream(
            "Say hello in one sentence.",
            Box::new(move |delta| {
                captured.lock().unwrap().push_str(&delta);
                true
            }),
            std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false))
        )?,
        StreamOutcome::Completed
    );
    assert!(!chunks.lock().unwrap().is_empty());
    drop(reopened);
    Ok(())
}
