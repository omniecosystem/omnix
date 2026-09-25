//! Capability-neutral, opt-in paired-node identity proof.
//!
//! This prototype establishes a peer key, not permission to use any feature.

use std::{
    collections::HashMap,
    fs::{self, OpenOptions},
    io::Write,
    path::Path,
    sync::{Arc, Mutex},
    time::{SystemTime, UNIX_EPOCH},
};

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use ed25519_dalek::{Signature, Signer, SigningKey, Verifier, VerifyingKey};
use rand::{rngs::OsRng, RngCore};
use serde::{Deserialize, Serialize};

const MAX_SKEW_SECONDS: i64 = 60;
const MAX_REPLAY_ENTRIES: usize = 10_000;

fn now_seconds() -> Result<i64, Box<dyn std::error::Error>> {
    Ok(i64::try_from(
        SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs(),
    )?)
}

/// One durable local signing identity; never sent to a remote node.
pub struct SigningIdentity(SigningKey);

impl SigningIdentity {
    /// Creates a new identity without overwriting an existing secret.
    pub fn create_in(dir: &Path) -> Result<Self, Box<dyn std::error::Error>> {
        fs::create_dir_all(dir)?;
        let mut secret = [0u8; 32];
        OsRng.fill_bytes(&mut secret);
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options.open(dir.join("identity.key"))?;
        file.write_all(&secret)?;
        file.sync_all()?;
        let identity = Self(SigningKey::from_bytes(&secret));
        fs::write(dir.join("identity.pub"), identity.public_key_hex())?;
        Ok(identity)
    }

    /// Loads an existing identity without creating a replacement.
    pub fn load_from(dir: &Path) -> Result<Self, Box<dyn std::error::Error>> {
        let bytes = fs::read(dir.join("identity.key"))?;
        let secret: [u8; 32] = bytes.try_into().map_err(|_| "invalid identity.key")?;
        Ok(Self(SigningKey::from_bytes(&secret)))
    }

    pub fn public_key_hex(&self) -> String {
        hex::encode(self.0.verifying_key().as_bytes())
    }

    /// Signs a short-lived request for the named remote audience.
    pub fn bearer_for(&self, audience: &str) -> Result<String, Box<dyn std::error::Error>> {
        let mut nonce = [0u8; 16];
        OsRng.fill_bytes(&mut nonce);
        let payload = SignedClaim {
            version: 1,
            public_key: self.public_key_hex(),
            audience: audience.to_owned(),
            issued_at: now_seconds()?,
            nonce: URL_SAFE_NO_PAD.encode(nonce),
        };
        let bytes = serde_json::to_vec(&payload)?;
        let signature = self.0.sign(&bytes);
        Ok(format!(
            "{}.{}",
            URL_SAFE_NO_PAD.encode(&bytes),
            URL_SAFE_NO_PAD.encode(signature.to_bytes())
        ))
    }
}

#[derive(Serialize, Deserialize)]
struct SignedClaim {
    version: u8,
    public_key: String,
    audience: String,
    issued_at: i64,
    nonce: String,
}

pub(crate) fn normalize_public_key(input: &str) -> Result<String, Box<dyn std::error::Error>> {
    let decoded = hex::decode(input)?;
    let key: [u8; 32] = decoded
        .try_into()
        .map_err(|_| "invalid public key length")?;
    Ok(hex::encode(VerifyingKey::from_bytes(&key)?.as_bytes()))
}

/// Verifies identity only. Authorization remains with the receiving host.
#[derive(Clone)]
pub struct PeerProofVerifier {
    audience: String,
    seen: Arc<Mutex<HashMap<String, i64>>>,
}

/// The peer proof was invalid, expired, or replayed. Deliberately omits details.
#[derive(Debug, Clone, Copy)]
pub struct ProofRejected;

impl std::fmt::Display for ProofRejected {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("peer proof rejected")
    }
}

impl std::error::Error for ProofRejected {}

impl PeerProofVerifier {
    pub fn new(audience: String) -> Self {
        Self {
            audience,
            seen: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Returns the verified public key. Consume the nonce at execution time.
    pub fn verify_bearer(
        &self,
        bearer: &str,
        consume_nonce: bool,
    ) -> Result<String, ProofRejected> {
        if bearer.len() > 2048 {
            return Err(ProofRejected);
        }
        let (payload, signature) = bearer.split_once('.').ok_or(ProofRejected)?;
        let payload = URL_SAFE_NO_PAD.decode(payload).map_err(|_| ProofRejected)?;
        let signature = URL_SAFE_NO_PAD
            .decode(signature)
            .map_err(|_| ProofRejected)?;
        let claim: SignedClaim = serde_json::from_slice(&payload).map_err(|_| ProofRejected)?;
        let now = now_seconds().map_err(|_| ProofRejected)?;
        if claim.version != 1
            || claim.audience != self.audience
            || claim.nonce.len() != 22
            || now.abs_diff(claim.issued_at) > MAX_SKEW_SECONDS as u64
        {
            return Err(ProofRejected);
        }
        let key = normalize_public_key(&claim.public_key).map_err(|_| ProofRejected)?;
        let key_bytes: [u8; 32] = hex::decode(&key)
            .map_err(|_| ProofRejected)?
            .try_into()
            .map_err(|_| ProofRejected)?;
        let verifying_key = VerifyingKey::from_bytes(&key_bytes).map_err(|_| ProofRejected)?;
        let signature = Signature::from_slice(&signature).map_err(|_| ProofRejected)?;
        verifying_key
            .verify(&payload, &signature)
            .map_err(|_| ProofRejected)?;
        if consume_nonce {
            let mut seen = self.seen.lock().map_err(|_| ProofRejected)?;
            seen.retain(|_, issued_at| now.abs_diff(*issued_at) <= MAX_SKEW_SECONDS as u64);
            if seen.len() >= MAX_REPLAY_ENTRIES {
                return Err(ProofRejected);
            }
            let replay_key = format!("{}:{}", key, claim.nonce);
            if seen.insert(replay_key, claim.issued_at).is_some() {
                return Err(ProofRejected);
            }
        }
        Ok(key)
    }
}
