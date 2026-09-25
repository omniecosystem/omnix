//! Opt-in paired-key identity experiment and demo-only Knowledge grants.
//!
//! A node keeps an Ed25519 signing key locally and explicitly grants public
//! Knowledge to pinned peer keys. This is not a production key store, consent
//! flow, or authorization system for private data or physical actions.

use std::{collections::HashMap, fs, path::Path, sync::Arc};

use a2a::A2AError;
use a2a_server::{RequestAuthorizer, ServiceParams};
use serde::{Deserialize, Serialize};

use super::CallerVerifier;
use crate::nexus::auth::normalize_public_key;
pub use crate::nexus::auth::{PeerProofVerifier, SigningIdentity};

fn denied() -> A2AError {
    A2AError::invalid_request("caller not authenticated or authorized")
}

/// One peer and the only capability this prototype can grant.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PeerGrant {
    pub public_key: String,
    pub public_knowledge: bool,
}

/// Local, explicit allowlist. No peer can grant itself access over A2A.
#[derive(Default, Serialize, Deserialize)]
pub struct PeerRegistry {
    pub peers: Vec<PeerGrant>,
}

impl PeerRegistry {
    pub fn load_from(dir: &Path) -> Result<Self, Box<dyn std::error::Error>> {
        let bytes = match fs::read(dir.join("peers.json")) {
            Ok(bytes) => bytes,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Ok(Self::default())
            }
            Err(error) => return Err(error.into()),
        };
        let registry: Self = serde_json::from_slice(&bytes)?;
        for peer in &registry.peers {
            normalize_public_key(&peer.public_key)?;
        }
        Ok(registry)
    }

    /// Grants a pinned public key access to the public Knowledge fixture.
    pub fn allow_public(dir: &Path, public_key: &str) -> Result<(), Box<dyn std::error::Error>> {
        let public_key = normalize_public_key(public_key)?;
        let path = dir.join("peers.json");
        let mut registry = if path.exists() {
            Self::load_from(dir)?
        } else {
            Self::default()
        };
        if let Some(peer) = registry
            .peers
            .iter_mut()
            .find(|p| p.public_key == public_key)
        {
            peer.public_knowledge = true;
        } else {
            registry.peers.push(PeerGrant {
                public_key,
                public_knowledge: true,
            });
        }
        fs::write(path, serde_json::to_vec_pretty(&registry)?)?;
        Ok(())
    }

    /// Revokes public Knowledge for a pinned key. Restart the server to load
    /// the updated registry; this prototype does not hot-reload grants.
    pub fn deny_public(dir: &Path, public_key: &str) -> Result<(), Box<dyn std::error::Error>> {
        let public_key = normalize_public_key(public_key)?;
        let mut registry = Self::load_from(dir)?;
        let peer = registry
            .peers
            .iter_mut()
            .find(|peer| peer.public_key == public_key)
            .ok_or("peer is not in the allowlist")?;
        peer.public_knowledge = false;
        fs::write(
            dir.join("peers.json"),
            serde_json::to_vec_pretty(&registry)?,
        )?;
        Ok(())
    }
}

/// Demo authorization policy for the public-Knowledge fixture only.
///
/// The cryptographic proof is capability-neutral; this allowlist is not an
/// Omnixus-wide permission model and should be replaced by a host policy.
#[derive(Clone)]
pub struct PairedNodeAuthorizer {
    proof: PeerProofVerifier,
    permits: Arc<dyn Fn(&str) -> bool + Send + Sync>,
}

impl PairedNodeAuthorizer {
    /// Compatibility constructor for the public-Knowledge demo registry.
    pub fn new(audience: String, registry: PeerRegistry) -> Self {
        let grants: HashMap<_, _> = registry
            .peers
            .into_iter()
            .map(|peer| (peer.public_key, peer.public_knowledge))
            .collect();
        Self::with_access(audience, move |key| {
            grants.get(key).copied().unwrap_or(false)
        })
    }

    /// Lets a host decide which verified peer keys may access this endpoint.
    /// The predicate is a local authorization decision, not an A2A claim.
    pub fn with_access(
        audience: String,
        permits: impl Fn(&str) -> bool + Send + Sync + 'static,
    ) -> Self {
        Self {
            proof: PeerProofVerifier::new(audience),
            permits: Arc::new(permits),
        }
    }

    fn check(&self, params: &ServiceParams, consume_nonce: bool) -> Result<String, A2AError> {
        let Some([header]) = params.get("authorization").map(Vec::as_slice) else {
            return Err(denied());
        };
        let bearer = header.strip_prefix("Bearer ").ok_or_else(denied)?;
        // Check the grant before consuming the proof's nonce. Neither a valid
        // signature nor knowledge of a key confers permission by itself.
        let key = self
            .proof
            .verify_bearer(bearer, false)
            .map_err(|_| denied())?;
        if !(self.permits)(&key) {
            return Err(denied());
        }
        if consume_nonce {
            self.proof
                .verify_bearer(bearer, true)
                .map_err(|_| denied())?;
        }
        Ok(format!("ed25519:{key}"))
    }
}

