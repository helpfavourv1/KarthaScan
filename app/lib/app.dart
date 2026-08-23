// lib/app.dart
//
// MaterialApp, router, theme injection, Directionality.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/providers/settings_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/utils/constants.dart';
import 'l10n/app_localizations.dart';
import 'router.dart';

class KatharScanApp extends StatefulWidget {
  const KatharScanApp({super.key});

  @override
  State<KatharScanApp> createState() => _KatharScanAppState();
}

class _KatharScanAppState extends State<KatharScanApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = buildRouter();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeProvider themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final SettingsProvider settingsProvider = Provider.of<SettingsProvider>(context, listen: false);

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        themeProvider.themeMode,
        themeProvider.accentColor,
        settingsProvider.settings,
      ]),
      builder: (BuildContext context, Widget? _) {
        final String languageCode = settingsProvider.settings.value.language;
        final Locale locale = Locale(languageCode);
        final bool isRtl = AppLocales.isRtl(languageCode);
        final Color accentColor = themeProvider.accentColor.value;

        return MaterialApp.router(
          title: 'KatharScan',
          debugShowCheckedModeBanner: false,
          themeMode: themeProvider.themeMode.value,
          theme: _buildTheme(Brightness.light, accentColor),
          darkTheme: _buildTheme(Brightness.dark, accentColor),
          routerConfig: _router,
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (BuildContext context, Widget? child) {
            return Directionality(
              textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
      },
    );
  }

  ThemeData _buildTheme(Brightness brightness, Color accentColor) {
    final bool isDark = brightness == Brightness.dark;
    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accentColor,
        brightness: brightness,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight,
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
