//! Bridge adapter only. The registry, selection and loop remain in root Rust.
use flutter_rust_bridge::DartFnFuture;

pub fn agent_open_registered(
    engine_id: u64,
    model_path: String,
    instructions: Option<String>,
    max_output_tokens: u32,
    registration_json: String,
    execute: impl Fn(String) -> DartFnFuture<String> + Send + Sync + 'static,
) -> Result<u64, String> {
    #[cfg(all(feature = "agent", not(target_arch = "wasm32")))]
    {
        let (registry, grants, discovery, media, max_rounds) =
            registered_tools(Some(engine_id), registration_json, execute)?;
        super::agent::native::open(
            engine_id,
            model_path,
            instructions,
            max_output_tokens,
            false,
            Some((registry, grants, discovery, max_rounds)),
            media,
            None,
            false,
        )
    }
    #[cfg(not(all(feature = "agent", not(target_arch = "wasm32"))))]
    {
        let _ = (
            engine_id,
            model_path,
            instructions,
            max_output_tokens,
            registration_json,
            execute,
        );
        Err("Native agent is not selected".into())
    }
}

#[allow(clippy::too_many_arguments)] // Keep the existing generated bridge signature stable.
pub fn agent_open_sampled_registered(
    engine_id: u64,
    model_path: String,
    instructions: Option<String>,
    max_output_tokens: u32,
    sampling_json: Option<String>,
    thinking: bool,
    registration_json: String,
    execute: impl Fn(String) -> DartFnFuture<String> + Send + Sync + 'static,
) -> Result<u64, String> {
    #[cfg(all(feature = "agent", not(target_arch = "wasm32")))]
    {
        let sampling: Option<crate::core::SamplingOptions> = sampling_json
            .as_deref()
            .map(|json| serde_json::from_str(json).map_err(|_| "Invalid sampling configuration"))
            .transpose()?;
        if let Some(sampling) = &sampling {
            sampling.validate().map_err(|e| e.to_string())?;
        }
        let (registry, grants, discovery, media, max_rounds) =
            registered_tools(Some(engine_id), registration_json, execute)?;
        super::agent::native::open(
            engine_id,
            model_path,
            instructions,
            max_output_tokens,
            false,
            Some((registry, grants, discovery, max_rounds)),
            media,
            sampling,
            thinking,
        )
    }
    #[cfg(not(all(feature = "agent", not(target_arch = "wasm32"))))]
    {
        let _ = (
            engine_id,
            model_path,
            instructions,
            max_output_tokens,
            sampling_json,
            thinking,
            registration_json,
            execute,
        );
        Err("Native agent is not selected".into())
    }
}

#[cfg(all(feature = "agent", not(target_arch = "wasm32")))]
#[allow(clippy::type_complexity)]
pub(super) fn registered_tools(
    engine_id: Option<u64>,
    registration_json: String,
    execute: impl Fn(String) -> DartFnFuture<String> + Send + Sync + 'static,
) -> Result<
    (
        crate::agent::registry::ToolRegistry,
        Vec<String>,
        String,
        (bool, bool),
        usize,
    ),
    String,
