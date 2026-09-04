import 'package:flutter/material.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';

class ReviewSentimentSheet extends StatelessWidget {
  const ReviewSentimentSheet({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF111111);
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(l10n.reviewPromptTitle, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: textPrimary)),
          const SizedBox(height: 12),
          Text(l10n.reviewPromptBody, style: TextStyle(fontSize: 15, color: textPrimary.withValues(alpha: 0.7)), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text(l10n.reviewPromptYes, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          )),
          const SizedBox(height: 8),
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.reviewPromptNo, style: TextStyle(color: textPrimary.withValues(alpha: 0.6)))),
        ]),
      ),
    );
  }
}
