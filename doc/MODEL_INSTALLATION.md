# Model installation

Core owns artifact identity, integrity checks, installed-state records and
publication into a model catalog. Inference does not acquire files implicitly.

The optional Rust feature is `model-installation`.
Dart exposes the same implementation through `OmnixModelInstaller`;
Flutter hosts supply picking, directory discovery, consent and OS transfer.

## Foreground installation

Native installation supports trusted HTTPS sources and local import paths.
A job reports progress and a terminal result. Consumers must observe completion
and release resources even when cancelling.

Importing can copy a source file; a platform picker can also create a cached
copy. Do not claim universal zero-copy acquisition.

## OS-backed transfers

`reserveTransfer`, `pendingTransfers` and `completeTransfer` expose native
reservation and verification to a host downloader.

```text
Host consent -> Core reservation -> OS transfer -> closed writer
             -> Core verification/publication -> explicit model selection
```

The host reconciles its OS task ID with the reservation.
A recovered reservation does not itself resume a network task.

Publication can rename completed staging on the same filesystem rather than
copy multi-gigabyte weights again. The OS transport may still use its own
temporary files.

## Integrity and privacy

Mandatory expected size, SHA-256 and container checks distinguish installed
artifacts from partial transfers. Trust in a digest depends on its source.

Pending bytes are not installed models. A verification failure must not remove
an existing valid installation. Uncertain completion needs catalog inspection,
not blind replay of publication or deletion.

Reservations do not contain download URLs or bearer tokens.
Host downloaders can persist those separately; review their credential storage
and cleanup semantics.

## Runtime compatibility

A verified container is not proof of model quality, licensing acceptance,
modality support or device capacity.
Downloading GGUF cannot enable an omitted Android llama.cpp implementation.

Artifact management is independent of agent, Knowledge, Storage and Nexus
selection. Native runtime libraries are build dependencies, not model weights.

## Host transport

The Flutter example uses an OS-backed downloader adapter; other hosts can
implement their own. Rust foreground transfer does not guarantee background
survival, HTTP Range resume or platform scheduling.

See [example transfers](EXAMPLE_MODEL_DOWNLOADS.md),
[model preparation](CHAT_READINESS.md), and the
[Core module](../modules/omnix_core/README.md).
