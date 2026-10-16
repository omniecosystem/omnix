# Experimental Matter controller

The rs-matter controller experiment evaluates commissioning and On/Off behavior
against disposable software devices. It is not production device onboarding.

## Security boundary

The selected prototype's test-attestation path is unsuitable for production.
Explicit simulator consent does not establish certificate verification.
Restrict the experiment to disposable fixtures, not real user devices.

Official C++ SDK integration is a separate adapter path; see
[Matter backends](MATTER_BACKENDS.md).

## Maintainer tests

The tooling uses pinned sources, container images and dependency locks.
From the repository root, supply your own clean upstream checkout:

```powershell
.\tool\test_matter.ps1 -SourcePath C:/path/to/rs-matter
.\tool\test_matter_interop.ps1 -SourcePath C:/path/to/rs-matter
```

Read each script's prerequisites and network behavior before execution.
Images and SDK dependencies can require large downloads.
These are maintainer tests, not consumer runtime requirements.

## Evidence distinctions

An upstream same-stack test, cross-stack software-device interoperability,
native host integration and real-device qualification are different checks.

Address substitution does not qualify discovery.
Persisted credentials do not prove reconnection.
A Windows compilation does not establish Android lifecycle behavior.
A container result does not qualify native Windows multicast or BLE.

## Source and provenance

The adapted controller and mDNS helper retain upstream Apache-2.0 notices.
Preserve those notices and pinned source identities when updating the experiment.

Test outputs can contain session or identity material. Keep generated diagnostic
directories outside source publication. Do not load consumer fabrics or change
firewall policy to make a fixture pass.

See the [host contract](MATTER_HOST_CONTRACT.md) for the independent platform
adapter boundary.
