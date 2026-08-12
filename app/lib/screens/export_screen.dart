// lib/screens/export_screen.dart
//
// Export flow: format select → filter apply (Pro) → signature (Pro) →
// password (Pro) → share (Section 16 file #38).
//
// Batch export (more than one document at once) is Pro-gated per Section
// 19 — a single document's export flow is always free regardless of
// format; this screen checks that before anything else.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/models/export_job.dart';
import '../core/models/scan_document.dart';
import '../core/providers/scan_provider.dart';
import '../core/providers/subscription_provider.dart';
import '../core/services/export_service.dart';
import '../core/services/share_service.dart';
import '../core/utils/constants.dart';
import '../widgets/export_dialog.dart';
import '../widgets/filter_bottom_sheet.dart';
import '../widgets/signature_canvas.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key, required this.documentIds});

  final List<String> documentIds;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late final ScanProvider _scanProvider;
  late final SubscriptionProvider _subscriptionProvider;
  final ExportService _exportService = ExportService();
  final ShareService _shareService = ShareService();

  bool _isRunning = false;
  String? _statusMessage;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _scanProvider = Provider.of<ScanProvider>(context, listen: false);
    _subscriptionProvider = Provider.of<SubscriptionProvider>(context, listen: false);
  }

  List<ScanDocument> get _documents {
    final List<ScanDocument> all = _scanProvider.documents.value;
    final List<ScanDocument> result = <ScanDocument>[];
    for (final String id in widget.documentIds) {
      for (final ScanDocument doc in all) {
        if (doc.id == id) {
          result.add(doc);
          break;
        }
      }
    }
    return result;
  }

  Future<void> _startFlow() async {
    if (_started) return;
    _started = true;

    final bool isPro = _subscriptionProvider.isPro.value;

    if (widget.documentIds.length > 1 && !isPro) {
      final bool? goToPaywall = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Batch export is a Pro feature'),
          content: const Text(
            'Exporting several scans at once needs KatharScan Pro. You can '
            'still export one at a time for free.',
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Upgrade')),
          ],
        ),
      );
      if (!mounted) return;
      if (goToPaywall == true) {
        context.push('/paywall');
      } else {
        context.pop();
      }
      return;
    }

    final ExportFormat? format = await showExportFormatSheet(context);
    if (!mounted) return;
    if (format == null) {
      context.pop();
      return;
    }

    FilterType filter = FilterType.none;
    Uint8List? signatureBytes;
    String? password;

    if (isPro) {
      final FilterType? chosenFilter = await showFilterSheet(
        context,
        isPro: true,
        current: FilterType.none,
      );
      if (chosenFilter != null) filter = chosenFilter;
      if (!mounted) return;

      final bool wantsSignature = await _confirmStep('Add a signature?');
      if (wantsSignature && mounted) {
        signatureBytes = await _captureSignature();
        if (!mounted) return;
      }

      if (format == ExportFormat.pdf) {
        final bool wantsPassword = await _confirmStep('Password-protect this PDF?');
        if (wantsPassword && mounted) {
          password = await _promptPassword();
          if (!mounted) return;
        }
      }
    }

    await _runExport(
      format: format,
      filter: filter,
      signatureBytes: signatureBytes,
      password: password,
    );
  }

  Future<bool> _confirmStep(String question) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(question),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Skip')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Yes')),
        ],
      ),
    );
    return result ?? false;
  }

  Future<Uint8List?> _captureSignature() {
    final GlobalKey<SignatureCanvasState> signatureKey = GlobalKey<SignatureCanvasState>();
    return showModalBottomSheet<Uint8List?>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => _SignatureSheet(signatureKey: signatureKey),
    );
  }

  Future<String?> _promptPassword() async {
    final TextEditingController controller = TextEditingController();
    final String? password = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Set a password'),
        content: TextField(controller: controller, obscureText: true, autofocus: true),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Set')),
        ],
      ),
    );
    controller.dispose();
    final String trimmed = password?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _runExport({
    required ExportFormat format,
    required FilterType filter,
    Uint8List? signatureBytes,
    String? password,
  }) async {
    setState(() {
      _isRunning = true;
      _statusMessage = 'Exporting…';
    });

    final List<ScanDocument> documents = _documents;
    final List<String> allOutputPaths = <String>[];
    String? errorMessage;

    try {
      final Directory outputDir = await getTemporaryDirectory();
      for (final ScanDocument document in documents) {
        final List<String> paths = await _exportService.export(
          document: document,
          format: format,
          outputDirectoryPath: outputDir.path,
          filter: filter,
          signatureBytes: signatureBytes,
          pdfPassword: password,
        );
        allOutputPaths.addAll(paths);
      }
    } on ExportFailedException catch (error) {
      errorMessage = error.message;
    } catch (_) {
      errorMessage = 'Something went wrong while exporting.';
    }

    if (!mounted) return;

    if (errorMessage != null) {
      setState(() {
        _isRunning = false;
        _statusMessage = errorMessage;
      });
      return;
    }

    setState(() {
      _isRunning = false;
      _statusMessage = 'Done';
    });

    try {
      await _shareService.shareFiles(filePaths: allOutputPaths);
    } on ShareFailedException {
      // Share sheet failing to open isn't fatal here — the export itself
      // already succeeded and the files exist on disk; no need to
      // re-surface an error for a share dismissal or a rare platform
      // channel hiccup.
    }

    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    // The flow is kicked off here, in build, rather than initState —
    // showDialog/showModalBottomSheet need a fully mounted widget tree
    // with an Overlay ancestor, which isn't guaranteed yet during
    // initState. _started guards against re-triggering on rebuild.
    if (!_started) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) => _startFlow());
    }

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (_isRunning) const CircularProgressIndicator(),
                if (_statusMessage != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _statusMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _isRunning ? textSecondary : textPrimary,
                      fontSize: AppTypography.bodySize,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SignatureSheet extends StatelessWidget {
  const _SignatureSheet({required this.signatureKey});

  final GlobalKey<SignatureCanvasState> signatureKey;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(AppShape.bottomSheetTopRadius),
              topRight: Radius.circular(AppShape.bottomSheetTopRadius),
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Sign',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: AppTypography.title1Size,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(height: 180, child: SignatureCanvas(key: signatureKey)),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  TextButton(
                    onPressed: () => signatureKey.currentState?.clear(),
                    child: const Text('Clear'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Skip'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      final Uint8List? bytes = await signatureKey.currentState?.exportPng();
                      if (context.mounted) Navigator.of(context).pop(bytes);
                    },
                    child: const Text('Use signature'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
