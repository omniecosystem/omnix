// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! First native Nexus surface for public A2A Knowledge requests.
//!
//! Deliberately does not start a listener or authorize remote actions. The
//! receiving node still needs an in-process Omnix Knowledge adapter.

/// Text artifacts from an authorized peer's completed A2A response.
pub struct NexusKnowledgeReply {
    pub task_id: Option<String>,
    pub texts: Vec<String>,
}

/// Creates this node's local signing identity; refuses to replace one.
pub fn create_node_identity(node_dir: String) -> Result<String, String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        omnixus_a2a::paired_auth::SigningIdentity::create_in(std::path::Path::new(&node_dir))
            .map(|identity| identity.public_key_hex())
            .map_err(|error| error.to_string())
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = node_dir;
        Err("native Nexus node identity is not available in the browser".into())
    }
}

/// Returns this node's existing public key without creating another identity.
pub fn node_public_key(node_dir: String) -> Result<String, String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        omnixus_a2a::paired_auth::SigningIdentity::load_from(std::path::Path::new(&node_dir))
            .map(|identity| identity.public_key_hex())
            .map_err(|error| error.to_string())
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = node_dir;
        Err("native Nexus node identity is not available in the browser".into())
    }
}

/// Grants a pinned peer key access to public Knowledge only.
pub fn allow_public_peer(node_dir: String, public_key: String) -> Result<(), String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        omnixus_a2a::paired_auth::PeerRegistry::allow_public(
            std::path::Path::new(&node_dir),
            &public_key,
        )
        .map_err(|error| error.to_string())
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (node_dir, public_key);
        Err("native Nexus peer grants are not available in the browser".into())
    }
}

/// Revokes a public Knowledge grant. A running receiver must reload grants.
pub fn deny_public_peer(node_dir: String, public_key: String) -> Result<(), String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        omnixus_a2a::paired_auth::PeerRegistry::deny_public(
            std::path::Path::new(&node_dir),
            &public_key,
        )
        .map_err(|error| error.to_string())
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (node_dir, public_key);
        Err("native Nexus peer grants are not available in the browser".into())
    }
}

/// Sends one signed public Knowledge request to a remote A2A node.
pub async fn query_peer_public_knowledge(
    node_dir: String,
    remote_origin: String,
    question: String,
) -> Result<NexusKnowledgeReply, String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        omnixus_a2a::node::query_public_knowledge(
            std::path::Path::new(&node_dir),
            &remote_origin,
            &question,
        )
        .await
        .map(|reply| NexusKnowledgeReply {
            task_id: reply.task_id,
            texts: reply.texts,
        })
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (node_dir, remote_origin, question);
        Err("native Nexus A2A requests are not available in the browser".into())
    }
}
