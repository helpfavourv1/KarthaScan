import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/utils/constants.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/models/scan_document.dart';
import '../l10n/app_localizations.dart';

/// What the Pages manager hands back on Save: the pages in their new order,
/// and for each page file the quarter turns added with "Rotate 90".
class PagesManagerResult {
  const PagesManagerResult({required this.paths, required this.turnsByPath});
  final List<String> paths;
  final Map<String, int> turnsByPath;
}

class PagesManagerSheet extends StatefulWidget {
  const PagesManagerSheet({
    super.key,
    required this.pagePaths,
    required this.allDocuments,
    this.onExtract,
  });

  final List<String> pagePaths;
  final List<ScanDocument> allDocuments;
  final void Function(int index, String path)? onExtract;

  @override
  State<PagesManagerSheet> createState() => PagesManagerSheetState();
}

class PagesManagerSheetState extends State<PagesManagerSheet> {
  late List<String> _pages;
  final ImagePicker _picker = ImagePicker();
  final Map<String, int> _turnsByPath = <String, int>{};
  // Files this sheet created (copies of added, duplicated or merged pages).
  // Whatever is not kept when the sheet closes is deleted again.
  final List<String> _created = <String>[];
  bool _saved = false;

  @override
  void dispose() {
    for (final String path in _created) {
      if (!_saved || !_pages.contains(path)) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
    }
    super.dispose();
  }

