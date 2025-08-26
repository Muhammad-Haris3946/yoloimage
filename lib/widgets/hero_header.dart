import 'package:flutter/material.dart';

class HeroHeader extends StatefulWidget {
  const HeroHeader({Key? key,}) : super(key: key);

  @override
  State<HeroHeader> createState() => _HeroHeaderState();
}

class _HeroHeaderState extends State<HeroHeader> with SingleTickerProviderStateMixin  {

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
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) {
        final t = _ac.value;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: const [Color(0xFF22D3EE), Color(0xFF6366F1), Color(0xFF9333EA)],
              stops: [0.0, (0.4 + 0.2 * t).clamp(0.2, .8), 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x22000000), blurRadius: 16, offset: Offset(0, 8))
            ],
          ),
          child: Row(
            children: const [
              Icon(Icons.auto_awesome, color: Colors.white, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'YOLOv11 Object Detection',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: .4,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
