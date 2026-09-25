// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! First native Nexus surface for public A2A Knowledge requests.
//!
//! Starts a public-Knowledge-only loopback listener when the host opts in.
//! Remote actions are not authorized by this surface.

use flutter_rust_bridge::DartFnFuture;

/// Text artifacts from an authorized peer's completed A2A response.
pub struct NexusKnowledgeReply {
    pub task_id: Option<String>,
    pub texts: Vec<String>,
}

/// A loopback-only A2A listener managed by the host application.
pub struct NexusListenerInfo {
    pub id: u64,
    pub port: u16,
}

#[cfg(not(target_arch = "wasm32"))]
mod listener {
    use flutter_rust_bridge::DartFnFuture;
    use futures::future::BoxFuture;
    use omnixus_a2a::AsyncKnowledgeSource;
    use std::{
        collections::HashMap,
        path::Path,
        sync::atomic::{AtomicU64, Ordering},
        sync::{Arc, Mutex, OnceLock},
    };
    use tokio::{sync::oneshot, task::JoinHandle};

    use super::NexusListenerInfo;

    struct Entry {
        shutdown: oneshot::Sender<()>,
        task: JoinHandle<()>,
    }

    static LISTENERS: OnceLock<Mutex<HashMap<u64, Entry>>> = OnceLock::new();
    static NEXT_ID: AtomicU64 = AtomicU64::new(1);

    fn listeners() -> &'static Mutex<HashMap<u64, Entry>> {
        LISTENERS.get_or_init(|| Mutex::new(HashMap::new()))
    }

    struct DartKnowledge<F>(Arc<F>);

    impl<F> AsyncKnowledgeSource for DartKnowledge<F>
    where
        F: Fn(String, String) -> DartFnFuture<String> + Send + Sync + 'static,
    {
        fn answer(
            &self,
            caller_id: String,
            question: String,
        ) -> BoxFuture<'static, Result<String, String>> {
            let callback = Arc::clone(&self.0);
            Box::pin(async move {
                let answer = callback(caller_id, question).await;
                if answer.trim().is_empty() || answer.len() > 16_384 {
                    return Err("public Knowledge unavailable".into());
                }
                Ok(answer)
            })
        }
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub(super) async fn start<F>(
        node_dir: String,
        advertised_origin: String,
        port: u16,
        callback: F,
    ) -> Result<NexusListenerInfo, String>
    where
        F: Fn(String, String) -> DartFnFuture<String> + Send + Sync + 'static,
    {
        let router = omnixus_a2a::node::paired_public_router_async(
            Path::new(&node_dir),
            &advertised_origin,
            DartKnowledge(Arc::new(callback)),
        )?;
        let tcp = tokio::net::TcpListener::bind(("127.0.0.1", port))
            .await
            .map_err(|_| "loopback port unavailable")?;
        let actual_port = tcp
            .local_addr()
            .map_err(|_| "loopback address unavailable")?
            .port();
        let (shutdown, receiver) = oneshot::channel();
        let task = tokio::spawn(async move {
            let _ = axum::serve(tcp, router)
                .with_graceful_shutdown(async {
                    let _ = receiver.await;
                })
                .await;
        });
        let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
        listeners()
            .lock()
            .map_err(|_| "listener registry unavailable")?
            .insert(id, Entry { shutdown, task });
        Ok(NexusListenerInfo {
            id,
            port: actual_port,
        })
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub(super) async fn stop(id: u64) -> Result<(), String> {
        let mut entry = listeners()
            .lock()
            .map_err(|_| "listener registry unavailable")?
            .remove(&id)
            .ok_or("listener not found")?;
        let _ = entry.shutdown.send(());
        if tokio::time::timeout(std::time::Duration::from_secs(2), &mut entry.task)
            .await
            .is_err()
        {
            entry.task.abort();
            let _ = entry.task.await;
        }
        Ok(())
    }
}

/// Starts a paired, public-Knowledge-only A2A endpoint on local loopback.
///
/// The host must supply a reachable HTTPS origin and own any TLS proxy. The
/// callback is invoked only after the remote peer's signed proof is verified.
/// An empty answer denies the request. No private Knowledge or actions are
/// exposed. Restart the listener after modifying peer grants.
pub async fn start_public_knowledge_listener(
    node_dir: String,
    advertised_origin: String,
    port: u16,
    answer: impl Fn(String, String) -> DartFnFuture<String> + Send + Sync + 'static,
) -> Result<NexusListenerInfo, String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        listener::start(node_dir, advertised_origin, port, answer).await
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (node_dir, advertised_origin, port, answer);
        Err("native Nexus listener is not available in the browser".into())
    }
}

/// Stops a listener started by this process.
pub async fn stop_public_knowledge_listener(id: u64) -> Result<(), String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        listener::stop(id).await
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = id;
        Err("native Nexus listener is not available in the browser".into())
    }
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
