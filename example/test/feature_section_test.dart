import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_example/app/feature_section.dart';

void main() {
  testWidgets('feature cards wrap long headings on narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FeatureSection(
            title: 'A longer feature settings heading for compact devices',
            icon: Icons.settings,
            children: [Text('All controls remain available.')],
          ),
        ),
      ),
    );
    expect(find.text('All controls remain available.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
