import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/services/ad_pacing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final DateTime t0 = DateTime(2026, 11, 14, 12);

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('spacing window', () {
    test('no earlier ad: allowed straight away', () {
      expect(AdPacingService.forTest().canShowAd(now: t0), isTrue);
    });
    test('blocked until 7 minutes have passed, allowed from 7:00', () async {
      final AdPacingService s = AdPacingService.forTest();
      await s.recordAdShown(now: t0);
      expect(s.canShowAd(now: t0), isFalse);
      expect(s.canShowAd(now: t0.add(const Duration(minutes: 6, seconds: 59))), isFalse);
      expect(s.canShowAd(now: t0.add(const Duration(minutes: 7))), isTrue);
    });
    test('a clock set backwards does not block ads', () async {
      final AdPacingService s = AdPacingService.forTest();
      await s.recordAdShown(now: t0);
      expect(s.canShowAd(now: t0.subtract(const Duration(hours: 2))), isTrue);
    });
    test('the last-ad time survives a new launch', () async {
      await AdPacingService.forTest().recordAdShown(now: t0);
      final AdPacingService next = AdPacingService.forTest();
      await next.initialize();
      expect(next.canShowAd(now: t0.add(const Duration(minutes: 3))), isFalse);
      expect(next.canShowAd(now: t0.add(const Duration(minutes: 8))), isTrue);
    });
    test('no daily, hourly or session cap: 60 ads 7 minutes apart are all allowed', () async {
      final AdPacingService s = AdPacingService.forTest();
      DateTime t = t0;
      for (int i = 0; i < 60; i++) {
        expect(s.canShowAd(now: t), isTrue, reason: 'ad $i');
        await s.recordAdShown(now: t);
        t = t.add(const Duration(minutes: 7));
      }
    });
  });

  group('startup', () {
    test('start() clears old action counts and keeps the last-ad time', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ad_pacing.scans_this_session': 2,
        'ad_pacing.exports_this_session': 3,
        'ad_pacing.converts_this_session': 4,
        'ad_pacing.signatures_this_session': 5,
        'ad_pacing.last_ad_shown': t0.toIso8601String(),
      });
      final AdPacingService s = AdPacingService.forTest();
      await s.start();
      expect(<int>[s.scansThisSession, s.exportsThisSession, s.convertsThisSession, s.signaturesThisSession], <int>[0, 0, 0, 0]);
      expect(s.canShowAd(now: t0.add(const Duration(minutes: 1))), isFalse);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('ad_pacing.exports_this_session'), 0);
    });
  });

  group('triggers', () {
    const Duration later = Duration(minutes: 10);
    test('every finished scan is eligible', () {
      expect(AdPacingService.forTest().canShowAfterScan(now: t0), isTrue);
    });
    test('export, convert and signature need every 2nd one', () async {
      final AdPacingService s = AdPacingService.forTest();
      expect(s.canShowAfterExport(now: t0), isFalse);
      await s.recordExport();
      expect(s.canShowAfterExport(now: t0), isFalse);
      await s.recordExport();
      expect(s.canShowAfterExport(now: t0), isTrue);
      await s.recordExport();
      expect(s.canShowAfterExport(now: t0), isFalse);

      expect(s.canShowAfterConvert(now: t0), isFalse);
      await s.recordConvert();
      await s.recordConvert();
      expect(s.canShowAfterConvert(now: t0), isTrue);

      expect(s.canShowAfterSignature(now: t0), isFalse);
      await s.recordSignature();
      await s.recordSignature();
      expect(s.canShowAfterSignature(now: t0), isTrue);
    });
    test('the 7-minute gap blocks every trigger, and lifts for all of them', () async {
      final AdPacingService s = AdPacingService.forTest();
      await s.recordScan();
      await s.recordExport();
      await s.recordExport();
      await s.recordConvert();
      await s.recordConvert();
      await s.recordSignature();
      await s.recordSignature();
      await s.recordAdShown(now: t0);
      expect(s.canShowAfterScan(now: t0), isFalse);
      expect(s.canShowAfterExport(now: t0), isFalse);
      expect(s.canShowAfterConvert(now: t0), isFalse);
      expect(s.canShowAfterSignature(now: t0), isFalse);
      expect(s.canShowAfterScan(now: t0.add(later)), isTrue);
      expect(s.canShowAfterExport(now: t0.add(later)), isTrue);
      expect(s.canShowAfterConvert(now: t0.add(later)), isTrue);
      expect(s.canShowAfterSignature(now: t0.add(later)), isTrue);
    });
  });
}
