import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/subscription_provider.dart';
import '../utils/constants.dart';
import 'modal_moment_gate.dart';
import 'share_service.dart';
import 'notification_service.dart';

enum PendingPrompt { share }

class EngagementService {
  EngagementService._(this._prefs, this._isAdsRemoved, this._requestReview, this._gate);

  static EngagementService? _instance;
  static Future<EngagementService> init(SubscriptionProvider sub) async {
    if (_instance == null) {
      final prefs = await SharedPreferences.getInstance();
      _instance = EngagementService._(prefs, () => sub.adsRemoved.value, _googleReview, ModalMomentGate.instance);
    }
    return _instance!;
  }

  @visibleForTesting
  EngagementService.forTest(
    SharedPreferences prefs, {
    required bool Function() isAdsRemoved,
    required Future<void> Function() requestReview,
    required ModalMomentGate gate,
  }) : this._(prefs, isAdsRemoved, requestReview, gate);

  static EngagementService get instance => _instance!;

  final SharedPreferences _prefs;
  final bool Function() _isAdsRemoved;
  final Future<void> Function() _requestReview;
  final ModalMomentGate _gate;

  bool _hasViewedScanDetail = false;
  final ValueNotifier<PendingPrompt?> pendingPrompt = ValueNotifier<PendingPrompt?>(null);

  static const _kEngagements = 'engagementsSinceExport';
  static const _kShareShown = 'sharePromptShownCount';
  static const _kShareLast = 'sharePromptLastDate';
  static const _kActions = 'reviewActionCount';
  static const _kActionDays = 'reviewActionDays';

  /// The review is asked for from this many successful actions...
  static const int reviewMinActions = 10;

  /// ...spread over at least this many different days.
  static const int reviewMinDays = 3;

  /// Google's own review dialog stays on screen after the call returns, so ads
  /// stay out of the way for a short while.
  static const Duration reviewHold = Duration(seconds: 20);

  static Future<void> _googleReview() async {
    final InAppReview review = InAppReview.instance;
    if (await review.isAvailable()) await review.requestReview();
  }

  void markScanDetailViewed() { _hasViewedScanDetail = true; }

  Future<void> recordHomeReturn() async {
    if (!_hasViewedScanDetail) return;
    _hasViewedScanDetail = false;
    if (_isAdsRemoved()) return; // Premium suppression

    if (!(_prefs.getBool('enableSharePrompts') ?? true)) return; // Opt-in check
    final engagements = (_prefs.getInt(_kEngagements) ?? 0) + 1;
    await _prefs.setInt(_kEngagements, engagements);

    if (engagements >= 5) {
      final shown = _prefs.getInt(_kShareShown) ?? 0;
      final last = _prefs.getInt(_kShareLast) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (shown < 5 && (now - last) > (3 * 24 * 60 * 60 * 1000)) {
        pendingPrompt.value = PendingPrompt.share;
      }
    }
  }

  Future<void> recordExportForDocument(String documentId) async {
    await NotificationService.instance.cancelDocumentNotifications(documentId);
    await recordExport();
  }

  /// A finished share or save to the device.
  Future<void> recordExport() async {
    await _prefs.setInt(_kEngagements, 0);
    await recordSuccessfulAction();
  }

  /// Counts one successful action (a scan saved, a conversion saved, a file shared
  /// or saved). From the 10th action across at least 3 different days, every further
  /// action asks Google for the in-app review. The app adds no waiting period; Google
  /// decides whether the dialog is actually shown. Paid users count too.
  Future<void> recordSuccessfulAction({DateTime? now}) async {
    if (!(_prefs.getBool('enableReviewPrompts') ?? true)) return; // Opt-out check
    final DateTime t = now ?? DateTime.now();
    final int count = (_prefs.getInt(_kActions) ?? 0) + 1;
    await _prefs.setInt(_kActions, count);
    final String day = '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    final List<String> days = List<String>.of(_prefs.getStringList(_kActionDays) ?? const <String>[]);
    if (!days.contains(day)) {
      days.add(day);
      await _prefs.setStringList(_kActionDays, days);
    }
    if (count < reviewMinActions || days.length < reviewMinDays) return;
    await _askForReview(now: t);
  }

  Future<void> _askForReview({DateTime? now}) async {
    // Never in the same moment as a full-screen ad; skip now, the next action tries again.
    if (!_gate.tryAcquire(now: now)) return;
    try {
      await _requestReview();
    } catch (e) {
      debugPrint('In-app review failed: $e');
    } finally {
      _gate.release(hold: reviewHold, now: now);
    }
  }

  /// The Settings "Rate" row: opens the store listing, which always shows.
  /// It sets no flag, so the automatic review above is never switched off by it.
  Future<void> openStoreListing() async {
    try {
      await InAppReview.instance.openStoreListing();
    } catch (e) {
      debugPrint('Opening the store listing failed: $e');
    }
  }

  Future<void> recordShareDismissed() async {
    await _prefs.setInt(_kShareShown, (_prefs.getInt(_kShareShown) ?? 0) + 1);
    await _prefs.setInt(_kShareLast, DateTime.now().millisecondsSinceEpoch);
    pendingPrompt.value = null;
  }

  Future<void> recordShareCompleted() async {
    await recordShareDismissed();
    await ShareService().shareText(text: "I'm using KatharScan to scan, edit & sign documents. Get it: ${AppStoreLinks.playStoreUrl}");
  }
}
