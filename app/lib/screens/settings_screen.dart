// lib/screens/settings_screen.dart
//
// Theme, language, OCR language, storage location, restore purchases,
// privacy policy, support (Section 16 file #37).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/providers/settings_provider.dart';
import '../core/providers/subscription_provider.dart';
import '../core/providers/theme_provider.dart';
import '../core/utils/constants.dart';
import '../widgets/pro_badge.dart';

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

  Future<void> _openUrl(String url) async {
    final Uri uri = Uri.parse(url);
    bool launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link.')),
      );
    }
  }

  Future<void> _restorePurchases() async {
    await _subscriptionProvider.restore();
    if (!mounted) return;
    final String? error = _subscriptionProvider.lastError.value;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Restore complete.')),
    );
  }

  Future<void> _pickLanguage() async {
    final String? chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext context) =>
          _LanguagePickerSheet(current: _settingsProvider.settings.value.language),
    );
    if (chosen != null) {
      await _settingsProvider.setLanguage(chosen);
    }
  }

  Future<void> _pickOcrLanguage() async {
    final bool isPro = _subscriptionProvider.isPro.value;
    final String? chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext context) => _OcrLanguagePickerSheet(
        current: _settingsProvider.settings.value.ocrLanguage,
        isPro: isPro,
        onUpgradeRequired: () {
          Navigator.of(context).pop();
          context.push('/paywall');
        },
      ),
    );
    if (chosen != null) {
      await _settingsProvider.setOcrLanguage(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final Color border = isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text('Settings', style: TextStyle(color: textPrimary)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: <Widget>[
            _sectionLabel('Appearance', textSecondary),
            ListenableBuilder(
              listenable: _themeProvider.themeMode,
              builder: (BuildContext context, Widget? _) => _settingsTile(
                title: 'Theme',
                trailing: DropdownButton<ThemeMode>(
                  value: _themeProvider.themeMode.value,
                  underline: const SizedBox.shrink(),
                  onChanged: (ThemeMode? mode) {
                    if (mode != null) _themeProvider.setThemeMode(mode);
                  },
                  items: const <DropdownMenuItem<ThemeMode>>[
                    DropdownMenuItem<ThemeMode>(value: ThemeMode.system, child: Text('System')),
                    DropdownMenuItem<ThemeMode>(value: ThemeMode.light, child: Text('Light')),
                    DropdownMenuItem<ThemeMode>(value: ThemeMode.dark, child: Text('Dark')),
                  ],
                ),
                textPrimary: textPrimary,
                border: border,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _sectionLabel('Language', textSecondary),
            ListenableBuilder(
              listenable: Listenable.merge(<Listenable>[_settingsProvider.settings, _subscriptionProvider.isPro]),
              builder: (BuildContext context, Widget? _) => Column(
                children: <Widget>[
                  _settingsTile(
                    title: 'App language',
                    trailing: Text(
                      _settingsProvider.settings.value.language.toUpperCase(),
                      style: TextStyle(color: textSecondary),
                    ),
                    onTap: _pickLanguage,
                    textPrimary: textPrimary,
                    border: border,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _settingsTile(
                    title: 'OCR language',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (!_subscriptionProvider.isPro.value) const ProBadge(),
                        const SizedBox(width: AppSpacing.xs),
                        Text(_settingsProvider.settings.value.ocrLanguage, style: TextStyle(color: textSecondary)),
                      ],
                    ),
                    onTap: _pickOcrLanguage,
                    textPrimary: textPrimary,
                    border: border,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _sectionLabel('Storage', textSecondary),
            _settingsTile(
              title: 'Device Migration',
              trailing: Icon(Icons.chevron_right, color: textSecondary),
              onTap: () => context.push('/migration'),
              textPrimary: textPrimary,
              border: border,
            ),
            const SizedBox(height: AppSpacing.md),
            _sectionLabel('Subscription', textSecondary),
            ListenableBuilder(
              listenable: _subscriptionProvider.isPro,
              builder: (BuildContext context, Widget? _) => Column(
                children: <Widget>[
                  _settingsTile(
                    title: _subscriptionProvider.isPro.value ? 'KatharScan Pro' : 'Upgrade to Pro',
                    trailing: Icon(Icons.chevron_right, color: textSecondary),
                    onTap: () => context.push('/paywall'),
                    textPrimary: textPrimary,
                    border: border,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _settingsTile(
                    title: 'Restore purchases',
                    trailing: const SizedBox.shrink(),
                    onTap: _restorePurchases,
                    textPrimary: textPrimary,
                    border: border,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _sectionLabel('About', textSecondary),
            _settingsTile(
              title: 'Privacy policy',
              trailing: Icon(Icons.open_in_new, color: textSecondary, size: 16),
              onTap: () => _openUrl(AppSupportContact.privacyPolicyUrl),
              textPrimary: textPrimary,
              border: border,
            ),
            const SizedBox(height: AppSpacing.xs),
            _settingsTile(
              title: 'Support',
              trailing: Icon(Icons.open_in_new, color: textSecondary, size: 16),
              onTap: () => _openUrl(AppSupportContact.supportUrl),
              textPrimary: textPrimary,
              border: border,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: AppTypography.captionSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _settingsTile({
    required String title,
    required Widget trailing,
    required Color textPrimary,
    required Color border,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppShape.cardRadius),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppShape.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: border, width: AppShape.cardBorderWidth)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(title, style: TextStyle(color: textPrimary, fontSize: AppTypography.bodySize)),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguagePickerSheet extends StatelessWidget {
  const _LanguagePickerSheet({required this.current});

  final String current;

  static const Map<String, String> _labels = <String, String>{
    'en': 'English',
    'es': 'Español',
    'fr': 'Français',
    'de': 'Deutsch',
    'pt': 'Português',
    'ar': 'العربية',
    'hi': 'हिन्दी',
    'ja': '日本語',
    'ko': '한국어',
    'zh': '中文',
    'he': 'עברית',
  };

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppShape.bottomSheetTopRadius),
            topRight: Radius.circular(AppShape.bottomSheetTopRadius),
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'App language',
              style: TextStyle(
                color: textPrimary,
                fontSize: AppTypography.title1Size,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ...AppLocales.supportedLanguageCodes.map(
              (String code) => ListTile(
                title: Text(_labels[code] ?? code, style: TextStyle(color: textPrimary)),
                trailing: code == current ? Icon(Icons.check, color: accent) : null,
                onTap: () => Navigator.of(context).pop(code),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OcrLangOption {
  const _OcrLangOption(this.value, this.label);
  final String value;
  final String label;
}

class _OcrLanguagePickerSheet extends StatelessWidget {
  const _OcrLanguagePickerSheet({
    required this.current,
    required this.isPro,
    this.onUpgradeRequired,
  });

  final String current;
  final bool isPro;
  final VoidCallback? onUpgradeRequired;

  // Matches OcrScript exactly (core/services/ocr_service.dart) — Latin
  // free, everything else Pro. No Arabic/Hebrew: ML Kit Text Recognition
  // doesn't support those scripts at all (verified against the package's
  // docs in Phase 2) — they remain RTL interface languages only, not OCR
  // options. See ocr_service.dart's file header for the full reasoning.
  static const List<_OcrLangOption> _options = <_OcrLangOption>[
    _OcrLangOption('latin', 'Latin (default)'),
    _OcrLangOption('chinese', 'Chinese'),
    _OcrLangOption('devanagari', 'Devanagari (Hindi)'),
    _OcrLangOption('japanese', 'Japanese'),
    _OcrLangOption('korean', 'Korean'),
  ];

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppShape.bottomSheetTopRadius),
            topRight: Radius.circular(AppShape.bottomSheetTopRadius),
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'OCR language',
              style: TextStyle(
                color: textPrimary,
                fontSize: AppTypography.title1Size,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ..._options.map((_OcrLangOption opt) {
              final bool locked = !isPro && opt.value != 'latin';
              return ListTile(
                title: Text(opt.label, style: TextStyle(color: locked ? textSecondary : textPrimary)),
                trailing: locked
                    ? const ProBadge()
                    : (opt.value == current ? Icon(Icons.check, color: accent) : null),
                onTap: locked ? onUpgradeRequired : () => Navigator.of(context).pop(opt.value),
              );
            }),
          ],
        ),
      ),
    );
  }
}
