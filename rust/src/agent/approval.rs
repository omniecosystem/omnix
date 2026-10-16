//! Session-scoped autonomy never grants capabilities or overrides host safeguards.
use super::*;
use std::collections::BTreeSet;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AutonomyMode {
    ReviewEveryCall,
    ScopedAssistance,
    DelegatedScope,
}
pub struct ApprovalPolicy {
    pub mode: AutonomyMode,
    pub automatic_tools: BTreeSet<String>,
    pub always_review: BTreeSet<String>,
}
impl ApprovalPolicy {
    pub fn requires_review(&self, call: &ToolCall) -> bool {
        self.mode == AutonomyMode::ReviewEveryCall
            || self.always_review.contains(&call.name)
            || !self.automatic_tools.contains(&call.name)
    }
}
pub trait ToolApprover: Send {
    /// Approval applies to this exact call only; enforce bounded waits and cancellation.
    fn approve(&mut self, call: &ToolCall, cancel: &AtomicBool) -> Result<bool, AgentError>;
}
pub struct ApprovalGuard {
    pub policy: ApprovalPolicy,
    pub approver: Box<dyn ToolApprover>,
    budget: Option<(usize, std::time::Instant)>,
}
impl ApprovalGuard {
    pub fn new(policy: ApprovalPolicy, approver: Box<dyn ToolApprover>) -> Self {
        Self {
            policy,
            approver,
            budget: None,
        }
    }
    pub fn with_automatic_budget(
        mut self,
        calls: usize,
        lifetime: std::time::Duration,
    ) -> Result<Self, AgentError> {
        if calls == 0
            || calls > 32
            || lifetime.is_zero()
            || lifetime > std::time::Duration::from_secs(3600)
        {
            return Err(AgentError::InvalidArguments);
        }
        self.budget = Some((calls, std::time::Instant::now() + lifetime));
        Ok(self)
    }
    pub fn check(&mut self, call: &ToolCall, cancel: &AtomicBool) -> Result<bool, AgentError> {
        if cancel.load(Ordering::Acquire) {
            return Err(AgentError::Cancelled);
        }
        let exhausted = self
            .budget
            .as_ref()
            .is_some_and(|(calls, deadline)| *calls == 0 || std::time::Instant::now() >= *deadline);
        let unbounded_delegation =
            self.policy.mode == AutonomyMode::DelegatedScope && self.budget.is_none();
        let automatic = !self.policy.requires_review(call) && !exhausted && !unbounded_delegation;
        let approved = automatic || self.approver.approve(call, cancel)?;
        if cancel.load(Ordering::Acquire) {
            return Err(AgentError::Cancelled);
        }
        if automatic {
            if let Some((calls, _)) = &mut self.budget {
                *calls -= 1;
            }
        }
        Ok(approved)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Refuse;
    impl ToolApprover for Refuse {
        fn approve(&mut self, _: &ToolCall, _: &AtomicBool) -> Result<bool, AgentError> {
            Ok(false)
        }
    }
    #[test]
    fn review_overrides_automatic_and_cancel_prevents_dispatch() {
        let call = ToolCall {
            id: "1".into(),
            name: "clock".into(),
            arguments: json!({}),
        };
        for mode in [AutonomyMode::ScopedAssistance, AutonomyMode::DelegatedScope] {
            let mut guard = ApprovalGuard {
                policy: ApprovalPolicy {
                    mode,
                    automatic_tools: ["clock".into()].into(),
                    always_review: [].into(),
                },
                approver: Box::new(Refuse),
                budget: Some((
                    1,
                    std::time::Instant::now() + std::time::Duration::from_secs(60),
                )),
            };
            assert!(guard.check(&call, &AtomicBool::new(false)).unwrap());
            guard.policy.always_review.insert("clock".into());
            assert!(!guard.check(&call, &AtomicBool::new(false)).unwrap());
            assert!(matches!(
                guard.check(&call, &AtomicBool::new(true)),
                Err(AgentError::Cancelled)
            ));
        }
        let mut guard = ApprovalGuard {
            policy: ApprovalPolicy {
                mode: AutonomyMode::ReviewEveryCall,
                automatic_tools: ["clock".into()].into(),
                always_review: [].into(),
            },
            approver: Box::new(Refuse),
            budget: None,
        };
        assert!(!guard.check(&call, &AtomicBool::new(false)).unwrap());
    }
    #[test]
    fn delegation_expires_and_budget_exhaustion_requires_review() {
        let call = ToolCall {
            id: "1".into(),
            name: "clock".into(),
            arguments: json!({}),
        };
        let mut guard = ApprovalGuard::new(
            ApprovalPolicy {
                mode: AutonomyMode::DelegatedScope,
                automatic_tools: ["clock".into()].into(),
                always_review: [].into(),
            },
            Box::new(Refuse),
        );
        assert!(!guard.check(&call, &AtomicBool::new(false)).unwrap());
        guard = guard
            .with_automatic_budget(1, std::time::Duration::from_secs(60))
            .unwrap();
        assert!(guard.check(&call, &AtomicBool::new(false)).unwrap());
        assert!(!guard.check(&call, &AtomicBool::new(false)).unwrap());
        guard.budget = Some((1, std::time::Instant::now()));
        assert!(!guard.check(&call, &AtomicBool::new(false)).unwrap());
    }
}
