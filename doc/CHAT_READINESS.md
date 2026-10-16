# Model preparation and Home readiness

The example can prepare its selected installed chat model during startup.
Preparation is not a model download and does not send a dummy inference prompt.

The host controls when preparation starts and how loading or failure is
presented. Root Omnix owns runtime selection, shared model leases, conversation
resources and checkpoint restoration.

## Sending and restoring

Preparing a saved conversation restores its supported native context before
the next live turn. Restoration must not execute historical tools.

Presentation state and runtime readiness are distinct: a host may accept a
draft while preparing the model, then submit it once resources are available.
A preparation failure should preserve the draft and visible history and
provide a retry path rather than silently start a different conversation.

## Resource ownership

A preparation lease retains a compatible model without generating a turn.
Reuse depends on model and runtime configuration; a different model, context
configuration or required capability can require different native resources.

Do not preload every model and embedding encoder indiscriminately. Release
unused resources when their owning host is closed.

The example's startup preparation can be disabled with:

```text
--dart-define=OMNIX_EAGER_PREPARATION=false
```

This is an example application setting, not a mandatory engine policy.

## Lifecycle limits

Warmup does not guarantee background residency or prevent OS memory pressure.
After process termination, applications must reopen native resources and
restore compatible saved state.

Readiness tests with doubles do not establish packaged startup, memory-pressure
or process-death behavior. Validate those scenarios on each supported target.
