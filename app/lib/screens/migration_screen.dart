// lib/screens/migration_screen.dart
//
// "Device Migration": export encrypted archive (AES-256) or import from
// archive. Honest label — not "sync." (Section 16 file #39).
//
// No dedicated migration_service.dart exists in the fixed 75-file
// manifest, and this logic (archive building, AES-256 encryption, backup
// parsing) doesn't fit local_storage.dart's stated "documents/folders
// CRUD, FTS5 search, settings" scope either — so it lives here,
// self-contained, as private helpers on this screen's State. That makes
// this file larger than a typical screen, but that's the more honest
// choice than scope-creeping a file that already has a clear, different
// purpose.
//
// ENCRYPTION: see core/services/backup_crypto.dart (PBKDF2 + HMAC for new
// backups; old-format backups can still be opened).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/models/fill_snippet.dart';
import '../core/models/folder.dart';
import '../core/models/scan_document.dart';
import '../core/providers/folder_provider.dart';
import '../core/providers/scan_provider.dart';
import '../core/services/backup_crypto.dart';
import '../core/services/local_storage.dart';
import '../core/services/share_service.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';

class MigrationScreen extends StatefulWidget {
  const MigrationScreen({super.key});

  @override
  State<MigrationScreen> createState() => _MigrationScreenState();
}

class _MigrationScreenState extends State<MigrationScreen> {
  late final ScanProvider _scanProvider;
  late final FolderProvider _folderProvider;
  final ShareService _shareService = ShareService();

