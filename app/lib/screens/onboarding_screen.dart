import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/constants.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentIndex = 0;

  final List<_OnboardingPageData> _pages = const [
    _OnboardingPageData(
      title: 'Instant Edge Detection',
      subtitle:
          'Automatically capture crisp document boundaries with real-time perspective correction.',
      icon: PhosphorIconsRegular.scan,
    ),
    _OnboardingPageData(
      title: 'On-Device OCR',
      subtitle:
          'Extract text locally across multiple languages with complete privacy.',
      icon: PhosphorIconsRegular.textT,
    ),
    _OnboardingPageData(
      title: 'Enterprise-Grade PDFs',
      subtitle:
          'Export clean, watermark-free documents instantly in multiple professional formats.',
      icon: PhosphorIconsRegular.fileText,
    ),
  ];

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
  }

  Future<void> _nextPage() async {
    if (_currentIndex < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      // Mark onboarding as complete
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasSeenOnboarding', true);
      
      if (!mounted) return;
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: _onPageChanged,
                itemCount: _pages.length,
                itemBuilder: (BuildContext context, int index) {
                  return _OnboardingPage(
                    data: _pages[index],
                    isActive: index == _currentIndex,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Row(
                    children: List.generate(
                      _pages.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.only(right: 6),
                        height: 8,
                        width: _currentIndex == index ? 24 : 8,
                        decoration: BoxDecoration(
                          color: _currentIndex == index
                              ? accent
                              : textSecondary.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _nextPage,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _currentIndex == _pages.length - 1
                            ? 'Get Started'
                            : 'Continue',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
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

class _OnboardingPageData {
  final String title;
  final String subtitle;
  final IconData icon;

  const _OnboardingPageData({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

class _OnboardingPage extends StatelessWidget {
  final _OnboardingPageData data;
  final bool isActive;

  const _OnboardingPage({
    required this.data,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return AnimatedScale(
      scale: isActive ? 1.0 : 0.96,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                data.icon,
                size: 52,
                color: accent,
              ),
            ),
            const SizedBox(height: 40),
            Text(
              data.title,
              style: TextStyle(
                color: textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            Text(
              data.subtitle,
              style: TextStyle(
                color: textSecondary,
                fontSize: 17,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
