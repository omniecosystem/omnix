//! Runtime-independent working-context selection owned by the orchestrator.
//!
//! Selection borrows the durable transcript; it never truncates that transcript.
//! Costs must include runtime framing, media, system instructions and tool schemas.
//! A tokenizer count for individual messages is not necessarily an exact count for
//! the rendered prompt. Adapters must retain native overflow checks even when a
//! selection fits this budget.

use std::collections::HashSet;
use std::ops::Range;

/// Recent complete turns with host-configurable headroom for template overhead.
#[derive(Debug, Clone, Copy)]
pub struct RecentContextPolicy {
    pub safety_margin: usize,
}

#[cfg(feature = "core")]
impl crate::core::working_context::WorkingContextPolicy for RecentContextPolicy {
    fn select(
        &self,
        costs: &[usize],
        mandatory: usize,
        capacity: usize,
        output: usize,
    ) -> Result<crate::core::working_context::WorkingSelection, crate::core::CoreError> {
        let entries: Vec<_> = costs
            .iter()
            .flat_map(|&cost| {
                [
                    ContextEntry {
                        role: ContextRole::User,
                        payload: (),
                        estimated_tokens: cost,
                    },
                    ContextEntry {
                        role: ContextRole::Assistant,
                        payload: (),
                        estimated_tokens: 0,
                    },
                ]
            })
            .collect();
        let selection = ContextBudget {
            capacity,
            reserved_output: output,
            safety_margin: self.safety_margin,
        }
        .select(&entries, mandatory)
        .map_err(|error| crate::core::CoreError::BackendFailure(error.to_string()))?;
        Ok(crate::core::working_context::WorkingSelection {
            omitted_turns: selection.omitted_turns,
            estimated_input_tokens: selection.estimated_input_tokens,
        })
    }
}

/// The structural role of an entry, independent of its runtime-owned payload.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ContextRole {
    User,
    Assistant,
    AssistantCalls(Vec<String>),
    ToolResult(String),
}

/// A transcript entry with an adapter-supplied token cost estimate.
#[derive(Debug, Clone)]
pub struct ContextEntry<T> {
    pub role: ContextRole,
    pub payload: T,
    pub estimated_tokens: usize,
}

/// Limits for one inference request, not limits on stored conversation history.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ContextBudget {
    pub capacity: usize,
    pub reserved_output: usize,
    pub safety_margin: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ContextError {
    InvalidBudget,
    InvalidTranscript { entry: usize },
    ArithmeticOverflow,
    MandatoryOverflow { required: usize, available: usize },
}

impl std::fmt::Display for ContextError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "context selection: {self:?}")
    }
}

impl std::error::Error for ContextError {}

/// A contiguous suffix of complete turns, with observable omission accounting.
/// The range refers to the original transcript. System instructions, tool schemas
/// and the current (possibly active tool) turn remain separate mandatory input.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ContextSelection {
    pub history: Range<usize>,
    pub omitted_turns: usize,
    pub estimated_input_tokens: usize,
    pub available_input_tokens: usize,
}

impl ContextBudget {
    pub fn available_input(&self) -> Result<usize, ContextError> {
        if self.capacity == 0 || self.reserved_output == 0 {
            return Err(ContextError::InvalidBudget);
        }
        self.capacity
            .checked_sub(self.reserved_output)
            .and_then(|n| n.checked_sub(self.safety_margin))
            .filter(|n| *n > 0)
            .ok_or(ContextError::InvalidBudget)
    }

