// lib/screens/debug_logs_screen.dart
import 'package:flutter/material.dart';
import '../core/services/debug_log_service.dart';
import '../core/utils/constants.dart';

class DebugLogsScreen extends StatelessWidget {
  const DebugLogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    final DebugLogService logger = DebugLogService();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text('Debug Logs', style: TextStyle(color: textPrimary)),
        iconTheme: IconThemeData(color: textPrimary),
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.delete_outline, color: textSecondary),
            tooltip: 'Clear logs',
            onPressed: logger.clear,
          ),
        ],
      ),
      body: SafeArea(
        child: ValueListenableBuilder<List<DebugLogEntry>>(
          valueListenable: logger.logs,
          builder: (BuildContext context, List<DebugLogEntry> logs, Widget? _) {
            if (logs.isEmpty) {
              return Center(
                child: Text(
                  'No logs yet',
                  style: TextStyle(color: textSecondary, fontSize: AppTypography.bodySize),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: logs.length,
              itemBuilder: (BuildContext context, int index) {
                final DebugLogEntry entry = logs[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight,
                    borderRadius: BorderRadius.circular(AppShape.cardRadius),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              entry.tag,
                              style: TextStyle(
                                color: accent,
                                fontSize: AppTypography.captionSize,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
                            '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
                            '${entry.timestamp.second.toString().padLeft(2, '0')}.'
                            '${entry.timestamp.millisecond.toString().padLeft(3, '0')}',
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: AppTypography.captionSize,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      SelectableText(
                        entry.message,
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: AppTypography.footnoteSize,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
