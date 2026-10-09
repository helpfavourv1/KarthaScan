// test/data_safety_test.dart
//
// Regression tests for silent data loss:
//  - one bad stored filter index must not break loading a page transform
//  - when the database cannot be opened, saves must report failure instead
//    of pretending to succeed.
import 'package:flutter_test/flutter_test.dart';
import 'package:katharscan/core/models/folder.dart';
import 'package:katharscan/core/models/page_transform.dart';
import 'package:katharscan/core/models/scan_document.dart';
import 'package:katharscan/core/services/export_service.dart' show FilterType;
import 'package:katharscan/core/services/local_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PageTransform.fromJson', () {
    test('keeps a valid stored filter', () {
      final PageTransform transform = PageTransform.fromJson(<String, dynamic>{
        'filter': FilterType.grayscale.index,
      });
      expect(transform.filter, FilterType.grayscale);
    });

    test('falls back to no filter for an out-of-range index', () {
      final PageTransform tooBig =
          PageTransform.fromJson(<String, dynamic>{'filter': 999});
      final PageTransform negative =
          PageTransform.fromJson(<String, dynamic>{'filter': -3});
      expect(tooBig.filter, FilterType.none);
      expect(negative.filter, FilterType.none);
    });
  });

  group('LocalStorageService without a database', () {
    // In a unit test the platform database folder is not available, so the
    // service runs in its "database could not be opened" mode.
    final DateTime now = DateTime(2026, 1, 1);
    final ScanDocument document = ScanDocument(
      id: 'doc-1',
      title: 'Test',
      pageCount: 1,
      pagePaths: const <String>['page.jpg'],
      createdAt: now,
      updatedAt: now,
      ocrText: 'hello',
      thumbnailPath: 'page.jpg',
    );

    test('saving or deleting a document reports failure', () async {
      final LocalStorageService storage = LocalStorageService();
      expect(await storage.saveDocument(document), isFalse);
      expect(await storage.deleteDocument(document.id), isFalse);
    });

    test('saving or deleting a folder reports failure', () async {
      final LocalStorageService storage = LocalStorageService();
      final Folder folder = Folder(
        id: 'folder-1',
        name: 'Receipts',
        documentIds: const <String>[],
        createdAt: now,
      );
      expect(await storage.saveFolder(folder), isFalse);
      expect(await storage.deleteFolder(folder.id), isFalse);
    });
  });
}
