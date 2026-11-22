import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

/// Decides when a full-screen ad may appear.
///
/// Every finished action the app counts adds one to a single tally. When the
/// tally reaches [actionsPerAd] an ad becomes *pending* and the tally stops.
/// A pending ad shows on the first counted action once [minGap] has passed
/// since the last ad. The tally goes back to zero only when an ad really
/// shows. An attempt that shows nothing (offline, no ad, SDK off) is retried
/// no sooner than [retryAfterFailure] later. The tally, the pending flag and
/// the time of the last ad are all saved, so they survive a restart.
///
/// There is no daily, hourly or per-session cap, and nothing is tied to
/// opening or returning to the app: ads only follow a finished action.
class AdPacingService {
  AdPacingService._();
  @visibleForTesting
  AdPacingService.forTest();
  static final AdPacingService instance = AdPacingService._();

  /// Counted actions before an ad becomes pending.
  static const int actionsPerAd = 7;

  /// Shortest time allowed between two full-screen ads.
  static const Duration minGap = Duration(minutes: 7);

  /// Shortest wait before trying again after an attempt showed nothing.
  static const Duration retryAfterFailure = Duration(seconds: 60);

  static const String _countKey = 'ad_pacing.action_count';
  static const String _pendingKey = 'ad_pacing.pending';
  static const String _lastAdShownKey = 'ad_pacing.last_ad_shown';
  static const String _lastFailedKey = 'ad_pacing.last_failed_attempt';

  int actionCount = 0;
  bool adPending = false;
  DateTime? lastAdShownAt;
  DateTime? lastFailedAttemptAt;

  /// Loads the saved tally, pending flag and times. Nothing is reset.
  Future<void> start() => initialize();

  Future<void> initialize() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    actionCount = prefs.getInt(_countKey) ?? 0;
    adPending = prefs.getBool(_pendingKey) ?? false;
    lastAdShownAt = DateTime.tryParse(prefs.getString(_lastAdShownKey) ?? '');
    lastFailedAttemptAt = DateTime.tryParse(prefs.getString(_lastFailedKey) ?? '');
  }

  Future<void> _save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_countKey, actionCount);
    await prefs.setBool(_pendingKey, adPending);
    if (lastAdShownAt != null) await prefs.setString(_lastAdShownKey, lastAdShownAt!.toIso8601String());
    if (lastFailedAttemptAt == null) {
      await prefs.remove(_lastFailedKey);
    } else {
      await prefs.setString(_lastFailedKey, lastFailedAttemptAt!.toIso8601String());
    }
  }

  /// Counts one finished action and says whether an ad should be tried now.
  /// While an ad is pending the tally does not move.
  Future<bool> registerAction({DateTime? now}) async {
    if (!adPending) {
      actionCount++;
      if (actionCount >= actionsPerAd) adPending = true;
      await _save();
    }
    return shouldAttemptNow(now: now);
  }

  /// True when an ad is pending, the gap has passed and the last failed
  /// attempt (if any) is old enough.
  bool shouldAttemptNow({DateTime? now}) {
    if (!adPending) return false;
    final DateTime t = now ?? DateTime.now();
    if (!canShowAd(now: t)) return false;
    final DateTime? failed = lastFailedAttemptAt;
    if (failed != null) {
      final Duration since = t.difference(failed);
      // A clock set backwards must not block ads for ever.
      if (!since.isNegative && since < retryAfterFailure) return false;
    }
    return true;
  }

  /// An ad was really shown: the tally and pending flag start over.
  Future<void> recordAdShown({DateTime? now}) async {
    lastAdShownAt = now ?? DateTime.now();
    lastFailedAttemptAt = null;
    actionCount = 0;
    adPending = false;
    await _save();
  }

  /// An attempt showed nothing. The ad stays pending and is retried later.
  Future<void> recordFailedAttempt({DateTime? now}) async {
    lastFailedAttemptAt = now ?? DateTime.now();
    await _save();
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
}
