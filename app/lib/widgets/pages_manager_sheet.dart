import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import '../core/utils/constants.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/models/page_transform.dart';
import '../core/models/scan_document.dart';
import '../l10n/app_localizations.dart';
import 'document_canvas.dart' show PagePreviewJob, renderPagePreview;

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
    this.transformsByPath = const <String, PageTransform>{},
  });

  /// The edits each page file already has (crop, tilt, filter...), so its thumbnail
  /// shows the page as it will be exported.
  final Map<String, PageTransform> transformsByPath;

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
  bool _selecting = false;
  final Set<String> _selected = <String>{};
  final Map<String, Future<Uint8List?>> _thumbs = <String, Future<Uint8List?>>{};

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

  /// The page as edited, small. Pages without edits show the plain file.
  Future<Uint8List?> _editedThumb(String path, PageTransform t) {
    return _thumbs.putIfAbsent(path, () async {
      final Uint8List bytes = await File(path).readAsBytes();
      return compute(renderPagePreview, PagePreviewJob(bytes, t));
    });
  }

  Widget _thumb(String path) {
    final PageTransform? t = widget.transformsByPath[path];
    final int turns = ((t?.rotationTurns ?? 0) + (_turnsByPath[path] ?? 0)) % 4;
    final bool edited = t != null && !t.isEmpty;
    final Widget picture = !edited
        ? Image.file(File(path), fit: BoxFit.cover, cacheWidth: 144)
        : FutureBuilder<Uint8List?>(
            future: _editedThumb(path, t),
            builder: (BuildContext context, AsyncSnapshot<Uint8List?> snap) {
              final Uint8List? bytes = snap.data;
              if (bytes == null) return Image.file(File(path), fit: BoxFit.cover, cacheWidth: 144);
              return Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 144, key: const Key('editedThumb'));
            },
          );
    return RotatedBox(quarterTurns: turns, child: picture);
  }

  Future<void> _deleteSelected() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // At least one page must stay.
    final List<String> doomed = _pages.where(_selected.contains).toList();
    if (doomed.isEmpty || doomed.length >= _pages.length) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.pagesDeleteConfirm(doomed.length)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.commonCancel)),
          TextButton(key: const Key('pagesDeleteConfirmYes'), onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.pagesDeleteCount(doomed.length), style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _pages.removeWhere(doomed.contains);
      _selected.clear();
      _selecting = false;
    });
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
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      key: const Key('pagesSelect'),
                      icon: Icon(Icons.checklist, color: _selecting ? accent : null),
                      tooltip: AppLocalizations.of(context).pagesSelectTooltip,
                      onPressed: _pages.length < 2 ? null : () => setState(() {
                            _selecting = !_selecting;
                            _selected.clear();
                          }),
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ]),
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
            if (_selecting)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('pagesDeleteSelected'),
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: Text(AppLocalizations.of(context).pagesDeleteCount(_selected.length)),
                      // Deleting every page is not allowed: one must stay.
                      onPressed: (_selected.isEmpty || _selected.length >= _pages.length) ? null : _deleteSelected,
                    ),
                  ),
                ]),
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
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
        onTap: _selecting
            ? () => setState(() {
                  final String path = _pages[index];
                  if (!_selected.remove(path)) _selected.add(path);
                })
            : null,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 48,
            height: 64,
            child: _thumb(_pages[index]),
          ),
        ),
        title: Text(AppLocalizations.of(context).pageLabel(index + 1), style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600)),
        trailing: _selecting
            ? Checkbox(key: Key('pageCheck:$index'), value: _selected.contains(_pages[index]), onChanged: (_) => setState(() {
                  final String path = _pages[index];
                  if (!_selected.remove(path)) _selected.add(path);
                }))
            : Row(
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
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
        leading: Icon(Icons.add_circle_outline, color: accent, size: 48),
        title: Text(AppLocalizations.of(context).addPageTitle, style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
        onTap: _showAddOptions,
        ),
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
