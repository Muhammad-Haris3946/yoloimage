import 'package:flutter/material.dart';

class CustomAppbar extends StatefulWidget {
  final String title;
  const CustomAppbar({Key? key, required this.title}) : super(key: key);

  @override
  State<CustomAppbar> createState() => _CustomAppbarState();
}

class _CustomAppbarState extends State<CustomAppbar> with SingleTickerProviderStateMixin  {

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
    return AppBar(
      elevation: 0,
      centerTitle: true,
      foregroundColor: Colors.white,
      backgroundColor: Colors.transparent,
      flexibleSpace: AnimatedBuilder(
        animation: _ac,
        builder: (_, __) {
          final t = _ac.value;
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: const [Color(0xFF0EA5E9), Color(0xFF4F46E5), Color(0xFF8B5CF6)],
                stops: [0.0, (0.35 + 0.3 * t).clamp(0.2, 0.7), 1.0],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          );
        },
      ),
      title:  Text(
        widget.title,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
