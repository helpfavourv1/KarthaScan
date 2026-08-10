// lib/platform/permission_service.dart
//
// Camera + storage permission request + rationale dialogs + permanent-
// denial handling (Section 16 file #18).
//
// WHY THIS FILE LIVES IN platform/, NOT core/services/: this is the
// concrete illustration of the confirmed layering distinction. Android's
// permission model has a real middle state — denied-but-can-ask-again,
// surfaced via shouldShowRequestRationale — that iOS's model doesn't have
// at all (iOS shows its native prompt exactly once; after that, Settings
// is the only path). That's genuine OS-branching *decision* logic living
// inside this file (see shouldShowRationale below), not just a plugin
// call with a uniform cross-platform contract — which is exactly the
// bar core/services/ files don't clear. This file uses dart:io's
// Platform.isAndroid directly, which core/ is never allowed to do.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:permission_handler/permission_handler.dart';

/// The two permission types this app ever requests (Section 8 — camera
/// for scanning, photos for gallery import). Nothing else: no location,
/// contacts, SMS, call log, biometric, or notifications.
enum AppPermission { camera, photos }

extension _AppPermissionMapping on AppPermission {
  Permission get _handlerPermission {
    switch (this) {
      case AppPermission.camera:
        return Permission.camera;
      case AppPermission.photos:
        // On Android 13+ this resolves to READ_MEDIA_IMAGES; on older
        // Android it resolves to the legacy READ_EXTERNAL_STORAGE
        // (maxSdk 32) permission — permission_handler handles that
        // version branching internally. Both are declared in
        // AndroidManifest.xml (file #59) per Section 8.
        return Permission.photos;
    }
  }
}

enum PermissionOutcome { granted, denied, permanentlyDenied, restricted }

class PermissionService {
  /// Requests [permission], returning its resulting state. If already
  /// granted (or limited, iOS's partial-photo-access state), returns
  /// immediately without prompting again. Never throws — any platform
  /// channel failure is treated as [PermissionOutcome.denied] so a
  /// caller's UI has a safe default to render.
  Future<PermissionOutcome> request(AppPermission permission) async {
    try {
      final Permission target = permission._handlerPermission;
      PermissionStatus status = await target.status;

      if (status.isGranted || status.isLimited) {
        return PermissionOutcome.granted;
      }

      status = await target.request();
      return _toOutcome(status);
    } catch (error, stackTrace) {
      _logError('request', error, stackTrace);
      return PermissionOutcome.denied;
    }
  }

  Future<bool> isGranted(AppPermission permission) async {
    try {
      final PermissionStatus status = await permission._handlerPermission.status;
      return status.isGranted || status.isLimited;
    } catch (error, stackTrace) {
      _logError('isGranted', error, stackTrace);
      return false;
    }
  }

  /// Android-only concept: true when the OS recommends showing an in-app
  /// rationale before the *next* request, because the user denied once
  /// but hasn't hit "don't ask again" / permanent denial yet. Always
  /// false on iOS — there's no equivalent state to check, since iOS's
  /// native prompt never appears a second time regardless of what this
  /// app does. Callers should show settings_screen.dart-style rationale
  /// copy from AppPermissionRationale (constants.dart) when this is true,
  /// and route straight to [openSettings] when the outcome is
  /// [PermissionOutcome.permanentlyDenied].
  Future<bool> shouldShowRationale(AppPermission permission) async {
    if (!Platform.isAndroid) return false;
    try {
      return await permission._handlerPermission.shouldShowRequestRationale;
    } catch (error, stackTrace) {
      _logError('shouldShowRationale', error, stackTrace);
      return false;
    }
  }

  /// Opens this app's OS settings page — the only path back to a
  /// permission once permanently denied, on either platform.
  Future<bool> openSettings() async {
    try {
      return await openAppSettings();
    } catch (error, stackTrace) {
      _logError('openSettings', error, stackTrace);
      return false;
    }
  }

  PermissionOutcome _toOutcome(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return PermissionOutcome.granted;
    }
    if (status.isPermanentlyDenied) {
      return PermissionOutcome.permanentlyDenied;
    }
    if (status.isRestricted) {
      return PermissionOutcome.restricted;
    }
    return PermissionOutcome.denied;
  }

  void _logError(String operation, Object error, StackTrace stackTrace) {
    debugPrint('[PermissionService] $operation failed: $error');
  }
}
