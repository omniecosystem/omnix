//! Opt-in composition of independent native engine modules.
//!
//! No module or Flutter binding is enabled by default. Modules can also be
//! consumed directly without this facade. The `flutter-bridge` feature selects
//! the transitional Flutter adapter, not a requirement for Rust consumers.

pub mod context;

#[cfg(feature = "flutter-bridge")]
pub mod api;
#[cfg(feature = "flutter-bridge")]
mod frb_generated;

#[cfg(feature = "core")]
pub use omnix_core as core;
#[cfg(feature = "agent")]
pub mod agent;
#[cfg(all(feature = "knowledge-local", not(target_arch = "wasm32")))]
pub mod local_knowledge;
#[cfg(feature = "core")]
pub mod session;
#[cfg(all(
    any(
        all(feature = "agent", feature = "flutter-bridge"),
        feature = "workflow-local"
    ),
    not(target_arch = "wasm32")
))]
mod tool_arguments;
#[cfg(feature = "knowledge")]
pub use omnix_knowledge as knowledge;
#[cfg(feature = "workflow")]
pub use omnix_workflow as workflow;
#[cfg(all(feature = "workflow-local", not(target_arch = "wasm32")))]
pub mod task_runtime;
#[cfg(all(feature = "workflow-local", not(target_arch = "wasm32")))]
pub mod workflow_runtime;
// Preserve the existing Rust path while Nexus lives in an independent crate.
#[cfg(any(
    feature = "nexus",
    feature = "nexus-a2a",
    feature = "nexus-matter-experimental"
))]
pub use omnix_nexus as nexus;

#[cfg(all(
    any(
        feature = "storage",
        feature = "storage-rusqlite",
        feature = "storage-qdrant"
    ),
    not(target_arch = "wasm32")
))]
pub use omnix_storage as storage;
