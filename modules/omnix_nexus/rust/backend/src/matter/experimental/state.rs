// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! Atomic, single-owner simulator state. Secrets remain in the host's private
//! app directory; OS-keychain protection is required before production use.

use super::MatterDevice;
use serde::{Deserialize, Serialize};
use std::{
    fs::{self, File, OpenOptions},
    io::Write,
    path::PathBuf,
};

#[derive(Serialize, Deserialize)]
pub(super) struct Identity {
    pub rcac: Vec<u8>,
    pub icac: Vec<u8>,
    pub noc: Vec<u8>,
    pub private_key: Vec<u8>,
    pub signer: Vec<u8>,
    pub ipk: Vec<u8>,
}

#[derive(Serialize, Deserialize)]
pub(super) struct ControllerState {
    schema: u8,
    pub identity: Option<Identity>,
    pub devices: Vec<MatterDevice>,
    pub next_node: u64,
    #[serde(skip)]
    path: PathBuf,
    #[serde(skip)]
    lock: Option<File>,
}

impl ControllerState {
    pub fn open(directory: &str) -> Result<Self, String> {
        if directory.trim().is_empty() {
            return Err("A private app directory is required".into());
        }
        let path = PathBuf::from(directory);
        fs::create_dir_all(&path).map_err(|_| "Could not create Matter storage")?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&path, fs::Permissions::from_mode(0o700))
                .map_err(|_| "Could not protect Matter storage")?;
        }
        let lock = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(path.join("controller.lock"))
            .map_err(|_| "Could not open Matter storage lock")?;
        lock.try_lock()
            .map_err(|_| "Another controller owns this Matter directory")?;
        let snapshot = path.join("controller.json");
        let mut state = match fs::read(&snapshot) {
            Ok(bytes) => {
                if bytes.len() > 1024 * 1024 {
                    return Err("Matter snapshot is too large".into());
                }
                let saved: Self = serde_json::from_slice(&bytes)
                    .map_err(|_| "Matter state is corrupt; no credentials were replaced")?;
                if saved.schema != 1 || saved.identity.is_none() || saved.next_node < 112234 {
                    return Err(
                        "Matter state is incomplete or incompatible; no credentials were replaced"
                            .into(),
                    );
                }
                if saved.devices.iter().any(|d| {
                    d.node_id
                        .parse::<u64>()
                        .map_or(true, |id| id < 112234 || id >= saved.next_node)
                }) {
                    return Err("Matter device registry is invalid".into());
                }
                saved
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Self {
                schema: 1,
                identity: None,
                devices: vec![],
                next_node: 112234,
                path: PathBuf::new(),
                lock: None,
            },
            Err(_) => {
                return Err("Could not read Matter state; no credentials were replaced".into())
            }
        };
        state.path = path;
        state.lock = Some(lock);
        Ok(state)
    }

    pub fn save(&self) -> Result<(), String> {
        let bytes = serde_json::to_vec(self).map_err(|_| "Could not encode Matter state")?;
        let temp = self.path.join(format!(
            "controller-{:016x}.tmp",
            rand_matter::random::<u64>()
        ));
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options
            .open(&temp)
            .map_err(|_| "Could not create Matter snapshot")?;
        let result = (|| {
            file.write_all(&bytes)?;
            file.sync_all()?;
            drop(file);
            fs::rename(&temp, self.path.join("controller.json"))?;
            #[cfg(unix)]
            File::open(&self.path)?.sync_all()?;
            Ok::<_, std::io::Error>(())
        })();
        if result.is_err() {
            let _ = fs::remove_file(&temp);
        }
        result.map_err(|_| "Could not commit Matter state".into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_corrupt_state_and_concurrent_owners() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().to_str().unwrap();
        let owner = ControllerState::open(path).unwrap();
        assert!(ControllerState::open(path).is_err());
        drop(owner);
        fs::write(dir.path().join("controller.json"), b"broken").unwrap();
        assert!(ControllerState::open(path).is_err());
        assert_eq!(
            fs::read(dir.path().join("controller.json")).unwrap(),
            b"broken"
        );
    }
}