impl RequestAuthorizer for PairedNodeAuthorizer {
    fn authorize(&self, params: &ServiceParams, task_id: Option<&str>) -> Result<(), A2AError> {
        // No cross-peer task history until task ownership is implemented.
        if task_id.is_some() {
            return Err(A2AError::invalid_request("task access unavailable"));
        }
        self.check(params, false).map(|_| ())
    }
}

impl CallerVerifier for PairedNodeAuthorizer {
    fn verify(&self, params: &ServiceParams) -> Result<String, A2AError> {
        self.check(params, true)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn params(token: &str) -> ServiceParams {
        ServiceParams::from([("authorization".into(), vec![format!("Bearer {token}")])])
    }

    #[test]
    fn identity_persists_and_cannot_be_silently_replaced() {
        let dir = tempfile::tempdir().expect("temp directory");
        let first = SigningIdentity::create_in(dir.path()).expect("create identity");
        let reloaded = SigningIdentity::load_from(dir.path()).expect("load identity");
        assert_eq!(first.public_key_hex(), reloaded.public_key_hex());
        assert!(!dir.path().join("peers.json").exists());
        assert!(PeerRegistry::load_from(dir.path())
            .expect("missing grant file means no grants")
            .peers
            .is_empty());
        assert!(SigningIdentity::create_in(dir.path()).is_err());
    }

    #[test]
    fn valid_identity_proof_does_not_imply_a_knowledge_grant() {
        let dir = tempfile::tempdir().expect("temp directory");
        let identity = SigningIdentity::create_in(dir.path()).expect("identity");
        let token = identity
            .bearer_for("https://server.example")
            .expect("token");
        let request = params(&token);
        let proof = PeerProofVerifier::new("https://server.example".into());
        assert_eq!(
            proof.verify_bearer(&token, true).expect("valid proof"),
            identity.public_key_hex()
        );
        assert!(proof.verify_bearer(&token, true).is_err(), "replay");

        let no_grants =
            PairedNodeAuthorizer::new("https://server.example".into(), PeerRegistry::default());
        assert!(no_grants.authorize(&request, None).is_err());
    }

    #[test]
    fn explicit_peer_grant_authenticates_once_for_its_audience() {
        let client = tempfile::tempdir().expect("client directory");
        let server = tempfile::tempdir().expect("server directory");
        let identity = SigningIdentity::create_in(client.path()).expect("identity");
        PeerRegistry::allow_public(server.path(), &identity.public_key_hex()).expect("grant");
        let registry = PeerRegistry::load_from(server.path()).expect("load grants");
        let auth = PairedNodeAuthorizer::new("https://server.example".into(), registry);
        let token = identity
            .bearer_for("https://server.example")
            .expect("signed credential");
        let request = params(&token);
        assert!(auth.authorize(&request, None).is_ok());
        assert!(auth.authorize(&request, Some("other-task")).is_err());
        assert!(auth
            .verify(&request)
            .expect("verified peer")
            .starts_with("ed25519:"));
        assert!(auth.verify(&request).is_err(), "replay must be denied");
    }

    #[test]
    fn missing_grant_wrong_audience_and_tampering_fail_closed() {
        let dir = tempfile::tempdir().expect("temp directory");
        let identity = SigningIdentity::create_in(dir.path()).expect("identity");
        let unpaired =
            PairedNodeAuthorizer::new("https://server.example".into(), PeerRegistry::default());
        let token = identity
            .bearer_for("https://server.example")
            .expect("token");
        assert!(unpaired.authorize(&params(&token), None).is_err());
        let allowed = PairedNodeAuthorizer::new(
            "https://server.example".into(),
            PeerRegistry {
                peers: vec![PeerGrant {
                    public_key: identity.public_key_hex(),
                    public_knowledge: true,
                }],
            },
        );
        let wrong_audience = identity.bearer_for("https://other.example").expect("token");
        assert!(allowed.authorize(&params(&wrong_audience), None).is_err());
        let mut tampered = token.into_bytes();
        let last = tampered.len() - 1;
        tampered[last] = if tampered[last] == b'A' { b'B' } else { b'A' };
        assert!(allowed
            .authorize(&params(&String::from_utf8(tampered).expect("ascii")), None)
            .is_err());
    }

    #[test]
    fn revocation_removes_the_public_grant_after_reload() {
        let dir = tempfile::tempdir().expect("temp directory");
        let identity = SigningIdentity::create_in(dir.path()).expect("identity");
        PeerRegistry::allow_public(dir.path(), &identity.public_key_hex()).expect("grant");
        PeerRegistry::deny_public(dir.path(), &identity.public_key_hex()).expect("revoke");
        let auth = PairedNodeAuthorizer::new(
            "https://server.example".into(),
            PeerRegistry::load_from(dir.path()).expect("registry"),
        );
        let token = identity
            .bearer_for("https://server.example")
            .expect("token");
        assert!(auth.authorize(&params(&token), None).is_err());
    }
}