    /// Keep the newest complete turns that fit, without skipping a newer turn to
    /// insert an older, smaller one. `mandatory_tokens` includes all pinned input:
    /// instructions, enabled tool schemas, the new request and any active round.
    /// If mandatory input cannot fit, fail rather than silently omit any of it.
    pub fn select<T>(
        &self,
        transcript: &[ContextEntry<T>],
        mandatory_tokens: usize,
    ) -> Result<ContextSelection, ContextError> {
        let available = self.available_input()?;
        let turns = complete_turns(transcript)?;
        if mandatory_tokens > available {
            return Err(ContextError::MandatoryOverflow {
                required: mandatory_tokens,
                available,
            });
        }
        let mut used = mandatory_tokens;
        let mut start = transcript.len();
        let mut retained = 0;
        for turn in turns.iter().rev() {
            let cost = transcript[turn.clone()]
                .iter()
                .try_fold(0usize, |sum, entry| {
                    sum.checked_add(entry.estimated_tokens)
                        .ok_or(ContextError::ArithmeticOverflow)
                })?;
            let remaining = available - used;
            if cost > remaining {
                break;
            }
            used += cost;
            start = turn.start;
            retained += 1;
        }
        Ok(ContextSelection {
            history: start..transcript.len(),
            omitted_turns: turns.len() - retained,
            estimated_input_tokens: used,
            available_input_tokens: available,
        })
    }
}

