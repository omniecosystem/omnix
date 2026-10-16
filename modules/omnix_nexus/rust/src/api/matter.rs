// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! Opt-in, simulator-only Matter controller. Not a production commissioning API.

pub async fn matter_open(directory: String) -> Result<u64, String> {
    #[cfg(all(feature = "experimental-matter", not(target_arch = "wasm32")))]
    {
        return crate::nexus::matter::open(directory).await;
    }
    #[cfg(not(all(feature = "experimental-matter", not(target_arch = "wasm32"))))]
    {
        let _ = directory;
        Err("Experimental Matter was not enabled in this build".into())
    }
}

pub async fn matter_request(
    id: u64,
    operation: String,
    arguments: String,
) -> Result<String, String> {
    #[cfg(all(feature = "experimental-matter", not(target_arch = "wasm32")))]
    {
        return crate::nexus::matter::request(id, operation, arguments).await;
    }
    #[cfg(not(all(feature = "experimental-matter", not(target_arch = "wasm32"))))]
    {
        let _ = (id, operation, arguments);
        Err("Experimental Matter was not enabled in this build".into())
    }
}

pub async fn matter_close(id: u64) -> Result<(), String> {
    #[cfg(all(feature = "experimental-matter", not(target_arch = "wasm32")))]
    {
        return crate::nexus::matter::close(id).await;
    }
    #[cfg(not(all(feature = "experimental-matter", not(target_arch = "wasm32"))))]
    {
        let _ = id;
        Ok(())
    }
}
