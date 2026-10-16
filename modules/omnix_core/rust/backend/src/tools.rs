//! Runtime-neutral model/tool messages. Core never executes a requested tool.
use crate::CoreError;
use serde_json::Value;
use std::collections::BTreeSet;
use std::sync::{atomic::AtomicBool, Arc};

#[derive(Clone, Debug)]
pub struct ToolDefinition {
    pub name: String,
    pub description: String,
    pub parameters: Value,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ToolCall {
    /// Conversation-local correlation, including when the runtime omits an ID.
    pub id: String,
    pub name: String,
    pub arguments: Value,
}

#[derive(Clone, Debug)]
pub struct ToolResult {
    pub call_id: String,
    pub value: Value,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ToolTurn {
    pub text: String,
    pub calls: Vec<ToolCall>,
}

pub trait ToolConversation: Send {
    /// Imports observations as context only; historical calls are never dispatched.
    #[cfg(feature = "history")]
    fn import_portable_history(
        &mut self,
        history: Vec<crate::history::HistoryTurn>,
    ) -> Result<(), CoreError> {
        self.import_chat_history(crate::history::text_pairs(&history)?)
    }
    /// Restores validated context with an explicit future reasoning setting, not new tool authority.
    fn restore_checkpoint_with_thinking(
        &mut self,
        _checkpoint: &str,
        _enabled: bool,
    ) -> Result<(), CoreError> {
        Err(CoreError::BackendFailure(
            "thinking-restoration-unsupported".into(),
        ))
    }
    /// Changes future reasoning output; pending calls and tool authority are unchanged.
    fn set_thinking(&mut self, _enabled: bool) -> Result<(), CoreError> {
        Err(CoreError::BackendFailure(
            "thinking-reconfiguration-unsupported".into(),
        ))
    }
    /// Restores prior context plus a text-only partial answer without tool dispatch.
    /// Unsupported or invalid restoration must leave the fresh handle unchanged.
    fn restore_interrupted_turn(
        &mut self,
        _checkpoint: &str,
        _message: &crate::CoreMessage,
        _partial: &str,
    ) -> Result<(), CoreError> {
        Err(CoreError::BackendFailure(
            "interrupted-history-unsupported".into(),
        ))
    }
    /// Creates a fresh conversation sharing the same loaded model resources.
    /// No tools are executed. Providers without this capability fail explicitly.
    fn restart(&mut self) -> Result<Box<dyn ToolConversation>, CoreError> {
        Err(CoreError::BackendFailure("tool-restart-unsupported".into()))
    }
    fn configure_context(
        &mut self,
        _policy: Option<crate::working_context::SharedContextPolicy>,
    ) -> Result<(), CoreError> {
        Err(CoreError::BackendFailure(
            "context-policy-unsupported".into(),
        ))
    }
    fn context_usage(&mut self) -> Result<Option<crate::working_context::ContextUsage>, CoreError> {
        Ok(None)
    }
    /// Imports completed ordinary text exchanges into a fresh tool-capable session.
    fn import_chat_history(&mut self, _history: Vec<(String, String)>) -> Result<(), CoreError> {
        Err(CoreError::BackendFailure("chat-import-unsupported".into()))
    }
    /// Imports owned ordinary native context, never historical tool authority.
    fn import_chat_checkpoint(&mut self, _context: &str) -> Result<(), CoreError> {
        Err(CoreError::BackendFailure("chat-import-unsupported".into()))
    }
    /// Changes which future turns may request the supplied tools, between completed turns.
    /// Disabling removes native declarations; it does not erase historical results.
    fn set_tools_enabled(&mut self, _enabled: bool) -> Result<(), CoreError> {
        Err(CoreError::BackendFailure(
            "tool-switching-unsupported".into(),
        ))
    }
    fn reconfigure(
        &mut self,
        _max_output_tokens: u32,
        _sampling: Option<crate::SamplingOptions>,
    ) -> Result<(), CoreError> {
        Err(CoreError::BackendFailure(
            "reconfiguration-unsupported".into(),
        ))
    }
    /// Exports completed exchanges, not executor state or tool authority.
    fn export_checkpoint(&mut self) -> Result<String, CoreError> {
        Err(CoreError::BackendFailure("tool-history-unsupported".into()))
    }
    /// Restores context into a fresh conversation without executing tools.
    fn restore_checkpoint(&mut self, _checkpoint: &str) -> Result<(), CoreError> {
        Err(CoreError::BackendFailure("tool-history-unsupported".into()))
    }
    fn send_message(&mut self, message: &crate::CoreMessage) -> Result<ToolTurn, CoreError> {
        self.send(&message.text_only()?)
    }
    fn send_message_stream(
        &mut self,
        message: &crate::CoreMessage,
        consumer: Box<dyn FnMut(String) -> bool + Send>,
        cancel: Arc<AtomicBool>,
    ) -> Result<ToolTurn, CoreError> {
        self.send_stream(&message.text_only()?, consumer, cancel)
    }
    /// Streams model output channels; tools are still dispatched only after a
    /// complete, validated native turn, never from fragments.
    fn send_message_events(
        &mut self,
        message: &crate::CoreMessage,
        mut consumer: Box<dyn FnMut(crate::ConversationDelta) -> bool + Send>,
        cancel: Arc<AtomicBool>,
    ) -> Result<ToolTurn, CoreError> {
        self.send_message_stream(
            message,
            Box::new(move |text| consumer(crate::ConversationDelta::Text(text))),
            cancel,
        )
    }
    fn respond_events(
        &mut self,
        results: Vec<ToolResult>,
        mut consumer: Box<dyn FnMut(crate::ConversationDelta) -> bool + Send>,
        cancel: Arc<AtomicBool>,
    ) -> Result<ToolTurn, CoreError> {
        self.respond_stream(
            results,
            Box::new(move |text| consumer(crate::ConversationDelta::Text(text))),
            cancel,
        )
    }
    fn send(&mut self, text: &str) -> Result<ToolTurn, CoreError>;
    /// Answers every pending call exactly once, in the model's original order.
    fn respond(&mut self, results: Vec<ToolResult>) -> Result<ToolTurn, CoreError>;
    /// Streams text only; complete typed calls are returned after the native turn.
    fn send_stream(
        &mut self,
        _text: &str,
        _consumer: Box<dyn FnMut(String) -> bool + Send>,
        _cancel: Arc<AtomicBool>,
    ) -> Result<ToolTurn, CoreError> {
        Err(CoreError::BackendFailure(
            "tool-streaming-unsupported".into(),
        ))
    }
    fn respond_stream(
        &mut self,
        _results: Vec<ToolResult>,
        _consumer: Box<dyn FnMut(String) -> bool + Send>,
        _cancel: Arc<AtomicBool>,
    ) -> Result<ToolTurn, CoreError> {
        Err(CoreError::BackendFailure(
            "tool-streaming-unsupported".into(),
        ))
    }
}

/// Validates bounded, uniquely named declarations; not a full JSON Schema validator.
pub fn validate_definitions(tools: &[ToolDefinition]) -> Result<(), CoreError> {
    let mut names = BTreeSet::new();
    if tools.is_empty() || tools.len() > 32 {
        return Err(CoreError::InvalidRequest);
    }
    for tool in tools {
        if tool.name.is_empty()
            || tool.name.len() > 64
            || !tool
                .name
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b"_-".contains(&b))
            || !names.insert(&tool.name)
            || tool.description.len() > 4096
            || tool.parameters["type"] != "object"
            || tool.parameters.to_string().len() > 65536
        {
            return Err(CoreError::InvalidRequest);
        }
    }
    Ok(())
}

/// Verifies that ordered results balance one pending batch before inference.
pub fn validate_results(calls: &[ToolCall], results: &[ToolResult]) -> Result<(), CoreError> {
    if calls.is_empty()
        || calls.len() != results.len()
        || calls.iter().zip(results).any(|(call, result)| {
            call.id != result.call_id || result.value.to_string().len() > 65536
        })
    {
        return Err(CoreError::InvalidRequest);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn unimplemented_provider_never_silently_falls_back_to_text() {
        struct PlainModel;
        impl crate::LoadedModel for PlainModel {
            fn provider_id(&self) -> &str {
                "plain"
            }
        }
        use crate::LoadedModel;
        let result = PlainModel.start_tool_conversation(
            crate::ConversationOptions {
                thinking: false,
                system_prompt: None,
                max_output_tokens: 16,
                sampling: None,
            },
            vec![],
        );
        assert!(
            matches!(result, Err(CoreError::BackendFailure(code)) if code == "tool-conversations-unsupported")
        );
    }
    #[test]
    fn rejects_duplicate_and_invalid_definitions() {
        let tool = ToolDefinition {
            name: "search_knowledge".into(),
            description: "Search".into(),
            parameters: json!({"type":"object"}),
        };
        assert!(validate_definitions(std::slice::from_ref(&tool)).is_ok());
        assert!(validate_definitions(&[tool.clone(), tool]).is_err());
        assert!(validate_definitions(&[]).is_err());
    }

    #[test]
    fn hyphenated_names_are_exact_identifiers_not_normalized_aliases() {
        let declarations = vec![
            ToolDefinition {
                name: "send-email".into(),
                description: "Draft an email".into(),
                parameters: json!({"type":"object"}),
            },
            ToolDefinition {
                name: "send_email".into(),
                description: "Legacy executor".into(),
                parameters: json!({"type":"object"}),
            },
        ];
        assert!(validate_definitions(&declarations).is_ok());
        let mut invalid = declarations[0].clone();
        invalid.name = "send/email".into();
        assert!(validate_definitions(&[invalid]).is_err());
    }
    #[test]
    fn results_must_balance_calls_before_native_execution() {
        let calls = vec![ToolCall {
            id: "0".into(),
            name: "search".into(),
            arguments: json!({}),
        }];
        assert!(validate_results(&calls, &[]).is_err());
        assert!(validate_results(
            &calls,
            &[ToolResult {
                call_id: "wrong".into(),
                value: json!({})
            }]
        )
        .is_err());
        assert!(validate_results(
            &calls,
            &[ToolResult {
                call_id: "0".into(),
                value: json!({})
            }]
        )
        .is_ok());
    }
}
