import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../core/utils/constants.dart';
import 'ios_pressable.dart';

class QuickActionPill extends StatelessWidget {
  const QuickActionPill({
    super.key,
    required this.onAnnotate,
    required this.onSign,
    required this.onRegionOcr,
    required this.onConvert,
    required this.onCompress,
  });

  final VoidCallback onAnnotate;
  final VoidCallback onSign;
  final VoidCallback onRegionOcr;
  final VoidCallback onConvert;
  final VoidCallback onCompress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(AppShape.cardRadius),
        boxShadow: AppShadows.fab,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildButton(PhosphorIconsRegular.highlighter, onAnnotate),
          _buildButton(PhosphorIconsRegular.pen, onSign),
          _buildButton(PhosphorIconsRegular.crop, onRegionOcr),
          _buildButton(PhosphorIconsRegular.fileText, onConvert),
          _buildButton(PhosphorIconsRegular.arrowsIn, onCompress),
        ],
      ),
    );
  }

  Widget _buildButton(PhosphorIconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: IOSPressable(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Colors.white10,
            shape: BoxShape.circle,
          ),
          child: PhosphorIcon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}
