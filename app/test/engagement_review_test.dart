import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/services/engagement_service.dart';
import 'package:katharscan/core/services/modal_moment_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final DateTime day1 = DateTime(2026, 11, 14, 9);

  group('ModalMomentGate', () {
    test('only one holder at a time; release lets the next one in', () {
      final ModalMomentGate g = ModalMomentGate.forTest();
      expect(g.tryAcquire(now: day1), isTrue);
      expect(g.tryAcquire(now: day1), isFalse);
      g.release(now: day1);
      expect(g.tryAcquire(now: day1), isTrue);
    });
    test('a hold keeps the other side out for a while', () {
      final ModalMomentGate g = ModalMomentGate.forTest();
      expect(g.tryAcquire(now: day1), isTrue);
      g.release(hold: const Duration(seconds: 20), now: day1);
      expect(g.tryAcquire(now: day1.add(const Duration(seconds: 19))), isFalse);
      expect(g.tryAcquire(now: day1.add(const Duration(seconds: 20))), isTrue);
    });
    test('a holder that never releases stops blocking after two minutes', () {
      final ModalMomentGate g = ModalMomentGate.forTest();
      expect(g.tryAcquire(now: day1), isTrue);
      expect(g.tryAcquire(now: day1.add(const Duration(minutes: 1, seconds: 59))), isFalse);
      expect(g.tryAcquire(now: day1.add(const Duration(minutes: 2))), isTrue);
    });
  });

  group('review request', () {
    late int asked;
    late bool adsRemoved;
    late bool throwOnReview;
    late ModalMomentGate gate;
    late EngagementService service;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      asked = 0;
      adsRemoved = false;
      throwOnReview = false;
      gate = ModalMomentGate.forTest();
      service = EngagementService.forTest(
        prefs,
        isAdsRemoved: () => adsRemoved,
        requestReview: () async {
          asked++;
          if (throwOnReview) throw StateError('review failed');
        },
        gate: gate,
      );
    });

    Future<void> act(int n, DateTime day) async {
      for (int i = 0; i < n; i++) {
        await service.recordSuccessfulAction(now: day);
      }
    }

    test('9 actions over 3 days: not yet', () async {
      await act(3, day1);
      await act(3, day1.add(const Duration(days: 1)));
      await act(3, day1.add(const Duration(days: 2)));
      expect(asked, 0);
    });

    test('the 10th action across 3 days asks for the review', () async {
      await act(3, day1);
      await act(3, day1.add(const Duration(days: 1)));
      await act(3, day1.add(const Duration(days: 2)));
      await service.recordSuccessfulAction(now: day1.add(const Duration(days: 2, minutes: 1)));
      expect(asked, 1);
    });

    test('10+ actions all on 1 or 2 days: not asked', () async {
      await act(8, day1);
      await act(8, day1.add(const Duration(days: 1)));
      expect(asked, 0);
    });

    test('no cooldown from us: every later action asks again (Google decides what is shown)', () async {
      await act(4, day1);
      await act(4, day1.add(const Duration(days: 1)));
      await act(2, day1.add(const Duration(days: 2))); // 10th
      expect(asked, 1);
      // Each ask releases the gate with a 20 s hold, so later actions come after it.
      await service.recordSuccessfulAction(now: day1.add(const Duration(days: 3)));
      await service.recordSuccessfulAction(now: day1.add(const Duration(days: 4)));
      expect(asked, 3);
    });

    test('paid users count and are asked too', () async {
      adsRemoved = true;
      await act(4, day1);
      await act(4, day1.add(const Duration(days: 1)));
      await act(2, day1.add(const Duration(days: 2)));
      expect(asked, 1);
    });

    test('switching review prompts off stops counting and asking', () async {
      await prefs.setBool('enableReviewPrompts', false);
      await act(4, day1);
      await act(4, day1.add(const Duration(days: 1)));
      await act(4, day1.add(const Duration(days: 2)));
      expect(asked, 0);
      expect(prefs.getInt('reviewActionCount'), isNull);
    });

    test('a full-screen ad holding the gate skips this time; the next action asks', () async {
      await act(4, day1);
      await act(4, day1.add(const Duration(days: 1)));
      await act(1, day1.add(const Duration(days: 2)));
      final DateTime t = day1.add(const Duration(days: 2, hours: 1));
      expect(gate.tryAcquire(now: t), isTrue); // an interstitial starts
      await service.recordSuccessfulAction(now: t); // the 10th action
      expect(asked, 0);
      gate.release(now: t);
      await service.recordSuccessfulAction(now: t.add(const Duration(minutes: 1)));
      expect(asked, 1);
    });

    test('a failing review call is swallowed and the gate is released', () async {
      throwOnReview = true;
      await act(4, day1);
      await act(4, day1.add(const Duration(days: 1)));
      await act(2, day1.add(const Duration(days: 2)));
      expect(asked, 1);
      // Held for 20 s after the ask, then free again.
      expect(gate.tryAcquire(now: day1.add(const Duration(days: 2, minutes: 1))), isTrue);
    });

    test('the Rate row never touches the review counters or switches the prompt off', () async {
      await act(2, day1);
      final Set<String> before = prefs.getKeys();
      final int? count = prefs.getInt('reviewActionCount');
      await service.openStoreListing(); // the plugin is absent in tests; the error is caught
      expect(prefs.getKeys(), before);
      expect(prefs.getInt('reviewActionCount'), count);
      expect(prefs.getBool('enableReviewPrompts'), isNull);
    });

    test('recordExport counts as a successful action', () async {
      await service.recordExport();
      expect(prefs.getInt('reviewActionCount'), 1);
    });
  });
}
