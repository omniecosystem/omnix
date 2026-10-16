// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
//! Isolated qualification glue, not a published JNI SDK or native pointer shim.
use jni::{
    objects::{JObject, JValue},
    sys::{jboolean, JNI_FALSE, JNI_TRUE},
    JNIEnv,
};
use omnix_nexus::matter::host::*;

struct AndroidHost<'env, 'local> {
    env: &'env mut JNIEnv<'local>,
    owner: JObject<'local>,
}

impl ControllerHost for AndroidHost<'_, '_> {
    fn backend(&self) -> Backend {
        Backend::AndroidSdk
    }
    fn execute(&mut self, command: Command) -> Result<Reply, Error> {
        let target = match command {
            Command::SetOnOff { target, .. } | Command::ReadOnOff { target } => target,
        };
        let node = self
            .env
            .new_string(target.node_id.to_string())
            .map_err(|_| Error::HostFailure)?;
        let node = JObject::from(node);
        let result = match command {
            Command::SetOnOff { on, .. } => self
                .env
                .call_method(
                    &self.owner,
                    "hostSetOnOff",
                    "(Ljava/lang/String;IZ)V",
                    &[
                        JValue::Object(&node),
                        JValue::Int(target.endpoint.into()),
                        JValue::Bool(if on { JNI_TRUE } else { JNI_FALSE }),
                    ],
                )
                .map(|_| Reply::Acknowledged),
            Command::ReadOnOff { .. } => self
                .env
                .call_method(
                    &self.owner,
                    "hostReadOnOff",
                    "(Ljava/lang/String;I)Z",
                    &[JValue::Object(&node), JValue::Int(target.endpoint.into())],
                )
                .and_then(|value| value.z())
                .map(Reply::OnOff),
        };
        result.map_err(|_| {
            // Preserve no opaque Java exception across subsequent JNI calls.
            let _ = self.env.exception_clear();
            Error::HostFailure
        })
    }
    fn shutdown(&mut self) -> Result<Shutdown, Error> {
        // Only detach this frontend. The process-scoped owner remains alive.
        Ok(Shutdown::RetainedUntilProcessExit)
    }
}

#[no_mangle]
pub extern "system" fn Java_xyz_omniecosystem_qualification_omnix_1matter_1android_1app_RustMatterHost_verify<
    'local,
>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    owner: JObject<'local>,
) -> jboolean {
    let success = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let host = AndroidHost {
            env: &mut env,
            owner,
        };
        let mut controller = Controller::attach(Backend::AndroidSdk, host).map_err(|_| ())?;
        let target = Target {
            node_id: 0x12344321,
            endpoint: 1,
        };
        for on in [true, false] {
            if controller.execute(Command::SetOnOff { target, on }) != Ok(Reply::Acknowledged)
                || controller.execute(Command::ReadOnOff { target }) != Ok(Reply::OnOff(on))
            {
                let _ = controller.shutdown();
                return Err(());
            }
        }
        if controller.shutdown() != Ok(Shutdown::RetainedUntilProcessExit) {
            return Err(());
        }
        Ok(())
    }))
    .is_ok_and(|result| result.is_ok());
    if !success {
        let _ = env.exception_clear();
    }
    if success {
        JNI_TRUE
    } else {
        JNI_FALSE
    }
}
