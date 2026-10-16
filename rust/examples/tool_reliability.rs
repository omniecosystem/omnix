//! Read-only real-model qualification. No device actions or model downloads.
use omnix::{
    agent::{registry::ToolRegistry, AgentError, ToolExecutor},
    core::*,
};
use serde_json::{json, Value};
use std::{
    path::Path,
    sync::{
        atomic::{AtomicBool, AtomicUsize, Ordering},
        Arc,
    },
};

struct ReadOnlyTool {
    invalid: Arc<AtomicUsize>,
    calls: Arc<AtomicUsize>,
}
impl ToolExecutor for ReadOnlyTool {
    fn argument_feedback(&self, call: &tools::ToolCall) -> Option<Value> {
        if call
            .arguments
            .as_object()
            .is_some_and(|args| args.is_empty())
        {
            return None;
        }
        self.invalid.fetch_add(1, Ordering::Relaxed);
        Some(
            json!({"status":"invalid_arguments","reason":"This tool takes no arguments; pass {}."}),
        )
    }
    fn execute(&mut self, _: &tools::ToolCall) -> Result<Value, AgentError> {
        self.calls.fetch_add(1, Ordering::Relaxed);
        Ok(json!({"status":"succeeded","reading":"qualification-value"}))
    }
}
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if !(args.len() == 2 || (args.len() == 3 && args[2] == "stream")) {
        return Err(
            "Usage: tool_reliability <trusted-runtime-library> <existing-model> [stream]".into(),
        );
    }
    // Explicit host-selected trusted library, using the pinned runtime ABI.
    let provider = unsafe { litertlm::LiteRtLmProvider::from_library(Path::new(&args[0]), 4096)? };
    let mut runtimes = RuntimeRegistry::default();
    runtimes.register(Box::new(provider))?;
    let model = runtimes.load(
        &ModelRequest {
            format: ModelFormat::LiteRtLm,
            platform: TargetPlatform::Windows,
            input_modalities: [InputModality::Text].into(),
            thinking: false,
            tools: false,
            preferred_provider: None,
        },
        Path::new(&args[1]),
    )?;
    let invalid = Arc::new(AtomicUsize::new(0));
    let calls = Arc::new(AtomicUsize::new(0));
    for prompt in [
        "Read the test value using read_value.",
        "Use read_value with no arguments and report the reading.",
        "Please get the current test reading.",
    ] {
        let mut registry = ToolRegistry::default();
        registry.register(tools::ToolDefinition {
            name: "read_value".into(), description: "Read a test value. No arguments; use {}. No external effects.".into(),
            parameters: json!({"type":"object","properties":{},"required":[],"additionalProperties":false}),
        }, ReadOnlyTool { invalid: invalid.clone(), calls: calls.clone() })?;
        let mut agent = registry.start(
            model.as_ref(),
            ConversationOptions {
                thinking: false,
                system_prompt: Some(
                    "Use read_value to answer reading requests. Report only the confirmed result."
                        .into(),
                ),
                max_output_tokens: 512,
                sampling: None,
            },
            vec!["read_value".into()],
            4,
        )?;
        let before = calls.load(Ordering::Relaxed);
        let reply = if args.get(2).is_some() {
            // This harness contains only public synthetic inputs/results. Never
            // enable equivalent raw event logging in a consumer application.
            agent.run_stream(
                prompt,
                Arc::new(AtomicBool::new(false)),
                Box::new(|event| {
                    if let omnix::agent::AgentEvent::Text(text) = event {
                        println!("Synthetic text delta: {text:?}");
                    }
                    true
                }),
            )?
        } else {
            agent.run(prompt, &AtomicBool::new(false))?
        };
        println!(
            "Qualification: executed={}, rejected={}, reply={:?}",
            calls.load(Ordering::Relaxed) - before,
            invalid.load(Ordering::Relaxed),
            reply.text
        );
        if calls.load(Ordering::Relaxed) <= before || !reply.text.contains("qualification-value") {
            return Err("Model did not complete the confirmed read-only tool round trip".into());
        }
    }
    println!(
        "PASS: 3 real-model prompts; {} executed calls; {} rejected argument attempts.",
        calls.load(Ordering::Relaxed),
        invalid.load(Ordering::Relaxed)
    );
    Ok(())
}
