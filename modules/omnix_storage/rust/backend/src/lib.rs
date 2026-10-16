// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! Native storage components, selected explicitly by the consuming application.
//! No database engine is included by default.

#[cfg(all(feature = "qdrant", target_arch = "wasm32"))]
compile_error!("The native Qdrant Edge component is not available on wasm32");

#[cfg(feature = "rusqlite")]
mod sqlite;
#[cfg(feature = "rusqlite")]
pub use sqlite::*;

#[cfg(feature = "rusqlite")]
mod workflow;
#[cfg(feature = "rusqlite")]
pub use workflow::WorkflowStore;

#[cfg(all(feature = "qdrant", not(target_arch = "wasm32")))]
mod qdrant;
#[cfg(all(feature = "qdrant", not(target_arch = "wasm32")))]
pub use qdrant::{QdrantStore, VectorHit, VectorProfile};
