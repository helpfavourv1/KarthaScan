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

  test('every dismissal hides the card for 2 days, never for good', () async {
    await setUpService();
    await r.noteInterstitialShown();
    var t = t0;
    for (var i = 0; i < 4; i++) {
      expect(card(t), isTrue);
      await r.dismissCard(now: t);
      expect(card(t.add(const Duration(days: 1))), isFalse);
      t = t.add(const Duration(days: 2, minutes: 1));
    }
    expect(card(t), isTrue);
  });

  test('grant gives 6 hours, freezes card, stays away until next day', () async {
    await setUpService();
    await r.noteInterstitialShown();
    await r.grant(now: t0);
    expect(r.isActive(t0.add(const Duration(hours: 5, minutes: 59))), isTrue);
    expect(r.isActive(t0.add(const Duration(hours: 6))), isFalse);
    expect(card(t0.add(const Duration(hours: 7))), isFalse);
    expect(card(DateTime(2026, 11, 23, 0, 1)), isTrue);
  });

  test('cap of 3 per local day resets at midnight', () async {
    await setUpService();
    await r.noteInterstitialShown();
    for (var i = 0; i < 3; i++) {
      await r.grant(now: t0.add(Duration(hours: i * 7)));
    }
    final late = t0.add(const Duration(hours: 22));
    expect(r.claimsUsed(late), 3);
    expect(r.capReached(late), isTrue);
    expect(r.shouldShowCard(now: DateTime(2026, 11, 22, 23, 50), adsRemoved: false, adsAllowed: true, adLoaded: true), isFalse);
    expect(r.claimsUsed(DateTime(2026, 11, 23, 0, 5)), 0);
    expect(r.capReached(DateTime(2026, 11, 23, 0, 5)), isFalse);
  });

  test('prompt shows at most once per day', () async {
    await setUpService();
    await r.noteInterstitialShown();
    bool p(DateTime t) => r.shouldShowPrompt(now: t, adsRemoved: false, adsAllowed: true, adLoaded: true);
    expect(p(t0), isTrue);
    await r.markPromptShown(now: t0);
    expect(p(t0.add(const Duration(hours: 3))), isFalse);
    expect(p(DateTime(2026, 11, 23, 9)), isTrue);
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
  });
}
