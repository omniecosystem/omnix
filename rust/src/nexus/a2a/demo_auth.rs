//! Loopback-only credential-to-principal demonstration.
//!
//! A copied bearer token is not durable node identity, pairing, or secure
//! transport. Do not use this adapter to expose private knowledge or actions.

use a2a::A2AError;
use a2a_server::{RequestAuthorizer, ServiceParams};
use subtle::ConstantTimeEq;

use super::CallerVerifier;

/// Maps one locally configured bearer credential to one caller principal.
#[derive(Clone)]
pub struct DemoBearerAuthorizer {
    token: String,
    principal: String,
    allow_public_knowledge: bool,
}

impl DemoBearerAuthorizer {
    /// Creates a loopback-only identity and policy check.
    ///
    /// The token must be generated randomly and never be used on a network
    /// without confidential, authenticated transport.
    pub fn new(token: String, principal: String, allow_public_knowledge: bool) -> Self {
        Self {
            token,
            principal,
            allow_public_knowledge,
        }
    }

    /// Returns the local principal only for the configured credential.
    pub fn authenticate<'a>(&'a self, params: &ServiceParams) -> Result<&'a str, A2AError> {
        let Some([header]) = params.get("authorization").map(Vec::as_slice) else {
            return Err(A2AError::invalid_request("caller not authenticated"));
        };
        let Some(provided) = header.strip_prefix("Bearer ") else {
            return Err(A2AError::invalid_request("caller not authenticated"));
        };
        let valid = provided.len() == self.token.len()
            && bool::from(provided.as_bytes().ct_eq(self.token.as_bytes()));
        if !valid {
            return Err(A2AError::invalid_request("caller not authenticated"));
        }
        Ok(&self.principal)
    }
}

impl RequestAuthorizer for DemoBearerAuthorizer {
    fn authorize(&self, params: &ServiceParams, _task_id: Option<&str>) -> Result<(), A2AError> {
        self.authenticate(params)?;
        if !self.allow_public_knowledge {
            return Err(A2AError::invalid_request("knowledge access denied"));
        }
        Ok(())
    }
}

impl CallerVerifier for DemoBearerAuthorizer {
    fn verify(&self, params: &ServiceParams) -> Result<String, A2AError> {
        self.authorize(params, None)?;
        self.authenticate(params).map(str::to_owned)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn params(token: &str) -> ServiceParams {
        ServiceParams::from([("authorization".into(), vec![format!("Bearer {token}")])])
    }

    #[test]
    fn credential_maps_to_principal_and_permission() {
        let auth = DemoBearerAuthorizer::new("secret".into(), "node-x".into(), true);
        assert_eq!(
            auth.authenticate(&params("secret")).expect("known token"),
            "node-x"
        );
        assert!(auth.authorize(&params("secret"), None).is_ok());
        assert!(auth.authorize(&params("wrong"), None).is_err());
        assert!(auth.authorize(&ServiceParams::new(), None).is_err());
        let denied = DemoBearerAuthorizer::new("secret".into(), "node-x".into(), false);
        assert_eq!(
            denied.authenticate(&params("secret")).expect("known token"),
            "node-x"
        );
        assert!(denied.authorize(&params("secret"), None).is_err());
    }
}