> {
    use crate::agent::{intents::EmailIntentTool, registry::*, AgentError, ToolExecutor};
    use crate::core::tools::*;
    use serde_json::{json, Value};
    use std::{
        sync::{
            atomic::{AtomicBool, AtomicU64, Ordering},
            Arc,
        },
        time::Duration,
    };
    struct Host<F> {
        callback: Arc<F>,
        next: Arc<AtomicU64>,
        schema: Value,
    }
    impl<F: Fn(String) -> DartFnFuture<String> + Send + Sync> ToolExecutor for Host<F> {
        fn argument_feedback(&self, call: &ToolCall) -> Option<Value> {
            argument_feedback(&self.schema, &call.arguments)
        }
        fn execute(&mut self, call: &ToolCall) -> Result<Value, AgentError> {
            self.execute_cancellable(call, &AtomicBool::new(false))
        }
        fn execute_cancellable(
            &mut self,
            call: &ToolCall,
            cancel: &AtomicBool,
        ) -> Result<Value, AgentError> {
            // Intentionally limited schema dialect: closed objects with scalar fields.
            if cancel.load(Ordering::Acquire) {
                return Err(AgentError::Cancelled);
            }
            if let Some(feedback) = argument_feedback(&self.schema, &call.arguments) {
                return Ok(feedback);
            }
            let id = self.next.fetch_add(1, Ordering::Relaxed).to_string();
            let future = (self.callback)(
                    json!({"requestId":id,"callId":call.id,"toolName":call.name,"arguments":call.arguments})
                        .to_string(),
                );
            wait_for_host(future, &id, cancel, Duration::from_secs(30))
        }
    }
    if registration_json.len() > 262144 {
        return Err("Registration too large".into());
    }
    let config: Value =
        serde_json::from_str(&registration_json).map_err(|_| "Invalid registration")?;
    let max_rounds = match config.get("maxRounds") {
        None => 4,
        Some(value) => value
            .as_u64()
            .filter(|value| (1..=crate::agent::MAX_AGENT_ROUNDS as u64).contains(value))
            .ok_or("Agent maxRounds must be an integer from 1 to 32")?
            as usize,
    };
    let strings = |key: &str| -> Result<Vec<String>, String> {
        let values = config[key].as_array().ok_or("Missing registration list")?;
        if values.len() > 64 {
            return Err("Registration list too large".into());
        }
        values
            .iter()
            .map(|v| {
                v.as_str()
                    .map(str::to_owned)
                    .ok_or("Invalid registration name".into())
            })
            .collect()
    };
    let mut grants = strings("grants")?;
    let selected = strings("selectedSkills")?;
    let mut registry = ToolRegistry::default();
    let mut catalog = SkillCatalog::default();
    let tools = config["tools"].as_array().ok_or("Missing tools")?;
    if tools.len() > 32 {
        return Err("Too many tools".into());
    }
    let callback = Arc::new(execute);
    let next = Arc::new(AtomicU64::new(1));
    if !config["approvalPolicy"].is_null() {
        use crate::agent::approval::*;
        struct Approver<F> {
            callback: Arc<F>,
            next: Arc<AtomicU64>,
        }
        impl<F: Fn(String) -> DartFnFuture<String> + Send + Sync> ToolApprover for Approver<F> {
            fn approve(
                &mut self,
                call: &ToolCall,
                cancel: &AtomicBool,
            ) -> Result<bool, AgentError> {
                let id = self.next.fetch_add(1, Ordering::Relaxed).to_string();
                let future = (self.callback)(json!({"requestId":id,"phase":"approval","toolName":call.name,"arguments":call.arguments}).to_string());
                let response = wait_for_host(future, &id, cancel, Duration::from_secs(30))?;
                Ok(response["approved"] == true)
            }
        }
        let policy = &config["approvalPolicy"];
        let mode = match policy["mode"].as_str() {
            Some("reviewEveryCall") => AutonomyMode::ReviewEveryCall,
            Some("scopedAssistance") => AutonomyMode::ScopedAssistance,
            Some("delegatedScope") => AutonomyMode::DelegatedScope,
            _ => return Err("Invalid autonomy mode".into()),
        };
        let names = |key: &str| -> Result<std::collections::BTreeSet<String>, String> {
            let values = policy[key].as_array().ok_or("Missing approval list")?;
            if values.len() > 32 {
                return Err("Approval list too large".into());
            }
            values
                .iter()
                .map(|v| {
                    let name = v.as_str().ok_or("Invalid approval tool")?;
                    if !grants.iter().any(|g| g == name) && name != "load_skill" {
                        return Err("Approval policy cannot grant tools".into());
                    }
                    Ok(name.to_owned())
                })
                .collect()
        };
        let mut guard = ApprovalGuard::new(
            ApprovalPolicy {
                mode,
                automatic_tools: names("automaticTools")?,
                always_review: names("alwaysReview")?,
            },
            Box::new(Approver {
                callback: callback.clone(),
                next: next.clone(),
            }),
        );
        if mode == AutonomyMode::DelegatedScope {
            let calls = policy["maxAutomaticCalls"]
                .as_u64()
                .ok_or("Delegation needs a call budget")?;
            let seconds = policy["validForSeconds"]
                .as_u64()
                .ok_or("Delegation needs an expiry")?;
            guard = guard
                .with_automatic_budget(
                    usize::try_from(calls).map_err(|_| "Invalid budget")?,
                    Duration::from_secs(seconds),
                )
                .map_err(|e| e.to_string())?;
        }
        registry.set_approval(guard);
    }
    for tool in tools {
        let schema = tool["parameters"].clone();
        validate_schema(&schema).map_err(|e| e.to_string())?;
        let name = tool["name"].as_str().ok_or("Missing tool name")?;
        if ["load_skill", "search_knowledge", "prepare_email_intent"].contains(&name) {
            return Err("Reserved adapter name".into());
        }
        registry
            .register(
                ToolDefinition {
                    name: name.into(),
                    description: tool["description"]
                        .as_str()
                        .ok_or("Missing description")?
                        .into(),
                    parameters: schema.clone(),
                },
                Host {
                    callback: callback.clone(),
                    next: next.clone(),
                    schema,
                },
            )
            .map_err(|e| e.to_string())?;
    }
    let skills = config["skills"].as_array().ok_or("Missing skills")?;
    for skill in skills {
        let field = |key: &str| {
            skill[key]
                .as_str()
                .map(str::to_owned)
                .ok_or("Invalid skill field")
        };
        let required = skill["requiredTools"]
            .as_array()
            .ok_or("Missing skill dependencies")?
            .iter()
            .map(|v| {
                v.as_str()
                    .map(str::to_owned)
                    .ok_or("Invalid skill dependency")
            })
            .collect::<Result<Vec<_>, _>>()?;
        catalog
            .register(Skill {
                name: field("name")?,
                description: field("description")?,
                instructions: field("instructions")?,
                required_tools: required,
            })
            .map_err(|e| e.to_string())?;
    }
    let catalog = catalog
        .select(&selected, &grants)
        .map_err(|e| e.to_string())?;
    let discovery = catalog.discovery();
    if !selected.is_empty() {
        registry
            .register_skills(catalog)
            .map_err(|e| e.to_string())?;
        grants.push("load_skill".into());
    }
    if grants.iter().any(|n| n == "search_knowledge") {
        let engine = super::interaction::native::engine(
            engine_id.ok_or("Knowledge tool requires a live Omnix engine")?,
        )?;
        engine
            .register_knowledge_tool(&mut registry)
            .map_err(|e| e.to_string())?;
    }
    if grants.iter().any(|n| n == "prepare_email_intent") {
        registry
            .register(EmailIntentTool::definition(), EmailIntentTool)
            .map_err(|e| e.to_string())?;
    }
    Ok((
        registry,
        grants,
        discovery,
        (
            config["images"].as_bool().unwrap_or(false),
            config["audio"].as_bool().unwrap_or(false),
        ),
        max_rounds,
    ))
}

