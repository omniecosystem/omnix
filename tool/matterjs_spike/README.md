# Matter.js controller fixture

Maintainer experiment for controller startup, shutdown and software-light
interoperability. It is not a production device or a consumer runtime dependency.

From the repository root:

```powershell
cd tool/matterjs_spike
pnpm install --frozen-lockfile
pnpm test
pnpm run test:control
```

Use the Node and package-manager versions required by the checked-in manifests.

## Network behavior

The control fixture creates a disposable software light and temporary fabric
state. mDNS uses LAN multicast, and the light listens on port 5542.
This is not a network-disabled test even when controller addresses are loopback.

Use a trusted test LAN and public development credentials only.
Port conflicts must fail rather than target an unrelated device.
The harness must not alter firewall policy or load consumer fabric state.

`android_light.mjs` is a desktop-hosted fixture for the Android controller;
it is not Matter.js running inside Android. Supply the host's actual LAN address.

## Validation limits

Both peers in `test:control` use Matter.js. A pass does not establish
cross-SDK interoperability, physical-device attestation or production
credential management.

Windows interface normalization is isolated in `windows_interfaces.mjs`.
Its regression tests and [mDNS guide](MDNS_WINDOWS.md) describe the fixture
behavior. Desktop packaging and the Android SDK host remain separate checks.
