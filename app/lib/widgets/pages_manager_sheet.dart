import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/models/scan_document.dart';

class PagesManagerSheet extends StatefulWidget {
  const PagesManagerSheet({
    super.key,
    required this.pagePaths,
    required this.allDocuments,
  });

  final List<String> pagePaths;
  final List<ScanDocument> allDocuments;

  @override
  State<PagesManagerSheet> createState() => PagesManagerSheetState();
}

class PagesManagerSheetState extends State<PagesManagerSheet> {
  late List<String> _pages;
  final ImagePicker _picker = ImagePicker();

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
    final accent = isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);

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
                  Text('Manage Pages', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary)),
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
                      _pages.insert(newIndex, item);
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
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, _pages),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Save'),
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
            child: Image.file(File(_pages[index]), fit: BoxFit.cover),
          ),
        ),
        title: Text('Page ${index + 1}', style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.drag_handle, color: textPrimary), // Visual cue only
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
        title: Text('Add Page', style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
        onTap: _showAddOptions,
      ),
    );
  }

  Future<void> _showAddOptions() async {
    final choice = await showModalBottomSheet<String>(
      if (!mounted) return;
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Import from Gallery'),
              onTap: () => Navigator.pop(ctx, 'import'),
            ),
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('From Another Document'),
              onTap: () => Navigator.pop(ctx, 'document'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    if (choice == 'camera') {
      final xFile = await _picker.pickImage(source: ImageSource.camera);
      if (xFile != null) setState(() => _pages.add(xFile.path));
    } else if (choice == 'import') {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null) {
        setState(() => _pages.add(result.files.single.path!));
      }
    } else if (choice == 'document') {
      final docId = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: ListView(
            children: widget.allDocuments.map((doc) => ListTile(
              title: Text(doc.title),
              subtitle: Text('${doc.pageCount} pages'),
              onTap: () => Navigator.pop(ctx, doc.id),
            )).toList(),
          ),
        ),
      );
      if (docId != null) {
        final doc = widget.allDocuments.firstWhere((d) => d.id == docId);
        final appDir = await getApplicationDocumentsDirectory();
        final combinedDir = Directory(p.join(appDir.path, 'combined_pages'));
        await combinedDir.create(recursive: true);
        for (final path in doc.pagePaths) {
          final fileName = '${DateTime.now().microsecondsSinceEpoch}_${p.basename(path)}';
          final newPath = p.join(combinedDir.path, fileName);
          await File(path).copy(newPath);
          setState(() => _pages.add(newPath));
        }
      }
    }
  }
}
