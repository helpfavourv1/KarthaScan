// A version-1 database (search index without tags) must upgrade to version 2
// with every document kept and tags searchable.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/models/scan_document.dart';
import 'package:katharscan/core/services/local_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('v1 database upgrades, keeps documents and finds tags', () async {
    final Directory tmp = Directory.systemTemp.createTempSync('db_upgrade_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => tmp.path,
    );

    final Database old = await databaseFactory.openDatabase(
      '${tmp.path}/katharscan.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (Database db, int v) async {
          await db.execute('''CREATE TABLE documents (
            id TEXT PRIMARY KEY, title TEXT NOT NULL, page_count INTEGER NOT NULL,
            page_paths TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
            ocr_text TEXT NOT NULL, thumbnail_path TEXT NOT NULL, tags TEXT NOT NULL,
            is_favorite INTEGER NOT NULL DEFAULT 0)''');
          await db.execute('CREATE TABLE folders (id TEXT PRIMARY KEY, name TEXT NOT NULL, document_ids TEXT NOT NULL, created_at TEXT NOT NULL)');
          await db.execute('CREATE VIRTUAL TABLE documents_fts USING fts5(id UNINDEXED, title, ocr_text)');
          await db.insert('documents', <String, Object?>{
            'id': 'a', 'title': 'Old scan', 'page_count': 1, 'page_paths': '["/x.jpg"]',
            'created_at': '2026-01-01T00:00:00.000', 'updated_at': '2026-01-01T00:00:00.000',
            'ocr_text': 'hello world', 'thumbnail_path': '/x.jpg', 'tags': '["invoice"]', 'is_favorite': 0,
          });
          await db.insert('documents_fts', <String, Object?>{'id': 'a', 'title': 'Old scan', 'ocr_text': 'hello world'});
        },
      ),
    );
    await old.close();

    final LocalStorageService storage = LocalStorageService();
    expect((await storage.getAllDocuments()).length, 1);
    expect((await storage.searchDocuments('invoice')).map((ScanDocument d) => d.id), <String>['a']);
    expect((await storage.searchDocuments('hello')).length, 1);

    final DateTime now = DateTime(2026, 2, 2);
    await storage.saveDocument(ScanDocument(
      id: 'b', title: 'New', pageCount: 1, pagePaths: const <String>['/y.jpg'],
      createdAt: now, updatedAt: now, ocrText: 'text', thumbnailPath: '/y.jpg',
      tags: const <String>['receipt'],
    ));
    expect((await storage.searchDocuments('receipt')).map((ScanDocument d) => d.id), <String>['b']);
    expect((await storage.getAllDocuments()).length, 2);
  });
}