  /// Copies a picked photo into the app's own storage. Pickers hand back files
  /// in a cache folder that Android may clear, which would empty the page.
  Future<String?> _importIntoApp(String sourcePath) async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final Directory dir = Directory(p.join(appDir.path, 'managed_pages'));
      await dir.create(recursive: true);
      final String ext = p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
      final String target = p.join(dir.path, 'managed_${DateTime.now().microsecondsSinceEpoch}$ext');
      await File(sourcePath).copy(target);
      _created.add(target);
      return target;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _pages = List<String>.from(widget.pagePaths);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF111111);
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(AppLocalizations.of(context).managePagesTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false, // Disable default handles to prevent "Add" tile dragging
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _pages.length + 1,
                onReorderItem: (oldIndex, newIndex) {
                  if (oldIndex < _pages.length && newIndex <= _pages.length) {
                    setState(() {
                      final item = _pages.removeAt(oldIndex);
                      // Dropping below the last page (onto the Add tile) can
                      // report an index past the end of the shortened list.
                      _pages.insert(newIndex.clamp(0, _pages.length), item);
                    });
                  }
                },
                itemBuilder: (context, index) {
                  if (index == _pages.length) {
                    return _buildAddTile(accent, textPrimary); // Non-draggable
                  }
                  return ReorderableDragStartListener( // Only page tiles are draggable
                    key: ValueKey(_pages[index]),
                    index: index,
                    child: _buildPageTile(index, accent, textPrimary),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context).commonCancel)),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () { _saved = true; Navigator.pop(context, PagesManagerResult(paths: List<String>.from(_pages), turnsByPath: Map<String, int>.from(_turnsByPath))); },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(AppLocalizations.of(context).commonSave),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageTile(int index, Color accent, Color textPrimary) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 48,
            height: 64,
            child: RotatedBox(
              quarterTurns: (_turnsByPath[_pages[index]] ?? 0) % 4,
              child: Image.file(File(_pages[index]), fit: BoxFit.cover, cacheWidth: 144),
            ),
          ),
        ),
        title: Text(AppLocalizations.of(context).pageLabel(index + 1), style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showPageMenu(index),
            ),
            Icon(Icons.drag_handle, color: textPrimary),
            IconButton(
              icon: Icon(Icons.close, color: _pages.length > 1 ? Colors.red : Colors.grey),
              onPressed: _pages.length > 1
                  ? () => setState(() => _pages.removeAt(index))
                  : null,
            ),
          ],
        ),
      ),
    );
  }


  Future<void> _showPageMenu(int index) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.copy), title: Text(AppLocalizations.of(ctx).duplicateAction), onTap: () => Navigator.pop(ctx, 'duplicate')),
        ListTile(leading: const Icon(Icons.rotate_90_degrees_ccw), title: Text(AppLocalizations.of(ctx).rotate90Action), onTap: () => Navigator.pop(ctx, 'rotate')),
        ListTile(leading: const Icon(Icons.open_in_new), title: Text(AppLocalizations.of(ctx).extractToNewDocAction), onTap: () => Navigator.pop(ctx, 'extract')),
      ])),
    );
    if (action == null || !mounted) return;
    if (action == 'duplicate') {
      // A real copy, so the two tiles have distinct keys and the copy can
      // be edited or deleted on its own.
      try {
        final String source = _pages[index];
        final String copy = p.join(
          p.dirname(source),
          'dup_${DateTime.now().microsecondsSinceEpoch}${p.extension(source)}',
        );
        await File(source).copy(copy);
        _created.add(copy);
        final int? turns = _turnsByPath[source];
        if (turns != null) _turnsByPath[copy] = turns;
        if (mounted) setState(() => _pages.insert(index + 1, copy));
      } catch (_) {}
    } else if (action == 'rotate') {
      // The turn is stored as an edit on the page (applied on Save), so the
      // picture file and everything already done to the page stay as they are.
      setState(() {
        final String path = _pages[index];
        _turnsByPath[path] = ((_turnsByPath[path] ?? 0) + 1) % 4;
      });
    } else if (action == 'extract') {
      final cb = widget.onExtract;
      if (cb != null) cb(index, _pages[index]);
    }
  }

  Widget _buildAddTile(Color accent, Color textPrimary) {
    return Container(
      key: const ValueKey('add'),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: accent, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(Icons.add_circle_outline, color: accent, size: 48),
        title: Text(AppLocalizations.of(context).addPageTitle, style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
        onTap: _showAddOptions,
      ),
    );
  }

  Future<void> _showAddOptions() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(AppLocalizations.of(ctx).cameraSource),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(AppLocalizations.of(ctx).importFromGallery),
              onTap: () => Navigator.pop(ctx, 'import'),
            ),
            ListTile(
              leading: const Icon(Icons.description),
              title: Text(AppLocalizations.of(ctx).fromAnotherDocument),
              onTap: () => Navigator.pop(ctx, 'document'),
            ),
          ],
        ),
      ),
    );
        if (choice == null) return;

    if (choice == 'camera') {
      final xFile = await _picker.pickImage(source: ImageSource.camera);
      if (xFile != null) {
        final String? kept = await _importIntoApp(xFile.path);
        if (kept != null && mounted) setState(() => _pages.add(kept));
      }
    } else if (choice == 'import') {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null) {
        final String? kept = await _importIntoApp(result.files.single.path!);
        if (kept != null && mounted) setState(() => _pages.add(kept));
      }
    } else if (choice == 'document') {
      if (!mounted) return;
      final docId = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(
        children: widget.allDocuments.map((doc) => ListTile(
          title: Text(doc.title),
          subtitle: Text(AppLocalizations.of(ctx).pageCountLabel(doc.pageCount)),
          onTap: () => Navigator.pop(ctx, doc.id),
        )).toList(),
      ),
    ),
  );
  if (!mounted) return;
      if (docId != null) {
        final doc = widget.allDocuments.firstWhere((d) => d.id == docId);
        final appDir = await getApplicationDocumentsDirectory();
        final combinedDir = Directory(p.join(appDir.path, 'combined_pages'));
        await combinedDir.create(recursive: true);
        for (final path in doc.pagePaths) {
          final fileName = '${DateTime.now().microsecondsSinceEpoch}_${p.basename(path)}';
          final newPath = p.join(combinedDir.path, fileName);
          await File(path).copy(newPath);
          _created.add(newPath);
          if (mounted) setState(() => _pages.add(newPath));
        }
      }
    }
  }
}
