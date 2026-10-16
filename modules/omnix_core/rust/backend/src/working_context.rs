//! Core provides replay/accounting mechanics; the consumer owns selection policy.
use std::sync::Arc;

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
pub enum ContextAccounting {
    EstimatedText,
    UnavailableMedia,
}

/// Diagnostics for the last admitted input, not a measured native prompt size.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct ContextUsage {
    pub accounting: ContextAccounting,
    pub capacity: usize,
    pub reserved_output: usize,
    pub estimated_input_tokens: Option<usize>,
    pub omitted_turns: usize,
    pub retained_messages: usize,
}

#[derive(Debug, Clone, Copy)]
pub struct WorkingSelection {
    pub omitted_turns: usize,
    pub estimated_input_tokens: usize,
}

/// Costs describe complete history turns. Mandatory input includes the current
/// active tool round; a policy must never evict any part of that round.
pub trait WorkingContextPolicy: Send + Sync {
    fn select(
        &self,
        turn_costs: &[usize],
        mandatory_tokens: usize,
        capacity: usize,
        reserved_output: usize,
    ) -> Result<WorkingSelection, crate::CoreError>;
}

pub type SharedContextPolicy = Arc<dyn WorkingContextPolicy>;