// Only completed user turns are candidates for eviction. A tool chain belongs
// to its originating user turn, including intermediate assistant/tool rounds.
fn complete_turns<T>(entries: &[ContextEntry<T>]) -> Result<Vec<Range<usize>>, ContextError> {
    let mut turns = Vec::new();
    let mut start = None;
    let mut complete = false;
    let mut pending = HashSet::new();
    let mut seen = HashSet::new();
    for (index, entry) in entries.iter().enumerate() {
        let invalid = || ContextError::InvalidTranscript { entry: index };
        match &entry.role {
            ContextRole::User => {
                if let Some(previous) = start {
                    if !complete || !pending.is_empty() {
                        return Err(invalid());
                    }
                    turns.push(previous..index);
                }
                start = Some(index);
                complete = false;
                seen.clear();
            }
            ContextRole::Assistant if start.is_some() && !complete && pending.is_empty() => {
                complete = true;
            }
            ContextRole::AssistantCalls(ids)
                if start.is_some() && !complete && pending.is_empty() && !ids.is_empty() =>
            {
                for id in ids {
                    if id.is_empty() || !seen.insert(id.clone()) {
                        return Err(invalid());
                    }
                    pending.insert(id.clone());
                }
            }
            ContextRole::ToolResult(id) if start.is_some() && !complete => {
                if !pending.remove(id) {
                    return Err(invalid());
                }
            }
            _ => return Err(invalid()),
        }
    }
    if let Some(start) = start {
        if !complete || !pending.is_empty() {
            return Err(ContextError::InvalidTranscript {
                entry: entries.len(),
            });
        }
        turns.push(start..entries.len());
    }
    Ok(turns)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn entry(role: ContextRole, cost: usize) -> ContextEntry<&'static str> {
        ContextEntry {
            role,
            payload: "opaque text/media",
            estimated_tokens: cost,
        }
    }
    fn budget(capacity: usize) -> ContextBudget {
        ContextBudget {
            capacity,
            reserved_output: 10,
            safety_margin: 5,
        }
    }
    fn plain() -> Vec<ContextEntry<&'static str>> {
        vec![
            entry(ContextRole::User, 10),
            entry(ContextRole::Assistant, 10),
        ]
    }
    fn tool_turn() -> Vec<ContextEntry<&'static str>> {
        vec![
            entry(ContextRole::User, 10),
            entry(
                ContextRole::AssistantCalls(vec!["a".into(), "b".into()]),
                10,
            ),
            entry(ContextRole::ToolResult("b".into()), 10),
            entry(ContextRole::ToolResult("a".into()), 10),
            entry(ContextRole::AssistantCalls(vec!["c".into()]), 10),
            entry(ContextRole::ToolResult("c".into()), 10),
            entry(ContextRole::Assistant, 10),
        ]
    }

    #[test]
    fn full_transcript_is_unchanged_and_newest_turns_are_selected() {
        let history: Vec<_> = (0..1000).flat_map(|_| plain()).collect();
        let selection = budget(75).select(&history, 20).unwrap();
        assert_eq!(selection.history, 1996..2000);
        assert_eq!(selection.omitted_turns, 998);
        assert_eq!(selection.estimated_input_tokens, 60);
        assert_eq!(history.len(), 2000);
        assert_eq!(history[0].payload, "opaque text/media");
    }

    #[test]
    fn tool_chain_is_retained_or_omitted_as_a_whole() {
        let mut history = plain();
        history.extend(tool_turn());
        let fits = budget(95).select(&history, 10).unwrap();
        assert_eq!(fits.history, 2..9);
        let too_small = budget(94).select(&history, 10).unwrap();
        assert_eq!(too_small.history, 9..9);
        assert_eq!(too_small.omitted_turns, 2);
    }

    #[test]
    fn pinned_input_is_never_trimmed() {
        assert_eq!(
            budget(50).select(&plain(), 36),
            Err(ContextError::MandatoryOverflow {
                required: 36,
                available: 35,
            })
        );
        assert_eq!(budget(50).select(&plain(), 35).unwrap().history, 2..2);
    }

    #[test]
    fn empty_history_and_exact_fit_work() {
        assert_eq!(budget(45).select(&plain(), 10).unwrap().history, 0..2);
        let empty: Vec<ContextEntry<()>> = vec![];
        assert_eq!(budget(45).select(&empty, 0).unwrap().history, 0..0);
    }

    #[test]
    fn rejects_incomplete_and_unbalanced_tool_exchanges() {
        let mut history = tool_turn();
        history.pop();
        assert!(matches!(
            budget(200).select(&history, 0),
            Err(ContextError::InvalidTranscript { .. })
        ));
        history.push(entry(ContextRole::User, 1));
        assert!(budget(200).select(&history, 0).is_err());
        let mut history = tool_turn();
        history[2].role = ContextRole::ToolResult("unknown".into());
        assert!(budget(200).select(&history, 0).is_err());
        history[2].role = ContextRole::ToolResult("a".into());
        assert!(budget(200).select(&history, 0).is_err());
    }

    #[test]
    fn rejects_duplicate_call_ids_and_unexpected_roles() {
        for history in [
            vec![entry(ContextRole::Assistant, 1)],
            vec![
                entry(ContextRole::User, 1),
                entry(ContextRole::Assistant, 1),
                entry(ContextRole::Assistant, 1),
            ],
            vec![
                entry(ContextRole::User, 1),
                entry(ContextRole::AssistantCalls(vec!["x".into(), "x".into()]), 1),
            ],
            vec![
                entry(ContextRole::User, 1),
                entry(ContextRole::AssistantCalls(vec![]), 1),
            ],
        ] {
            assert!(matches!(
                budget(100).select(&history, 0),
                Err(ContextError::InvalidTranscript { .. })
            ));
        }
    }

    #[test]
    fn invalid_budgets_and_arithmetic_overflow_fail_explicitly() {
        assert_eq!(
            budget(15).available_input(),
            Err(ContextError::InvalidBudget)
        );
        assert_eq!(
            ContextBudget {
                capacity: 100,
                reserved_output: 0,
                safety_margin: 0
            }
            .available_input(),
            Err(ContextError::InvalidBudget)
        );
        let history = vec![
            entry(ContextRole::User, usize::MAX),
            entry(ContextRole::Assistant, 1),
        ];
        assert_eq!(
            budget(100).select(&history, 0),
            Err(ContextError::ArithmeticOverflow)
        );
    }

    #[test]
    fn accounting_uses_payload_cost_not_text_length() {
        let mut history = plain();
        // The adapter estimates a large image/audio payload independently of its label.
        history[0].estimated_tokens = 1000;
        assert_eq!(budget(100).select(&history, 10).unwrap().history, 2..2);
    }
}
