// lib/screens/scan_detail_screen.dart
//
// Full document viewer: pages, OCR text, edit title, move to folder,
// delete (Section 16 file #35). Tag editing is included too — not
// explicitly listed in file #35's purpose text, but tag_chip.dart (file
// #33) was documented from the start as being for "editing contexts like
// scan_detail_screen.dart's tag editor," so this is completing that
// already-declared intent rather than adding new scope.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/models/folder.dart';
import '../core/models/scan_document.dart';
import '../core/providers/folder_provider.dart';
import '../core/providers/scan_provider.dart';
import '../core/services/share_service.dart';
import '../core/utils/constants.dart';
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
  bool _showOcrText = false;

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

  Future<void> _editTitle(ScanDocument document) async {
    final TextEditingController controller = TextEditingController(text: document.title);
    final String? newTitle = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Rename document'),
        content: TextField(controller: controller, autofocus: true),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newTitle != null && newTitle.trim().isNotEmpty) {
      await _scanProvider.renameDocument(document.id, newTitle);
    }
  }

  Future<void> _addTag(ScanDocument document) async {
    final TextEditingController controller = TextEditingController();
    final String? tag = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Add tag'),
        content: TextField(controller: controller, autofocus: true),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Add')),
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

  Future<void> _moveToFolder(ScanDocument document) async {
    final List<Folder> folders = _folderProvider.folders.value;
    final String? chosenFolderId = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext context) => _FolderPickerSheet(folders: folders),
    );
    if (chosenFolderId == null) return;
    await _folderProvider.addDocumentToFolder(chosenFolderId, document.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Moved to folder.')),
    );
  }

  Future<void> _delete(ScanDocument document) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete this scan?'),
        content: const Text("This can't be undone."),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
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
    } on ShareFailedException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

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
                  const Expanded(
                    child: Center(child: Text('This scan is no longer available.')),
                  ),
                ],
              ),
            );
          }

          return SafeArea(
            child: Column(
              children: <Widget>[
                AppBar(
                  backgroundColor: bg,
                  elevation: 0,
                  title: GestureDetector(
                    onTap: () => _editTitle(document),
                    child: Text(
                      document.title,
                      style: TextStyle(color: textPrimary, fontSize: AppTypography.title2Size),
                    ),
                  ),
                  actions: <Widget>[
                    IconButton(
                      icon: Icon(Icons.drive_file_move_outlined, color: textSecondary),
                      tooltip: 'Move to folder',
                      onPressed: () => _moveToFolder(document),
                    ),
                    IconButton(
                      icon: Icon(Icons.file_download_outlined, color: textSecondary),
                      tooltip: 'Export',
                      onPressed: () => context.push('/export', extra: <String>[document.id]),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline, color: textSecondary),
                      tooltip: 'Delete',
                      onPressed: () => _delete(document),
                    ),
                  ],
                ),
                Expanded(
                  flex: 3,
                  child: ScanPreviewCard(
                    pagePaths: document.pagePaths,
                    onShare: () => _share(document),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
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
                      TagChip(label: '+ Add tag', onTap: () => _addTag(document)),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _showOcrText = !_showOcrText),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: <Widget>[
                        Text(
                          'OCR text',
                          style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Icon(
                          _showOcrText ? Icons.expand_less : Icons.expand_more,
                          color: textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showOcrText)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        document.ocrText.isEmpty ? 'No text recognized.' : document.ocrText,
                        style: TextStyle(color: textSecondary, fontSize: AppTypography.bodySize),
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
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
              'Move to folder',
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
                  'No folders yet. Create one from the home screen.',
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
