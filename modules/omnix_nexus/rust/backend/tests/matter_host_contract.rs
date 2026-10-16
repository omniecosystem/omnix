// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
#![cfg(feature = "matter-host")]
use omnix_nexus::matter::host::*;
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc,
};

struct Host {
    calls: Arc<AtomicUsize>,
    closes: Arc<AtomicUsize>,
    reply: Result<Reply, Error>,
    close: Result<Shutdown, Error>,
}
impl ControllerHost for Host {
    fn backend(&self) -> Backend {
        Backend::AndroidSdk
    }
    fn execute(&mut self, _: Command) -> Result<Reply, Error> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        self.reply
    }
    fn shutdown(&mut self) -> Result<Shutdown, Error> {
        self.closes.fetch_add(1, Ordering::SeqCst);
        self.close
    }
}
fn host(reply: Result<Reply, Error>) -> Host {
    Host {
        calls: Arc::new(AtomicUsize::new(0)),
        closes: Arc::new(AtomicUsize::new(0)),
        reply,
        close: Ok(Shutdown::RetainedUntilProcessExit),
    }
}
fn read() -> Command {
    Command::ReadOnOff {
        target: Target {
            node_id: 0x12344321,
            endpoint: 1,
        },
    }
}

#[test]
fn selection_and_target_validation_precede_host_calls() {
    assert!(matches!(
        Controller::attach(Backend::WindowsMatterJs, host(Ok(Reply::OnOff(true)))),
        Err(Error::BackendMismatch)
    ));
    let h = host(Ok(Reply::OnOff(true)));
    let calls = h.calls.clone();
    let mut controller = Controller::attach(Backend::AndroidSdk, h).unwrap();
    for target in [
        Target {
            node_id: 0,
            endpoint: 1,
        },
        Target {
            node_id: 1,
            endpoint: 0,
        },
        Target {
            node_id: u64::MAX,
            endpoint: 1,
        },
    ] {
        assert_eq!(
            controller.execute(Command::ReadOnOff { target }),
            Err(Error::InvalidTarget)
        );
    }
    assert_eq!(calls.load(Ordering::SeqCst), 0);
    assert_eq!(controller.execute(read()), Ok(Reply::OnOff(true)));
}

#[test]
fn acknowledgements_do_not_masquerade_as_readback() {
    let mut controller =
        Controller::attach(Backend::AndroidSdk, host(Ok(Reply::Acknowledged))).unwrap();
    assert_eq!(controller.execute(read()), Err(Error::InvalidReply));
    assert_eq!(controller.execute(read()), Err(Error::Closed));
}

#[test]
fn timeout_blocks_reuse_and_shutdown_is_truthful_and_idempotent() {
    let h = host(Err(Error::TimedOut));
    let calls = h.calls.clone();
    let closes = h.closes.clone();
    let mut controller = Controller::attach(Backend::AndroidSdk, h).unwrap();
    assert_eq!(controller.execute(read()), Err(Error::TimedOut));
    assert_eq!(controller.execute(read()), Err(Error::Closed));
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    for _ in 0..2 {
        assert_eq!(
            controller.shutdown(),
            Ok(Shutdown::RetainedUntilProcessExit)
        );
    }
    assert_eq!(closes.load(Ordering::SeqCst), 1);
}

#[test]
fn busy_allows_retry_but_failed_shutdown_does_not_allow_commands() {
    let mut h = host(Err(Error::Busy));
    h.close = Err(Error::HostFailure);
    let calls = h.calls.clone();
    let mut controller = Controller::attach(Backend::AndroidSdk, h).unwrap();
    assert_eq!(controller.execute(read()), Err(Error::Busy));
    assert_eq!(controller.execute(read()), Err(Error::Busy));
    assert_eq!(calls.load(Ordering::SeqCst), 2);
    assert_eq!(controller.shutdown(), Err(Error::HostFailure));
    assert_eq!(controller.execute(read()), Err(Error::Closed));
}

#[test]
fn set_command_accepts_only_acknowledgement_and_release_blocks_reuse() {
    let mut h = host(Ok(Reply::Acknowledged));
    h.close = Ok(Shutdown::Released);
    let mut controller = Controller::attach(Backend::AndroidSdk, h).unwrap();
    assert_eq!(
        controller.execute(Command::SetOnOff {
            target: Target {
                node_id: 0x12344321,
                endpoint: 1
            },
            on: false,
        }),
        Ok(Reply::Acknowledged)
    );
    assert_eq!(controller.shutdown(), Ok(Shutdown::Released));
    assert_eq!(controller.execute(read()), Err(Error::Closed));
}
