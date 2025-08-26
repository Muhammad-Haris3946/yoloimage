import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomGradientButton extends StatelessWidget {
  final List<Color> colors;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const CustomGradientButton({Key? key, required this.colors, required this.icon, required this.label, this.onTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        elevation: 8,
        shadowColor: colors.last.withOpacity(.35),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          onTapDown: (_) => HapticFeedback.selectionClick(),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
