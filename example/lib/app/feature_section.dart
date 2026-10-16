import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

// Consumer-only presentation shared by module feature screens.
class FeatureSection extends StatelessWidget {
  const FeatureSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card.filled(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    ),
  );
}

@Preview(name: 'Feature settings card', group: 'Omnix', size: Size(390, 280))
Widget featureSectionPreview() => MaterialApp(
  theme: ThemeData.dark(),
  home: const Scaffold(
    body: Padding(
      padding: EdgeInsets.all(16),
      child: FeatureSection(
        title: 'Response length',
        icon: Icons.tune,
        children: [
          Text('1024 output tokens'),
          SizedBox(height: 12),
          Text('Set a response budget before starting a conversation.'),
        ],
      ),
    ),
  ),
);
