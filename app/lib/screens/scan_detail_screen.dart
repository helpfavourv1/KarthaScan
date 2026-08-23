// lib/screens/scan_detail_screen.dart
//
// Full document viewer: pages, OCR text in DraggableScrollableSheet,
// edit title, move to folder, delete. Tag editing included.
// PHASE 1 REDESIGN: OCR tray is now a DraggableScrollableSheet with
// copy-to-clipboard. Share and Export are prominent bottom buttons.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/models/folder.dart';
import '../core/models/scan_document.dart';
import '../core/providers/folder_provider.dart';
import '../core/providers/scan_provider.dart';
import '../core/services/share_service.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';
import '../widgets/scan_preview_card.dart';
import '../widgets/tag_chip.dart';

class ScanDetailScreen extends StatefulWidget {
  const ScanDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  State<ScanDetailScreen> createState() => _ScanDetailScreenState();
}

class _ScanDetailScreenState extends State<ScanDetailScreen> {
  late final ScanProvider _scanProvider;
  late final FolderProvider _folderProvider;
  final ShareService _shareService = ShareService();

  // CRITICAL FIX: Use a local ScrollController in the builder, NOT a global one.
  // DraggableScrollableSheet provides its own controller. We must NOT dispose it.

  @override
  void initState() {
    super.initState();
    _scanProvider = Provider.of<ScanProvider>(context, listen: false);
    _folderProvider = Provider.of<FolderProvider>(context, listen: false);
    _scanProvider.setActiveScan(widget.documentId);
  }

  ScanDocument? get _document {
    for (final ScanDocument doc in _scanProvider.documents.value) {
      if (doc.id == widget.documentId) return doc;
    }
    return null;
  }