#[cfg(all(feature = "agent", not(target_arch = "wasm32")))]
fn wait_for_host(
    future: impl std::future::Future<Output = String>,
    id: &str,
    cancel: &std::sync::atomic::AtomicBool,
    timeout: std::time::Duration,
) -> Result<serde_json::Value, crate::agent::AgentError> {
    use crate::agent::AgentError;
    use std::{
        sync::atomic::Ordering,
        task::{Context, Waker},
        time::Instant,
    };
    let mut future = Box::pin(future);
    let deadline = Instant::now() + timeout;
    let mut context = Context::from_waker(Waker::noop());
    loop {
        if cancel.load(Ordering::Acquire) {
            return Err(AgentError::Cancelled);
        }
        if Instant::now() >= deadline {
            return Err(AgentError::Execution);
        }
        if let std::task::Poll::Ready(raw) = future.as_mut().poll(&mut context) {
            if raw.len() > 65536 {
                return Err(AgentError::Limit);
            }
            let response: serde_json::Value =
                serde_json::from_str(&raw).map_err(|_| AgentError::Execution)?;
            if response["requestId"] != id || response.get("result").is_none() {
                return Err(AgentError::Execution);
            }
            return Ok(response["result"].clone());
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
}

#[cfg(all(feature = "agent", not(target_arch = "wasm32")))]
fn validate_schema(schema: &serde_json::Value) -> Result<(), crate::agent::AgentError> {
    use crate::agent::AgentError;
    if schema["type"] != "object" || schema["additionalProperties"] != false {
        return Err(AgentError::InvalidArguments);
    }
    let properties = schema["properties"]
        .as_object()
        .ok_or(AgentError::InvalidArguments)?;
    let required = schema["required"]
        .as_array()
        .ok_or(AgentError::InvalidArguments)?;
    if properties.len() > 16
        || schema.as_object().is_none_or(|o| o.len() != 4)
        || required
            .iter()
            .any(|v| v.as_str().is_none_or(|name| !properties.contains_key(name)))
        || properties.values().any(|p| {
            p.as_object().is_none_or(|o| {
                o.keys().any(|key| key != "type" && key != "description")
                    || o.get("description").is_some_and(|description| {
                        description
                            .as_str()
                            .is_none_or(|s| s.len() > 4096 || s.contains('\0'))
                    })
            }) || !["string", "boolean", "integer", "number"]
                .iter()
                .any(|t| p["type"] == *t)
        })
    {
        return Err(AgentError::InvalidArguments);
    }
    Ok(())
}
#[cfg(all(feature = "agent", not(target_arch = "wasm32")))]
fn validate_arguments(
    schema: &serde_json::Value,
    args: &serde_json::Value,
) -> Result<(), crate::agent::AgentError> {
    crate::tool_arguments::validate(schema, args, &Default::default())
        .map_err(|_| crate::agent::AgentError::InvalidArguments)
}

#[cfg(all(feature = "agent", not(target_arch = "wasm32")))]
fn argument_feedback(
    schema: &serde_json::Value,
    args: &serde_json::Value,
) -> Option<serde_json::Value> {
    validate_arguments(schema, args).err()?;
    let mut issues = Vec::new();
    if let Some(args) = args.as_object() {
        if args.len() > 16 {
            issues.push("Too many fields (maximum 16)".to_owned());
        }
        if let Some(required) = schema["required"].as_array() {
            for name in required.iter().filter_map(|v| v.as_str()) {
                if !args.contains_key(name) {
                    issues.push(format!("Missing required field: {name}"));
                }
            }
        }
        if let Some(properties) = schema["properties"].as_object() {
            // Never echo unknown keys or supplied values: either can contain private text.
            if args.keys().any(|name| !properties.contains_key(name)) {
                issues.push("Unexpected field(s); use only declared fields".to_owned());
            }
            for (name, property) in properties {
                let Some(value) = args.get(name) else {
                    continue;
                };
                let expected = property["type"].as_str().unwrap_or("unsupported");
                let valid = match expected {
                    "string" => value.is_string(),
                    "boolean" => value.is_boolean(),
                    "integer" => value.is_i64() || value.is_u64(),
                    "number" => value.is_number(),
                    _ => false,
                };
                if !valid {
                    issues.push(format!("Field {name} must be {expected}"));
                } else if value
                    .as_str()
                    .is_some_and(|s| s.len() > 8192 || s.contains('\0'))
                {
                    issues.push(format!(
                        "Field {name} exceeds string limits or contains NUL"
                    ));
                }
            }
        }
    } else {
        issues.push("Arguments must be an object".to_owned());
    }
    let reason = format!("{}. No host action was executed.", issues.join("; "));
    #[cfg(debug_assertions)]
    eprintln!("[Omnix][tool-schema] {reason}");
    Some(serde_json::json!({
        "status": "invalid_arguments",
        "reason": reason,
        "issues": issues,
        "expectedSchema": schema,
    }))
}

#[cfg(all(test, feature = "agent", not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    #[test]
    fn registered_round_budget_is_bounded_and_old_configs_keep_four() {
        let base = serde_json::json!({"tools":[],"skills":[],"selectedSkills":[],"grants":[]});
        let parse = |value: serde_json::Value| {
            registered_tools(None, value.to_string(), |_| {
                Box::pin(std::future::ready(String::new()))
            })
        };
        assert_eq!(parse(base.clone()).unwrap().4, 4);
        for rounds in [1, 4, 10, 32] {
            let mut value = base.clone();
            value["maxRounds"] = serde_json::json!(rounds);
            assert_eq!(parse(value).unwrap().4, rounds);
        }
        for invalid in [
            serde_json::json!(0),
            serde_json::json!(-1),
            serde_json::json!(33),
            serde_json::json!(4.5),
            serde_json::json!("10"),
            serde_json::json!(null),
        ] {
            let mut value = base.clone();
            value["maxRounds"] = invalid;
            assert!(parse(value).is_err());
        }
    }
    #[test]
    fn parameter_descriptions_are_metadata_not_extra_arguments() {
        let schema = serde_json::json!({"type":"object","properties":{
            "sender":{"type":"string","description":"Exact host identifier"},
            "instructions":{"type":"string","description":"Task instructions"}
        },"required":["sender","instructions"],"additionalProperties":false});
        assert!(validate_schema(&schema).is_ok());
        let registration = serde_json::json!({
            "tools":[{"name":"host_create_message_task","description":"Consumer test tool","parameters":schema}],
            "skills":[],"selectedSkills":[],"grants":["host_create_message_task"]
        });
        let (registry, _, _, _, _) = registered_tools(None, registration.to_string(), |_| {
            Box::pin(std::future::ready(String::new()))
        })
        .expect("Described parameters must pass real agent registration");
        assert_eq!(registry.definitions().len(), 1);
        assert!(validate_arguments(
            &schema,
            &serde_json::json!({"sender":"Alice","instructions":"Test"})
        )
        .is_ok());
        assert!(validate_arguments(&schema, &serde_json::json!({"sender":"Alice","instructions":"Test","description":"not an argument"})).is_err());
        let mut invalid = schema.clone();
        invalid["properties"]["sender"]["description"] = serde_json::json!(42);
        assert!(validate_schema(&invalid).is_err());
        invalid = schema;
        invalid["properties"]["sender"]["unsupported"] = serde_json::json!(true);
        assert!(validate_schema(&invalid).is_err());
    }
    #[test]
    fn host_wait_is_bounded_cancelled_and_correlated() {
        use std::{
            future::{pending, ready},
            sync::atomic::AtomicBool,
            time::Duration,
        };
        let running = AtomicBool::new(false);
        let second = Duration::from_secs(1);
        assert_eq!(
            wait_for_host(
                ready(r#"{"requestId":"1","result":{"utc":"now"}}"#.into()),
                "1",
                &running,
                second
            )
            .unwrap()["utc"],
            "now"
        );
        assert!(wait_for_host(
            ready(r#"{"requestId":"stale","result":{}}"#.into()),
            "1",
            &running,
            second
        )
        .is_err());
        assert!(matches!(
            wait_for_host(pending(), "1", &AtomicBool::new(true), second),
            Err(crate::agent::AgentError::Cancelled)
        ));
        assert!(matches!(
            wait_for_host(pending(), "1", &running, Duration::ZERO),
            Err(crate::agent::AgentError::Execution)
        ));
        assert!(wait_for_host(ready("x".repeat(65537)), "1", &running, second).is_err());
    }
    #[test]
    fn host_arguments_use_a_closed_supported_schema() {
        let schema = serde_json::json!({"type":"object","properties":{"zone":{"type":"string"}},"required":["zone"],"additionalProperties":false});
        assert!(validate_schema(&schema).is_ok());
        assert!(validate_arguments(&schema, &serde_json::json!({"zone":"UTC"})).is_ok());
        for args in [
            serde_json::json!({}),
            serde_json::json!({"zone":1}),
            serde_json::json!({"zone":"UTC","command":"shell"}),
        ] {
            assert!(validate_arguments(&schema, &args).is_err());
        }
        assert!(validate_schema(&serde_json::json!({"type":"object"})).is_err());
    }

    #[test]
    fn invalid_host_arguments_provide_repair_feedback_without_echoing_input() {
        let schema = serde_json::json!({"type":"object","properties":{"title":{"type":"string"},"location":{"type":"string"}},"required":["title","location"],"additionalProperties":false});
        let feedback =
            argument_feedback(&schema, &serde_json::json!({"title":"private title"})).unwrap();
        assert_eq!(feedback["status"], "invalid_arguments");
        assert_eq!(feedback["expectedSchema"], schema);
        assert!(!feedback.to_string().contains("private title"));
        assert!(feedback["reason"]
            .as_str()
            .unwrap()
            .contains("Missing required field: location"));
        assert!(argument_feedback(
            &schema,
            &serde_json::json!({"title":"meeting","location":""})
        )
        .is_none());
    }

    #[test]
    fn feedback_identifies_types_without_echoing_unknown_keys_or_values() {
        let schema = serde_json::json!({"type":"object","properties":{"title":{"type":"string"}},"required":["title"],"additionalProperties":false});
        let feedback = argument_feedback(
            &schema,
            &serde_json::json!({"title":42,"private appointment":"secret"}),
        )
        .unwrap();
        let text = feedback.to_string();
        assert!(text.contains("Field title must be string"));
        assert!(text.contains("Unexpected field"));
        assert!(!text.contains("private appointment"));
        assert!(!text.contains("secret"));
        assert!(!text.contains("42"));
    }
}
