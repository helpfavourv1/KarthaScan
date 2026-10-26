import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_saver/file_saver.dart';
import 'dart:async' show unawaited;
import '../core/services/ad_pacing_service.dart';
import '../core/services/interstitial_ad_service.dart';
import '../widgets/conditional_banner.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import '../core/services/conversion_workspace.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;

import '../core/models/scan_document.dart';
import '../core/providers/scan_provider.dart';
import '../core/services/csv_to_pdf_service.dart';
import '../core/utils/csv_utils.dart';
import '../core/services/docx_parser_service.dart';
import '../core/services/export_service.dart';
import '../core/services/pdf_to_images_service.dart';
import '../core/services/ocr_service.dart';
import '../core/services/share_service.dart';
import '../core/services/downloads_service.dart';
import '../core/services/txt_to_pdf_service.dart';
import '../l10n/app_localizations.dart';

enum _TargetFormat { pdf, jpg, png, txt, docx, csv }
enum _ActionType { saveToDownloads, saveDoc, exportShare }

class ConvertScreen extends StatefulWidget {
  final String sourcePath;
  final String sourceType;
  const ConvertScreen({super.key, required this.sourcePath, required this.sourceType});

  @override
  State<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConversionCancelled implements Exception {
  const _ConversionCancelled();
}

class _ConvertScreenState extends State<ConvertScreen> {
  bool _cancelRequested = false;
  final ExportService _exportService = ExportService();
  _TargetFormat _target = _TargetFormat.pdf;
  _ActionType _action = _ActionType.exportShare;
  bool _isConverting = false;
  double _progress = 0.0;
  String _progressLabel = '';

  @override
  void initState() {
    super.initState();
    _action = _ActionType.saveToDownloads;
  }

  void _report(double value, String label) {
    if (!mounted) return;
    setState(() {
      _progress = value.clamp(0.0, 1.0);
      _progressLabel = label;
    });
  }

  bool _saveDocAllowed(_TargetFormat t) =>
      (t == _TargetFormat.jpg || t == _TargetFormat.png) && widget.sourceType != 'docx';

  bool _targetAllowed(_TargetFormat t) {
    // No artificial restrictions: every source can target every format.
    return true;
  }

  void _onTargetChanged(_TargetFormat newTarget) {
    setState(() {
      _target = newTarget;
      if (!_saveDocAllowed(newTarget) && _action == _ActionType.saveDoc) {
        _action = _ActionType.exportShare;
      }
    });
  }

  MimeType _getMimeType(String ext) {
    switch (ext) {
      case 'pdf': return MimeType.pdf;
      case 'docx': return MimeType.other;
      case 'csv': return MimeType.csv;
      case 'txt': return MimeType.text;
      case 'jpg': case 'jpeg': return MimeType.jpeg;
      case 'png': return MimeType.png;
      default: return MimeType.other;
    }
  }

  String _mimeTypeToString(MimeType type) {
    switch (type) {
      case MimeType.pdf: return 'application/pdf';
      case MimeType.jpeg: return 'image/jpeg';
      case MimeType.png: return 'image/png';
      case MimeType.text: return 'text/plain';
      case MimeType.csv: return 'text/csv';
      case MimeType.other: return 'application/octet-stream';
      default: return 'application/octet-stream';
    }
  }

  /// Removes leftovers from earlier conversions that no document uses.
  Future<void> _sweepOld() async {
    try {
      final used = <String>{};
      for (final d in Provider.of<ScanProvider>(context, listen: false).documents.value) {
        used.addAll(d.pagePaths);
        used.add(d.thumbnailPath);
      }
      await (await ConversionWorkspace.create()).sweep(keep: used);
    } catch (_) {}
  }

  Future<List<String>> _convert(ConversionJob job) async {
    final l10n = AppLocalizations.of(context);
    final String src = widget.sourcePath;
    final String type = widget.sourceType;
    _report(0.05, l10n.progressReading);
    final appDir = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(appDir.path, 'converted_docs'));
    await outDir.create(recursive: true);
    await _sweepOld();
    final ts = DateTime.now().microsecondsSinceEpoch;

    List<String> finalPaths = [];
    String? intermediatePdf;

