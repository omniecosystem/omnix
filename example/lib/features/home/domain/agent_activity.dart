enum AgentActivityState { running, completed, cancelled, failed }

class AgentActivity {
  const AgentActivity(
    this.toolName,
    this.state, {
    this.outcomeStatus,
    this.reason,
  });
  final String toolName;
  final AgentActivityState state;
  final String? outcomeStatus;
  final String? reason;
  String get label => toolName == 'search_knowledge'
      ? 'Search local Knowledge'
      : toolName == 'prepare_email_intent'
      ? 'Prepare email draft'
      : toolName;
}
