# Consumer-supplied skills

New skills use `skills/<kebab-case-id>/SKILL.md`, with optional `examples/`
containing executable argument fixtures and `references/` for supporting material.

SKILL.md defines purpose, available capabilities, argument shapes, examples and
failure semantics. Register its instructions in the consumer extension catalogue
and declare its assets in pubspec.yaml. Assets alone do not register a skill.
Supporting files are not automatically loaded into a model's context.

Executable tool callbacks and retry contracts belong to host code, not Markdown.
Skills cannot grant permissions, override policy or change recovery safety.
These are example-app assets, not domain-specific behavior built into Omnix Rust.
