// for ImageFilter.blur
import 'package:flutter/material.dart';
import 'package:image_detection_new/screens/home_screen.dart';

void main() {
  runApp(const MyApp());
}

class Detection {
  final Rect rect;
  final String label;
  final double score;
  Detection({required this.rect, required this.label, required this.score});
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6366F1), // indigo
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'YOLOv11 Object Detection',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        fontFamily: 'Roboto',
      ),
      home: const HomeScreen(),
    );
  }
}

