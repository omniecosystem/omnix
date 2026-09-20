// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

/// Performs a minimal native call used to verify bridge initialization.
#[flutter_rust_bridge::frb(sync)]
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