  bool _isBusy = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _scanProvider = Provider.of<ScanProvider>(context, listen: false);
    _folderProvider = Provider.of<FolderProvider>(context, listen: false);
  }

  // ---------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------

  Future<void> _exportBackup(AppLocalizations l10n) async {
    final String? password = await _promptPassword(
      title: l10n.setBackupPasswordTitle,
      confirmLabel: l10n.commonExport,
    );
    if (password == null) return;

    setState(() {
      _isBusy = true;
      _statusMessage = l10n.buildingBackupStatus;
    });

    try {
      final List<ScanDocument> documents = _scanProvider.documents.value;
      final List<Folder> folders = _folderProvider.folders.value;
      final Archive archive = Archive();

      // Bundle every page image, keyed by a flat, collision-safe filename
      // — the manifest's pagePaths get rewritten to these flat names so
      // import doesn't need to reconstruct the exporting device's
      // original directory structure, which won't exist on the importing
      // device anyway.
      final Set<String> usedArchiveNames = <String>{};
      final Map<String, String> pathToArchiveName = <String, String>{};
      for (final ScanDocument document in documents) {
        for (final String path in document.pagePaths) {
          if (pathToArchiveName.containsKey(path)) continue;
          final String base = p.basename(path);
          String archiveName = base;
          int suffix = 1;
          while (usedArchiveNames.contains(archiveName)) {
            archiveName = '${suffix}_$base';
            suffix++;
          }
          usedArchiveNames.add(archiveName);
          pathToArchiveName[path] = archiveName;
          try {
            final Uint8List bytes = await File(path).readAsBytes();
            archive.addFile(ArchiveFile('pages/$archiveName', bytes.length, bytes));
          } catch (_) {
            // A missing/unreadable page is skipped rather than failing
            // the whole backup — the manifest simply won't reference it.
          }
        }
      }

      // Annotation drawings are separate image files; without them an
      // imported document would lose its annotations.
      final Map<String, String> annotationToArchiveName = <String, String>{};
      for (final ScanDocument document in documents) {
        for (final AnnotateLayer layer in document.annotateLayers) {
          if (annotationToArchiveName.containsKey(layer.bytesPath)) continue;
          try {
            final Uint8List bytes = await File(layer.bytesPath).readAsBytes();
            final String name = 'a${annotationToArchiveName.length}_${p.basename(layer.bytesPath)}';
            archive.addFile(ArchiveFile('annotations/$name', bytes.length, bytes));
            annotationToArchiveName[layer.bytesPath] = name;
          } catch (_) {
            // Missing file: the layer is simply left without a picture.
          }
        }
      }

      final List<Map<String, dynamic>> documentJson = documents.map((ScanDocument d) {
        final Map<String, dynamic> json = d.toJson();
        json['pagePaths'] = d.pagePaths
            .map((String path) => pathToArchiveName[path] ?? p.basename(path))
            .toList();
        final List<dynamic> layers = json['annotateLayers'] as List<dynamic>? ?? <dynamic>[];
        json['annotateLayers'] = layers.map((dynamic l) {
          final Map<String, dynamic> layer = Map<String, dynamic>.from(l as Map);
          layer['bytesPath'] = annotationToArchiveName[layer['bytesPath']] ?? '';
          return layer;
        }).toList();
        return json;
      }).toList();

      // Saved signature and text snippets travel with the backup too.
      final LocalStorageService storage = LocalStorageService();
      final Uint8List? signature = await storage.loadSignaturePng();
      if (signature != null) {
        archive.addFile(ArchiveFile('signature.png', signature.length, signature));
      }
      final List<FillSnippet> snippets = await storage.loadFillSnippets();

      final Map<String, dynamic> manifest = <String, dynamic>{
        'version': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'documents': documentJson,
        'folders': folders.map((Folder f) => f.toJson()).toList(),
        'snippets': snippets.map((FillSnippet s) => s.toJson()).toList(),
      };
      final List<int> manifestBytes = utf8.encode(jsonEncode(manifest));
      archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

      final List<int>? zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) {
        throw Exception('Could not build the archive.');
      }

      // Key stretching is slow on purpose, so it runs off the UI thread.
      final Uint8List encrypted = await compute(
        backupEncryptJob,
        <String, Object>{'data': Uint8List.fromList(zipBytes), 'password': password},
      );

      final Directory outDir = await getTemporaryDirectory();
      final String outPath = p.join(
        outDir.path,
        'KatharScan-Backup-${DateTime.now().millisecondsSinceEpoch}.katharscanbackup',
      );
      await File(outPath).writeAsBytes(encrypted);

      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _statusMessage = l10n.backupReadyStatus;
      });

      try {
        await _shareService.shareFiles(filePaths: <String>[outPath]);
      } on ShareFailedException {
        if (!mounted) return;
        // ShareFailedException.message is English, set in
        // core/services/share_service.dart with no BuildContext available
        // there to localize at the source — shown here as a localized
        // generic fallback per Section 18 rather than that raw string.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.genericErrorMessage)),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('[MigrationScreen] export failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _statusMessage = l10n.couldNotCreateBackupError;
      });
    }
  }

  // ---------------------------------------------------------------------
  // Import
  // ---------------------------------------------------------------------

  Future<void> _importBackup(AppLocalizations l10n) async {
    final FilePickerResult? picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final String? pickedPath = picked?.files.single.path;
    if (pickedPath == null) return;

    if (!mounted) return;
    final String? password = await _promptPassword(
      title: l10n.enterBackupPasswordTitle,
      confirmLabel: l10n.commonImport,
    );
    if (password == null) return;

    setState(() {
      _isBusy = true;
      _statusMessage = l10n.importingStatus;
    });

    try {
      final Uint8List encrypted = await File(pickedPath).readAsBytes();
      final Uint8List decrypted = await compute(
        backupDecryptJob,
        <String, Object>{'data': encrypted, 'password': password},
      );
      final Archive archive = ZipDecoder().decodeBytes(decrypted);

      final ArchiveFile? manifestFile = archive.findFile('manifest.json');
      if (manifestFile == null) {
        throw Exception(l10n.backupCorruptedError);
      }
      final Map<String, dynamic> manifest =
          jsonDecode(utf8.decode(manifestFile.content as List<int>)) as Map<String, dynamic>;

      final appDir = await getApplicationDocumentsDirectory();
      final Directory importDir = Directory(p.join(appDir.path, 'imported_pages'));
      await importDir.create(recursive: true);

      final Map<String, String> archiveNameToNewPath = <String, String>{};
      for (final ArchiveFile file in archive.files) {
        if (!file.isFile || !file.name.startsWith('pages/')) continue;
        // basename: never let an archive entry name walk out of the folder.
        final String archiveName = p.basename(file.name.substring('pages/'.length));
        final String newPath = p.join(
          importDir.path,
          '${DateTime.now().microsecondsSinceEpoch}_$archiveName',
        );
        await File(newPath).writeAsBytes(file.content as List<int>);
        archiveNameToNewPath[archiveName] = newPath;
      }

      final Map<String, String> annotationNameToNewPath = <String, String>{};
      for (final ArchiveFile file in archive.files) {
        if (!file.isFile || !file.name.startsWith('annotations/')) continue;
        final String name = p.basename(file.name.substring('annotations/'.length));
        final String newPath = p.join(
          importDir.path,
          'ann_${DateTime.now().microsecondsSinceEpoch}_$name',
        );
        await File(newPath).writeAsBytes(file.content as List<int>);
        annotationNameToNewPath[name] = newPath;
      }

      final List<dynamic> folderJsonList = manifest['folders'] as List<dynamic>? ?? <dynamic>[];
      for (final dynamic json in folderJsonList) {
        final Folder folder = Folder.fromJson(json as Map<String, dynamic>);
        await _folderProvider.importFolder(folder);
      }

      final List<dynamic> docJsonList = manifest['documents'] as List<dynamic>? ?? <dynamic>[];
      int importedCount = 0;
      for (final dynamic json in docJsonList) {
        final Map<String, dynamic> docJson = Map<String, dynamic>.from(json as Map<String, dynamic>);
        final List<dynamic> archiveNames = docJson['pagePaths'] as List<dynamic>? ?? <dynamic>[];
        final List<String> newPaths = archiveNames
            .map((dynamic name) => archiveNameToNewPath[name as String])
            .whereType<String>()
            .toList();
        if (newPaths.isEmpty) continue;

        docJson['pagePaths'] = newPaths;
        docJson['pageCount'] = newPaths.length; // some pages may have been skipped
        docJson['thumbnailPath'] = newPaths.first;
        final List<dynamic> layerList = docJson['annotateLayers'] as List<dynamic>? ?? <dynamic>[];
        docJson['annotateLayers'] = layerList
            .map((dynamic l) => Map<String, dynamic>.from(l as Map))
            .where((Map<String, dynamic> l) => annotationNameToNewPath.containsKey(l['bytesPath']))
            .map((Map<String, dynamic> l) {
          l['bytesPath'] = annotationNameToNewPath[l['bytesPath']];
          return l;
        }).toList();
        final ScanDocument document = ScanDocument.fromJson(docJson);
        final bool success = await _scanProvider.importDocument(document);
        if (success) importedCount++;
      }

      // Saved signature (kept if one already exists here) and snippets (merged).
      final LocalStorageService storage = LocalStorageService();
      final ArchiveFile? signatureFile = archive.findFile('signature.png');
      if (signatureFile != null && await storage.loadSignaturePng() == null) {
        await storage.saveSignaturePng(Uint8List.fromList(signatureFile.content as List<int>));
      }
      final List<dynamic> snippetJson = manifest['snippets'] as List<dynamic>? ?? <dynamic>[];
      if (snippetJson.isNotEmpty) {
        final List<FillSnippet> existing = await storage.loadFillSnippets();
        final Set<String> known = existing.map((FillSnippet s) => s.id).toSet();
        for (final dynamic j in snippetJson) {
          final FillSnippet snippet = FillSnippet.fromJson(Map<String, dynamic>.from(j as Map));
          if (known.add(snippet.id)) existing.add(snippet);
        }
        await storage.saveFillSnippets(existing);
      }

      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _statusMessage = l10n.importedCount(importedCount);
      });
    } catch (error, stackTrace) {
      debugPrint('[MigrationScreen] import failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _statusMessage = l10n.couldNotImportBackupError;
      });
    }
  }

  Future<String?> _promptPassword({required String title, required String confirmLabel}) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextEditingController controller = TextEditingController();
    final String? password = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, obscureText: true, autofocus: true),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(controller.text), child: Text(confirmLabel)),
        ],
      ),
    );
    controller.dispose();
    final String trimmed = password?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text(l10n.migrationTitle, style: TextStyle(color: textPrimary)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Honest label per Section 16 file #39 — this is a one-time
              // export/import a user runs manually, not background sync.
              Text(
                l10n.migrationExplainer,
                style: TextStyle(
                  color: textSecondary,
                  fontSize: AppTypography.bodySize,
                  height: AppTypography.bodyLineHeight,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: AppShape.buttonMinHeight,
                child: ElevatedButton.icon(
                  onPressed: _isBusy ? null : () => _exportBackup(l10n),
                  icon: const Icon(Icons.upload_outlined),
                  label: Text(l10n.exportBackupButton),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppShape.buttonRadius),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: AppShape.buttonMinHeight,
                child: OutlinedButton.icon(
                  onPressed: _isBusy ? null : () => _importBackup(l10n),
                  icon: const Icon(Icons.download_outlined),
                  label: Text(l10n.importBackupButton),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppShape.buttonRadius),
                    ),
                  ),
                ),
              ),
              if (_isBusy || _statusMessage != null) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                if (_isBusy) const Center(child: CircularProgressIndicator()),
                if (_statusMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      _statusMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textSecondary, fontSize: AppTypography.footnoteSize),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
