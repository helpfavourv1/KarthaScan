// lib/screens/folder_screen.dart
//
// Folder contents: documents inside folder, batch select, rename folder
// (Section 16 file #36).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/models/folder.dart';
import '../core/models/scan_document.dart';
import '../core/providers/folder_provider.dart';
import '../core/providers/scan_provider.dart';
import '../core/providers/settings_provider.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';
import '../widgets/empty_state.dart';
import '../widgets/scan_list_tile.dart';

class FolderScreen extends StatefulWidget {
  const FolderScreen({super.key, required this.folderId});

  final String folderId;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  late final ScanProvider _scanProvider;
  late final FolderProvider _folderProvider;
  late final SettingsProvider _settingsProvider;
  final Set<String> _selectedIds = <String>{};
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    _scanProvider = Provider.of<ScanProvider>(context, listen: false);
    _folderProvider = Provider.of<FolderProvider>(context, listen: false);
    _settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    _folderProvider.setActiveFolder(widget.folderId);
  }

  Folder? get _folder {
    for (final Folder f in _folderProvider.folders.value) {
      if (f.id == widget.folderId) return f;
    }
    return null;
  }

  Future<void> _rename(Folder folder, AppLocalizations l10n) async {
    final TextEditingController controller = TextEditingController(text: folder.name);
    final String? newName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.renameFolderTitle),
        content: TextField(controller: controller, autofocus: true),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(controller.text), child: Text(l10n.commonSave)),
        ],
      ),
    );
    controller.dispose();
    if (newName != null && newName.trim().isNotEmpty) {
      await _folderProvider.renameFolder(folder.id, newName);
    }
  }

  Future<void> _deleteFolder(Folder folder, AppLocalizations l10n) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.deleteFolderTitle),
        content: Text(l10n.deleteFolderMessage),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.commonDelete)),
        ],
      ),
    );
    if (confirmed != true) return;
    await _folderProvider.deleteFolder(folder.id);
    if (!mounted) return;
    context.pop();
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _enterSelectionMode(String id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  Future<void> _removeSelectedFromFolder(Folder folder) async {
    for (final String id in _selectedIds.toList()) {
      await _folderProvider.removeDocumentFromFolder(folder.id, id);
    }
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final String localeCode = _settingsProvider.settings.value.language;

    return Scaffold(
      backgroundColor: bg,
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[_folderProvider.folders, _scanProvider.documents]),
        builder: (BuildContext context, Widget? _) {
          final Folder? folder = _folder;
          if (folder == null) {
            return SafeArea(
              child: Column(
                children: <Widget>[
                  AppBar(backgroundColor: bg, elevation: 0),
                  Expanded(
                    child: Center(child: Text(l10n.folderUnavailable)),
                  ),
                ],
              ),
            );
          }

          final List<ScanDocument> documentsInFolder = _scanProvider.documents.value
              .where((ScanDocument d) => folder.documentIds.contains(d.id))
              .toList();

          return SafeArea(
            child: Column(
              children: <Widget>[
                _selectionMode
                    ? AppBar(
                        backgroundColor: bg,
                        elevation: 0,
                        leading: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _selectionMode = false;
                            _selectedIds.clear();
                          }),
                        ),
                        title: Text(l10n.selectedCount(_selectedIds.length)),
                        actions: <Widget>[
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            tooltip: l10n.removeFromFolderTooltip,
                            onPressed: _selectedIds.isEmpty
                                ? null
                                : () => _removeSelectedFromFolder(folder),
                          ),
                        ],
                      )
                    : AppBar(
                        backgroundColor: bg,
                        elevation: 0,
                        title: GestureDetector(
                          onTap: () => _rename(folder, l10n),
                          child: Text(folder.name, style: TextStyle(color: textPrimary)),
                        ),
                        actions: <Widget>[
                          IconButton(
                            icon: Icon(Icons.delete_outline, color: textSecondary),
                            tooltip: l10n.deleteFolderTooltip,
                            onPressed: () => _deleteFolder(folder, l10n),
                          ),
                        ],
                      ),
                Expanded(
                  child: documentsInFolder.isEmpty
                      ? EmptyState(
                          icon: Icons.folder_open_outlined,
                          message: l10n.noDocumentsInFolder,
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          itemCount: documentsInFolder.length,
                          separatorBuilder: (BuildContext context, int index) =>
                              const SizedBox(height: AppSpacing.xs),
                          itemBuilder: (BuildContext context, int index) {
                            final ScanDocument doc = documentsInFolder[index];
                            final bool isSelected = _selectedIds.contains(doc.id);
                            return ScanListTile(
                              document: doc,
                              localeCode: localeCode,
                              isSelected: isSelected,
                              onTap: _selectionMode
                                  ? () => _toggleSelection(doc.id)
                                  : () => context.push('/scan/${doc.id}'),
                              onLongPress:
                                  _selectionMode ? null : () => _enterSelectionMode(doc.id),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
