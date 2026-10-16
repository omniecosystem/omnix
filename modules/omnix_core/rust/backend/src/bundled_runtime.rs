// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

// Resolve beside this bridge, not in the working directory or system PATH.
pub(crate) fn litertlm_path() -> Result<String, String> {
    #[cfg(windows)]
    {
        use windows_sys::Win32::System::LibraryLoader::{
            GetModuleFileNameW, GetModuleHandleExW, GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
            GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        };
        let mut module = std::ptr::null_mut();
        let flags =
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT;
        // The function's address belongs to the currently loaded bridge DLL.
        if unsafe {
            GetModuleHandleExW(flags, litertlm_path as *const () as *const u16, &mut module)
        } == 0
        {
            return Err("Cannot locate bundled Core bridge".into());
        }
        let mut buffer = vec![0u16; 32768];
        let length = unsafe { GetModuleFileNameW(module, buffer.as_mut_ptr(), buffer.len() as u32) }
            as usize;
        if length == 0 || length >= buffer.len() {
            return Err("Cannot locate bundled Core bridge path".into());
        }
        use std::os::windows::ffi::OsStringExt;
        let bridge = std::path::PathBuf::from(std::ffi::OsString::from_wide(&buffer[..length]));
        let path = bridge
            .parent()
            .ok_or("Core bridge has no directory")?
            .join("LiteRtLm.dll");
        if !path.is_file() {
            return Err(
                "Bundled LiteRT-LM is missing beside Core; rebuild the app with litertlm selected"
                    .into(),
            );
        }
        path.into_os_string()
            .into_string()
            .map_err(|_| "Runtime path is not UTF-8".into())
    }
    #[cfg(target_os = "android")]
    {
        let mut info: libc::Dl_info = unsafe { std::mem::zeroed() };
        // Find this loaded bridge, not the working directory or a global PATH.
        if unsafe { libc::dladdr(litertlm_path as *const () as *const _, &mut info) } == 0
            || info.dli_fname.is_null()
        {
            return Err("Cannot locate Android Core bridge".into());
        }
        let bridge = unsafe { std::ffi::CStr::from_ptr(info.dli_fname) }
            .to_str()
            .map_err(|_| "Core bridge path is not UTF-8")?;
        let bridge = std::path::Path::new(bridge);
        if !bridge.is_absolute() || !bridge.is_file() {
            return Err("Android Core requires android:extractNativeLibs=\"true\"".into());
        }
        let path = bridge
            .parent()
            .ok_or("Core bridge has no directory")?
            .join(option_env!("OMNIX_CORE_LITERTLM_ANDROID_LIBRARY").unwrap_or("liblitert-lm.so"));
        if !path.is_file() {
            return Err("Pinned Android LiteRT-LM is missing beside Core".into());
        }
        Ok(path.to_string_lossy().into_owned())
    }
    #[cfg(not(any(windows, target_os = "android")))]
    Err("Automatic LiteRT-LM loading is supported only on Windows x64 and Android".into())
}

#[cfg(feature = "litertlm-embedding-engine")]
pub(crate) fn embedding_path() -> Result<std::path::PathBuf, String> {
    let chat = std::path::PathBuf::from(litertlm_path()?);
    #[cfg(windows)]
    return Ok(chat.with_file_name("litert-lm.dll"));
    #[cfg(not(windows))]
    Ok(chat)
}