  Future<void> _editTitle(ScanDocument document, AppLocalizations l10n) async {
    final TextEditingController controller = TextEditingController(text: document.title);
    final String? newTitle = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.renameDocumentTitle),
        content: TextField(controller: controller, autofocus: true),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newTitle != null && newTitle.trim().isNotEmpty) {
      await _scanProvider.renameDocument(document.id, newTitle);
    }
  }

  Future<void> _addTag(ScanDocument document, AppLocalizations l10n) async {
    final TextEditingController controller = TextEditingController();
    final String? tag = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.addTagTitle),
        content: TextField(controller: controller, autofocus: true),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(controller.text), child: Text(l10n.commonAdd)),
        ],
      ),
    );
    controller.dispose();
    final String trimmed = tag?.trim() ?? '';
    if (trimmed.isEmpty) return;
    final List<String> updated = <String>{...document.tags, trimmed}.toList();
    await _scanProvider.updateTags(document.id, updated);
  }

  Future<void> _removeTag(ScanDocument document, String tag) async {
    final List<String> updated = document.tags.where((String t) => t != tag).toList();
    await _scanProvider.updateTags(document.id, updated);
  }

  Future<void> _moveToFolder(ScanDocument document, AppLocalizations l10n) async {
    final List<Folder> folders = _folderProvider.folders.value;
    final String? chosenFolderId = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext context) => _FolderPickerSheet(folders: folders),
    );
    if (chosenFolderId == null) return;
    await _folderProvider.addDocumentToFolder(chosenFolderId, document.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.movedToFolderMessage)),
    );
  }

  Future<void> _delete(ScanDocument document, AppLocalizations l10n) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.deleteScanTitle),
        content: Text(l10n.deleteScanMessage),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.commonDelete)),
        ],
      ),
    );
    if (confirmed != true) return;
    await _scanProvider.deleteDocument(document.id);
    await _folderProvider.removeDocumentFromAllFolders(document.id);
    if (!mounted) return;
    context.pop();
  }

  Future<void> _share(ScanDocument document) async {
    try {
      await _shareService.shareFiles(filePaths: document.pagePaths);
    } on ShareFailedException {
      if (!mounted) return;
      final AppLocalizations l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.genericErrorMessage)),
      );
    }
  }

  Future<void> _export(ScanDocument document) async {
    if (!mounted) return;
    context.push('/export', extra: <String>[document.id]);
  }

  void _copyOcrToClipboard(String text, AppLocalizations l10n) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final Color textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    final Color border = isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight;

    return Scaffold(
      backgroundColor: bg,
      body: ListenableBuilder(
        listenable: _scanProvider.documents,
        builder: (BuildContext context, Widget? _) {
          final ScanDocument? document = _document;
          if (document == null) {
            return SafeArea(
              child: Column(
                children: <Widget>[
                  AppBar(backgroundColor: bg, elevation: 0),
                  Expanded(
                    child: Center(child: Text(l10n.scanUnavailable)),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: <Widget>[
              AppBar(
                backgroundColor: bg,
                elevation: 0,
                title: GestureDetector(
                  onTap: () => _editTitle(document, l10n),
                  child: Text(
                    document.title,
                    style: TextStyle(color: textPrimary, fontSize: AppTypography.title2Size),
                  ),
                ),
                actions: <Widget>[
                  IconButton(
                    icon: Icon(Icons.drive_file_move_outlined, color: textSecondary),
                    tooltip: l10n.moveToFolderTooltip,
                    onPressed: () => _moveToFolder(document, l10n),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: textSecondary),
                    tooltip: l10n.deleteTooltip,
                    onPressed: () => _delete(document, l10n),
                  ),
                ],
              ),
              Expanded(
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: ScanPreviewCard(
                        pagePaths: document.pagePaths,
                      ),
                    ),
                    DraggableScrollableSheet(
                      initialChildSize: 0.25,
                      minChildSize: 0.12,
                      maxChildSize: 0.85,
                      // CRITICAL FIX: Use the provided scrollController directly.
                      builder: (BuildContext context, ScrollController scrollController) {
                        return Container(
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(AppShape.bottomSheetTopRadius),
                              topRight: Radius.circular(AppShape.bottomSheetTopRadius),
                            ),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 10,
                                offset: const Offset(0, -2),
                              ),
                            ],
                          ),
                          child: Column(
                            children: <Widget>[
                              Center(
                                child: Container(
                                  width: 36,
                                  height: 4,
                                  margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                                  decoration: BoxDecoration(
                                    color: border,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                                child: Row(
                                  children: <Widget>[
                                    Text(
                                      l10n.ocrTextLabel,
                                      style: TextStyle(
                                        color: textPrimary,
                                        fontSize: AppTypography.title2Size,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      icon: Icon(Icons.copy_outlined, color: textSecondary),
                                      tooltip: 'Copy',
                                      onPressed: () => _copyOcrToClipboard(document.ocrText, l10n),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Expanded(
                                child: SingleChildScrollView(
                                  controller: scrollController,
                                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                                  child: SelectableText(
                                    document.ocrText.isEmpty ? l10n.noTextRecognized : document.ocrText,
                                    style: TextStyle(
                                      color: textSecondary,
                                      fontSize: AppTypography.bodySize,
                                      height: AppTypography.bodyLineHeight,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Container(
                color: bg,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                child: Wrap(
                  spacing: AppSpacing.xxs,
                  runSpacing: AppSpacing.xxs,
                  children: <Widget>[
                    ...document.tags.map(
                      (String tag) => TagChip(
                        label: tag,
                        onDeleted: () => _removeTag(document, tag),
                      ),
                    ),
                    TagChip(label: l10n.addTagChipLabel, onTap: () => _addTag(document, l10n)),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: bg,
                    border: Border(
                      top: BorderSide(color: border, width: AppShape.cardBorderWidth),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _share(document),
                          icon: const Icon(Icons.ios_share),
                          label: Text(l10n.shareTooltip),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, AppShape.buttonMinHeight),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppShape.buttonRadius),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _export(document),
                          icon: const Icon(Icons.file_download_outlined),
                          label: Text(l10n.exportTooltip),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: surface,
                            foregroundColor: textPrimary,
                            minimumSize: const Size(double.infinity, AppShape.buttonMinHeight),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppShape.buttonRadius),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FolderPickerSheet extends StatelessWidget {
  const _FolderPickerSheet({required this.folders});

  final List<Folder> folders;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;

    return SafeArea(
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.moveToFolderTooltip,
              style: TextStyle(
                color: textPrimary,
                fontSize: AppTypography.title1Size,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (folders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text(
                  l10n.noFoldersYetMessage,
                  style: TextStyle(color: textPrimary),
                ),
              )
            else
              ...folders.map(
                (Folder folder) => ListTile(
                  title: Text(folder.name),
                  onTap: () => Navigator.of(context).pop(folder.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
