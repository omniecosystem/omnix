//! Native Nexus integrations. Each adapter stays internal to Omnix until an
//! independently reusable boundary is demonstrated.

#[cfg(not(target_arch = "wasm32"))]
#[path = "a2a/lib.rs"]
pub mod a2a;

#[cfg(not(target_arch = "wasm32"))]
pub mod auth;
