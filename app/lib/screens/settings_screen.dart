import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/providers/settings_provider.dart';
import '../core/providers/subscription_provider.dart';
import '../core/providers/theme_provider.dart';
import '../core/services/debug_log_service.dart';
import '../core/services/ocr_service.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsProvider _settingsProvider;
  late final ThemeProvider _themeProvider;
  late final SubscriptionProvider _subscriptionProvider;

  @override
  void initState() {
    super.initState();
    _settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    _themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    _subscriptionProvider = Provider.of<SubscriptionProvider>(context, listen: false);
  }

  Future<void> _openUrl(String url, AppLocalizations l10n) async {
    final uri = Uri.parse(url);
    bool launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.couldNotOpenLinkError)));
    }
  }

  Future<void> _restorePurchases(AppLocalizations l10n) async {
    await _subscriptionProvider.restore();
    if (!mounted) return;
    final error = _subscriptionProvider.lastError.value;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? l10n.restoreCompleteMessage)));
  }

  Future<void> _pickLanguage() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => _LanguagePickerSheet(current: _settingsProvider.settings.value.language),
    );
    if (chosen != null) await _settingsProvider.setLanguage(chosen);
  }

  Future<void> _openOcrLanguages() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _OcrLanguagesSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final border = isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(backgroundColor: bg, elevation: 0, title: Text(l10n.settingsTitle, style: TextStyle(color: textPrimary))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _sectionLabel(l10n.appearanceSectionLabel, textSecondary),
            ListenableBuilder(
              listenable: _themeProvider.themeMode,
              builder: (context, _) => _settingsTile(
                title: l10n.themeLabel,
                trailing: DropdownButton<ThemeMode>(
                  value: _themeProvider.themeMode.value,
                  underline: const SizedBox.shrink(),
                  onChanged: (mode) { if (mode != null) _themeProvider.setThemeMode(mode); },
                  items: [
                    DropdownMenuItem(value: ThemeMode.system, child: Text(l10n.systemThemeOption)),
                    DropdownMenuItem(value: ThemeMode.light, child: Text(l10n.lightThemeOption)),
                    DropdownMenuItem(value: ThemeMode.dark, child: Text(l10n.darkThemeOption)),
                  ],
                ),
                textPrimary: textPrimary,
                border: border,
              ),
            ),
            ListenableBuilder(
              listenable: _themeProvider.accentColor,
              builder: (context, _) {
                final current = _themeProvider.accentColor.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Accent Color', style: TextStyle(color: textPrimary, fontSize: AppTypography.bodySize)),
                      Row(
                        children: kAccentPalettes.map((p) {
                          final isSelected = p.light == current;
                          return GestureDetector(
                            onTap: () => _themeProvider.setAccentColor(p.light),
                            child: Container(
                              width: 28, height: 28, margin: const EdgeInsets.only(left: 8),
                              decoration: BoxDecoration(
                                color: p.light, shape: BoxShape.circle,
                                border: Border.all(color: isSelected ? textPrimary : Colors.transparent, width: 2),
                              ),
                              child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            _sectionLabel(l10n.languageSectionLabel, textSecondary),
            ListenableBuilder(
              listenable: _settingsProvider.settings,
              builder: (context, _) => Column(
                children: [
                  _settingsTile(title: l10n.appLanguageLabel, trailing: Text(_settingsProvider.settings.value.language.toUpperCase(), style: TextStyle(color: textSecondary)), onTap: _pickLanguage, textPrimary: textPrimary, border: border),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),
            _sectionLabel('OCR', textSecondary),
            _settingsTile(
              title: 'OCR Languages',
              trailing: Icon(Icons.chevron_right, color: textSecondary),
              onTap: _openOcrLanguages,
              textPrimary: textPrimary,
              border: border,
            ),
            const SizedBox(height: AppSpacing.md),
            _sectionLabel('CAPTURE BEHAVIOR', textSecondary),
            ListenableBuilder(
              listenable: _settingsProvider.settings,
              builder: (context, _) => Column(
                children: [
                  SwitchListTile(
                    title: Text('Auto-copy OCR', style: TextStyle(color: textPrimary, fontSize: AppTypography.bodySize)),
                    subtitle: Text('Copy text to clipboard after scan', style: TextStyle(color: textSecondary, fontSize: AppTypography.footnoteSize)),
                    value: _settingsProvider.settings.value.autoCopyOcr,
                    onChanged: (value) => _settingsProvider.setAutoCopyOcr(value),
                    activeThumbColor: accent,
                    tileColor: Colors.transparent,
                  ),
                  SwitchListTile(
                    title: Text('Beep on capture', style: TextStyle(color: textPrimary, fontSize: AppTypography.bodySize)),
                    subtitle: Text('Play sound when scan completes', style: TextStyle(color: textSecondary, fontSize: AppTypography.footnoteSize)),
                    value: _settingsProvider.settings.value.beepOnCapture,
                    onChanged: (value) => _settingsProvider.setBeepOnCapture(value),
                    activeThumbColor: accent,
                    tileColor: Colors.transparent,
                  ),
                  SwitchListTile(
                    title: Text('Vibrate on capture', style: TextStyle(color: textPrimary, fontSize: AppTypography.bodySize)),
                    subtitle: Text('Haptic feedback when scan completes', style: TextStyle(color: textSecondary, fontSize: AppTypography.footnoteSize)),
                    value: _settingsProvider.settings.value.vibrateOnCapture,
                    onChanged: (value) => _settingsProvider.setVibrateOnCapture(value),
                    activeThumbColor: accent,
                    tileColor: Colors.transparent,
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),
            _sectionLabel(l10n.storageSectionLabel, textSecondary),
            _settingsTile(title: l10n.deviceMigrationLabel, trailing: Icon(Icons.chevron_right, color: textSecondary), onTap: () => context.push('/migration'), textPrimary: textPrimary, border: border),
            const SizedBox(height: AppSpacing.md),
            _sectionLabel(l10n.subscriptionSectionLabel, textSecondary),
            ListenableBuilder(
              listenable: _subscriptionProvider.adsRemoved,
              builder: (context, _) => Column(
                children: [
                  _settingsTile(title: _subscriptionProvider.adsRemoved.value ? 'Ads Removed' : 'Remove Ads', trailing: Icon(Icons.chevron_right, color: textSecondary), onTap: () => context.push('/paywall'), textPrimary: textPrimary, border: border),
                  const SizedBox(height: AppSpacing.xs),
                  _settingsTile(title: l10n.restorePurchasesButton, trailing: const SizedBox.shrink(), onTap: () => _restorePurchases(l10n), textPrimary: textPrimary, border: border),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _sectionLabel('DIAGNOSTICS', textSecondary),
            ListenableBuilder(
              listenable: DebugLogService().logs,
              builder: (context, _) => _settingsTile(title: 'Debug Logs', trailing: Text('${DebugLogService().count} entries', style: TextStyle(color: textSecondary)), onTap: () => context.push('/debug-logs'), textPrimary: textPrimary, border: border),
            ),
            const SizedBox(height: AppSpacing.md),
            _sectionLabel(l10n.aboutSectionLabel, textSecondary),
            _settingsTile(title: l10n.privacyPolicyLabel, trailing: Icon(Icons.open_in_new, color: textSecondary, size: 16), onTap: () => _openUrl(AppSupportContact.privacyPolicyUrl, l10n), textPrimary: textPrimary, border: border),
            const SizedBox(height: AppSpacing.xs),
            _settingsTile(title: l10n.supportLabel, trailing: Icon(Icons.open_in_new, color: textSecondary, size: 16), onTap: () => _openUrl(AppSupportContact.supportUrl, l10n), textPrimary: textPrimary, border: border),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(label.toUpperCase(), style: TextStyle(color: color, fontSize: AppTypography.captionSize, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
    );
  }

  Widget _settingsTile({required String title, required Widget trailing, required Color textPrimary, required Color border, VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppShape.cardRadius),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppShape.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: border, width: AppShape.cardBorderWidth))),
          child: Row(children: [Expanded(child: Text(title, style: TextStyle(color: textPrimary, fontSize: AppTypography.bodySize))), trailing]),
        ),
      ),
    );
  }
}

class _LanguagePickerSheet extends StatelessWidget {
  const _LanguagePickerSheet({required this.current});
  final String current;

  static const Map<String, String> _labels = {
    'en': 'English', 'es': 'Español', 'fr': 'Français', 'de': 'Deutsch', 'pt': 'Português',
    'ar': 'العربية', 'hi': 'हिन्दी', 'ja': '日本語', 'ko': '한국어', 'zh': '中文', 'he': 'עברית',
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.only(topLeft: Radius.circular(AppShape.bottomSheetTopRadius), topRight: Radius.circular(AppShape.bottomSheetTopRadius))),
        padding: const EdgeInsets.all(AppSpacing.md),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.appLanguageLabel, style: TextStyle(color: textPrimary, fontSize: AppTypography.title1Size, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: AppLocales.supportedLanguageCodes.map((code) => ListTile(title: Text(_labels[code] ?? code, style: TextStyle(color: textPrimary)), trailing: code == current ? Icon(Icons.check, color: accent) : null, onTap: () => Navigator.of(context).pop(code))).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _OcrLanguagesSheet extends StatefulWidget {
  const _OcrLanguagesSheet();

  @override
  State<_OcrLanguagesSheet> createState() => _OcrLanguagesSheetState();
}

class _OcrLanguagesSheetState extends State<_OcrLanguagesSheet> {
  static const Map<OcrScript, String> _labels = {
    OcrScript.latin: 'Latin (English, European)',
    OcrScript.chinese: 'Chinese',
    OcrScript.korean: 'Korean',
    OcrScript.japanese: 'Japanese',
  };

  OcrScript? _probing;

  Future<void> _probe(OcrScript script) async {
    setState(() => _probing = script);
    try {
      final dir = await getTemporaryDirectory();
      final path = p.join(dir.path, 'ocr_probe.png');
      final file = File(path);
      if (!await file.exists()) {
        await file.writeAsBytes(base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));
      }
      await OcrService().recognizeText(imagePath: path, script: script);
      OcrService.clearFailureFor(script);
    } on OcrUnavailableException {
      // Service already recorded the classified failure.
    } catch (_) {
      // Probe errors are non-fatal here.
    }
    if (mounted) setState(() => _probing = null);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.only(topLeft: Radius.circular(AppShape.bottomSheetTopRadius), topRight: Radius.circular(AppShape.bottomSheetTopRadius))),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('OCR Languages', style: TextStyle(color: textPrimary, fontSize: AppTypography.title1Size, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            ...OcrScript.values.map((script) {
              final failure = OcrService.lastFailureFor(script);
              final String status = script == OcrScript.latin
                  ? 'Built-in'
                  : _probing == script
                      ? 'Checking...'
                      : failure != null
                          ? 'Unavailable'
                          : 'On-demand';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_labels[script] ?? script.name, style: TextStyle(color: textPrimary)),
                subtitle: Text(status, style: TextStyle(color: textSecondary, fontSize: 11)),
                trailing: _probing == script
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : script == OcrScript.latin
                        ? Icon(Icons.check, color: accent)
                        : IconButton(
                            icon: Icon(failure != null ? Icons.refresh : Icons.download_for_offline_outlined, color: accent),
                            onPressed: () => _probe(script),
                          ),
              );
            }),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}
