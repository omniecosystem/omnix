import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

class TypingDots extends StatefulWidget {
  const TypingDots({super.key});
  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Waiting for response',
    child: AnimatedBuilder(
      animation: _animation,
      builder: (context, _) => SizedBox(
        width: 48,
        height: 20,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (var i = 0; i < 3; i++)
              Opacity(
                opacity:
                    0.35 +
                    0.65 *
                        (1 +
                            math.sin(
                              (_animation.value - i / 3) * 2 * math.pi,
                            )) /
                        2,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: 'Waiting response dots', size: Size(100, 60))
Widget typingDotsPreview() =>
    const Material(child: Center(child: TypingDots()));
