# Node authentication and authorization

Omnix defines a node boundary without selecting a network topology, identity
provider, or wire protocol. An application may begin with a server-mediated
identity service and later adopt direct peer authentication without changing
Knowledge retrieval contracts.

## Authentication boundary

`OmnixNodeAuthenticationEvidence` carries an opaque scheme and byte payload.
Omnix does not interpret or persist that payload. An application supplies an
`OmnixNodeAuthenticator` that verifies it and returns an
`OmnixNodePrincipal`.

Possible adapters include:

- a Supabase access token validated locally or by a trusted server;
- a relay-issued session credential;
- a signed nonce verified against a peer public key;
- a mutually authenticated transport mapped to a node identity.

Authentication proves identity. It does not by itself grant access.

## Knowledge authorization

`OmnixNodeKnowledgeAuthorizer` receives the verified principal, semantic query,
and request context. It either denies the operation or returns an explicit
grant containing:

- permitted access labels;
- maximum result count;
- minimum similarity floor.

`OmnixNodeKnowledgeService` intersects the request with that grant before
retrieval. It rejects expired principals and empty access intersections without
touching the Knowledge backend. Private knowledge therefore cannot become
remotely available merely because a caller requested it.

## Deliberate omissions

The core package does not yet prescribe discovery, routing, relays, public-key
formats, token validation, revocation, replay prevention, rate-limit storage,
or encrypted transport. Those concerns belong to replaceable adapters and the
future Omnixus protocol. Request identifiers, timestamps, and attributes are
available so adapters can enforce replay and resource policies without leaking
their implementation into the engine.
