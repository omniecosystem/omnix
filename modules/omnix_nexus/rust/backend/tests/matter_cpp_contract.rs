// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
#![cfg(all(feature = "matter-cpp", not(target_arch = "wasm32")))]

#[test]
#[ignore = "requires explicitly built C++ contract library, not the official SDK"]
fn cpp_callback_lifetimes_through_native_library() {
    let path = std::env::var_os("OMNIX_MATTER_CONTRACT_LIBRARY")
        .expect("set OMNIX_MATTER_CONTRACT_LIBRARY to the absolute test-double library path");
    let path = std::path::Path::new(&path);
    // Only an explicitly built, locally authored test artifact is acceptable.
    let api = unsafe { omnix_nexus::matter::cpp::CppMatterApi::load(path) }.unwrap();
    let library = unsafe { libloading::Library::new(path) }.unwrap();
    let run =
        unsafe { library.get::<unsafe extern "C" fn() -> i32>(b"omnix_matter_contract_run\0") }
            .unwrap();
    assert_eq!(unsafe { run() }, 0);
    drop(api); // Loader keeps the native callback module pinned.
}
