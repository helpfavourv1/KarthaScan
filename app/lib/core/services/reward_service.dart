import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

/// "Watch one ad, get 1 hour ad-free" bookkeeping.
///
/// Holds only state and rules, so it can be tested on a fake clock. The ad
/// itself is [RewardedAdService]; the screens are in widgets/reward_offer.dart.
///
/// - A reward lasts [rewardLength]; up to [dailyCap] can be claimed per local day.
/// - The Home card and the after-interstitial chip only appear when
///   [eligible]: no ad removal, no active reward, ads allowed, a rewarded ad
///   loaded, an interstitial has been shown before, and the daily cap not used.
///   While a reward runs (and so until it expires) neither shows.
/// - Dismissing the card with its X hides the card and the chip until
///   [dismissHideInterstitials] more interstitials have been shown.
/// - The chip shows after every [promptEveryInterstitials]th interstitial
///   (2nd, 4th, 6th ...), counted over the life of the install.
class RewardService {
  RewardService._();
  @visibleForTesting
  RewardService.forTest();
  static final RewardService instance = RewardService._();

  static const Duration rewardLength = Duration(hours: 1);
  static const int dailyCap = 21;
  static const int dismissHideInterstitials = 4;
  static const int promptEveryInterstitials = 2;

  static const String _endsKey = 'reward.ends_at';
  static const String _claimsKey = 'reward.claims_today';
  static const String _claimsDayKey = 'reward.claims_day';
  static const String _seenKey = 'reward.interstitial_seen';
  static const String _countKey = 'reward.interstitial_count';
  static const String _hiddenUntilCountKey = 'reward.hidden_until_count';
  static const String _promptedAtKey = 'reward.prompted_at_count';

  DateTime? endsAt;
  int _claims = 0;
  String? _claimsDay;
  /// Interstitials really shown, over the life of the install.
  int interstitialCount = 0;
  int _hiddenUntilCount = 0;
  int _promptedAtCount = 0;
  bool get interstitialSeen => interstitialCount > 0;

  /// True while a reward is running. Banners and interstitials listen to this.
  final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  /// Bumped on every change, so screens showing the card or the status redraw.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// Bumped each time an interstitial closes; the app listens to offer the message.
  final ValueNotifier<int> interstitialClosedTick = ValueNotifier<int>(0);

  Timer? _expiry;

  static String dayKey(DateTime t) => '${t.year}-${t.month}-${t.day}';
  static DateTime nextMidnight(DateTime t) => DateTime(t.year, t.month, t.day + 1);

  Future<void> initialize({DateTime? now}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    endsAt = DateTime.tryParse(prefs.getString(_endsKey) ?? '');
    _claims = prefs.getInt(_claimsKey) ?? 0;
    _claimsDay = prefs.getString(_claimsDayKey);
    interstitialCount = prefs.getInt(_countKey) ?? ((prefs.getBool(_seenKey) ?? false) ? 1 : 0);
    _hiddenUntilCount = prefs.getInt(_hiddenUntilCountKey) ?? 0;
    _promptedAtCount = prefs.getInt(_promptedAtKey) ?? 0;
    _refreshActive(now ?? DateTime.now());
  }

  Future<void> _save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (endsAt != null) await prefs.setString(_endsKey, endsAt!.toIso8601String());
    await prefs.setInt(_claimsKey, _claims);
    if (_claimsDay != null) await prefs.setString(_claimsDayKey, _claimsDay!);
    await prefs.setInt(_countKey, interstitialCount);
    await prefs.setBool(_seenKey, interstitialSeen);
    await prefs.setInt(_hiddenUntilCountKey, _hiddenUntilCount);
    await prefs.setInt(_promptedAtKey, _promptedAtCount);
  }

  void _notify() => changes.value++;

  void _refreshActive(DateTime now) {
    final bool on = isActive(now);
    active.value = on;
    _expiry?.cancel();
    if (on) {
      final Duration left = endsAt!.difference(now);
      _expiry = Timer(left + const Duration(seconds: 1), () {
        _refreshActive(DateTime.now());
        _notify();
      });
    }
    _notify();
  }

  /// True while a claimed reward has not run out.
  bool isActive([DateTime? now]) {
    final DateTime? e = endsAt;
    if (e == null) return false;
    return (now ?? DateTime.now()).isBefore(e);
  }

  Duration timeLeft([DateTime? now]) {
    final DateTime? e = endsAt;
    if (e == null) return Duration.zero;
    final Duration d = e.difference(now ?? DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  /// Rewards claimed on the local day of [now].
  int claimsUsed([DateTime? now]) => _claimsDay == dayKey(now ?? DateTime.now()) ? _claims : 0;

  bool capReached([DateTime? now]) => claimsUsed(now) >= dailyCap;

  /// The person watched the whole ad: start the reward.
  Future<void> grant({DateTime? now}) async {
    final DateTime t = now ?? DateTime.now();
    final String today = dayKey(t);
    if (_claimsDay != today) {
      _claimsDay = today;
      _claims = 0;
    }
    _claims++;
    endsAt = t.add(rewardLength);
    await _save();
    _refreshActive(t);
  }

  /// The X on the Home card: card and chip stay away for the next few interstitials.
  Future<void> dismissCard({DateTime? now}) async {
    _hiddenUntilCount = interstitialCount + dismissHideInterstitials;
    await _save();
    _notify();
  }

  /// An interstitial really showed: counts toward the chip schedule, and the
  /// card may appear from now on.
  Future<void> noteInterstitialShown() async {
    interstitialCount++;
    await _save();
    _notify();
  }

  /// The conditions shared by the card and the after-interstitial message.
  bool eligible({
    DateTime? now,
    required bool adsRemoved,
    required bool adsAllowed,
    required bool adLoaded,
  }) {
    final DateTime t = now ?? DateTime.now();
    return !adsRemoved && adsAllowed && adLoaded && interstitialSeen && !isActive(t) && !capReached(t);
  }

  bool _outsideHiddenWindow(DateTime t) => interstitialCount >= _hiddenUntilCount;

  bool shouldShowCard({
    DateTime? now,
    required bool adsRemoved,
    required bool adsAllowed,
    required bool adLoaded,
  }) {
    final DateTime t = now ?? DateTime.now();
    return eligible(now: t, adsRemoved: adsRemoved, adsAllowed: adsAllowed, adLoaded: adLoaded) && _outsideHiddenWindow(t);
  }

  bool shouldShowPrompt({
    DateTime? now,
    required bool adsRemoved,
    required bool adsAllowed,
    required bool adLoaded,
  }) {
    final DateTime t = now ?? DateTime.now();
    return eligible(now: t, adsRemoved: adsRemoved, adsAllowed: adsAllowed, adLoaded: adLoaded) &&
        _outsideHiddenWindow(t) &&
        interstitialCount % promptEveryInterstitials == 0 &&
        _promptedAtCount != interstitialCount;
  }

  Future<void> markPromptShown({DateTime? now}) async {
    _promptedAtCount = interstitialCount;
    await _save();
  }

  /// Called when an interstitial closes.
  void interstitialClosed() => interstitialClosedTick.value++;
}
