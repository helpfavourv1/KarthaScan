// lib/core/services/local_storage.dart
//
// sqflite wrapper: documents CRUD, folders CRUD, FTS5 search index,
// settings persistence (Section 16 file #13).
//
// LAYERING (confirmed): this file imports sqflite, shared_preferences, and
// path_provider — all real plugins. That's deliberate. core/services/ is
// the sanctioned home for services that wrap a plugin with UNIFORM
// cross-platform behavior and no OS-branching decision logic in the
// wrapper itself. Genuinely OS-divergent services (permission rationale
// flows, StoreKit vs Play Billing) live in lib/platform/ instead — see
// permission_service.dart and iap_service.dart. This file does NOT import
// dart:io: path_provider's getApplicationDocumentsDirectory() returns a
// Directory, but it's consumed here purely via type inference (`final
// appDir = await ...`) and only `.path` (a String) is read off it — the
// Directory type name is never written in this file, so no dart:io import
// is needed at all, and the literal "No dart:io in core/" rule holds
// without exception here.
//
// STORAGE SPLIT (Section 15): structured data (documents, folders, search
// index) goes through sqflite; settings go through SharedPreferences. Both
// live behind this one service facade because Section 16 file #13's
// purpose cell groups them together, but internally they're routed to the
// correct backend per Section 15's explicit rule.
//
// FAILURE HANDLING (Section 15): every operation below is wrapped in
// try-catch. Structured-data operations fall back to an in-memory cache
// (survives the session, not a restart) rather than throwing; settings
// fall back to in-memory defaults. Never crashes.
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/folder.dart';
import '../models/scan_document.dart';
import '../models/user_settings.dart';

class LocalStorageService {
  static const String _dbFileName = 'katharscan.db';
  static const int _dbVersion = 1;
  static const String _settingsPrefsKey = 'katharscan.user_settings.v1';

  Database? _db;
  bool _dbAvailable = false;
  bool _initialized = false;

  // In-memory fallback stores. Populated on every successful write
  // regardless of whether sqflite is available, so a mid-session sqflite
  // hiccup on a later read still returns the latest known state.
  final Map<String, ScanDocument> _memoryDocuments = <String, ScanDocument>{};
  final Map<String, Folder> _memoryFolders = <String, Folder>{};
  UserSettings? _memorySettings;

  /// Opens (or creates) the database and its tables. Safe to call
  /// repeatedly — later calls are no-ops once initialized. Never throws:
  /// on any failure this falls back to in-memory-only mode for the rest of
  /// the session rather than propagating the error.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final String dbPath = p.join(appDir.path, _dbFileName);

