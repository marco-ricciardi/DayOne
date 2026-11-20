import 'package:flutter/material.dart';

class CustomSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final String? label;

  const CustomSlider({
    super.key,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    required this.onChanged,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Text(
            label!,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 12,
            ),
            overlayShape: const RoundSliderOverlayShape(
              overlayRadius: 20,
            ),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white30,
            thumbColor: Colors.white,
            overlayColor: Colors.white24,
          ),
          child: Slider(
            min: min,
            max: max,
            divisions: divisions,
            value: value,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
