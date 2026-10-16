// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! Independently selected Matter adapters. No platform silently selects a
//! backend: the experimental controller and official SDK boundary have
//! different qualification levels.

#[cfg(feature = "matter-host")]
pub mod host;

#[cfg(all(feature = "matter-process", target_os = "windows"))]
pub mod process;

#[cfg(all(feature = "matter-cpp", not(target_arch = "wasm32")))]
pub mod cpp;

#[cfg(all(feature = "experimental-matter", not(target_arch = "wasm32")))]
mod experimental;

// Preserve the existing experimental controller API for bridge consumers.
#[cfg(all(feature = "experimental-matter", not(target_arch = "wasm32")))]
pub use experimental::*;
