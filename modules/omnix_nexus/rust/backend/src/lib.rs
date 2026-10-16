//! Native Nexus identity and protocol integrations, independent of Flutter.
//!
//! The host supplies capability implementations and access policy. Matter
//! adapters remain opt-in and experimental; enabling one does not authorize
//! devices or establish production platform support.

#[cfg(all(feature = "a2a", not(target_arch = "wasm32")))]
#[path = "a2a/lib.rs"]
pub mod a2a;

#[cfg(all(feature = "a2a", not(target_arch = "wasm32")))]
pub mod auth;

#[cfg(any(
    feature = "matter-host",
    all(
        any(feature = "experimental-matter", feature = "matter-cpp"),
        not(target_arch = "wasm32")
    )
))]
pub mod matter;

// Compatibility path; new consumers should use matter::cpp.
#[cfg(all(feature = "matter-cpp", not(target_arch = "wasm32")))]
pub use matter::cpp as matter_cpp;
