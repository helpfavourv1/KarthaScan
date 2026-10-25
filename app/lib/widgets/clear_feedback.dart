import 'package:flutter/material.dart';

import '../core/providers/scan_provider.dart';
import '../l10n/app_localizations.dart';

/// Shows "Cleared N" with an Undo button after a clear.
///
/// [onUndo] puts back exactly what was cleared. When [staleOn] is given the
/// message goes away as soon as it changes (another edit was made), so Undo can
/// never undo something other than the clear it belongs to.
void showClearedMessage(
  BuildContext context,
  int count,
  Future<void> Function() onUndo, {
  ValueNotifier<int>? staleOn,
}) {
  _show(ScaffoldMessenger.of(context), AppLocalizations.of(context), count, onUndo, staleOn);
}

void _show(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  int count,
  Future<void> Function() onUndo,
  ValueNotifier<int>? staleOn,
) {
  if (count <= 0) return;
  final int version = staleOn?.value ?? 0;
  messenger.hideCurrentSnackBar();
  final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> shown = messenger.showSnackBar(SnackBar(
    content: Text(l10n.clearedCount(count)),
    duration: const Duration(seconds: 6),
    action: SnackBarAction(label: l10n.undoTooltip, onPressed: () => onUndo()),
  ));
  if (staleOn != null) {
    void listener() {
      if (staleOn.value != version) messenger.hideCurrentSnackBar();
    }

    staleOn.addListener(listener);
    shown.closed.then((_) => staleOn.removeListener(listener));
  }
}

/// Runs a clear that goes through [ScanProvider] (so it is on the Undo list) and
/// shows the Undo message. [clear] returns how many items it removed. The message
/// is shown even though the controls that were tapped disappear with the item.
Future<void> clearWithUndo(BuildContext context, ScanProvider provider, Future<int> Function() clear) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final AppLocalizations l10n = AppLocalizations.of(context);
  final int n = await clear();
  _show(messenger, l10n, n, () => provider.undoManager.undo(), provider.undoManager.version);
}
