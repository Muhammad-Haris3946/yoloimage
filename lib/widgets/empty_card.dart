import 'package:flutter/material.dart';
import 'dart:ui' as ui; // for ImageFilter.blur

class EmptyPreviewCard extends StatefulWidget {

  const EmptyPreviewCard({super.key, required});

  @override
  State<EmptyPreviewCard> createState() => _EmptyPreviewCardState();
}

class _EmptyPreviewCardState extends State<EmptyPreviewCard>  with SingleTickerProviderStateMixin{
  late final AnimationController _ac;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library_outlined, size: 48, color: Color(0xFF64748B)),
            const SizedBox(height: 10),
            const Text(
              "No image selected",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
            ),
            const SizedBox(height: 8),
            _ShimmerBar(controller: _ac),
            const SizedBox(height: 6),
            const Text(
              "Pick from Gallery or use Quick Capture",
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }
}


class _GlassPanel extends StatelessWidget {
  final Widget child;
  const _GlassPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.55),
            border: Border.all(color: Colors.white.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ShimmerBar extends StatelessWidget {
  final AnimationController controller;
  const _ShimmerBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = controller.value;
        return Container(
          height: 8,
          width: 180,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              colors: const [Color(0xFFE5E7EB), Color(0xFFF3F4F6), Color(0xFFE5E7EB)],
              stops: [0.0, (0.3 + 0.4 * t).clamp(0.2, .8), 1.0],
            ),
          ),
        );
      },
    );
  }
}