import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/subscription_provider.dart';
import '../utils/constants.dart';
import 'share_service.dart';
import 'notification_service.dart';

enum PendingPrompt { share, review }

class EngagementService {
  EngagementService._(this._prefs, this._subscription);
  
  static EngagementService? _instance;
  static Future<EngagementService> init(SubscriptionProvider sub) async {
    if (_instance == null) {
      final prefs = await SharedPreferences.getInstance();
      _instance = EngagementService._(prefs, sub);
    }
    return _instance!;
  }
  static EngagementService get instance => _instance!;

  final SharedPreferences _prefs;
  final SubscriptionProvider _subscription;
  
  bool _hasViewedScanDetail = false;
  final ValueNotifier<PendingPrompt?> pendingPrompt = ValueNotifier<PendingPrompt?>(null);

  static const _kEngagements = 'engagementsSinceExport';
  static const _kExports = 'successfulExports';
  static const _kShareShown = 'sharePromptShownCount';
  static const _kShareLast = 'sharePromptLastDate';
  static const _kReviewShown = 'reviewPromptShownCount';
  static const _kReviewLast = 'reviewPromptLastDate';
  static const _kSentimentDeclinedUntil = 'sentimentDeclinedUntil';

  void markScanDetailViewed() { _hasViewedScanDetail = true; }

  Future<void> recordHomeReturn() async {
    if (!_hasViewedScanDetail) return;
    _hasViewedScanDetail = false;
    if (_subscription.adsRemoved.value) return; // Premium suppression
    
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

  Future<void> recordExport() async {
    if (_subscription.adsRemoved.value) return;
    final exports = (_prefs.getInt(_kExports) ?? 0) + 1;
    await _prefs.setInt(_kExports, exports);
    await _prefs.setInt(_kEngagements, 0);
    
    if (exports >= 4 && exports % 4 == 0) {
      final shown = _prefs.getInt(_kReviewShown) ?? 0;
      final last = _prefs.getInt(_kReviewLast) ?? 0;
      final declinedUntil = _prefs.getInt(_kSentimentDeclinedUntil) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now > declinedUntil && shown < 10 && (now - last) > (24 * 60 * 60 * 1000)) {
        pendingPrompt.value = PendingPrompt.review;
      }
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

  Future<void> recordReviewSentiment(bool enjoyed) async {
    await _prefs.setInt(_kReviewShown, (_prefs.getInt(_kReviewShown) ?? 0) + 1);
    await _prefs.setInt(_kReviewLast, DateTime.now().millisecondsSinceEpoch);
    if (enjoyed) {
      try { await InAppReview.instance.requestReview(); } catch (_) {}
    } else {
      await _prefs.setInt(_kSentimentDeclinedUntil, DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch);
      if (await canLaunchUrl(Uri.parse(AppSupportContact.supportUrl))) {
        await launchUrl(Uri.parse(AppSupportContact.supportUrl), mode: LaunchMode.externalApplication);
      }
    }
    pendingPrompt.value = null;
  }
}
