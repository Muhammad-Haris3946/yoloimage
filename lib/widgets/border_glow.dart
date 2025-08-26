import 'package:flutter/material.dart';

class BorderGlow extends StatelessWidget {
  final Widget child;
  const BorderGlow({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(boxShadow: [
        BoxShadow(
          color: Color(0x33FF3B30), // soft red glow
          blurRadius: 12,
          spreadRadius: 1,
        ),
      ]),
      child: child,
    );
  }
}