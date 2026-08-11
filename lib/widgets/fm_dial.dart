import 'package:flutter/material.dart';
import 'dart:math';

class FMDial extends StatefulWidget {
  final double frequency;
  final double minFrequency;
  final double maxFrequency;
  final ValueChanged<double> onChanged;

  const FMDial({
    super.key,
    required this.frequency,
    required this.onChanged,
    this.minFrequency = 88.0,
    this.maxFrequency = 108.0,
  });

  @override
  State<FMDial> createState() => _FMDialState();
}

class _FMDialState extends State<FMDial> {
  double _currentAngle = 0;

  @override
  void initState() {
    super.initState();
    _updateAngleFromFrequency();
  }

  @override
  void didUpdateWidget(FMDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frequency != widget.frequency) {
      _updateAngleFromFrequency();
    }
  }

  void _updateAngleFromFrequency() {
    final range = widget.maxFrequency - widget.minFrequency;
    final normalized = (widget.frequency - widget.minFrequency) / range;
    _currentAngle = normalized * 2 * pi;
  }

  void _updateFrequencyFromAngle(double angle) {
    final normalized = angle / (2 * pi);
    final range = widget.maxFrequency - widget.minFrequency;
    double frequency = widget.minFrequency + (normalized * range);
    frequency = frequency.clamp(widget.minFrequency, widget.maxFrequency);

    // Round to 0.1
    frequency = (frequency * 10).round() / 10;

    if (frequency != widget.frequency) {
      widget.onChanged(frequency);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) {
        final RenderBox box = context.findRenderObject() as RenderBox;
        final center = box.size.center(Offset.zero);
        final localPosition = box.globalToLocal(details.globalPosition);

        final dx = localPosition.dx - center.dx;
        final dy = localPosition.dy - center.dy;

        double angle = atan2(dy, dx);
        if (angle < 0) angle += 2 * pi;

        _updateFrequencyFromAngle(angle);
      },
      child: Container(
        width: 300,
        height: 300,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            center: Alignment.center,
            startAngle: 0,
            endAngle: 2 * pi,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.secondary,
              Theme.of(context).colorScheme.tertiary,
              Theme.of(context).colorScheme.primary,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color:
                  Theme.of(context).colorScheme.shadow.withValues(alpha: 0.3),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Container(
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Frequency markers
              for (int i = 88; i <= 108; i += 2)
                Positioned(
                  top: 30,
                  child: Transform.rotate(
                    angle: ((i - 88) / 20) * 2 * pi,
                    child: Text(
                      '$i',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

              // Dial indicator
              Transform.rotate(
                angle: _currentAngle,
                child: Container(
                  width: 4,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Center knob
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primaryContainer,
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.shadow.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.radio,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: 30,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
