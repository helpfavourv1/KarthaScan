import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentIndex = 0;

  static const List<String> _assets = [
    'assets/onboarding/welcome.svg',
    'assets/onboarding/tools.svg',
    'assets/onboarding/ocr.svg',
    'assets/onboarding/sign.svg',
    'assets/onboarding/edit.svg',
    'assets/onboarding/privacy.svg',
  ];

  void _onPageChanged(int index) => setState(() => _currentIndex = index);

  void _goTo(int index) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _controller.jumpToPage(index);
    } else {
      _controller.animateToPage(index, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Future<void> _next() async {
    if (_currentIndex < _assets.length - 1) {
      _goTo(_currentIndex + 1);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasSeenOnboarding', true);
      if (!mounted) return;
      context.go('/');
    }
  }

  void _back() {
    if (_currentIndex > 0) _goTo(_currentIndex - 1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    final titles = [
      l10n.onboardingWelcomeTitle, l10n.onboardingToolsTitle, l10n.onboardingOcrTitle,
      l10n.onboardingSignTitle, l10n.onboardingEditTitle, l10n.onboardingPrivacyTitle,
    ];
    final subs = [
      l10n.onboardingWelcomeSubtitle, l10n.onboardingToolsSubtitle, l10n.onboardingOcrSubtitle,
      l10n.onboardingSignSubtitle, l10n.onboardingEditSubtitle, l10n.onboardingPrivacySubtitle,
    ];

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: _onPageChanged,
                itemCount: _assets.length,
                itemBuilder: (context, index) => Semantics(
                  label: '${titles[index]}. ${subs[index]}',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.asset(_assets[index], height: 240, width: 240),
                        const SizedBox(height: 40),
                        Text(titles[index], style: TextStyle(color: textPrimary, fontSize: 26, fontWeight: FontWeight.w700, height: 1.2), textAlign: TextAlign.center),
                        const SizedBox(height: 14),
                        Text(subs[index], style: TextStyle(color: textSecondary, fontSize: 17, height: 1.5), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_assets.length, (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 8, width: _currentIndex == i ? 24 : 8,
                decoration: BoxDecoration(color: _currentIndex == i ? accent : textSecondary.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(4)),
              )),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _currentIndex > 0 ? _back : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _currentIndex > 0 ? accent : textSecondary.withValues(alpha: 0.3), width: 1),
                      ),
                      child: Text(l10n.onboardingBack, style: TextStyle(color: _currentIndex > 0 ? accent : textSecondary.withValues(alpha: 0.3), fontWeight: FontWeight.w600, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: _next,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(14)),
                        child: Text(
                          _currentIndex == _assets.length - 1 ? l10n.onboardingGetStarted : l10n.onboardingContinue,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
