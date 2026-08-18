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
// KEY DERIVATION: the user's backup password is turned into a 32-byte
// AES-256 key via a single SHA-256 hash (crypto package), not a proper
// password-based KDF (PBKDF2/Argon2 with salt and iteration count). For a
// device-to-device backup file the user creates and consumes themselves
// within a short window, this is a reasonable, honestly-stated tradeoff —
// but it is a weaker defense against a stolen-file brute-force attempt
// than a real KDF would be. Worth revisiting if this feature's threat
// model changes (e.g., long-term cloud storage of these backup files).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as enc;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/models/folder.dart';
import '../core/models/scan_document.dart';
import '../core/providers/folder_provider.dart';
import '../core/providers/scan_provider.dart';
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

      final List<Map<String, dynamic>> documentJson = documents.map((ScanDocument d) {
        final Map<String, dynamic> json = d.toJson();
        json['pagePaths'] = d.pagePaths
            .map((String path) => pathToArchiveName[path] ?? p.basename(path))
            .toList();
        return json;
      }).toList();

      final Map<String, dynamic> manifest = <String, dynamic>{
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'documents': documentJson,
        'folders': folders.map((Folder f) => f.toJson()).toList(),
      };
      final List<int> manifestBytes = utf8.encode(jsonEncode(manifest));
      archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

      final List<int>? zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) {
        throw Exception('Could not build the archive.');
      }

      final Uint8List encrypted = _encrypt(Uint8List.fromList(zipBytes), password);

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
      final Uint8List decrypted = _decrypt(encrypted, password);
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
        final String archiveName = file.name.substring('pages/'.length);
        final String newPath = p.join(
          importDir.path,
          '${DateTime.now().microsecondsSinceEpoch}_$archiveName',
        );
        await File(newPath).writeAsBytes(file.content as List<int>);
        archiveNameToNewPath[archiveName] = newPath;
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
        docJson['thumbnailPath'] = newPaths.first;
        final ScanDocument document = ScanDocument.fromJson(docJson);
        final bool success = await _scanProvider.importDocument(document);
        if (success) importedCount++;
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

  // ---------------------------------------------------------------------
  // Encryption helpers
  // ---------------------------------------------------------------------

  Uint8List _deriveKey(String password) {
    final crypto.Digest digest = crypto.sha256.convert(utf8.encode(password));
    return Uint8List.fromList(digest.bytes);
  }

  Uint8List _encrypt(Uint8List data, String password) {
    final enc.Key key = enc.Key(_deriveKey(password));
    final enc.IV iv = enc.IV.fromSecureRandom(16);
    final enc.Encrypter encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final enc.Encrypted encrypted = encrypter.encryptBytes(data, iv: iv);
    // The IV is prepended in plaintext — it doesn't need to be secret,
    // only unique per encryption, and decrypt needs it to proceed.
    return Uint8List.fromList(<int>[...iv.bytes, ...encrypted.bytes]);
  }

  Uint8List _decrypt(Uint8List data, String password) {
    if (data.length <= 16) {
      throw Exception('This backup file looks corrupted.');
    }
    final enc.Key key = enc.Key(_deriveKey(password));
    final enc.IV iv = enc.IV(data.sublist(0, 16));
    final Uint8List cipherBytes = data.sublist(16);
    final enc.Encrypter encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final List<int> decrypted = encrypter.decryptBytes(enc.Encrypted(cipherBytes), iv: iv);
    return Uint8List.fromList(decrypted);
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