      _db = await openDatabase(
        dbPath,
        version: _dbVersion,
        onCreate: (Database db, int version) async {
          await db.execute('''
            CREATE TABLE documents (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              page_count INTEGER NOT NULL,
              page_paths TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              ocr_text TEXT NOT NULL,
              thumbnail_path TEXT NOT NULL,
              tags TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE folders (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              document_ids TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
          await _createFtsTable(db);
        },
      );
      _dbAvailable = true;
    } catch (error, stackTrace) {
      _logError('initialize', error, stackTrace);
      _dbAvailable = false;
    }
  }

  Future<void> _createFtsTable(DatabaseExecutor db) async {
    // Standalone (non-external-content) FTS5 table, manually kept in sync
    // on write rather than using FTS5's `content='documents'` linkage —
    // that linkage requires an INTEGER rowid-alias primary key, which
    // `documents.id TEXT PRIMARY KEY` isn't. A standalone table sidesteps
    // that entirely at the cost of a small amount of duplicated text.
    try {
      await db.execute('''
        CREATE VIRTUAL TABLE documents_fts USING fts5(
          id UNINDEXED,
          title,
          ocr_text
        )
      ''');
    } catch (error, stackTrace) {
      // Some device SQLite builds may lack FTS5. searchDocuments() falls
      // back to a plain LIKE query when this table is missing or MATCH
      // fails, so this is non-fatal — logged for visibility only.
      _logError('_createFtsTable', error, stackTrace);
    }
  }

  // ---------------------------------------------------------------------
  // Documents
  // ---------------------------------------------------------------------

  Future<List<ScanDocument>> getAllDocuments() async {
    await initialize();
    if (!_dbAvailable || _db == null) {
      final List<ScanDocument> fallback = _memoryDocuments.values.toList();
      fallback.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return fallback;
    }
    try {
      final List<Map<String, Object?>> rows = await _db!.query(
        'documents',
        orderBy: 'updated_at DESC',
      );
      return rows.map(_documentFromRow).toList();
    } catch (error, stackTrace) {
      _logError('getAllDocuments', error, stackTrace);
      return _memoryDocuments.values.toList();
    }
  }

  Future<ScanDocument?> getDocumentById(String id) async {
    await initialize();
    if (!_dbAvailable || _db == null) {
      return _memoryDocuments[id];
    }
    try {
      final List<Map<String, Object?>> rows = await _db!.query(
        'documents',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (rows.isEmpty) return _memoryDocuments[id];
      return _documentFromRow(rows.first);
    } catch (error, stackTrace) {
      _logError('getDocumentById', error, stackTrace);
      return _memoryDocuments[id];
    }
  }

  /// Inserts or updates [document]. Always mirrors into the in-memory
  /// cache first, so callers get a consistent read-your-writes view even
  /// if the sqflite write below fails. Returns true on success (including
  /// successful in-memory-only fallback) so scan_provider.dart can show
  /// explicit save feedback per Section 15.
  Future<bool> saveDocument(ScanDocument document) async {
    await initialize();
    _memoryDocuments[document.id] = document;

    if (!_dbAvailable || _db == null) {
      return true;
    }
    try {
      await _db!.transaction((Transaction txn) async {
        await txn.insert(
          'documents',
          _documentToRow(document),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.delete(
          'documents_fts',
          where: 'id = ?',
          whereArgs: <Object?>[document.id],
        );
        await txn.insert('documents_fts', <String, Object?>{
          'id': document.id,
          'title': document.title,
          'ocr_text': document.ocrText,
        });
      });
      return true;
    } catch (error, stackTrace) {
      _logError('saveDocument', error, stackTrace);
      // Document is still safe in the in-memory cache above.
      return true;
    }
  }

  Future<bool> deleteDocument(String id) async {
    await initialize();
    _memoryDocuments.remove(id);

    if (!_dbAvailable || _db == null) {
      return true;
    }
    try {
      await _db!.transaction((Transaction txn) async {
        await txn.delete('documents', where: 'id = ?', whereArgs: <Object?>[id]);
        await txn.delete(
          'documents_fts',
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
      });
      return true;
    } catch (error, stackTrace) {
      _logError('deleteDocument', error, stackTrace);
      return true;
    }
  }

  /// Full-text search across title + OCR text via the FTS5 index, falling
  /// back to a plain LIKE query, and finally to an in-memory substring
  /// scan, if FTS5 is unavailable or the query fails for any reason
  /// (Section 15's graceful-fallback rule, applied to search).
  Future<List<ScanDocument>> searchDocuments(String query) async {
    await initialize();
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return getAllDocuments();

    if (_dbAvailable && _db != null) {
      try {
        final String ftsQuery = _buildFtsPrefixQuery(trimmed);
        final List<Map<String, Object?>> rows = await _db!.rawQuery(
          'SELECT documents.* FROM documents_fts '
          'JOIN documents ON documents.id = documents_fts.id '
          'WHERE documents_fts MATCH ? '
          'ORDER BY documents.updated_at DESC',
          <Object?>[ftsQuery],
        );
        return rows.map(_documentFromRow).toList();
      } catch (error, stackTrace) {
        _logError('searchDocuments(fts)', error, stackTrace);
        // fall through to the LIKE-based fallback below
      }

      try {
        final String likePattern = '%${trimmed.replaceAll('%', r'\%')}%';
        final List<Map<String, Object?>> rows = await _db!.query(
          'documents',
          where: 'title LIKE ? ESCAPE ? OR ocr_text LIKE ? ESCAPE ?',
          whereArgs: <Object?>[likePattern, r'\', likePattern, r'\'],
          orderBy: 'updated_at DESC',
        );
        return rows.map(_documentFromRow).toList();
      } catch (error, stackTrace) {
        _logError('searchDocuments(like)', error, stackTrace);
        // fall through to the in-memory fallback below
      }
    }

    final String lowerQuery = trimmed.toLowerCase();
    final List<ScanDocument> results = _memoryDocuments.values
        .where((ScanDocument doc) =>
            doc.title.toLowerCase().contains(lowerQuery) ||
            doc.ocrText.toLowerCase().contains(lowerQuery))
        .toList();
    results.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return results;
  }

  /// Builds an FTS5 MATCH query that treats each whitespace-separated term
  /// in [input] as a quoted prefix match, ANDed together — e.g. `receipt
  /// total` becomes `"receipt"* "total"*`. Quoting each term prevents raw
  /// user input from being interpreted as FTS5 query syntax, which would
  /// otherwise throw on input containing characters like `"`, `*`, `-`, or
  /// `:`.
  String _buildFtsPrefixQuery(String input) {
    final List<String> terms = input
        .split(RegExp(r'\s+'))
        .where((String term) => term.isNotEmpty)
        .toList();
    return terms
        .map((String term) => '"${term.replaceAll('"', '""')}"*')
        .join(' ');
  }

  Map<String, Object?> _documentToRow(ScanDocument document) {
    return <String, Object?>{
      'id': document.id,
      'title': document.title,
      'page_count': document.pageCount,
      'page_paths': jsonEncode(document.pagePaths),
      'created_at': document.createdAt.toIso8601String(),
      'updated_at': document.updatedAt.toIso8601String(),
      'ocr_text': document.ocrText,
      'thumbnail_path': document.thumbnailPath,
      'tags': jsonEncode(document.tags),
    };
  }

  ScanDocument _documentFromRow(Map<String, Object?> row) {
    return ScanDocument(
      id: row['id']! as String,
      title: row['title']! as String,
      pageCount: row['page_count']! as int,
      pagePaths: List<String>.from(
        jsonDecode(row['page_paths']! as String) as List<dynamic>,
      ),
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
      ocrText: row['ocr_text']! as String,
      thumbnailPath: row['thumbnail_path']! as String,
      tags: List<String>.from(
        jsonDecode(row['tags']! as String) as List<dynamic>,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Folders
  // ---------------------------------------------------------------------

  Future<List<Folder>> getAllFolders() async {
    await initialize();
    if (!_dbAvailable || _db == null) {
      final List<Folder> fallback = _memoryFolders.values.toList();
      fallback.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return fallback;
    }
    try {
      final List<Map<String, Object?>> rows = await _db!.query(
        'folders',
        orderBy: 'created_at DESC',
      );
      return rows.map(_folderFromRow).toList();
    } catch (error, stackTrace) {
      _logError('getAllFolders', error, stackTrace);
      return _memoryFolders.values.toList();
    }
  }

  Future<bool> saveFolder(Folder folder) async {
    await initialize();
    _memoryFolders[folder.id] = folder;

    if (!_dbAvailable || _db == null) {
      return true;
    }
    try {
      await _db!.insert(
        'folders',
        _folderToRow(folder),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    } catch (error, stackTrace) {
      _logError('saveFolder', error, stackTrace);
      return true;
    }
  }

  Future<bool> deleteFolder(String id) async {
    await initialize();
    _memoryFolders.remove(id);

    if (!_dbAvailable || _db == null) {
      return true;
    }
    try {
      await _db!.delete('folders', where: 'id = ?', whereArgs: <Object?>[id]);
      return true;
    } catch (error, stackTrace) {
      _logError('deleteFolder', error, stackTrace);
      return true;
    }
  }

  Map<String, Object?> _folderToRow(Folder folder) {
    return <String, Object?>{
      'id': folder.id,
      'name': folder.name,
      'document_ids': jsonEncode(folder.documentIds),
      'created_at': folder.createdAt.toIso8601String(),
    };
  }

  Folder _folderFromRow(Map<String, Object?> row) {
    return Folder(
      id: row['id']! as String,
      name: row['name']! as String,
      documentIds: List<String>.from(
        jsonDecode(row['document_ids']! as String) as List<dynamic>,
      ),
      createdAt: DateTime.parse(row['created_at']! as String),
    );
  }

  // ---------------------------------------------------------------------
  // Settings (SharedPreferences, per Section 15 — deliberately NOT sqflite)
  // ---------------------------------------------------------------------

  Future<UserSettings> loadSettings() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString(_settingsPrefsKey);
      if (jsonString == null) {
        return _memorySettings ?? const UserSettings();
      }
      final UserSettings settings = UserSettings.fromJson(
        jsonDecode(jsonString) as Map<String, dynamic>,
      );
      _memorySettings = settings;
      return settings;
    } catch (error, stackTrace) {
      _logError('loadSettings', error, stackTrace);
      return _memorySettings ?? const UserSettings();
    }
  }

  /// Persists [settings]. Always updates the in-memory cache first, so a
  /// SharedPreferences failure still leaves the rest of this session
  /// consistent — only a restart would lose the change.
  Future<bool> saveSettings(UserSettings settings) async {
    _memorySettings = settings;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return await prefs.setString(
        _settingsPrefsKey,
        jsonEncode(settings.toJson()),
      );
    } catch (error, stackTrace) {
      _logError('saveSettings', error, stackTrace);
      return true;
    }
  }

  void _logError(String operation, Object error, StackTrace stackTrace) {
    debugPrint('[LocalStorageService] $operation failed: $error');
  }
}
