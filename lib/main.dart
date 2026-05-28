import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  sherpa.initBindings();
  runApp(const ProviderScope(child: MindMateApp()));
}

class MindMateApp extends StatelessWidget {
  const MindMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MindMate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}