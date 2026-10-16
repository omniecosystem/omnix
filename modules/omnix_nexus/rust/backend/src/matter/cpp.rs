// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! Official-SDK shim command boundary. Platform-owned commissioning and SDK
//! initialization are not implemented here. No simulator or CLI fallback.
use libloading::Library;
use std::{
    collections::HashMap,
    ffi::c_void,
    marker::PhantomData,
    path::{Path, PathBuf},
    ptr::NonNull,
    rc::Rc,
    sync::{Arc, Mutex, OnceLock},
};

pub type OwnerFn = unsafe extern "C" fn(*mut c_void);
#[repr(C)]
#[derive(Clone, Copy)]
struct ApiV1 {
    version: u32,
    size: u32,
    attach:
        unsafe extern "C" fn(*mut c_void, *mut c_void, OwnerFn, OwnerFn, *mut *mut c_void) -> i32,
    set_on_off: unsafe extern "C" fn(*mut c_void, u64, u16, u8, *mut u64) -> i32,
    poll: unsafe extern "C" fn(*mut c_void, u64, *mut u32) -> i32,
    close: unsafe extern "C" fn(*mut c_void),
}

// SDK callbacks can remain alive after a frontend is closed. Qualified native
// modules therefore stay loaded for the process lifetime, keyed by canonical
// path. Never unload callback code during an SDK operation.
static LIBRARIES: OnceLock<Mutex<HashMap<PathBuf, Arc<Library>>>> = OnceLock::new();

pub struct CppMatterApi {
    api: ApiV1,
    _library: Arc<Library>,
}
impl CppMatterApi {
    /// Loads executable native code. The caller must verify artifact provenance,
    /// architecture, ABI and host SDK compatibility before passing this path.
    ///
    /// # Safety
    /// The library must implement the exact v1 ABI, including valid function
    /// pointers and owner-retention semantics. A version number is not a trust check.
    pub unsafe fn load(path: &Path) -> Result<Arc<Self>, String> {
        if !path.is_absolute() {
            return Err("An absolute trusted SDK shim path is required".into());
        }
        let path = path.canonicalize().map_err(|e| e.to_string())?;
        let mut registry = LIBRARIES
            .get_or_init(|| Mutex::new(HashMap::new()))
            .lock()
            .map_err(|_| "SDK library registry unavailable")?;
        let library = match registry.get(&path) {
            Some(library) => library.clone(),
            None => Arc::new(unsafe { Library::new(&path) }.map_err(|e| e.to_string())?),
        };
        let getter = unsafe {
            library.get::<unsafe extern "C" fn() -> *const ApiV1>(b"omnix_matter_get_api_v1\0")
        }
        .map_err(|e| e.to_string())?;
        let table = unsafe { getter() };
        if table.is_null() {
            return Err("SDK shim returned no ABI table".into());
        }
        // Read only the fixed prefix before trusting the full table extent.
        let version = unsafe { std::ptr::read(table.cast::<u32>()) };
        let size = unsafe { std::ptr::read(table.cast::<u32>().add(1)) };
        validate_abi(version, size)?;
        let api = unsafe { *table };
        registry.insert(path, library.clone());
        Ok(Arc::new(Self {
            api,
            _library: library,
        }))
    }

    /// # Safety
    /// `controller` must be an initialized official DeviceController compatible
    /// with this shim. Owner hooks must retain its SDK/event-loop/storage lifetime
    /// through all pending callbacks, be nonthrowing, and defer destruction until
    /// after the SDK callback/stack-lock scope. Call outside the SDK stack lock.
    pub unsafe fn attach(
        self: &Arc<Self>,
        controller: NonNull<c_void>,
        owner: NonNull<c_void>,
        retain: OwnerFn,
        release: OwnerFn,
    ) -> Result<CppMatterController, String> {
        let mut handle = std::ptr::null_mut();
        check(unsafe {
            (self.api.attach)(
                controller.as_ptr(),
                owner.as_ptr(),
                retain,
                release,
                &mut handle,
            )
        })?;
        let handle = NonNull::new(handle).ok_or("SDK shim returned a null controller")?;
        Ok(CppMatterController {
            handle: Some(handle),
            api: self.clone(),
            _thread: PhantomData,
        })
    }
}

fn validate_abi(version: u32, size: u32) -> Result<(), String> {
    if version != 1 || size as usize != std::mem::size_of::<ApiV1>() {
        return Err("Unsupported official Matter shim ABI".into());
    }
    Ok(())
}
fn check(code: i32) -> Result<(), String> {
    match code {
        0 => Ok(()),
        -1 => Err("Invalid Matter handle or command".into()),
        -2 => Err("Matter operation capacity exceeded".into()),
        other => Err(format!("Matter shim failed: {other}")),
    }
}

#[derive(Debug, PartialEq, Eq)]
pub enum MatterCommandStatus {
    Pending,
    Complete { sdk_error: u32 },
}

