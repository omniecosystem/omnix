import 'package:flutter/material.dart';
import 'knowledge_example_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyan,
          brightness: Brightness.dark,
        ),
      ),
      home: const Scaffold(body: SafeArea(child: KnowledgeExampleScreen())),
    ),
  );
}
