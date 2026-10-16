// Consumer configuration, not an engine-wide policy. Core enforces the native
// context bound; this example uses a 4096-token context for Home conversations.
const homeResponseTokens = int.fromEnvironment(
  'OMNIX_HOME_OUTPUT_TOKENS',
  defaultValue: 1024,
);

int validateHomeResponseTokens(int tokens) {
  if (tokens < 1 || tokens > 4096) {
    throw ArgumentError.value(tokens, 'maxOutputTokens', 'Use 1–4096 tokens.');
  }
  return tokens;
}
