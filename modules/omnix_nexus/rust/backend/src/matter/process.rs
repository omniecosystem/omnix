// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
//! Windows matter.js fixture adapter using explicitly bundled Node, not PATH.
//! Hosts a disposable light for tests; it does not commission consumer devices.
use super::host::*;
use serde::Deserialize;
use std::{
    io::{BufRead, BufReader, Write},
    os::windows::process::CommandExt,
    path::Path,
    process::{Child, ChildStdin, Command as ProcessCommand, Stdio},
    sync::mpsc::{self, Receiver},
    thread,
    time::{Duration, Instant},
};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Frame {
    version: u8,
    id: u32,
    kind: String,
    node: Option<String>,
    endpoint: Option<u16>,
    on: Option<bool>,
}

fn read_frame(reader: &mut impl BufRead) -> Result<Frame, Error> {
    let mut bytes = Vec::new();
    loop {
        let buffer = reader.fill_buf().map_err(|_| Error::HostFailure)?;
        if buffer.is_empty() {
            return Err(Error::HostFailure);
        }
        let newline = buffer.iter().position(|b| *b == b'\n');
        let count = newline.map_or(buffer.len(), |n| n + 1);
        if bytes.len() + count > 4096 {
            return Err(Error::InvalidReply);
        }
        bytes.extend_from_slice(&buffer[..count]);
        reader.consume(count);
        if newline.is_some() {
            break;
        }
    }
    let frame: Frame = serde_json::from_slice(&bytes).map_err(|_| Error::InvalidReply)?;
    if frame.version != 1 {
        return Err(Error::InvalidReply);
    }
    Ok(frame)
}

pub struct ProcessHost {
    child: Child,
    input: Option<ChildStdin>,
    output: Receiver<Result<Frame, Error>>,
    next_id: u32,
    target: Target,
}

