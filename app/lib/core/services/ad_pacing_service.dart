import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

/// Decides when a full-screen ad may appear. One rule limits how often:
/// at least [minGap] since the last ad was shown (kept across launches).
/// There is no daily, hourly or per-session cap, and no ad is ever tied to
/// opening or returning to the app: ads only follow a finished action.
class AdPacingService {
  AdPacingService._();
  @visibleForTesting
  AdPacingService.forTest();
  static final AdPacingService instance = AdPacingService._();

  /// Shortest time allowed between two full-screen ads.
  static const Duration minGap = Duration(minutes: 7);

  static const String _scansKey = 'ad_pacing.scans_this_session';
  static const String _exportsKey = 'ad_pacing.exports_this_session';
  static const String _convertsKey = 'ad_pacing.converts_this_session';
  static const String _lastAdShownKey = 'ad_pacing.last_ad_shown';
  static const String _signaturesKey = 'ad_pacing.signatures_this_session';

  int scansThisSession = 0;
  int exportsThisSession = 0;
  int convertsThisSession = 0;
  int signaturesThisSession = 0;
  DateTime? lastAdShownAt;

  /// Loads the last-ad time and starts this launch with fresh action counts.
  /// The two steps run in order, so old counts can never survive the reset.
  Future<void> start() async {
    await initialize();
    await resetSessionCounters();
  }

  Future<void> initialize() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    scansThisSession = prefs.getInt(_scansKey) ?? 0;
    exportsThisSession = prefs.getInt(_exportsKey) ?? 0;
    convertsThisSession = prefs.getInt(_convertsKey) ?? 0;
    signaturesThisSession = prefs.getInt(_signaturesKey) ?? 0;
    final String? lastAdStr = prefs.getString(_lastAdShownKey);
    lastAdShownAt = lastAdStr == null ? null : DateTime.tryParse(lastAdStr);
  }

  Future<void> recordScan() async {
    scansThisSession++;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_scansKey, scansThisSession);
  }

  Future<void> recordExport() async {
    exportsThisSession++;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_exportsKey, exportsThisSession);
  }

  Future<void> recordConvert() async {
    convertsThisSession++;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_convertsKey, convertsThisSession);
  }

  Future<void> recordSignature() async {
    signaturesThisSession++;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_signaturesKey, signaturesThisSession);
  }

  Future<void> recordAdShown({DateTime? now}) async {
    lastAdShownAt = now ?? DateTime.now();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastAdShownKey, lastAdShownAt!.toIso8601String());
  }

  Future<void> resetSessionCounters() async {
    scansThisSession = 0;
    exportsThisSession = 0;
    convertsThisSession = 0;
    signaturesThisSession = 0;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_scansKey, 0);
    await prefs.setInt(_exportsKey, 0);
    await prefs.setInt(_convertsKey, 0);
    await prefs.setInt(_signaturesKey, 0);
  }

  /// True when [minGap] has passed since the last ad (or none was shown yet).
  bool canShowAd({DateTime? now}) {
    final DateTime? last = lastAdShownAt;
    if (last == null) return true;
    final Duration since = (now ?? DateTime.now()).difference(last);
    // A clock set backwards must not block ads for ever.
    if (since.isNegative) return true;
    return since >= minGap;
  }

  bool canShowAfterScan({DateTime? now}) => canShowAd(now: now);
  bool canShowAfterExport({DateTime? now}) => exportsThisSession > 0 && exportsThisSession % 2 == 0 && canShowAd(now: now);
  bool canShowAfterConvert({DateTime? now}) => convertsThisSession > 0 && convertsThisSession % 2 == 0 && canShowAd(now: now);
  bool canShowAfterSignature({DateTime? now}) => signaturesThisSession > 0 && signaturesThisSession % 2 == 0 && canShowAd(now: now);
}
