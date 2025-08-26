import 'package:flutter/material.dart';

class DetectionBox extends StatelessWidget {
  final String label;
  final double score;
  const DetectionBox({super.key, required this.label, required this.score});

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFFF3B30); // iOS red
    final text = '$label ${(score * 100).toStringAsFixed(1)}%';

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: red, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: Container(
          decoration: const BoxDecoration(
            color: red,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: .2,
            ),
          ),
        ),
      ),
    );
  }
}