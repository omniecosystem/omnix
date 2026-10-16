//! Host-reviewed proposals, never OS execution or authority supplied by a model.
use super::*;

pub struct EmailIntentTool;
impl EmailIntentTool {
    pub fn definition() -> ToolDefinition {
        ToolDefinition {
            name: "prepare_email_intent".into(),
            description: "Prepare an email draft for the user to review. Requires an explicit email recipient, subject and body. Never sends email or opens applications. Ask for missing details. The user must approve opening their mail composer.".into(),
            parameters: json!({"type":"object","properties":{
                "recipient":{"type":"string"},"subject":{"type":"string"},"body":{"type":"string"}
            },"required":["recipient","subject","body"],"additionalProperties":false}),
        }
    }
    pub fn validate(arguments: &Value) -> Result<Value, AgentError> {
        let args = arguments.as_object().ok_or(AgentError::InvalidArguments)?;
        if args.len() != 3 {
            return Err(AgentError::InvalidArguments);
        }
        let field = |name: &str| {
            args.get(name)
                .and_then(Value::as_str)
                .ok_or(AgentError::InvalidArguments)
        };
        let recipient = field("recipient")?;
        let subject = field("subject")?;
        let body = field("body")?;
        let parts: Vec<_> = recipient.split('@').collect();
        if recipient.len() > 254
            || parts.len() != 2
            || parts[0].is_empty()
            || !parts[0]
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || b"._+-".contains(&c))
            || parts[0].starts_with('.')
            || parts[0].ends_with('.')
            || parts[0].contains("..")
            || !parts[1].contains('.')
            || parts[1].split('.').any(|label| {
                label.is_empty()
                    || label.starts_with('-')
                    || label.ends_with('-')
                    || !label
                        .bytes()
                        .all(|c| c.is_ascii_alphanumeric() || c == b'-')
            })
            || subject.trim().is_empty()
            || subject.len() > 256
            || subject.chars().any(char::is_control)
            || body.trim().is_empty()
            || body.len() > 8192
            || body
                .chars()
                .any(|c| c.is_control() && !matches!(c, '\n' | '\r' | '\t'))
        {
            return Err(AgentError::InvalidArguments);
        }
        Ok(json!({"kind":"email","recipient":recipient,"subject":subject,"body":body}))
    }
}
impl ToolExecutor for EmailIntentTool {
    fn execute(&mut self, call: &ToolCall) -> Result<Value, AgentError> {
        if call.name != "prepare_email_intent" {
            return Err(AgentError::Denied);
        }
        // Recoverable input errors are fed back to the model. No proposal exists
        // until validation succeeds; policy denial still aborts the whole loop.
        Ok(match Self::validate(&call.arguments) {
            Ok(intent) => {
                json!({"status":"requires_confirmation","intent":intent,"message":"Draft prepared only. User must review and approve opening the OS mail composer. No email has been sent."})
            }
            Err(_) => {
                json!({"status":"failed","error":"Provide exactly recipient (one plain email address), subject (1-256 bytes without controls), and body (1-8192 bytes). No draft was prepared."})
            }
        })
    }
}

#[cfg(test)]
struct AgentPolicy {
    email: bool,
}
#[cfg(test)]
impl ToolPolicy for AgentPolicy {
    fn allows(&self, call: &ToolCall) -> bool {
        call.name == "search_knowledge" || (self.email && call.name == "prepare_email_intent")
    }
}
pub fn knowledge_intent_session(
    model: &dyn crate::core::LoadedModel,
    options: ConversationOptions,
    context: Arc<dyn ContextProvider>,
    email: bool,
) -> Result<AgentSession, AgentError> {
    let mut registry = super::registry::ToolRegistry::default();
    registry.register(KnowledgeTool::definition(), KnowledgeTool::new(context))?;
    let mut grants = vec!["search_knowledge".into()];
    if email {
        registry.register(EmailIntentTool::definition(), EmailIntentTool)?;
        grants.push("prepare_email_intent".into());
    }
    registry.start(model, options, grants, 4)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn invalid_draft_can_be_repaired_through_the_real_loop() {
        struct Chat {
            phase: usize,
        }
        impl ToolConversation for Chat {
            fn send(&mut self, _: &str) -> Result<ToolTurn, CoreError> {
                Ok(ToolTurn {
                    text: "Drafting".into(),
                    calls: vec![ToolCall {
                        id: "1".into(),
                        name: "prepare_email_intent".into(),
                        arguments: json!({"recipient":"invalid","subject":"Hi","body":"Hello"}),
                    }],
                })
            }
            fn respond(&mut self, results: Vec<ToolResult>) -> Result<ToolTurn, CoreError> {
                assert_eq!(results.len(), 1);
                if self.phase == 0 {
                    assert_eq!(results[0].call_id, "1");
                    assert_eq!(results[0].value["status"], "failed");
                    self.phase += 1;
                    Ok(ToolTurn {
                        text: String::new(),
                        calls: vec![ToolCall {
                            id: "2".into(),
                            name: "prepare_email_intent".into(),
                            arguments: json!({"recipient":"alex@example.com","subject":"Hi","body":"Hello"}),
                        }],
                    })
                } else {
                    assert_eq!(results[0].call_id, "2");
                    assert_eq!(results[0].value["status"], "requires_confirmation");
                    Ok(ToolTurn {
                        text: "Draft ready for review. Nothing sent.".into(),
                        calls: vec![],
                    })
                }
            }
        }
        let mut session = AgentSession::new(
            Box::new(Chat { phase: 0 }),
            Box::new(EmailIntentTool),
            Box::new(AgentPolicy { email: true }),
            4,
        )
        .unwrap();
        let reply = session.run("Draft email", &AtomicBool::new(false)).unwrap();
        assert_eq!(reply.tool_calls, 2);
        assert!(reply.evidence[0].1.get("intent").is_none());
        assert_eq!(
            reply.evidence[1].1["intent"]["recipient"],
            "alex@example.com"
        );
        assert_eq!(reply.text, "Draft ready for review. Nothing sent.");
    }
    #[test]
    fn proposal_is_validated_and_never_reports_execution() {
        let mut tool = EmailIntentTool;
        let mut call = ToolCall {
            id: "email-1".into(),
            name: "prepare_email_intent".into(),
            arguments: json!({"recipient":"test@example.com","subject":"Hello","body":"Bonjour\nWorld"}),
        };
        let result = tool.execute(&call).unwrap();
        assert_eq!(result["status"], "requires_confirmation");
        assert_eq!(result["intent"]["kind"], "email");
        for recipient in [
            "test@example.com?bcc=evil@example.com",
            "a@b.com\r\nBcc:evil@example.com",
            "a@b",
            "a@b..com",
            "mailto:a@b.com",
            "a@b.com,c@d.com",
        ] {
            call.arguments["recipient"] = json!(recipient);
            let result = tool.execute(&call).unwrap();
            assert_eq!(result["status"], "failed");
            assert!(result.get("intent").is_none());
        }
        call.arguments = json!({"recipient":"a@b.com","subject":"bad\nheader","body":"text"});
        assert!(EmailIntentTool::validate(&call.arguments).is_err());
        call.arguments = json!({"recipient":"a@b.com","subject":"subject","body":"x".repeat(8193)});
        assert!(EmailIntentTool::validate(&call.arguments).is_err());
        assert!(!AgentPolicy { email: false }.allows(&call));
        assert!(AgentPolicy { email: true }.allows(&call));
        call.name = "control_device".into();
        assert!(!AgentPolicy { email: true }.allows(&call));
    }
}
