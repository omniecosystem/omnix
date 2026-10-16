/// A Rust-validated email proposal awaiting explicit host/user confirmation.
///
/// This is data, not permission to launch an app or send an email.
final class OmnixEmailIntent {
  const OmnixEmailIntent._(this.recipient, this.subject, this.body);

  factory OmnixEmailIntent.fromJson(Map<String, dynamic> json) {
    final recipient = json['recipient'];
    final subject = json['subject'];
    final body = json['body'];
    if (json['kind'] != 'email' ||
        recipient is! String ||
        subject is! String ||
        body is! String ||
        recipient.length > 254 ||
        recipient.contains(RegExp(r'\s')) ||
        !RegExp(
          r'^[A-Za-z0-9._+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)+$',
        ).hasMatch(recipient) ||
        subject.trim().isEmpty ||
        subject.length > 256 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(subject) ||
        body.trim().isEmpty ||
        body.length > 8192 ||
        RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(body)) {
      throw const FormatException('Invalid native email proposal.');
    }
    return OmnixEmailIntent._(recipient, subject, body);
  }

  final String recipient;
  final String subject;
  final String body;
  Map<String, dynamic> toJson() => {
    'kind': 'email',
    'recipient': recipient,
    'subject': subject,
    'body': body,
  };
}