    if (type == 'pdf') {
      if (_target == _TargetFormat.pdf) {
        _report(0.5, l10n.progressCopying);
        final out = p.join(outDir.path, 'conv_$ts.pdf');
        await File(src).copy(out);
        finalPaths.add(out);
      } else if (_target == _TargetFormat.csv) {
        _report(0.3, l10n.progressExtractingText);
        final pngs = await PdfToImagesService().convertToImages(src, outDir: job.dir.path, onProgress: (v, l) => _report(0.3 + v * 0.3, l));
        if (pngs.isNotEmpty) {
          final ocr = OcrService();
          final text = StringBuffer();
          try {
            for (int i = 0; i < pngs.length; i++) {
              if (_cancelRequested) throw const _ConversionCancelled();
              _report(0.6 + 0.39 * (i / pngs.length), l10n.progressExtractingText);
              final page = await ocr.recognizeTextAuto(imagePath: pngs[i]);
              if (text.isNotEmpty) text.writeln();
              text.write(page.fullText);
            }
          } finally {
            await ocr.dispose();
          }
          final out = p.join(outDir.path, 'conv_$ts.csv');
          await File(out).writeAsString(csvFromText(text.toString()));
          finalPaths.add(out);
        }
      } else if (_target == _TargetFormat.txt) {
        _report(0.3, l10n.progressRasterizing);
        final pngs = await PdfToImagesService().convertToImages(src, outDir: job.dir.path, onProgress: (v, l) => _report(0.3 + v * 0.4, l));
        final sb = StringBuffer();
        final ocr = OcrService();
        try {
          for (int i = 0; i < pngs.length; i++) {
            if (_cancelRequested) throw const _ConversionCancelled();
            _report(0.7 + 0.29 * (i / pngs.length), l10n.progressExtractingText);
            final r = await ocr.recognizeTextAuto(imagePath: pngs[i]);
            sb.writeln(r.fullText);
          }
        } finally {
          await ocr.dispose();
        }
        final out = p.join(outDir.path, 'conv_$ts.txt');
        await File(out).writeAsString(sb.toString());
        finalPaths.add(out);
      } else {
        intermediatePdf = src;
      }
    } else if (type == 'image') {
      if (_target == _TargetFormat.pdf) {
        _report(0.4, l10n.progressBuildingPdf);
        final pdf = pw.Document();
        final raw = await File(src).readAsBytes();
        final decodedRaw = img.decodeImage(raw);
        if (decodedRaw == null) throw Exception('Cannot decode image');
        // Phone photos carry a rotation flag; apply it so the result is upright.
        final decodedSrc = img.bakeOrientation(decodedRaw);
        final image = pw.MemoryImage(Uint8List.fromList(img.encodePng(decodedSrc)));
        pdf.addPage(pw.Page(build: (pw.Context context) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain))));
        final out = p.join(outDir.path, 'conv_$ts.pdf');
        await File(out).writeAsBytes(await pdf.save());
        finalPaths.add(out);
      } else if (_target == _TargetFormat.docx) {
        _report(0.5, l10n.progressBuildingDocx);
        final out = await _exportService.buildDocxFromImages([src], outDir.path, 'conv_$ts');
        finalPaths.add(out);
      } else if (_target == _TargetFormat.txt) {
        _report(0.3, l10n.progressExtractingText);
        final ocr = OcrService();
        final result = await ocr.recognizeTextAuto(imagePath: src);
        await ocr.dispose();
        final out = p.join(outDir.path, 'conv_$ts.txt');
        await File(out).writeAsString(result.fullText);
        finalPaths.add(out);
      } else if (_target == _TargetFormat.csv) {
        _report(0.3, l10n.progressExtractingText);
        final ocr = OcrService();
        final result = await ocr.recognizeTextAuto(imagePath: src);
        await ocr.dispose();
        final out = p.join(outDir.path, 'conv_$ts.csv');
        await File(out).writeAsString(csvFromText(result.fullText));
        finalPaths.add(out);
      } else {
        _report(0.4, l10n.progressDecodingImage);
        final bytes = await File(src).readAsBytes();
        final decodedRaw = img.decodeImage(bytes);
        if (decodedRaw == null) throw Exception('Cannot decode image');
        final decoded = img.bakeOrientation(decodedRaw);
        final outExt = _target == _TargetFormat.jpg ? 'jpg' : 'png';
        final out = p.join(outDir.path, 'conv_$ts.$outExt');
        final outBytes = _target == _TargetFormat.jpg ? img.encodeJpg(decoded) : img.encodePng(decoded);
        await File(out).writeAsBytes(Uint8List.fromList(outBytes));
        finalPaths.add(out);
      }
    } else if (type == 'txt') {
      if (_target == _TargetFormat.txt) {
        _report(0.5, l10n.progressCopying);
        final out = p.join(outDir.path, 'conv_$ts.txt');
        await File(src).copy(out);
        finalPaths.add(out);
      } else if (_target == _TargetFormat.csv) {
        _report(0.5, l10n.progressCopying);
        final out = p.join(outDir.path, 'conv_$ts.csv');
        await File(out).writeAsString(csvFromText(await File(src).readAsString()));
        finalPaths.add(out);
      } else if (_target == _TargetFormat.docx) {
        _report(0.5, l10n.progressBuildingDocx);
        final text = await File(src).readAsString();
        final out = await _exportService.buildDocxFromText(text, outDir.path, 'conv_$ts');
        finalPaths.add(out);
      } else {
        intermediatePdf = await TxtToPdfService().convertToPdf(src, outDir: job.dir.path, onProgress: (v, l) => _report(0.1 + v * 0.4, l));
      }
    } else if (type == 'csv') {
      if (_target == _TargetFormat.txt) {
        _report(0.5, l10n.progressCopying);
        final out = p.join(outDir.path, 'conv_$ts.txt');
        await File(src).copy(out);
        finalPaths.add(out);
      } else if (_target == _TargetFormat.csv) {
        _report(0.5, l10n.progressCopying);
        final out = p.join(outDir.path, 'conv_$ts.csv');
        await File(src).copy(out);
        finalPaths.add(out);
      } else if (_target == _TargetFormat.docx) {
        _report(0.5, l10n.progressBuildingDocx);
        final text = await File(src).readAsString();
        final out = await _exportService.buildDocxFromText(text, outDir.path, 'conv_$ts');
        finalPaths.add(out);
      } else {
        intermediatePdf = await CsvToPdfService().convertToPdf(src, outDir: job.dir.path, onProgress: (v, l) => _report(0.1 + v * 0.4, l));
      }
    } else if (type == 'docx') {
      if (_target == _TargetFormat.txt) {
        _report(0.4, l10n.progressExtractingText);
        finalPaths.add(await DocxParserService().convertToTxt(src, outDir: outDir.path));
      } else if (_target == _TargetFormat.csv) {
        _report(0.4, l10n.progressExtractingText);
        final txtPath = await DocxParserService().convertToTxt(src, outDir: job.dir.path);
        final content = await File(txtPath).readAsString();
        final out = p.join(outDir.path, 'conv_$ts.csv');
        await File(out).writeAsString(csvFromText(content));
        finalPaths.add(out);
      } else if (_target == _TargetFormat.docx) {
        _report(0.5, l10n.progressCopying);
        final out = p.join(outDir.path, 'conv_$ts.docx');
        await File(src).copy(out);
        finalPaths.add(out);
      } else {
        intermediatePdf = await DocxParserService().convertToPdf(src, outDir: job.dir.path);
      }
    }

    if (intermediatePdf != null) {
      if (_target == _TargetFormat.pdf) {
        _report(0.7, l10n.progressSaving);
        // The scratch folder is deleted when the job ends, so the PDF moves out of it.
        if (p.isWithin(job.dir.path, intermediatePdf)) {
          final String moved = p.join(outDir.path, 'conv_$ts.pdf');
          await File(intermediatePdf).copy(moved);
          finalPaths.add(moved);
        } else {
          finalPaths.add(intermediatePdf);
        }
      } else if (_target == _TargetFormat.docx) {
        _report(0.6, l10n.progressRasterizing);
        final pngs = await PdfToImagesService().convertToImages(intermediatePdf, outDir: job.dir.path, onProgress: (v, l) => _report(0.5 + v * 0.3, l));
        _report(0.9, l10n.progressBuildingDocx);
        final out = await _exportService.buildDocxFromImages(pngs, outDir.path, 'conv_$ts');
        finalPaths.add(out);
      } else {
        // One pass, one page at a time, straight to the requested format.
        final bool asJpg = _target == _TargetFormat.jpg;
        finalPaths = await PdfToImagesService().convertToImages(
          intermediatePdf,
          outDir: asJpg ? outDir.path : p.join(appDir.path, 'converted_images'),
          format: asJpg ? PageImageFormat.jpg : PageImageFormat.png,
          isCancelled: () => _cancelRequested,
          onProgress: (v, l) => _report(0.5 + v * 0.45, l),
        );
        if (_cancelRequested) throw const _ConversionCancelled();
      }
    }

    if (finalPaths.isEmpty) throw Exception('Conversion produced no files');
    _report(1.0, l10n.commonDone);
    return finalPaths;
  }

  Future<void> _run() async {
    _cancelRequested = false;
    setState(() {
      _isConverting = true;
      _progress = 0.0;
      _progressLabel = AppLocalizations.of(context).conversionStarting;
    });
    ConversionJob? job;
    try {
      final workspace = await ConversionWorkspace.create();
      job = await workspace.begin('convert');
      final paths = await _convert(job);
      if (!mounted) return;

      if (_action == _ActionType.saveToDownloads) {
        final dlService = DownloadsService();
        int savedCount = 0;
        String? lastError;
        for (final path in paths) {
          try {
            final file = File(path);
            final bytes = await file.readAsBytes();
            final ext = p.extension(path).replaceAll('.', '');
            final name = p.basenameWithoutExtension(path);
            final mime = _mimeTypeToString(_getMimeType(ext));
            await dlService.saveToDownloads(
              fileName: '$name.$ext',
              bytes: bytes,
              mimeType: mime,
            );
            savedCount++;
          } catch (e) {
            lastError = e.toString();
          }
        }
        if (!mounted) return;
        if (savedCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).saveToDownloadsAction), duration: const Duration(seconds: 2)),
          );
          context.pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${AppLocalizations.of(context).saveFailedPrefix} $lastError'), duration: const Duration(seconds: 4)),
          );
        }
      } else if (_action == _ActionType.saveDoc) {
        final provider = Provider.of<ScanProvider>(context, listen: false);
        final now = DateTime.now();
        final doc = ScanDocument(
          id: '${now.microsecondsSinceEpoch}',
          title: AppLocalizations.of(context).convertedDocTitle('${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'),
          pageCount: paths.length,
          pagePaths: paths,
          createdAt: now,
          updatedAt: now,
          ocrText: '',
          thumbnailPath: paths.first,
        );
        final success = await provider.importDocument(doc);
        if (!mounted) return;
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).savedAsNewDocument)));
          // Make the converted pages searchable (runs in the background).
          unawaited(provider.refreshOcrText(doc.id));
          await AdPacingService.instance.recordConvert();
          if (!mounted) return;
          context.pushReplacement('/scan/${doc.id}');
          unawaited(InterstitialAdService.instance.showAfterConvert());
        }
      } else {
        await ShareService().shareFiles(filePaths: paths);
        if (!mounted) return;
        Navigator.of(context).pop();
      }
    } on _ConversionCancelled {
      // The person stopped the conversion; nothing to report.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppLocalizations.of(context).conversionFailedPrefix}: $e')));
    } finally {
      await job?.dispose();
      if (mounted) setState(() => _isConverting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileName = p.basename(widget.sourcePath);
    final File sourceFile = File(widget.sourcePath);
    final fileSize = sourceFile.existsSync()
        ? (sourceFile.lengthSync() / 1024).toStringAsFixed(1)
        : '0.0';

    return Scaffold(
      bottomNavigationBar: const ConditionalBanner(),
      appBar: AppBar(title: Text(AppLocalizations.of(context).convertDocumentTitle)),
      body: SafeArea(
        child: _isConverting
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(value: _progress),
                      const SizedBox(height: 12),
                      Text('${(_progress * 100).round()}%', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(_progressLabel, style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _cancelRequested ? null : () => setState(() => _cancelRequested = true),
                        child: Text(AppLocalizations.of(context).commonCancel),
                      ),
                    ],
                  ),
                ),
              )
            : SingleChildScrollView(
                child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.insert_drive_file, size: 40),
                      title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('$fileSize KB • ${widget.sourceType.toUpperCase()}'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(AppLocalizations.of(context).convertToLabel, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _TargetFormat.values.map((f) {
                      final allowed = _targetAllowed(f);
                      return ChoiceChip(
                        label: Text(f.name.toUpperCase()),
                        selected: _target == f,
                        onSelected: allowed ? (_) => _onTargetChanged(f) : null,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  Text(AppLocalizations.of(context).actionLabel, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(AppLocalizations.of(context).saveToDownloadsAction),
                        selected: _action == _ActionType.saveToDownloads,
                        onSelected: (_) => setState(() => _action = _ActionType.saveToDownloads),
                      ),
                      ChoiceChip(
                        label: Text(AppLocalizations.of(context).saveAsNewDocumentAction),
                        selected: _action == _ActionType.saveDoc,
                        onSelected: _saveDocAllowed(_target) ? (_) => setState(() => _action = _ActionType.saveDoc) : null,
                      ),
                      ChoiceChip(
                        label: Text(AppLocalizations.of(context).exportAndShareAction),
                        selected: _action == _ActionType.exportShare,
                        onSelected: (_) => setState(() => _action = _ActionType.exportShare),
                      ),
                    ],
                  ),
                  if (!_saveDocAllowed(_target))
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        widget.sourceType == 'docx'
                            ? AppLocalizations.of(context).docxWarningMessage
                            : AppLocalizations.of(context).saveInsideAppWarning,
                        style: const TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _run,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: Text(AppLocalizations.of(context).commonConvert, style: TextStyle(fontSize: 18)),
                  ),
                ],
              ),
                ),
              ),
        ),
    );
  }
}
