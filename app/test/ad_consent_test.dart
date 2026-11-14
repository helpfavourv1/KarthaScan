import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/services/ad_consent_service.dart';

class FakeGateway implements ConsentGateway {
  bool updateFails = false;
  bool? can = true; // null makes canRequestAds() throw
  bool optionsRequired = false;
  bool optionsThrow = false;
  bool initThrows = false;
  int formRuns = 0;
  int refreshOnlyRuns = 0;
  int initRuns = 0;
  int privacyFormRuns = 0;
  void Function()? onPrivacyForm;

  @override
  Future<bool> refreshAndShowFormIfRequired() async {
    formRuns++;
    return updateFails;
  }

  @override
  Future<bool> refreshOnly() async {
    refreshOnlyRuns++;
    return updateFails;
  }

  @override
  Future<bool> canRequestAds() async {
    if (can == null) throw StateError('sdk error');
    return can!;
  }

  @override
  Future<bool> privacyOptionsRequired() async {
    if (optionsThrow) throw StateError('status error');
    return optionsRequired;
  }

  @override
  Future<void> showPrivacyOptionsForm() async {
    privacyFormRuns++;
    onPrivacyForm?.call();
  }

  @override
  Future<void> initializeAds() async {
    if (initThrows) throw StateError('init error');
    initRuns++;
  }
}

void main() {
  group('consentOutcome (Google decides)', () {
    test('person outside the EEA/UK/CH: not required, SDK says yes', () {
      expect(consentOutcome(canRequestAds: true, infoUpdateFailed: false), ConsentOutcome.ready);
    });
    test('consent granted: ready', () {
      expect(consentOutcome(canRequestAds: true, infoUpdateFailed: false), ConsentOutcome.ready);
    });
    test('consent declined and the SDK says no: blocked', () {
      expect(consentOutcome(canRequestAds: false, infoUpdateFailed: false), ConsentOutcome.blocked);
    });
    test('refresh failed but the SDK still says yes from stored state: ready', () {
      expect(consentOutcome(canRequestAds: true, infoUpdateFailed: true), ConsentOutcome.ready);
    });
    test('refresh failed and the SDK says no: unknown, not blocked (ask again later)', () {
      expect(consentOutcome(canRequestAds: false, infoUpdateFailed: true), ConsentOutcome.unknown);
    });
    test('offline / the SDK call threw: unknown', () {
      expect(consentOutcome(canRequestAds: null, infoUpdateFailed: true), ConsentOutcome.unknown);
      expect(consentOutcome(canRequestAds: null, infoUpdateFailed: false), ConsentOutcome.unknown);
    });
  });

  group('AdConsentService', () {
    test('starts pending; ready opens the gate and starts the ads SDK once', () async {
      final FakeGateway g = FakeGateway();
      final AdConsentService s = AdConsentService.forTest(g);
      expect(s.outcome.value, ConsentOutcome.pending);
      await s.start();
      expect(s.outcome.value, ConsentOutcome.ready);
      expect(s.adsReady.value, isTrue);
      expect(g.initRuns, 1);
      expect(g.formRuns, 1);
    });

    test('declined: gate stays closed and the outcome is blocked', () async {
      final FakeGateway g = FakeGateway()..can = false;
      final AdConsentService s = AdConsentService.forTest(g);
      await s.start();
      expect(s.adsReady.value, isFalse);
      expect(s.outcome.value, ConsentOutcome.blocked);
      expect(g.initRuns, 0);
    });

    test('a failed first check is retried on the next foreground and then opens', () async {
      final FakeGateway g = FakeGateway()
        ..updateFails = true
        ..can = false;
      final AdConsentService s = AdConsentService.forTest(g);
      await s.start();
      expect(s.outcome.value, ConsentOutcome.unknown);
      expect(s.adsReady.value, isFalse);

      g
        ..updateFails = false
        ..can = true;
      await s.recheck();
      expect(s.outcome.value, ConsentOutcome.ready);
      expect(s.adsReady.value, isTrue);
      expect(g.formRuns, 2, reason: 'unknown asks again with the form');
    });

    test('withdrawn consent closes the gate again; granting again reopens it without a second SDK start', () async {
      final FakeGateway g = FakeGateway();
      final AdConsentService s = AdConsentService.forTest(g);
      await s.start();
      expect(s.adsReady.value, isTrue);

      g.can = false;
      await s.recheck();
      expect(s.adsReady.value, isFalse);
      expect(s.outcome.value, ConsentOutcome.blocked);
      expect(g.refreshOnlyRuns, 1, reason: 'a ready/blocked app only re-reads, no form');

      g.can = true;
      await s.recheck();
      expect(s.adsReady.value, isTrue);
      expect(g.initRuns, 1);
    });

    test('recheck before start does nothing (the tracking prompt may not be answered yet)', () async {
      final FakeGateway g = FakeGateway();
      final AdConsentService s = AdConsentService.forTest(g);
      await s.recheck();
      expect(g.formRuns + g.refreshOnlyRuns, 0);
      expect(s.outcome.value, ConsentOutcome.pending);
    });

    test('start runs once even when called twice', () async {
      final FakeGateway g = FakeGateway();
      final AdConsentService s = AdConsentService.forTest(g);
      await s.start();
      await s.start();
      expect(g.formRuns, 1);
    });

    test('the SDK throwing leaves the outcome unknown, never ready', () async {
      final FakeGateway g = FakeGateway()..can = null;
      final AdConsentService s = AdConsentService.forTest(g);
      await s.start();
      expect(s.outcome.value, ConsentOutcome.unknown);
      expect(s.adsReady.value, isFalse);
    });

    test('ads SDK failing to start keeps the gate closed and retries later', () async {
      final FakeGateway g = FakeGateway()..initThrows = true;
      final AdConsentService s = AdConsentService.forTest(g);
      await s.start();
      expect(s.adsReady.value, isFalse);
      expect(s.outcome.value, ConsentOutcome.unknown);
      g.initThrows = false;
      await s.recheck();
      expect(s.adsReady.value, isTrue);
    });

    test('privacy options: the form result takes effect at once', () async {
      final FakeGateway g = FakeGateway()
        ..can = false
        ..optionsRequired = true;
      final AdConsentService s = AdConsentService.forTest(g);
      await s.start();
      expect(s.privacyOptionsRequired.value, isTrue);
      expect(s.adsReady.value, isFalse);
      g.onPrivacyForm = () => g.can = true;
      await s.showPrivacyOptions();
      expect(g.privacyFormRuns, 1);
      expect(s.adsReady.value, isTrue);
    });

    test('a failing privacy-options status call does not break the check', () async {
      final FakeGateway g = FakeGateway()..optionsThrow = true;
      final AdConsentService s = AdConsentService.forTest(g);
      await s.start();
      expect(s.outcome.value, ConsentOutcome.ready);
      expect(s.privacyOptionsRequired.value, isFalse);
    });
  });
}