// Deliberately not Send/Sync: platform glue must own execution/lifecycle rather
// than move a borrowed controller arbitrarily between application workers.
pub struct CppMatterController {
    handle: Option<NonNull<c_void>>,
    api: Arc<CppMatterApi>,
    _thread: PhantomData<Rc<()>>,
}
impl CppMatterController {
    pub fn set_on_off(&mut self, node: u64, endpoint: u16, on: bool) -> Result<u64, String> {
        if node == 0 {
            return Err("An operational node ID is required".into());
        }
        let handle = self.handle.ok_or("Matter controller is closed")?;
        let mut id = 0;
        check(unsafe {
            (self.api.api.set_on_off)(handle.as_ptr(), node, endpoint, u8::from(on), &mut id)
        })?;
        if id == 0 {
            return Err("SDK shim returned an invalid operation ID".into());
        }
        Ok(id)
    }
    pub fn poll(&mut self, operation: u64) -> Result<MatterCommandStatus, String> {
        let handle = self.handle.ok_or("Matter controller is closed")?;
        let mut sdk_error = 0;
        let result = unsafe { (self.api.api.poll)(handle.as_ptr(), operation, &mut sdk_error) };
        if result == 1 {
            return Ok(MatterCommandStatus::Pending);
        }
        check(result)?;
        Ok(MatterCommandStatus::Complete { sdk_error })
    }
    pub fn close(&mut self) {
        if let Some(handle) = self.handle.take() {
            unsafe { (self.api.api.close)(handle.as_ptr()) };
        }
    }
}
impl Drop for CppMatterController {
    fn drop(&mut self) {
        self.close();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn abi_requires_exact_version_and_layout() {
        assert!(validate_abi(1, std::mem::size_of::<ApiV1>() as u32).is_ok());
        assert!(validate_abi(2, std::mem::size_of::<ApiV1>() as u32).is_err());
        assert!(validate_abi(1, 8).is_err());
    }
    #[test]
    fn errors_are_not_silently_reported_as_success() {
        assert!(check(0).is_ok());
        for code in [-1, -2, -3, 42] {
            assert!(check(code).is_err());
        }
    }

    // A deterministic function-table double checks the Rust consumer contract.
    // It does NOT compile or qualify the C++ SDK adapter.
    #[cfg(windows)]
    mod contract {
        use super::*;
        struct Fixture {
            closed: u32,
            polls: u32,
            commands: u32,
        }
        unsafe extern "C" fn attach(
            controller: *mut c_void,
            _: *mut c_void,
            _: OwnerFn,
            _: OwnerFn,
            output: *mut *mut c_void,
        ) -> i32 {
            unsafe {
                *output = controller;
            }
            0
        }
        unsafe extern "C" fn owner(_: *mut c_void) {}
        unsafe extern "C" fn command(
            handle: *mut c_void,
            _: u64,
            _: u16,
            value: u8,
            output: *mut u64,
        ) -> i32 {
            assert!(value <= 1);
            let fixture = unsafe { &mut *handle.cast::<Fixture>() };
            fixture.commands += 1;
            unsafe {
                *output = 7;
            }
            0
        }
        unsafe extern "C" fn poll(handle: *mut c_void, id: u64, error: *mut u32) -> i32 {
            let fixture = unsafe { &mut *handle.cast::<Fixture>() };
            if id != 7 || fixture.polls >= 2 {
                return -1;
            }
            fixture.polls += 1;
            if fixture.polls == 1 {
                return 1;
            }
            unsafe {
                *error = 123;
            }
            0
        }
        unsafe extern "C" fn close(handle: *mut c_void) {
            unsafe {
                (*handle.cast::<Fixture>()).closed += 1;
            }
        }
        #[test]
        fn pending_completion_consumption_and_close_are_distinct() {
            let library: Library = libloading::os::windows::Library::this().unwrap().into();
            let api = Arc::new(CppMatterApi {
                api: ApiV1 {
                    version: 1,
                    size: std::mem::size_of::<ApiV1>() as u32,
                    attach,
                    set_on_off: command,
                    poll,
                    close,
                },
                _library: Arc::new(library),
            });
            let mut fixture = Box::new(Fixture {
                closed: 0,
                polls: 0,
                commands: 0,
            });
            let pointer = NonNull::from(fixture.as_mut()).cast();
            let mut controller = unsafe { api.attach(pointer, pointer, owner, owner) }.unwrap();
            assert!(controller.set_on_off(0, 1, true).is_err());
            assert_eq!(fixture.commands, 0);
            let operation = controller.set_on_off(42, 1, false).unwrap();
            assert_eq!(
                controller.poll(operation).unwrap(),
                MatterCommandStatus::Pending
            );
            assert_eq!(
                controller.poll(operation).unwrap(),
                MatterCommandStatus::Complete { sdk_error: 123 }
            );
            assert!(controller.poll(operation).is_err());
            controller.close();
            controller.close();
            assert!(controller.set_on_off(42, 1, true).is_err());
            assert!(controller.poll(operation).is_err());
            drop(controller);
            assert_eq!(fixture.closed, 1);
            assert_eq!(fixture.commands, 1);
        }
    }
}
