# Core lifecycle validation

Validate model/session lifetime independently from response quality.

## Native caches

LiteRT-LM can create and reuse runtime-owned optimized caches.
Core exposes an explicit cache-directory option; omission preserves native
defaults. A cache is not a replacement model, conversation history or a
promise of warm reuse across configurations.

Hosts supply trusted directories and retain appropriate access permissions.
llama.cpp does not need an equivalent LiteRT-LM cache to load its own format.

Measure cold load, warm load and first-token latency separately.
An unchanged cache file is not a complete performance benchmark.

## Shared ownership

Core's model pool uses compatible configuration keys and separate leases.
Closing one model facade must not invalidate a surviving conversation.
Sharing weights must not share history, permissions or tool authority.

Keys involving file metadata are not cryptographic proof against malicious
replacement. Treat loaded model files as immutable.

Logical conversation multiplexing may reconstruct native context when switching.
That cost is distinct from loading weights and does not imply KV serialization.
Separate native libraries do not automatically share registries.

## Resource and recovery checks

- Concurrent compatible loads initialize once.
- Failed initialization can be retried without retaining a broken owner.
- Closing one lease preserves other live users.
- Cancellation drains callbacks before freeing their state.
- Switching preserves isolated histories.
- Restored history does not execute past tools.
- Memory-pressure handling does not discard live context silently.

Memory admission and idle release are separate from a total memory budget.
See [execution admission](EXECUTION_ADMISSION.md) and
[idle release](IDLE_RESOURCE_RELEASE.md).

## Qualification

Use equivalent models and settings when comparing implementations.
Test each native adapter, packaged application and target separately.
A CPU cache test does not qualify GPU/NPU, mobile process death or clean-machine
dependency delivery.
