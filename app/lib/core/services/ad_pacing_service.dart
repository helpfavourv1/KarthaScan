import 'package:shared_preferences/shared_preferences.dart';

class AdPacingService {
  AdPacingService._();
  static final AdPacingService instance = AdPacingService._();

  static const String _scansKey = 'ad_pacing.scans_this_session';
  static const String _exportsKey = 'ad_pacing.exports_this_session';
  static const String _convertsKey = 'ad_pacing.converts_this_session';
  static const String _adsTodayKey = 'ad_pacing.ads_today';
  static const String _adsDateKey = 'ad_pacing.ads_date';
  static const String _lastAdShownKey = 'ad_pacing.last_ad_shown';
  static const String _lastForegroundKey = 'ad_pacing.last_foreground';

  int scansThisSession = 0;
  int exportsThisSession = 0;
  int convertsThisSession = 0;
  int adsToday = 0;
  DateTime? lastAdShownAt;
  DateTime? lastForegroundAt;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    scansThisSession = prefs.getInt(_scansKey) ?? 0;
    exportsThisSession = prefs.getInt(_exportsKey) ?? 0;
    convertsThisSession = prefs.getInt(_convertsKey) ?? 0;
    adsToday = prefs.getInt(_adsTodayKey) ?? 0;
    final dateStr = prefs.getString(_adsDateKey);
    if (dateStr != null) {
      final savedDate = DateTime.parse(dateStr);
      final now = DateTime.now();
      if (savedDate.year != now.year || savedDate.month != now.month || savedDate.day != now.day) {
        adsToday = 0;
        await prefs.setInt(_adsTodayKey, 0);
        await prefs.setString(_adsDateKey, now.toIso8601String());
      }
    }
    final lastAdStr = prefs.getString(_lastAdShownKey);
    if (lastAdStr != null) lastAdShownAt = DateTime.parse(lastAdStr);
    final lastFgStr = prefs.getString(_lastForegroundKey);
    if (lastFgStr != null) lastForegroundAt = DateTime.parse(lastFgStr);
  }

  Future<void> recordScan() async {
    scansThisSession++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_scansKey, scansThisSession);
  }

  Future<void> recordExport() async {
    exportsThisSession++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_exportsKey, exportsThisSession);
  }

  Future<void> recordConvert() async {
    convertsThisSession++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_convertsKey, convertsThisSession);
  }

  Future<void> recordAdShown() async {
    adsToday++;
    lastAdShownAt = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_adsTodayKey, adsToday);
    await prefs.setString(_adsDateKey, lastAdShownAt!.toIso8601String());
    await prefs.setString(_lastAdShownKey, lastAdShownAt!.toIso8601String());
  }

  Future<void> recordForeground() async {
    lastForegroundAt = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastForegroundKey, lastForegroundAt!.toIso8601String());
  }

  Future<void> resetSessionCounters() async {
    scansThisSession = 0;
    exportsThisSession = 0;
    convertsThisSession = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_scansKey, 0);
    await prefs.setInt(_exportsKey, 0);
    await prefs.setInt(_convertsKey, 0);
  }

  bool canShowAd() {
    if (lastAdShownAt != null) {
      if (DateTime.now().difference(lastAdShownAt!).inSeconds < 60) return false;
    }
    if (adsToday >= 20) return false;
    return true;
  }

  bool canShowAfterScan() => scansThisSession > 0 && scansThisSession % 4 == 0 && canShowAd();
  bool canShowAfterExport() => exportsThisSession > 0 && exportsThisSession % 2 == 0 && canShowAd();
  bool canShowAfterConvert() => convertsThisSession > 0 && convertsThisSession % 2 == 0 && canShowAd();
  bool canShowAfterIdle() {
    if (lastForegroundAt == null) return false;
    return DateTime.now().difference(lastForegroundAt!).inMinutes >= 5 && canShowAd();
  }
}
