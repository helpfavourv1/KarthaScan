import 'package:flutter/foundation.dart' show visibleForTesting;

/// One shared gate so a full-screen ad and the Google review dialog are never
/// started at the same moment. Whoever takes it first goes ahead; the other
/// simply skips this time (there are no cooldowns, the next chance comes with
/// the next finished action).
class ModalMomentGate {
  ModalMomentGate._();
  @visibleForTesting
  ModalMomentGate.forTest();
  static final ModalMomentGate instance = ModalMomentGate._();

  /// A holder that never releases (for example a dismissed-callback that never
  /// came) stops blocking after this long.
  static const Duration staleAfter = Duration(minutes: 2);

  DateTime? _heldSince;
  DateTime? _blockedUntil;

  /// True when the caller may start its full-screen moment now.
  bool tryAcquire({DateTime? now}) {
    final DateTime t = now ?? DateTime.now();
    final DateTime? since = _heldSince;
    if (since != null && t.difference(since) < staleAfter) return false;
    final DateTime? until = _blockedUntil;
    if (until != null && t.isBefore(until)) return false;
    _heldSince = t;
    return true;
  }

  /// Gives the gate back. [hold] keeps the other side out for a little longer,
  /// for a dialog that stays on screen after the call that opened it returns.
  void release({Duration hold = Duration.zero, DateTime? now}) {
    final DateTime t = now ?? DateTime.now();
    _heldSince = null;
    _blockedUntil = hold == Duration.zero ? null : t.add(hold);
  }
}
