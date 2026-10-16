// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
//! Explicit registered/fixture host sessions. No production commissioning API.
use flutter_rust_bridge::frb;

#[cfg(any(
    all(feature = "matter-process", target_os = "windows"),
    all(feature = "matter-android", target_os = "android")
))]
struct SessionHost(Box<dyn crate::nexus::matter::host::ControllerHost + Send>);

#[cfg(any(
    all(feature = "matter-process", target_os = "windows"),
    all(feature = "matter-android", target_os = "android")
))]
impl crate::nexus::matter::host::ControllerHost for SessionHost {
    fn backend(&self) -> crate::nexus::matter::host::Backend {
        self.0.backend()
    }
    fn execute(
        &mut self,
        command: crate::nexus::matter::host::Command,
    ) -> Result<crate::nexus::matter::host::Reply, crate::nexus::matter::host::Error> {
        self.0.execute(command)
    }
    fn shutdown(
        &mut self,
    ) -> Result<crate::nexus::matter::host::Shutdown, crate::nexus::matter::host::Error> {
        self.0.shutdown()
    }
}

#[frb(opaque)]
pub struct MatterHostSession {
    #[cfg(any(
        all(feature = "matter-process", target_os = "windows"),
        all(feature = "matter-android", target_os = "android")
    ))]
    inner: std::sync::Mutex<crate::nexus::matter::host::Controller<SessionHost>>,
    node_id: u64,
    endpoint: u16,
}

pub fn matter_host_open_windows_fixture(
    bundle: String,
    storage: String,
) -> Result<MatterHostSession, String> {
    #[cfg(all(feature = "matter-process", target_os = "windows"))]
    {
        use crate::nexus::matter::{
            host::{Backend, Controller},
            process::ProcessHost,
        };
        let directory = std::path::Path::new(&bundle);
        let host = ProcessHost::qualification(
            &directory.join("node.exe"),
            &directory.join("host_controller.mjs"),
            std::path::Path::new(&storage),
        )
        .map_err(|error| format!("Matter host startup: {error:?}"))?;
        let target = host.target();
        let controller = Controller::attach(Backend::WindowsMatterJs, SessionHost(Box::new(host)))
            .map_err(|error| format!("Matter host attach: {error:?}"))?;
        Ok(MatterHostSession {
            inner: std::sync::Mutex::new(controller),
            node_id: target.node_id,
            endpoint: target.endpoint,
        })
    }
    #[cfg(not(all(feature = "matter-process", target_os = "windows")))]
    {
        let _ = (bundle, storage);
        Err(
            "Windows qualification host requires explicit matter-process selection on Windows"
                .into(),
        )
    }
}

pub fn matter_host_open_android(node_id: u64, endpoint: u16) -> Result<MatterHostSession, String> {
    if node_id == 0 || node_id > 0xFFFF_FFEF_FFFF_FFFF || endpoint == 0 {
        return Err("Invalid operational Matter target".into());
    }
    #[cfg(all(feature = "matter-android", target_os = "android"))]
    {
        use crate::nexus::matter::host::{Backend, Controller};
        let host = crate::android_matter_host::AndroidHost::attach()?;
        let controller = Controller::attach(Backend::AndroidSdk, SessionHost(Box::new(host)))
            .map_err(|error| format!("Android Matter attach: {error:?}"))?;
        Ok(MatterHostSession {
            inner: std::sync::Mutex::new(controller),
            node_id,
            endpoint,
        })
    }
    #[cfg(not(all(feature = "matter-android", target_os = "android")))]
    Err("Android host requires explicit matter-android selection on Android".into())
}

impl MatterHostSession {
    pub fn node_id(&self) -> u64 {
        self.node_id
    }
    pub fn endpoint(&self) -> u16 {
        self.endpoint
    }

    pub fn set_on_off(&self, on: bool) -> Result<(), String> {
        #[cfg(any(
            all(feature = "matter-process", target_os = "windows"),
            all(feature = "matter-android", target_os = "android")
        ))]
        {
            use crate::nexus::matter::host::*;
            let mut controller = self
                .inner
                .try_lock()
                .map_err(|_| "Matter host busy or poisoned")?;
            match controller.execute(Command::SetOnOff {
                target: Target {
                    node_id: self.node_id,
                    endpoint: self.endpoint,
                },
                on,
            }) {
                Ok(Reply::Acknowledged) => Ok(()),
                answer => Err(format!("Matter command: {answer:?}")),
            }
        }
        #[cfg(not(any(
            all(feature = "matter-process", target_os = "windows"),
            all(feature = "matter-android", target_os = "android")
        )))]
        {
            let _ = on;
            Err("Matter host not enabled".into())
        }
    }

    pub fn read_on_off(&self) -> Result<bool, String> {
        #[cfg(any(
            all(feature = "matter-process", target_os = "windows"),
            all(feature = "matter-android", target_os = "android")
        ))]
        {
            use crate::nexus::matter::host::*;
            let mut controller = self
                .inner
                .try_lock()
                .map_err(|_| "Matter host busy or poisoned")?;
            match controller.execute(Command::ReadOnOff {
                target: Target {
                    node_id: self.node_id,
                    endpoint: self.endpoint,
                },
            }) {
                Ok(Reply::OnOff(on)) => Ok(on),
                answer => Err(format!("Matter readback: {answer:?}")),
            }
        }
        #[cfg(not(any(
            all(feature = "matter-process", target_os = "windows"),
            all(feature = "matter-android", target_os = "android")
        )))]
        {
            Err("Matter host not enabled".into())
        }
    }

    pub fn close(&self) -> Result<(), String> {
        #[cfg(any(
            all(feature = "matter-process", target_os = "windows"),
            all(feature = "matter-android", target_os = "android")
        ))]
        {
            use crate::nexus::matter::host::Shutdown;
            let mut controller = self
                .inner
                .try_lock()
                .map_err(|_| "Matter host busy or poisoned")?;
            match controller.shutdown() {
                Ok(Shutdown::Released | Shutdown::RetainedUntilProcessExit) => Ok(()),
                answer => Err(format!("Matter shutdown: {answer:?}")),
            }
        }
        #[cfg(not(any(
            all(feature = "matter-process", target_os = "windows"),
            all(feature = "matter-android", target_os = "android")
        )))]
        {
            Err("Matter host not enabled".into())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_invalid_android_targets_before_host_access() {
        for (node, endpoint) in [(0, 1), (u64::MAX, 1), (1, 0)] {
            assert!(
                matches!(matter_host_open_android(node, endpoint), Err(error) if error == "Invalid operational Matter target")
            );
        }
    }
    #[cfg(not(all(feature = "matter-android", target_os = "android")))]
    #[test]
    fn android_never_falls_back_to_another_host() {
        assert!(
            matches!(matter_host_open_android(1, 1), Err(error) if error.contains("explicit matter-android"))
        );
    }
}
