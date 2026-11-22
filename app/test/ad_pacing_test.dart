import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/services/ad_pacing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final DateTime t0 = DateTime(2026, 11, 14, 12);
  DateTime at(int minutes, [int seconds = 0]) => t0.add(Duration(minutes: minutes, seconds: seconds));

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  /// Counts [n] actions at [when]; returns what the last one said.
  Future<bool> act(AdPacingService s, int n, DateTime when) async {
    bool last = false;
    for (int i = 0; i < n; i++) {
      last = await s.registerAction(now: when);
    }
    return last;
  }

  group('settings', () {
    test('7 actions, 7 minutes, 60 second retry', () {
      expect(AdPacingService.actionsPerAd, 7);
      expect(AdPacingService.minGap, const Duration(minutes: 7));
      expect(AdPacingService.retryAfterFailure, const Duration(seconds: 60));
    });
  });

  group('counting', () {
    test('actions 1 to 6 never ask for an ad', () async {
      final AdPacingService s = AdPacingService.forTest();
      for (int i = 1; i <= 6; i++) {
        expect(await s.registerAction(now: t0), isFalse, reason: 'action $i');
      }
      expect(s.actionCount, 6);
      expect(s.adPending, isFalse);
    });

    test('the 7th action makes an ad pending and asks for it when the gap is fine', () async {
      final AdPacingService s = AdPacingService.forTest();
      expect(await act(s, 7, t0), isTrue);
      expect(s.adPending, isTrue);
    });

    test('every kind of action counts the same: one tally, not one per type', () async {
      final AdPacingService s = AdPacingService.forTest();
      await act(s, 3, t0);
      await act(s, 3, t0);
      expect(s.actionCount, 6);
    });

    test('no "every 2nd" rule: 2 actions never ask for an ad', () async {
      final AdPacingService s = AdPacingService.forTest();
      expect(await act(s, 2, t0), isFalse);
    });
  });

  group('pending ad', () {
    test('inside the 7 minutes the ad stays pending and the tally stops', () async {
      final AdPacingService s = AdPacingService.forTest();
      await s.recordAdShown(now: t0);
      expect(await act(s, 7, at(1)), isFalse);
      expect(s.adPending, isTrue);
      expect(s.actionCount, 7);
      // More actions do not move the tally while pending.
      await act(s, 5, at(2));
      expect(s.actionCount, 7);
    });

    test('fires on the first counting action once 7 minutes have passed', () async {
      final AdPacingService s = AdPacingService.forTest();
      await s.recordAdShown(now: t0);
      await act(s, 7, at(1));
      expect(await s.registerAction(now: at(6, 59)), isFalse);
      expect(await s.registerAction(now: at(7)), isTrue);
    });

    test('the tally resets only when an ad really shows', () async {
      final AdPacingService s = AdPacingService.forTest();
      await act(s, 7, t0);
      expect(s.actionCount, 7);
      await s.recordAdShown(now: at(1));
      expect(s.actionCount, 0);
      expect(s.adPending, isFalse);
      expect(await s.registerAction(now: at(2)), isFalse);
      expect(s.actionCount, 1);
    });

    test('the 7 minutes run from the last ad shown', () async {
      final AdPacingService s = AdPacingService.forTest();
      await act(s, 7, t0);
      await s.recordAdShown(now: t0);
      await act(s, 7, at(3));
      expect(s.shouldAttemptNow(now: at(6, 59)), isFalse);
      expect(s.shouldAttemptNow(now: at(7)), isTrue);
    });

    test('a clock set backwards does not block ads for ever', () async {
      final AdPacingService s = AdPacingService.forTest();
      await s.recordAdShown(now: t0);
      await act(s, 7, t0);
      expect(s.shouldAttemptNow(now: t0.subtract(const Duration(hours: 2))), isTrue);
    });

    test('no daily cap: 30 ads 7 minutes apart all show', () async {
      final AdPacingService s = AdPacingService.forTest();
      DateTime t = t0;
      for (int i = 0; i < 30; i++) {
        expect(await act(s, 7, t), isTrue, reason: 'ad $i');
        await s.recordAdShown(now: t);
        t = t.add(const Duration(minutes: 7));
      }
    });
  });

  group('failed attempts', () {
    test('retry no sooner than 60 seconds later', () async {
      final AdPacingService s = AdPacingService.forTest();
      await act(s, 7, t0);
      await s.recordFailedAttempt(now: t0);
      expect(await s.registerAction(now: t0.add(const Duration(seconds: 59))), isFalse);
      expect(await s.registerAction(now: t0.add(const Duration(seconds: 60))), isTrue);
    });

    test('a failed attempt keeps the ad pending and the tally where it was', () async {
      final AdPacingService s = AdPacingService.forTest();
      await act(s, 7, t0);
      await s.recordFailedAttempt(now: t0);
      expect(s.adPending, isTrue);
      expect(s.actionCount, 7);
    });

    test('a shown ad clears the failed-attempt wait', () async {
      final AdPacingService s = AdPacingService.forTest();
      await act(s, 7, t0);
      await s.recordFailedAttempt(now: t0);
      await s.recordAdShown(now: at(1));
      expect(s.lastFailedAttemptAt, isNull);
    });
  });

  group('saved across restarts', () {
    test('tally survives a new launch and start() does not reset it', () async {
      final AdPacingService a = AdPacingService.forTest();
      await act(a, 5, t0);
      final AdPacingService b = AdPacingService.forTest();
      await b.start();
      expect(b.actionCount, 5);
      expect(await act(b, 2, t0), isTrue);
    });

    test('pending flag, last ad and failed attempt all survive', () async {
      final AdPacingService a = AdPacingService.forTest();
      await a.recordAdShown(now: t0);
      await act(a, 7, at(1));
      await a.recordFailedAttempt(now: at(2));
      final AdPacingService b = AdPacingService.forTest();
      await b.initialize();
      expect(b.adPending, isTrue);
      expect(b.actionCount, 7);
      expect(b.shouldAttemptNow(now: at(2, 30)), isFalse);
      expect(b.shouldAttemptNow(now: at(7)), isTrue);
    });
  });
}