impl ProcessHost {
    /// Caller must verify the bundle's runtime signature/hash and dependencies
    /// before loading executable code. Absolute paths alone are not provenance.
    /// Storage must be a fresh, private test directory. No consumer fabric.
    pub fn qualification(runtime: &Path, script: &Path, storage: &Path) -> Result<Self, Error> {
        if !runtime.is_absolute() || !script.is_absolute() || !storage.is_absolute() {
            return Err(Error::HostFailure);
        }
        let runtime = runtime.canonicalize().map_err(|_| Error::HostFailure)?;
        let script = script.canonicalize().map_err(|_| Error::HostFailure)?;
        let storage = storage.canonicalize().map_err(|_| Error::HostFailure)?;
        if runtime.parent() != script.parent() || !storage.is_dir() {
            return Err(Error::HostFailure);
        }
        if std::fs::read_dir(&storage)
            .map_err(|_| Error::HostFailure)?
            .next()
            .is_some()
        {
            return Err(Error::HostFailure);
        }
        // Node path arguments use ordinary Windows paths, not verbatim \\?\.
        let storage = storage.to_str().ok_or(Error::HostFailure)?;
        let storage = storage.strip_prefix(r"\\?\").unwrap_or(storage);
        let script_argument = script.to_str().ok_or(Error::HostFailure)?;
        let script_argument = script_argument
            .strip_prefix(r"\\?\")
            .unwrap_or(script_argument);
        let mut command = ProcessCommand::new(&runtime);
        command
            .arg(script_argument)
            .arg("--fixture")
            .arg(storage)
            .current_dir(runtime.parent().ok_or(Error::HostFailure)?)
            .env_clear()
            .env("PATH", "")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .creation_flags(0x08000000); // CREATE_NO_WINDOW
        for key in ["SystemRoot", "WINDIR", "TEMP", "TMP"] {
            if let Some(value) = std::env::var_os(key) {
                command.env(key, value);
            }
        }
        let mut child = command.spawn().map_err(|_| Error::HostFailure)?;
        let input = child.stdin.take();
        let stdout = child.stdout.take().expect("piped stdout");
        let (send, output) = mpsc::sync_channel(1);
        thread::spawn(move || {
            let mut reader = BufReader::new(stdout);
            loop {
                let frame = read_frame(&mut reader);
                let failed = frame.is_err();
                // Never block a pipe-draining thread on excess unsolicited output.
                if send.try_send(frame).is_err() || failed {
                    break;
                }
            }
        });
        let mut host = Self {
            child,
            input,
            output,
            next_id: 0,
            target: Target {
                node_id: 0,
                endpoint: 0,
            },
        };
        let ready = host.receive(0, Duration::from_secs(180))?;
        if ready.kind != "ready" || ready.on.is_some() {
            return Err(Error::InvalidReply);
        }
        let node_id = ready
            .node
            .ok_or(Error::InvalidReply)?
            .parse()
            .map_err(|_| Error::InvalidReply)?;
        let endpoint = ready.endpoint.ok_or(Error::InvalidReply)?;
        if node_id == 0 || node_id > 0xFFFF_FFEF_FFFF_FFFF || endpoint == 0 {
            return Err(Error::InvalidReply);
        }
        host.target = Target { node_id, endpoint };
        Ok(host)
    }

    pub fn target(&self) -> Target {
        self.target
    }

    fn receive(&mut self, id: u32, timeout: Duration) -> Result<Frame, Error> {
        let frame = self
            .output
            .recv_timeout(timeout)
            .map_err(|error| match error {
                mpsc::RecvTimeoutError::Timeout => Error::TimedOut,
                mpsc::RecvTimeoutError::Disconnected => Error::HostFailure,
            })??;
        if frame.id != id {
            return Err(Error::InvalidReply);
        }
        Ok(frame)
    }

    fn request(&mut self, mut value: serde_json::Value) -> Result<Frame, Error> {
        self.next_id = self.next_id.checked_add(1).ok_or(Error::Closed)?;
        value["id"] = self.next_id.into();
        let mut bytes = serde_json::to_vec(&value).map_err(|_| Error::HostFailure)?;
        bytes.push(b'\n');
        self.input
            .as_mut()
            .ok_or(Error::Closed)?
            .write_all(&bytes)
            .map_err(|_| Error::HostFailure)?;
        self.receive(self.next_id, Duration::from_secs(30))
    }

    fn stop(&mut self) {
        self.input.take();
        let _ = self.child.kill();
        let deadline = Instant::now() + Duration::from_secs(2);
        while Instant::now() < deadline {
            match self.child.try_wait() {
                Ok(Some(_)) | Err(_) => break,
                Ok(None) => thread::sleep(Duration::from_millis(10)),
            }
        }
    }
}

impl ControllerHost for ProcessHost {
    fn backend(&self) -> Backend {
        Backend::WindowsMatterJs
    }

    fn execute(&mut self, command: Command) -> Result<Reply, Error> {
        let (target, op, on) = match command {
            Command::SetOnOff { target, on } => (target, "set", Some(on)),
            Command::ReadOnOff { target } => (target, "read", None),
        };
        if target != self.target {
            return Err(Error::InvalidTarget);
        }
        let mut value = serde_json::json!({"op":op,"node":target.node_id.to_string(),"endpoint":target.endpoint});
        if let Some(on) = on {
            value["on"] = on.into();
        }
        let result = self.request(value).and_then(|frame| {
            if frame.node.is_some() || frame.endpoint.is_some() {
                return Err(Error::InvalidReply);
            }
            match (command, frame.kind.as_str(), frame.on) {
                (Command::SetOnOff { .. }, "ack", None) => Ok(Reply::Acknowledged),
                (Command::ReadOnOff { .. }, "state", Some(on)) => Ok(Reply::OnOff(on)),
                _ => Err(Error::InvalidReply),
            }
        });
        if result.is_err() {
            self.stop();
        }
        result
    }

    fn shutdown(&mut self) -> Result<Shutdown, Error> {
        let result = (|| {
            let frame = self.request(serde_json::json!({"op":"shutdown"}))?;
            if frame.kind != "released"
                || frame.node.is_some()
                || frame.endpoint.is_some()
                || frame.on.is_some()
            {
                return Err(Error::InvalidReply);
            }
            let deadline = Instant::now() + Duration::from_secs(2);
            loop {
                match self.child.try_wait().map_err(|_| Error::HostFailure)? {
                    Some(status) if status.success() => return Ok(Shutdown::Released),
                    Some(_) => return Err(Error::HostFailure),
                    None if Instant::now() >= deadline => return Err(Error::TimedOut),
                    None => thread::sleep(Duration::from_millis(10)),
                }
            }
        })();
        if result.is_err() {
            self.stop();
        }
        result
    }
}
impl Drop for ProcessHost {
    fn drop(&mut self) {
        self.stop();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn protocol_rejects_oversized_unknown_and_unversioned_frames() {
        for input in [
            vec![b'x'; 4097],
            b"{\"version\":2,\"id\":0,\"kind\":\"ready\"}\n".to_vec(),
            b"{\"version\":1,\"id\":0,\"kind\":\"ack\",\"extra\":1}\n".to_vec(),
        ] {
            assert!(matches!(
                read_frame(&mut std::io::Cursor::new(input)),
                Err(Error::InvalidReply)
            ));
        }
    }
    #[test]
    fn protocol_accepts_versioned_attribute_readback() {
        let frame = read_frame(&mut std::io::Cursor::new(
            b"{\"version\":1,\"id\":1,\"kind\":\"state\",\"on\":false}\n",
        ))
        .unwrap();
        assert_eq!(frame.on, Some(false));
    }
}
