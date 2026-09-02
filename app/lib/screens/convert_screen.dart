import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:async' show unawaited;
import '../core/services/ad_pacing_service.dart';
import '../core/services/interstitial_ad_service.dart';
import '../widgets/conditional_banner.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;

import '../core/models/scan_document.dart';
import '../core/providers/scan_provider.dart';
import '../core/services/csv_to_pdf_service.dart';
import '../core/services/docx_parser_service.dart';
import '../core/services/export_service.dart';
import '../core/services/pdf_to_images_service.dart';
import '../core/services/share_service.dart';
import '../core/services/txt_to_pdf_service.dart';
import '../l10n/app_localizations.dart';

enum _TargetFormat { pdf, jpg, png, txt, docx }
enum _ActionType { saveDoc, exportShare }

class ConvertScreen extends StatefulWidget {
  final String sourcePath;
  final String sourceType;
  const ConvertScreen({super.key, required this.sourcePath, required this.sourceType});

  @override
  State<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConvertScreenState extends State<ConvertScreen> {
  final ExportService _exportService = ExportService();
  _TargetFormat _target = _TargetFormat.pdf;
  _ActionType _action = _ActionType.exportShare;
  bool _isConverting = false;
  double _progress = 0.0;
  String _progressLabel = '';

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
    final type = widget.sourceType;
    if (t == _TargetFormat.txt) return type == 'txt' || type == 'csv' || type == 'docx';
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

  Future<List<String>> _convert() async {
    final l10n = AppLocalizations.of(context);
    final String src = widget.sourcePath;
    final String type = widget.sourceType;
    _report(0.05, l10n.progressReading);
    final appDir = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(appDir.path, 'converted_docs'));
    await outDir.create(recursive: true);
    final ts = DateTime.now().microsecondsSinceEpoch;

    List<String> finalPaths = [];
    String? intermediatePdf;

    if (type == 'pdf') {
      if (_target == _TargetFormat.pdf) {
        _report(0.5, l10n.progressCopying);
        final out = p.join(outDir.path, 'conv_$ts.pdf');
        await File(src).copy(out);
        finalPaths.add(out);
      } else {
        intermediatePdf = src;
      }
    } else if (type == 'image') {
      if (_target == _TargetFormat.pdf) {
        _report(0.4, l10n.progressBuildingPdf);
        final pdf = pw.Document();
        final bytes = await File(src).readAsBytes();
        final image = pw.MemoryImage(bytes);
        pdf.addPage(pw.Page(build: (pw.Context context) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain))));
        final out = p.join(outDir.path, 'conv_$ts.pdf');
        await File(out).writeAsBytes(await pdf.save());
        finalPaths.add(out);
      } else if (_target == _TargetFormat.docx) {
        _report(0.5, l10n.progressBuildingDocx);
        final out = await _exportService.buildDocxFromImages([src], outDir.path, 'conv_$ts');
        finalPaths.add(out);
      } else {
        _report(0.4, l10n.progressDecodingImage);
        final bytes = await File(src).readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) throw Exception('Cannot decode image');
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
      } else if (_target == _TargetFormat.docx) {
        _report(0.5, l10n.progressBuildingDocx);
        final text = await File(src).readAsString();
        final out = await _exportService.buildDocxFromText(text, outDir.path, 'conv_$ts');
        finalPaths.add(out);
      } else {
        intermediatePdf = await TxtToPdfService().convertToPdf(src, onProgress: (v, l) => _report(0.1 + v * 0.4, l));
      }
    } else if (type == 'csv') {
      if (_target == _TargetFormat.txt) {
        _report(0.5, l10n.progressCopying);
        final out = p.join(outDir.path, 'conv_$ts.txt');
        await File(src).copy(out);
        finalPaths.add(out);
      } else if (_target == _TargetFormat.docx) {
        _report(0.5, l10n.progressBuildingDocx);
        final text = await File(src).readAsString();
        final out = await _exportService.buildDocxFromText(text, outDir.path, 'conv_$ts');
        finalPaths.add(out);
      } else {
        intermediatePdf = await CsvToPdfService().convertToPdf(src, onProgress: (v, l) => _report(0.1 + v * 0.4, l));
      }
    } else if (type == 'docx') {
      if (_target == _TargetFormat.txt) {
        _report(0.4, l10n.progressExtractingText);
        finalPaths.add(await DocxParserService().convertToTxt(src));
      } else if (_target == _TargetFormat.docx) {
        _report(0.5, l10n.progressCopying);
        final out = p.join(outDir.path, 'conv_$ts.docx');
        await File(src).copy(out);
        finalPaths.add(out);
      } else {
        intermediatePdf = await DocxParserService().convertToPdf(src);
      }
    }

    if (intermediatePdf != null) {
      if (_target == _TargetFormat.pdf) {
        _report(0.7, l10n.progressSaving);
        finalPaths.add(intermediatePdf);
      } else if (_target == _TargetFormat.docx) {
        _report(0.6, l10n.progressRasterizing);
        final pngs = await PdfToImagesService().convertToImages(intermediatePdf, onProgress: (v, l) => _report(0.5 + v * 0.3, l));
        _report(0.9, l10n.progressBuildingDocx);
        final out = await _exportService.buildDocxFromImages(pngs, outDir.path, 'conv_$ts');
        finalPaths.add(out);
      } else {
        final pngs = await PdfToImagesService().convertToImages(intermediatePdf, onProgress: (v, l) => _report(0.5 + v * 0.4, l));
        if (_target == _TargetFormat.jpg) {
          final jpgs = <String>[];
          for (int i = 0; i < pngs.length; i++) {
            _report(0.9 + 0.09 * (i / pngs.length), l10n.progressEncodingPage(i + 1, pngs.length));
            final bytes = await File(pngs[i]).readAsBytes();
            final decoded = img.decodeImage(bytes);
            if (decoded != null) {
              final jpgPath = p.join(outDir.path, 'conv_${ts}_${p.basenameWithoutExtension(pngs[i])}.jpg');
              await File(jpgPath).writeAsBytes(Uint8List.fromList(img.encodeJpg(decoded)));
              jpgs.add(jpgPath);
            }
          }
          finalPaths = jpgs;
        } else {
          finalPaths = pngs;
        }
      }
    }

    if (finalPaths.isEmpty) throw Exception('Conversion produced no files');
    _report(1.0, l10n.commonDone);
    return finalPaths;
  }

  Future<void> _run() async {
    setState(() {
      _isConverting = true;
      _progress = 0.0;
      _progressLabel = AppLocalizations.of(context).conversionStarting;
    });
    try {
      final paths = await _convert();
      if (!mounted) return;

      if (_action == _ActionType.saveDoc) {
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppLocalizations.of(context).conversionFailedPrefix}: $e')));
    } finally {
      if (mounted) setState(() => _isConverting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileName = p.basename(widget.sourcePath);
    final fileSize = (File(widget.sourcePath).lengthSync() / 1024).toStringAsFixed(1);

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
