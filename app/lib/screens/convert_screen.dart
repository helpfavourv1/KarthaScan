import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
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
import '../core/services/pdf_to_images_service.dart';
import '../core/services/share_service.dart';
import '../core/services/txt_to_pdf_service.dart';

enum _TargetFormat { pdf, jpg, png }
enum _ActionType { saveDoc, exportShare }

class ConvertScreen extends StatefulWidget {
  final String sourcePath;
  final String sourceType;
  const ConvertScreen({super.key, required this.sourcePath, required this.sourceType});

  @override
  State<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConvertScreenState extends State<ConvertScreen> {
  _TargetFormat _target = _TargetFormat.pdf;
  _ActionType _action = _ActionType.exportShare;
  bool _isConverting = false;

  void _onTargetChanged(_TargetFormat newTarget) {
    setState(() {
      _target = newTarget;
      if (newTarget == _TargetFormat.pdf && _action == _ActionType.saveDoc) {
        _action = _ActionType.exportShare;
      }
    });
  }

  Future<List<String>> _convert() async {
    final String src = widget.sourcePath;
    final String type = widget.sourceType;
    final appDir = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(appDir.path, 'converted_docs'));
    await outDir.create(recursive: true);
    final ts = DateTime.now().microsecondsSinceEpoch;

    List<String> finalPaths = [];
    String? intermediatePdf;

    if (type == 'pdf') {
      if (_target == _TargetFormat.pdf) {
        final out = p.join(outDir.path, 'conv_$ts.pdf');
        await File(src).copy(out);
        finalPaths.add(out);
      } else {
        intermediatePdf = src;
      }
    } else if (type == 'image') {
      if (_target == _TargetFormat.pdf) {
        final pdf = pw.Document();
        final bytes = await File(src).readAsBytes();
        final image = pw.MemoryImage(bytes);
        pdf.addPage(pw.Page(build: (pw.Context context) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain))));
        final out = p.join(outDir.path, 'conv_$ts.pdf');
        await File(out).writeAsBytes(await pdf.save());
        finalPaths.add(out);
      } else {
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
      intermediatePdf = await TxtToPdfService().convertToPdf(src);
    } else if (type == 'csv') {
      intermediatePdf = await CsvToPdfService().convertToPdf(src);
    } else if (type == 'docx') {
      intermediatePdf = await DocxParserService().convertToPdf(src);
    }

    if (intermediatePdf != null) {
      if (_target == _TargetFormat.pdf) {
        finalPaths.add(intermediatePdf);
      } else {
        final pngs = await PdfToImagesService().convertToImages(intermediatePdf);
        if (_target == _TargetFormat.jpg) {
          final jpgs = <String>[];
          for (final pngPath in pngs) {
            final bytes = await File(pngPath).readAsBytes();
            final decoded = img.decodeImage(bytes);
            if (decoded != null) {
              final jpgPath = p.join(outDir.path, 'conv_${ts}_${p.basenameWithoutExtension(pngPath)}.jpg');
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
    return finalPaths;
  }

  Future<void> _run() async {
    setState(() => _isConverting = true);
    try {
      final paths = await _convert();
      if (!mounted) return;

      if (_action == _ActionType.saveDoc) {
        final provider = Provider.of<ScanProvider>(context, listen: false);
        final now = DateTime.now();
        final doc = ScanDocument(
          id: '${now.microsecondsSinceEpoch}',
          title: 'Converted ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved as new document')));
          context.pushReplacement('/scan/${doc.id}');
        }
      } else {
        await ShareService().shareFiles(filePaths: paths);
        if (!mounted) return;
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Conversion failed: $e')));
    } finally {
      if (mounted) setState(() => _isConverting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileName = p.basename(widget.sourcePath);
    final fileSize = (File(widget.sourcePath).lengthSync() / 1024).toStringAsFixed(1);
    final bool pdfTarget = _target == _TargetFormat.pdf;

    return Scaffold(
      appBar: AppBar(title: const Text('Convert Document')),
      body: _isConverting
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
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
                  const Text('Convert to:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _TargetFormat.values.map((f) {
                      return ChoiceChip(
                        label: Text(f.name.toUpperCase()),
                        selected: _target == f,
                        onSelected: (_) => _onTargetChanged(f),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  const Text('Action:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Save as new Document'),
                        selected: _action == _ActionType.saveDoc,
                        onSelected: pdfTarget ? null : (_) => setState(() => _action = _ActionType.saveDoc),
                      ),
                      ChoiceChip(
                        label: const Text('Export & Share'),
                        selected: _action == _ActionType.exportShare,
                        onSelected: (_) => setState(() => _action = _ActionType.exportShare),
                      ),
                    ],
                  ),
                  if (pdfTarget)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'PDFs are exported as files. To save inside the app, choose JPG or PNG.',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _run,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: const Text('Convert', style: TextStyle(fontSize: 18)),
                  ),
                ],
              ),
            ),
    );
  }
}
