# Tool reliability validation

Reliable tool use requires several independent checks:
native structured output, a usable declaration catalog, skill guidance,
argument validation, supplied policy and an accurate executor result.

Native constrained decoding does not grant permission, validate business
semantics or guarantee a correct plan.

## Validation layers

1. Register supported tool schemas and compatible instructions.
2. Expose only available, granted capabilities.
3. Validate model arguments before host execution.
4. Validate workflow plans against current executor contracts.
5. Return structured failures and actual execution outcomes.
6. Bound repair attempts and preserve cancellation semantics.

The current closed scalar-object validator is not full JSON Schema.
Dates, resource scope and other domain rules belong to the supplied executor.

Input-bound workflow arguments require validation after resolving saved inputs.
Historical successful results are not authority for a new action.

## Useful test cases

- Empty-object and required-field tools.
- Unknown fields, wrong literal types and unsupported schema forms.
- Explicit skill loading and premature action requests.
- Recoverable validation feedback and bounded model correction.
- Proposal-only versus execution requests.
- Cancellation, timeout and late host results.
- External effects whose outcome requires reconciliation.

Do not weaken schemas or replay uncertain actions simply to improve an apparent
success rate.

## Comparing implementations

Use the same model, runtime version, sampling settings and prompts.
Measure first-call validity, repair rounds and completed outcomes separately.
Catalog size and instruction content can affect results; comparing programming
languages alone does not explain reliability differences.

The read-only native harness at `rust/examples/tool_reliability.rs` exercises
a small tool scenario with explicitly supplied artifacts. It is not a benchmark
of every Home tool, model or device.

Scripted and compiled bridge tests establish contract behavior, not empirical
model success rates. Test the actual supported deployment configuration.
