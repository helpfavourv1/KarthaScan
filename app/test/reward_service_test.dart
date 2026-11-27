import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:katharscan/core/services/reward_service.dart';

void main() {
  late RewardService r;
  final DateTime t0 = DateTime(2026, 11, 22, 10, 0);

  Future<void> setUpService() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    r = RewardService.forTest();
    await r.initialize(now: t0);
  }

  bool card(DateTime t) => r.shouldShowCard(now: t, adsRemoved: false, adsAllowed: true, adLoaded: true);

  test('card needs a shown interstitial first', () async {
    await setUpService();
    expect(card(t0), isFalse);
    await r.noteInterstitialShown();
    expect(card(t0), isTrue);
  });

  test('card hidden when ads removed, not allowed, or no ad loaded', () async {
    await setUpService();
    await r.noteInterstitialShown();
    expect(r.shouldShowCard(now: t0, adsRemoved: true, adsAllowed: true, adLoaded: true), isFalse);
    expect(r.shouldShowCard(now: t0, adsRemoved: false, adsAllowed: false, adLoaded: true), isFalse);
    expect(r.shouldShowCard(now: t0, adsRemoved: false, adsAllowed: true, adLoaded: false), isFalse);
  });

  test('X hides card and chip until 4 more interstitials have shown', () async {
    await setUpService();
    await r.noteInterstitialShown();
    expect(card(t0), isTrue);
    await r.dismissCard(now: t0);
    expect(card(t0), isFalse);
    for (var i = 0; i < 3; i++) {
      await r.noteInterstitialShown();
      expect(card(t0), isFalse, reason: 'after ${i + 1} more');
    }
    await r.noteInterstitialShown();
    expect(card(t0), isTrue);
  });

  test('grant gives 1 hour; card is away until the reward ends, then back', () async {
    await setUpService();
    await r.noteInterstitialShown();
    await r.grant(now: t0);
    expect(r.isActive(t0.add(const Duration(minutes: 59))), isTrue);
    expect(r.isActive(t0.add(const Duration(hours: 1))), isFalse);
    expect(card(t0.add(const Duration(minutes: 30))), isFalse);
    expect(card(t0.add(const Duration(hours: 1, minutes: 1))), isTrue);
  });

  test('cap of 21 per local day resets at midnight', () async {
    await setUpService();
    await r.noteInterstitialShown();
    for (var i = 0; i < 21; i++) {
      await r.grant(now: t0.add(Duration(minutes: i * 2)));
    }
    final late = t0.add(const Duration(hours: 12));
    expect(r.claimsUsed(late), 21);
    expect(r.capReached(late), isTrue);
    expect(card(late), isFalse);
    expect(r.claimsUsed(DateTime(2026, 11, 23, 0, 5)), 0);
    expect(r.capReached(DateTime(2026, 11, 23, 0, 5)), isFalse);
  });

  test('chip shows after the 2nd, 4th, 6th interstitial, once each', () async {
    await setUpService();
    bool p() => r.shouldShowPrompt(now: t0, adsRemoved: false, adsAllowed: true, adLoaded: true);
    await r.noteInterstitialShown();
    expect(p(), isFalse, reason: '1st');
    await r.noteInterstitialShown();
    expect(p(), isTrue, reason: '2nd');
    await r.markPromptShown();
    expect(p(), isFalse, reason: 'already shown for the 2nd');
    await r.noteInterstitialShown();
    expect(p(), isFalse, reason: '3rd');
    await r.noteInterstitialShown();
    expect(p(), isTrue, reason: '4th');
  });

  test('chip follows the same rules as the card (X, reward, cap)', () async {
    await setUpService();
    await r.noteInterstitialShown();
    await r.noteInterstitialShown();
    bool p(DateTime t) => r.shouldShowPrompt(now: t, adsRemoved: false, adsAllowed: true, adLoaded: true);
    await r.dismissCard(now: t0);
    expect(p(t0), isFalse);
    await r.grant(now: t0);
    expect(p(t0), isFalse);
  });

  test('state survives a restart', () async {
    await setUpService();
    await r.noteInterstitialShown();
    await r.grant(now: t0);
    final r2 = RewardService.forTest();
    await r2.initialize(now: t0.add(const Duration(hours: 1)));
    expect(r2.isActive(t0.add(const Duration(hours: 1))), isTrue);
    expect(r2.claimsUsed(t0), 1);
    expect(r2.interstitialSeen, isTrue);
    expect(r2.interstitialCount, 1);
  });
}
