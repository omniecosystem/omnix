//! Explicit per-session registrations. Catalog membership never grants execution.
use super::*;
use std::collections::{BTreeMap, BTreeSet};
use std::sync::Mutex;

struct SkillLoading {
    requirements: BTreeMap<String, Vec<String>>,
    guidance: BTreeMap<String, Skill>,
    delivered: Arc<Mutex<BTreeSet<String>>>,
    ready: BTreeSet<String>,
}

/// Host-registered executors and optional review requirements for one session.
/// Registration does not grant access; `start` selects model-visible tools from
/// explicit grants. Without an approval guard, granted calls need no extra review.
#[derive(Default)]
pub struct ToolRegistry {
    entries: BTreeMap<String, (ToolDefinition, Box<dyn ToolExecutor>)>,
    approval: Option<approval::ApprovalGuard>,
    skill_loading: Option<SkillLoading>,
}
impl ToolRegistry {
    /// Registers discovery and supplies unambiguous missing guidance before a
    /// later model turn may execute a skill-dependent tool. No grants change.
    pub fn register_skills(&mut self, catalog: SkillCatalog) -> Result<(), AgentError> {
        let mut requirements: BTreeMap<String, Vec<String>> = BTreeMap::new();
        for skill in catalog.entries.values() {
            for tool in &skill.required_tools {
                requirements
                    .entry(tool.clone())
                    .or_default()
                    .push(skill.name.clone());
            }
        }
        let delivered = catalog.loaded.clone();
        let guidance = catalog.entries.clone();
        self.register(SkillCatalog::definition(), catalog)?;
        self.skill_loading = Some(SkillLoading {
            requirements,
            guidance,
            delivered,
            ready: BTreeSet::new(),
        });
        Ok(())
    }
    pub fn set_approval(&mut self, guard: approval::ApprovalGuard) {
        self.approval = Some(guard);
    }
    pub fn register(
        &mut self,
        definition: ToolDefinition,
        executor: impl ToolExecutor + 'static,
    ) -> Result<(), AgentError> {
        validate_definitions(std::slice::from_ref(&definition))?;
        if self.entries.len() >= 32 || self.entries.contains_key(&definition.name) {
            return Err(AgentError::InvalidArguments);
        }
        self.entries
            .insert(definition.name.clone(), (definition, Box::new(executor)));
        Ok(())
    }
    pub fn definitions(&self) -> Vec<ToolDefinition> {
        self.entries
            .values()
            .map(|(definition, _)| definition.clone())
            .collect()
    }
    pub fn start(
        self,
        model: &dyn crate::core::LoadedModel,
        options: ConversationOptions,
        grants: Vec<String>,
        rounds: usize,
    ) -> Result<AgentSession, AgentError> {
        let allowed: BTreeSet<_> = grants.into_iter().collect();
        if allowed.is_empty() || allowed.iter().any(|name| !self.entries.contains_key(name)) {
            return Err(AgentError::Denied);
        }
        let definitions: Vec<_> = self
            .definitions()
            .into_iter()
            .filter(|d| allowed.contains(&d.name))
            .collect();
        let chat = model.start_tool_conversation(options, definitions)?;
        AgentSession::new(
            chat,
            Box::new(self),
            Box::new(RegisteredPolicy(allowed)),
            rounds,
        )
    }
}
impl ToolExecutor for ToolRegistry {
    fn begin_tool_batch(&mut self) {
        if let Some(loading) = &mut self.skill_loading {
            if let Ok(delivered) = loading.delivered.lock() {
                loading.ready = delivered.clone();
            }
        }
    }
    fn execute(&mut self, call: &ToolCall) -> Result<Value, AgentError> {
        self.execute_cancellable(call, &AtomicBool::new(false))
    }
    fn execute_cancellable(
        &mut self,
        call: &ToolCall,
        cancel: &AtomicBool,
    ) -> Result<Value, AgentError> {
        if !self.entries.contains_key(&call.name) {
            return Err(AgentError::Denied);
        }
        if let Some(loading) = &self.skill_loading {
            if let Some(skills) = loading.requirements.get(&call.name) {
                if !skills.iter().any(|name| loading.ready.contains(name)) {
                    if cancel.load(Ordering::Acquire) {
                        return Err(AgentError::Cancelled);
                    }
                    // A single association is host-selected, not model-invented.
                    // Supply its complete guidance as this call's result, but do
                    // not execute or retain the premature action's arguments.
                    // `ready` changes only at the next model batch.
                    if let [name] = skills.as_slice() {
                        let skill = &loading.guidance[name];
                        loading
                            .delivered
                            .lock()
                            .map_err(|_| AgentError::Execution)?
                            .insert(name.clone());
                        return Ok(json!({
                            "status":"guidance_loaded",
                            "actionExecuted":false,
                            "reason":"Skill instructions loaded. No action was executed. Follow the supplied instructions and examples, then call this tool again with the appropriate arguments in your next model turn.",
                            "skill":name,
                            "instructions":skill.instructions,
                            "requiredTools":skill.required_tools
                        }));
                    }
                    return Ok(json!({"status":"instructions_required", "reason":
                        "No action was executed. Call load_skill with a listed skill name, read its instructions and examples, then call this tool in a subsequent model turn.",
                        "skills":skills}));
                }
            }
        }
        if let Some(feedback) = self.entries[&call.name].1.argument_feedback(call) {
            return Ok(feedback);
        }
        if let Some(guard) = &mut self.approval {
            if !guard.check(call, cancel)? {
                return Ok(
                    json!({"status":"denied","reason":"Approval was not granted. No tool action was executed."}),
                );
            }
        }
        let (_, executor) = self.entries.get_mut(&call.name).ok_or(AgentError::Denied)?;
        executor.execute_cancellable(call, cancel)
    }
}
struct RegisteredPolicy(BTreeSet<String>);
impl ToolPolicy for RegisteredPolicy {
    fn allows(&self, call: &ToolCall) -> bool {
        self.0.contains(&call.name)
    }
}

