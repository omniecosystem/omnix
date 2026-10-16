// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! Typed contract for platform-owned controllers, not another Matter stack.
//! No JNI pointer, JavaScript process, runtime selection or authorization lives
//! here. Hosts dispatch onto their SDK worker and retain callback ownership,
//! including when this Rust frontend is dropped. Call only after local policy
//! approval. This contract controls an already commissioned On/Off device;
//! it does not implement commissioning, BLE or discovery.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Backend {
    AndroidSdk,
    WindowsMatterJs,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Target {
    pub node_id: u64,
    pub endpoint: u16,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Command {
    SetOnOff { target: Target, on: bool },
    ReadOnOff { target: Target },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Reply {
    // A command acknowledgement is not attribute readback.
    Acknowledged,
    OnOff(bool),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Shutdown {
    Released,
    RetainedUntilProcessExit,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Error {
    InvalidTarget,
    BackendMismatch,
    Closed,
    Busy,
    TimedOut,
    HostFailure,
    InvalidReply,
}

/// Platform glue owns thread dispatch, bounded admission, deadlines, secrets
/// and native lifetimes. On timeout it must keep any pending callback owner
/// alive; dropping a Rust frontend must never invalidate such a callback.
/// `execute` completes only after the SDK response or a bounded failure.
pub trait ControllerHost {
    fn backend(&self) -> Backend;
    fn execute(&mut self, command: Command) -> Result<Reply, Error>;
    /// Detach the frontend safely. This is not necessarily native deletion.
    fn shutdown(&mut self) -> Result<Shutdown, Error>;
}

/// Serial typed frontend. Backend selection is explicit; no OS fallback.
pub struct Controller<H: ControllerHost> {
    host: H,
    blocked: bool,
    shutdown: Option<Shutdown>,
}

impl<H: ControllerHost> Controller<H> {
    pub fn attach(backend: Backend, host: H) -> Result<Self, Error> {
        if host.backend() != backend {
            return Err(Error::BackendMismatch);
        }
        Ok(Self {
            host,
            blocked: false,
            shutdown: None,
        })
    }

    pub fn execute(&mut self, command: Command) -> Result<Reply, Error> {
        if self.blocked || self.shutdown.is_some() {
            return Err(Error::Closed);
        }
        let target = match command {
            Command::SetOnOff { target, .. } | Command::ReadOnOff { target } => target,
        };
        // On/Off endpoints are not the root endpoint. Reject group/reserved IDs.
        if target.node_id == 0 || target.node_id > 0xFFFF_FFEF_FFFF_FFFF || target.endpoint == 0 {
            return Err(Error::InvalidTarget);
        }
        match self.host.execute(command) {
            Ok(reply) => {
                let valid = matches!(
                    (command, reply),
                    (Command::SetOnOff { .. }, Reply::Acknowledged)
                        | (Command::ReadOnOff { .. }, Reply::OnOff(_))
                );
                if !valid {
                    self.blocked = true;
                    return Err(Error::InvalidReply);
                }
                Ok(reply)
            }
            Err(error) => {
                // Timed-out work may still be running in the native host.
                if matches!(
                    error,
                    Error::TimedOut | Error::HostFailure | Error::InvalidReply
                ) {
                    self.blocked = true;
                }
                Err(error)
            }
        }
    }

    pub fn shutdown(&mut self) -> Result<Shutdown, Error> {
        if let Some(status) = self.shutdown {
            return Ok(status);
        }
        // Reject further commands even if shutdown itself fails. Retry only
        // shutdown, never use a possibly half-detached controller again.
        self.blocked = true;
        let status = self.host.shutdown()?;
        self.shutdown = Some(status);
        Ok(status)
    }
}
