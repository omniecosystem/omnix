// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
//! Retained JVM owner. The Java host dispatches onto its bounded SDK worker.
use crate::nexus::matter::host::*;
use jni::{
    objects::{GlobalRef, JObject, JValue},
    sys::{jboolean, JNI_FALSE, JNI_TRUE},
    JNIEnv, JavaVM,
};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, OnceLock,
};

struct Owner {
    vm: JavaVM,
    object: GlobalRef,
    leased: AtomicBool,
}
static OWNER: OnceLock<Arc<Owner>> = OnceLock::new();

// One process-scoped registration. No replacement while callbacks may survive.
#[no_mangle]
pub extern "system" fn Java_xyz_omniecosystem_omnix_nexus_MatterHostRegistration_register(
    mut env: JNIEnv,
    _class: JObject,
    owner: JObject,
) -> jboolean {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if owner.is_null() {
            return false;
        }
        let Ok(class) = env.get_object_class(&owner) else {
            return false;
        };
        if env
            .get_method_id(&class, "hostSetOnOff", "(Ljava/lang/String;IZ)V")
            .is_err()
            || env
                .get_method_id(&class, "hostReadOnOff", "(Ljava/lang/String;I)Z")
                .is_err()
        {
            return false;
        }
        let Ok(vm) = env.get_java_vm() else {
            return false;
        };
        let Ok(object) = env.new_global_ref(owner) else {
            return false;
        };
        OWNER
            .set(Arc::new(Owner {
                vm,
                object,
                leased: AtomicBool::new(false),
            }))
            .is_ok()
    }));
    if matches!(result, Ok(true)) {
        JNI_TRUE
    } else {
        let _ = env.exception_clear();
        JNI_FALSE
    }
}

pub struct AndroidHost {
    owner: Arc<Owner>,
    active: bool,
}
impl AndroidHost {
    pub fn attach() -> Result<Self, String> {
        let owner = OWNER
            .get()
            .ok_or("Android Matter host is not registered")?
            .clone();
        owner
            .leased
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .map_err(|_| "Android Matter host already has a frontend")?;
        Ok(Self {
            owner,
            active: true,
        })
    }
}
impl Drop for AndroidHost {
    fn drop(&mut self) {
        if self.active {
            self.owner.leased.store(false, Ordering::Release);
        }
    }
}
impl ControllerHost for AndroidHost {
    fn backend(&self) -> Backend {
        Backend::AndroidSdk
    }
    fn execute(&mut self, command: Command) -> Result<Reply, Error> {
        let mut env = self
            .owner
            .vm
            .attach_current_thread()
            .map_err(|_| Error::HostFailure)?;
        let target = match command {
            Command::SetOnOff { target, .. } | Command::ReadOnOff { target } => target,
        };
        env.with_local_frame(8, |env| {
            let node = env.new_string(target.node_id.to_string())?;
            let node = JObject::from(node);
            let result = match command {
                Command::SetOnOff { on, .. } => env
                    .call_method(
                        self.owner.object.as_obj(),
                        "hostSetOnOff",
                        "(Ljava/lang/String;IZ)V",
                        &[
                            JValue::Object(&node),
                            JValue::Int(target.endpoint.into()),
                            JValue::Bool(if on { JNI_TRUE } else { JNI_FALSE }),
                        ],
                    )
                    .map(|_| Reply::Acknowledged),
                Command::ReadOnOff { .. } => env
                    .call_method(
                        self.owner.object.as_obj(),
                        "hostReadOnOff",
                        "(Ljava/lang/String;I)Z",
                        &[JValue::Object(&node), JValue::Int(target.endpoint.into())],
                    )
                    .and_then(|value| value.z())
                    .map(Reply::OnOff),
            };
            result
        })
        .map_err(|_| {
            let _ = env.exception_clear();
            Error::HostFailure
        })
    }
    fn shutdown(&mut self) -> Result<Shutdown, Error> {
        // Release exactly this lease. A later Drop must not release a new one.
        if self.active {
            self.active = false;
            self.owner.leased.store(false, Ordering::Release);
        }
        Ok(Shutdown::RetainedUntilProcessExit)
    }
}