/// Instructions supplied separately from executor code and execution grants.
#[derive(Clone)]
pub struct Skill {
    pub name: String,
    pub description: String,
    pub instructions: String,
    pub required_tools: Vec<String>,
}
#[derive(Default)]
pub struct SkillCatalog {
    entries: BTreeMap<String, Skill>,
    loaded: Arc<Mutex<BTreeSet<String>>>,
}
impl SkillCatalog {
    pub fn register(&mut self, skill: Skill) -> Result<(), AgentError> {
        if self.entries.len() >= 64
            || self.entries.contains_key(&skill.name)
            || skill.name.is_empty()
            || skill.name.len() > 64
            || !skill
                .name
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b"_-".contains(&b))
            || skill.description.trim().is_empty()
            || skill.description.len() > 1024
            || skill.instructions.trim().is_empty()
            || skill.instructions.len() > 32768
            || skill.required_tools.len() > 32
        {
            return Err(AgentError::InvalidArguments);
        }
        self.entries.insert(skill.name.clone(), skill);
        Ok(())
    }
    pub fn select(&self, selected: &[String], grants: &[String]) -> Result<Self, AgentError> {
        let mut catalog = Self::default();
        for name in selected {
            let skill = self.entries.get(name).ok_or(AgentError::InvalidArguments)?;
            if skill
                .required_tools
                .iter()
                .any(|tool| !grants.contains(tool))
            {
                return Err(AgentError::Denied);
            }
            catalog.register(skill.clone())?;
        }
        Ok(catalog)
    }
    pub fn discovery(&self) -> String {
        self.entries
            .values()
            .map(|s| format!("- {}: {}", s.name, s.description))
            .collect::<Vec<_>>()
            .join("\n")
    }
    pub fn definition() -> ToolDefinition {
        ToolDefinition { name:"load_skill".into(), description:"Load the full instructions and examples for a selected skill by exact name. Call this first, then follow the returned guidance to use its tools in a subsequent model turn. Instructions never grant tool permissions.".into(), parameters:json!({"type":"object","properties":{"name":{"type":"string"}},"required":["name"],"additionalProperties":false}) }
    }
}
impl ToolExecutor for SkillCatalog {
    fn execute(&mut self, call: &ToolCall) -> Result<Value, AgentError> {
        if call.name != "load_skill"
            || call
                .arguments
                .as_object()
                .is_none_or(|args| args.len() != 1)
        {
            return Err(AgentError::InvalidArguments);
        }
        let name = call.arguments["name"]
            .as_str()
            .ok_or(AgentError::InvalidArguments)?;
        let skill = self.entries.get(name).ok_or(AgentError::Denied)?;
        self.loaded
            .lock()
            .map_err(|_| AgentError::Execution)?
            .insert(name.into());
        Ok(json!({"instructions":skill.instructions,"requiredTools":skill.required_tools}))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn guidance_must_be_loaded_in_a_prior_model_batch_without_executing_tools() {
        struct Count(Arc<std::sync::atomic::AtomicUsize>);
        impl ToolExecutor for Count {
            fn execute(&mut self, _: &ToolCall) -> Result<Value, AgentError> {
                self.0.fetch_add(1, Ordering::Relaxed);
                Ok(json!({"status":"succeeded"}))
            }
        }
        let count = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let mut registry = ToolRegistry::default();
        registry.register(ToolDefinition {
            name:"host_test".into(), description:"Test".into(),
            parameters:json!({"type":"object","properties":{},"required":[],"additionalProperties":false}),
        }, Count(count.clone())).unwrap();
        let mut catalog = SkillCatalog::default();
        catalog
            .register(Skill {
                name: "host-guide".into(),
                description: "A guide".into(),
                instructions: "Read the examples before acting.".into(),
                required_tools: vec!["host_test".into()],
            })
            .unwrap();
        registry.register_skills(catalog).unwrap();
        let action = ToolCall {
            id: "action".into(),
            name: "host_test".into(),
            arguments: json!({}),
        };
        registry.begin_tool_batch();
        let guidance = registry.execute(&action).unwrap();
        assert_eq!(guidance["status"], "guidance_loaded");
        assert_eq!(guidance["actionExecuted"], false);
        assert_eq!(guidance["skill"], "host-guide");
        assert_eq!(guidance["instructions"], "Read the examples before acting.");
        let load = ToolCall {
            id: "load".into(),
            name: "load_skill".into(),
            arguments: json!({"name":"host-guide"}),
        };
        assert!(registry.execute(&load).unwrap()["instructions"]
            .as_str()
            .unwrap()
            .contains("examples"));
        // A parallel load + action was generated before the model saw guidance.
        assert_eq!(
            registry.execute(&action).unwrap()["status"],
            "guidance_loaded"
        );
        assert_eq!(count.load(Ordering::Relaxed), 0);
        registry.begin_tool_batch();
        assert_eq!(registry.execute(&action).unwrap()["status"], "succeeded");
        assert_eq!(count.load(Ordering::Relaxed), 1);
    }
    #[test]
    fn automatic_guidance_does_not_guess_between_skills_or_ignore_cancellation() {
        let mut registry = ToolRegistry::default();
        registry
            .register(KnowledgeTool::definition(), EmailIntentToolForTest)
            .unwrap();
        let mut catalog = SkillCatalog::default();
        for name in ["first-guide", "second-guide"] {
            catalog
                .register(Skill {
                    name: name.into(),
                    description: "A selected guide".into(),
                    instructions: format!("Instructions for {name}"),
                    required_tools: vec!["search_knowledge".into()],
                })
                .unwrap();
        }
        registry.register_skills(catalog).unwrap();
        let call = ToolCall {
            id: "1".into(),
            name: "search_knowledge".into(),
            arguments: json!({}),
        };
        registry.begin_tool_batch();
        let result = registry.execute(&call).unwrap();
        assert_eq!(result["status"], "instructions_required");
        assert!(result.get("instructions").is_none());
        assert!(registry
            .skill_loading
            .as_ref()
            .unwrap()
            .delivered
            .lock()
            .unwrap()
            .is_empty());
        assert!(matches!(
            registry.execute_cancellable(&call, &AtomicBool::new(true)),
            Err(AgentError::Cancelled)
        ));
        // Reduce to one applicable skill; cancellation must still prevent loading.
        registry
            .skill_loading
            .as_mut()
            .unwrap()
            .requirements
            .get_mut("search_knowledge")
            .unwrap()
            .pop();
        assert!(matches!(
            registry.execute_cancellable(&call, &AtomicBool::new(true)),
            Err(AgentError::Cancelled)
        ));
        assert!(registry
            .skill_loading
            .as_ref()
            .unwrap()
            .delivered
            .lock()
            .unwrap()
            .is_empty());
    }
    #[test]
    fn invalid_arguments_are_rejected_before_review() {
        struct NeverReview;
        impl approval::ToolApprover for NeverReview {
            fn approve(&mut self, _: &ToolCall, _: &AtomicBool) -> Result<bool, AgentError> {
                panic!("invalid arguments must not request review");
            }
        }
        struct Invalid;
        impl ToolExecutor for Invalid {
            fn argument_feedback(&self, _: &ToolCall) -> Option<Value> {
                Some(json!({"status":"invalid_arguments"}))
            }
            fn execute(&mut self, _: &ToolCall) -> Result<Value, AgentError> {
                panic!("invalid arguments must not execute");
            }
        }
        let mut registry = ToolRegistry::default();
        registry
            .register(KnowledgeTool::definition(), Invalid)
            .unwrap();
        registry.set_approval(approval::ApprovalGuard::new(
            approval::ApprovalPolicy {
                mode: approval::AutonomyMode::ReviewEveryCall,
                automatic_tools: [].into(),
                always_review: [].into(),
            },
            Box::new(NeverReview),
        ));
        assert_eq!(
            registry
                .execute(&ToolCall {
                    id: "1".into(),
                    name: "search_knowledge".into(),
                    arguments: json!({})
                })
                .unwrap()["status"],
            "invalid_arguments"
        );
    }
    #[test]
    fn refused_review_never_reaches_registered_executor() {
        struct Refuse;
        impl approval::ToolApprover for Refuse {
            fn approve(&mut self, _: &ToolCall, _: &AtomicBool) -> Result<bool, AgentError> {
                Ok(false)
            }
        }
        struct Never;
        impl ToolExecutor for Never {
            fn execute(&mut self, _: &ToolCall) -> Result<Value, AgentError> {
                panic!("refused execution");
            }
        }
        let mut registry = ToolRegistry::default();
        registry
            .register(KnowledgeTool::definition(), Never)
            .unwrap();
        registry.set_approval(approval::ApprovalGuard::new(
            approval::ApprovalPolicy {
                mode: approval::AutonomyMode::ReviewEveryCall,
                automatic_tools: [].into(),
                always_review: [].into(),
            },
            Box::new(Refuse),
        ));
        let call = ToolCall {
            id: "1".into(),
            name: "search_knowledge".into(),
            arguments: json!({}),
        };
        assert_eq!(registry.execute(&call).unwrap()["status"], "denied");
        assert!(registry
            .execute(&ToolCall {
                name: "unknown".into(),
                ..call
            })
            .is_err());
    }
    #[test]
    fn duplicate_registration_and_unknown_dispatch_fail_closed() {
        let mut tools = ToolRegistry::default();
        tools
            .register(KnowledgeTool::definition(), EmailIntentToolForTest)
            .unwrap();
        assert!(tools
            .register(KnowledgeTool::definition(), EmailIntentToolForTest)
            .is_err());
        assert!(tools
            .execute(&ToolCall {
                id: "1".into(),
                name: "unknown".into(),
                arguments: json!({})
            })
            .is_err());
    }
    struct EmailIntentToolForTest;
    impl ToolExecutor for EmailIntentToolForTest {
        fn execute(&mut self, _: &ToolCall) -> Result<Value, AgentError> {
            Ok(json!({}))
        }
    }
    #[test]
    fn selection_does_not_grant_dependencies_or_expose_unselected_skills() {
        let mut catalog = SkillCatalog::default();
        catalog
            .register(Skill {
                name: "clock".into(),
                description: "Read the time".into(),
                instructions: "Call host_time.".into(),
                required_tools: vec!["host_time".into()],
            })
            .unwrap();
        assert!(catalog.select(&["clock".into()], &[]).is_err());
        let mut selected = catalog
            .select(&["clock".into()], &["host_time".into()])
            .unwrap();
        assert!(selected.discovery().contains("clock"));
        assert_eq!(
            selected
                .execute(&ToolCall {
                    id: "1".into(),
                    name: "load_skill".into(),
                    arguments: json!({"name":"clock"})
                })
                .unwrap()["instructions"],
            "Call host_time."
        );
        let mut empty = catalog.select(&[], &[]).unwrap();
        assert!(empty
            .execute(&ToolCall {
                id: "1".into(),
                name: "load_skill".into(),
                arguments: json!({"name":"clock"})
            })
            .is_err());
    }
}
