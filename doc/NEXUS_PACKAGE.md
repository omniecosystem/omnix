# Independent Nexus package

`modules/omnix_nexus` contains the Dart API, build hooks, Rust bridge and
independent `omnix-nexus` backend. Rust consumers can use the backend without
Dart or Flutter.

Nexus does not require inference or embedding execution.
Hosts supply application answers after their own authoritative access checks.

## Selection and ownership

A2A and Matter components are selected explicitly.
Each backend has its own target and packaging requirements.
No implicit fallback may convert one Matter implementation into another.

The Nexus bridge owns its identities, listeners and controller frontends.
Do not pass those handles to root or companion library registries.

## A2A

Identity is not permission. Peer grants and source visibility constrain dispatch.
A receiver must recheck authoritative access state rather than trust stale
vector metadata.

Listener startup, endpoint exposure and transport routing are host decisions.
Nexus does not imply automatic NAT traversal or a browser-native listener.

## Matter

See [backend selection](MATTER_BACKENDS.md) and
[the host contract](MATTER_HOST_CONTRACT.md).
Experimental controllers, software fixtures and contract doubles are not
production device certification.

## Validation

Run module analysis and its selected Rust/Dart tests with matching native
artifacts. Signed loopback tests are different from two-device networking
and mobile lifecycle tests.

The standalone example has its own application identity.
Use isolated apps and stores for device qualification; never reuse an installed
consumer app as a disposable test harness.

See the [module README](../modules/omnix_nexus/README.md).
