import 'package:omnix/omnix.dart' show OmnixEmailIntent;
import 'package:url_launcher/url_launcher.dart';

Uri emailComposerUri(OmnixEmailIntent intent) => Uri(
  scheme: 'mailto',
  path: intent.recipient,
  query: {'subject': intent.subject, 'body': intent.body}.entries
      .map(
        (entry) =>
            '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
      )
      .join('&'),
);

// Called only after the presentation layer obtains explicit confirmation.
Future<bool> openEmailComposer(OmnixEmailIntent intent) =>
    launchUrl(emailComposerUri(intent), mode: LaunchMode.externalApplication);
