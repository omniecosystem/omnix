# Agent sessions

Omnix exposes a headless agent contract without making a provider's dispatcher,
event classes, or UI types part of the public engine API.

An `OmnixRuntime` may be composed with an `OmnixAgentBackend`. Calling
`openAgent` takes an immutable snapshot of the runtime capability registry and
opens a session from that state. Later capability changes apply to newly opened
sessions. This avoids silently changing a live model's discovery prompt midway
through a turn.

Agent turns stream neutral events for:

- skill discovery;
- tool calls and structured results;
- visible response text;
- completion and iteration limits; and
- recoverable or terminal failures.

Text, image, web, and error tool outputs cross the core boundary directly. A
provider-native view is represented as an unavailable output with a descriptive
kind; framework widgets never enter the Omnix domain API.

## Flutter Gemma Agent adapter

The opt-in `omnix_flutter_gemma_agent.dart` library supplies the current
adapter. The same `FlutterGemmaAgentSkillAdapter` both imports provider skills
into `runtime.capabilities` and recreates a provider registry from the snapshot
used to open a session.

```dart
import 'package:omnix/omnix.dart';
import 'package:omnix/omnix_flutter_gemma.dart';
import 'package:omnix/omnix_flutter_gemma_agent.dart';

final skillAdapter = FlutterGemmaAgentSkillAdapter(providerSkills);
final capabilities = OmnixCapabilityRegistry();
skillAdapter.registerWith(
  capabilities,
  enabledSkillIds: {'get-current-time'},
);

final runtime = FlutterGemmaOmnix.createRuntime(
  capabilityRegistry: capabilities,
  agentBackend: FlutterGemmaAgentBackend(
    skills: skillAdapter,
    executors: providerExecutors,
  ),
);

final session = await runtime.openAgent(
  const OmnixAgentConfiguration(
    modelTemplate: OmnixModelTemplate.gemma4,
  ),
);
```

Inference arbitration remains an application policy. Hosts should run complete
agent turns through `InferenceScheduler` when interactive conversations and
background work share one model instance. A running turn is not preempted; a
higher-priority interactive request can run next.
