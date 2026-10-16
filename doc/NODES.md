# Node identity and authorized retrieval

Nexus separates identity from permission. An authenticated peer is not
automatically entitled to private Knowledge or device actions.

## Host and protocol boundaries

Applications select their endpoint exposure and routing.
Nexus A2A can use paired identities and peer grants without requiring a
particular account provider or route service.

A private HTTPS route is deployment infrastructure, not automatic NAT traversal.
A native listener cannot be assumed available inside a browser.

## Source visibility

Remote retrieval must apply current authoritative visibility and grant checks.
A public source is eligible under the host's sharing policy, not necessarily
anonymous internet data.

Recheck revocation rather than trust stale index metadata.
Returning a source does not grant the peer arbitrary action authority.

## Identity storage

Keep private keys and grant stores in host-owned private locations.
Exchange public keys only. Do not clone node identity directories between
devices or treat test tokens as production pairing.

Persistence, replay defenses, listener lifetime and transport authentication
need explicit integration tests; a signed loopback pass is not every network's
security or availability guarantee.

See the [Nexus module](../modules/omnix_nexus/README.md) and
[A2A demonstration](NEXUS_A2A_DEMO.md).
