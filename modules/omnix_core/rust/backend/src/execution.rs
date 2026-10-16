//! Bounded, host-scoped inference admission. No priorities or OS scheduling.
use std::{
    collections::VecDeque,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Condvar, Mutex,
    },
    time::{Duration, Instant},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AdmissionError {
    Busy,
    QueueFull,
    Cancelled,
    TimedOut,
    Unavailable,
}
impl std::fmt::Display for AdmissionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::Busy => "execution-busy",
            Self::QueueFull => "execution-queue-full",
            Self::Cancelled => "generation-cancelled",
            Self::TimedOut => "execution-admission-timeout",
            Self::Unavailable => "execution-admission-unavailable",
        })
    }
}
impl std::error::Error for AdmissionError {}

struct State {
    active: usize,
    next: u64,
    waiting: VecDeque<u64>,
}
struct Inner {
    state: Mutex<State>,
    changed: Condvar,
    slots: usize,
    queue: usize,
}

/// A cloneable resource gate; sharing it does not share conversation state.
#[derive(Clone)]
pub struct ExecutionAdmission(Arc<Inner>);
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AdmissionSnapshot {
    pub active: usize,
    pub waiting: usize,
}
impl ExecutionAdmission {
    /// Creates explicit concurrency and queue limits. Zero slots is invalid.
    pub fn new(slots: usize, queue: usize) -> Result<Self, AdmissionError> {
        if slots == 0 {
            return Err(AdmissionError::Unavailable);
        }
        Ok(Self(Arc::new(Inner {
            state: Mutex::new(State {
                active: 0,
                next: 0,
                waiting: VecDeque::new(),
            }),
            changed: Condvar::new(),
            slots,
            queue,
        })))
    }
    pub fn snapshot(&self) -> Result<AdmissionSnapshot, AdmissionError> {
        let state = self
            .0
            .state
            .lock()
            .map_err(|_| AdmissionError::Unavailable)?;
        Ok(AdmissionSnapshot {
            active: state.active,
            waiting: state.waiting.len(),
        })
    }
    /// Acquires a slot or waits FIFO within both the queue and time limits.
    /// Cancellation is polled while waiting; native cancellation remains cooperative.
    /// A zero wait rejects contention immediately. Callbacks must not synchronously
    /// reenter the same gate while retaining a permit.
    pub fn acquire(
        &self,
        cancel: &AtomicBool,
        wait: Duration,
    ) -> Result<ExecutionPermit, AdmissionError> {
        let start = Instant::now();
        let mut state = self
            .0
            .state
            .lock()
            .map_err(|_| AdmissionError::Unavailable)?;
        if cancel.load(Ordering::Acquire) {
            return Err(AdmissionError::Cancelled);
        }
        if state.active < self.0.slots && state.waiting.is_empty() {
            state.active += 1;
            return Ok(ExecutionPermit(self.clone()));
        }
        if wait.is_zero() {
            return Err(AdmissionError::Busy);
        }
        // Blocking host-thread waiting is not a browser execution contract.
        if cfg!(target_arch = "wasm32") {
            return Err(AdmissionError::Unavailable);
        }
        if state.waiting.len() >= self.0.queue {
            return Err(AdmissionError::QueueFull);
        }
        let ticket = state.next;
        state.next = state
            .next
            .checked_add(1)
            .ok_or(AdmissionError::Unavailable)?;
        state.waiting.push_back(ticket);
        loop {
            let failure = if cancel.load(Ordering::Acquire) {
                Some(AdmissionError::Cancelled)
            } else if start.elapsed() >= wait {
                Some(AdmissionError::TimedOut)
            } else {
                None
            };
            if let Some(error) = failure {
                state.waiting.retain(|t| *t != ticket);
                self.0.changed.notify_all();
                return Err(error);
            }
            if state.active < self.0.slots && state.waiting.front() == Some(&ticket) {
                state.waiting.pop_front();
                state.active += 1;
                self.0.changed.notify_all();
                return Ok(ExecutionPermit(self.clone()));
            }
            let remaining = wait
                .saturating_sub(start.elapsed())
                .min(Duration::from_millis(20));
            state = self
                .0
                .changed
                .wait_timeout(state, remaining)
                .map_err(|_| AdmissionError::Unavailable)?
                .0;
        }
    }
}
/// Releases capacity on success, error or unwinding. It does not cancel inference.
pub struct ExecutionPermit(ExecutionAdmission);
impl Drop for ExecutionPermit {
    fn drop(&mut self) {
        if let Ok(mut state) = self.0 .0.state.lock() {
            state.active -= 1;
            self.0 .0.changed.notify_all();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn queued(gate: &ExecutionAdmission) {
        let deadline = Instant::now() + Duration::from_secs(2);
        while gate.snapshot().unwrap().waiting != 1 {
            assert!(Instant::now() < deadline, "waiter did not enqueue");
            std::thread::yield_now();
        }
    }
    #[test]
    fn immediate_admission_is_bounded_and_drop_releases() {
        assert!(ExecutionAdmission::new(0, 0).is_err());
        let gate = ExecutionAdmission::new(1, 0).unwrap();
        let flag = AtomicBool::new(false);
        let permit = gate.acquire(&flag, Duration::ZERO).unwrap();
        assert!(matches!(
            gate.acquire(&flag, Duration::ZERO),
            Err(AdmissionError::Busy)
        ));
        assert!(matches!(
            gate.acquire(&flag, Duration::from_secs(1)),
            Err(AdmissionError::QueueFull)
        ));
        drop(permit);
        assert_eq!(gate.snapshot().unwrap().active, 0);
        flag.store(true, Ordering::Release);
        assert!(matches!(
            gate.acquire(&flag, Duration::ZERO),
            Err(AdmissionError::Cancelled)
        ));
    }
    #[test]
    fn queued_cancellation_removes_ticket_without_acquiring() {
        let gate = ExecutionAdmission::new(1, 1).unwrap();
        let active = gate
            .acquire(&AtomicBool::new(false), Duration::ZERO)
            .unwrap();
        let cancel = Arc::new(AtomicBool::new(false));
        let worker_gate = gate.clone();
        let worker_cancel = cancel.clone();
        let worker = std::thread::spawn(move || {
            worker_gate
                .acquire(&worker_cancel, Duration::from_secs(2))
                .err()
        });
        queued(&gate);
        assert!(matches!(
            gate.acquire(&AtomicBool::new(false), Duration::from_secs(1)),
            Err(AdmissionError::QueueFull)
        ));
        cancel.store(true, Ordering::Release);
        assert_eq!(worker.join().unwrap(), Some(AdmissionError::Cancelled));
        assert_eq!(
            gate.snapshot().unwrap(),
            AdmissionSnapshot {
                active: 1,
                waiting: 0
            }
        );
        drop(active);
    }
    #[test]
    fn release_wakes_waiter_and_timeout_cleans_queue() {
        let gate = ExecutionAdmission::new(1, 1).unwrap();
        let active = gate
            .acquire(&AtomicBool::new(false), Duration::ZERO)
            .unwrap();
        assert!(matches!(
            gate.acquire(&AtomicBool::new(false), Duration::from_millis(1)),
            Err(AdmissionError::TimedOut)
        ));
        assert_eq!(gate.snapshot().unwrap().waiting, 0);
        let worker_gate = gate.clone();
        let worker = std::thread::spawn(move || {
            let _permit = worker_gate
                .acquire(&AtomicBool::new(false), Duration::from_secs(2))
                .unwrap();
            assert_eq!(worker_gate.snapshot().unwrap().active, 1);
        });
        queued(&gate);
        drop(active);
        worker.join().unwrap();
        assert_eq!(gate.snapshot().unwrap().active, 0);
    }
    #[test]
    fn unwinding_releases_capacity() {
        let gate = ExecutionAdmission::new(1, 0).unwrap();
        let _ = std::panic::catch_unwind(|| {
            let _permit = gate
                .acquire(&AtomicBool::new(false), Duration::ZERO)
                .unwrap();
            panic!("simulated backend panic");
        });
        assert_eq!(gate.snapshot().unwrap().active, 0);
    }
    #[test]
    fn queued_requests_are_fifo_across_shared_clones() {
        let gate = ExecutionAdmission::new(1, 2).unwrap();
        let active = gate
            .acquire(&AtomicBool::new(false), Duration::ZERO)
            .unwrap();
        let (sent, received) = std::sync::mpsc::channel();
        let first_gate = gate.clone();
        let first_sent = sent.clone();
        let first = std::thread::spawn(move || {
            let _permit = first_gate
                .acquire(&AtomicBool::new(false), Duration::from_secs(2))
                .unwrap();
            first_sent.send(1).unwrap();
        });
        queued(&gate);
        let second_gate = gate.clone();
        let second = std::thread::spawn(move || {
            let _permit = second_gate
                .acquire(&AtomicBool::new(false), Duration::from_secs(2))
                .unwrap();
            sent.send(2).unwrap();
        });
        let deadline = Instant::now() + Duration::from_secs(2);
        while gate.snapshot().unwrap().waiting != 2 {
            assert!(Instant::now() < deadline);
            std::thread::yield_now();
        }
        drop(active);
        assert_eq!(received.recv_timeout(Duration::from_secs(2)).unwrap(), 1);
        assert_eq!(received.recv_timeout(Duration::from_secs(2)).unwrap(), 2);
        first.join().unwrap();
        second.join().unwrap();
        assert_eq!(
            gate.snapshot().unwrap(),
            AdmissionSnapshot {
                active: 0,
                waiting: 0
            }
        );
    }
}
