import 'package:flutter/material.dart';
import '../widgets/conditional_banner.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/models/folder.dart';
import '../core/models/scan_document.dart';
import '../core/providers/folder_provider.dart';
import '../core/providers/scan_provider.dart';
import '../core/services/ocr_service.dart';
import '../core/services/share_service.dart';
import '../core/services/local_storage.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';
import '../widgets/document_tools_mixin.dart';
import '../widgets/edit_tray.dart';
import '../widgets/ink_board.dart';
import '../widgets/scan_preview_card.dart';
import '../core/services/engagement_service.dart';

class ScanDetailScreen extends StatefulWidget {
  const ScanDetailScreen({super.key, required this.documentId});
  final String documentId;

  @override
  State<ScanDetailScreen> createState() => _ScanDetailScreenState();
}

class _ScanDetailScreenState extends State<ScanDetailScreen>
    with SingleTickerProviderStateMixin, DocumentTools {
  late final ScanProvider _scanProvider;
  late final InkController _inkController;
  late final FolderProvider _folderProvider;
  late final OcrService _ocrService;
  final ShareService _shareService = ShareService();
  final LocalStorageService _localStorage = LocalStorageService();

  late TabController _tabController;
  int _currentPageIndex = 0;
  TrayEditMode _editMode = TrayEditMode.none;
  String? _lastAddedAnnotatePath;
  String? _lastAddedWatermarkText;
  String? _lastAddedStampId;

  @override
  void initState() {
    super.initState();
    _scanProvider = Provider.of<ScanProvider>(context, listen: false);
    _folderProvider = Provider.of<FolderProvider>(context, listen: false);
    _ocrService = OcrService();
    _inkController = InkController(onChange: _persistSignature);
    _scanProvider.setActiveScan(widget.documentId);
    EngagementService.instance.markScanDetailViewed();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() { if (mounted) setState(() {}); });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final doc = _document;
      if (doc != null) _inkController.seed(doc);
    });
  }

  Future<void> _persistSignature() async {
    final doc = _document;
    if (doc == null) return;
    await _scanProvider.setSignatureState(doc.id, _inkController.inks.values.toList(), _inkController.layers);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ocrService.dispose();
    super.dispose();
  }

  ScanDocument? get _document {
    for (final doc in _scanProvider.documents.value) {
      if (doc.id == widget.documentId) return doc;
    }
    return null;
  }

  // --- DocumentTools mixin wiring ---
  @override
  ScanProvider get scanProvider => _scanProvider;
  @override
  InkController get inkController => _inkController;
  @override
  LocalStorageService get localStorage => _localStorage;
  @override
  OcrService get ocrService => _ocrService;
  @override
  ShareService get shareService => _shareService;
  @override
  ScanDocument? get document => _document;
  @override
  int get currentPageIndex => _currentPageIndex;
  @override
  set editMode(TrayEditMode mode) => setState(() => _editMode = mode);
  @override
  void closeEditor() => _closeEditor();

  void _closeEditor() {
    if (_editMode == TrayEditMode.none) return;
    setState(() {
      _editMode = TrayEditMode.none;
      _inkController.setEditInk(null);
      _lastAddedAnnotatePath = null;
      _lastAddedWatermarkText = null;
      _lastAddedStampId = null;
    });
  }

  @override
  void onLayerAdded(TrayEditMode mode, String? identifier) {
    setState(() {
      switch (mode) {
        case TrayEditMode.annotate:
          _lastAddedAnnotatePath = identifier;
          break;
        case TrayEditMode.watermark:
          _lastAddedWatermarkText = identifier;
          break;
        case TrayEditMode.text:
        case TrayEditMode.note:
        case TrayEditMode.date:
        case TrayEditMode.checkbox:
        case TrayEditMode.seal:
          _lastAddedStampId = identifier;
          break;
        default:
          break;
      }
    });
  }

  // --- Screen-specific actions ---
  Future<void> _editTitle(ScanDocument document, AppLocalizations l10n) async {
    final controller = TextEditingController(text: document.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.renameDocumentTitle),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(l10n.commonSave)),
        ],
      ),
    );
    controller.dispose();
    if (newTitle != null && newTitle.trim().isNotEmpty) {
      await _scanProvider.renameDocument(document.id, newTitle);
    }
  }

  Future<void> _moveToFolder(ScanDocument document, AppLocalizations l10n) async {
    final folders = _folderProvider.folders.value;
    final chosenFolderId = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => _FolderPickerSheet(folders: folders),
    );
    if (chosenFolderId == null) return;
    await _folderProvider.addDocumentToFolder(chosenFolderId, document.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.movedToFolderMessage)));
  }

  Future<void> _delete(ScanDocument document, AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteScanTitle),
        content: Text(l10n.deleteScanMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.commonDelete)),
        ],
      ),
    );
    if (confirmed != true) return;
    await _scanProvider.deleteDocument(document.id);
    await _folderProvider.removeDocumentFromAllFolders(document.id);
    if (!mounted) return;
    context.pop();
  }

  Future<void> _share(ScanDocument document) async {
    if (!mounted) return;
    context.push('/export', extra: <String>[document.id]);
  }

  Future<void> _export(ScanDocument document) async {
    if (!mounted) return;
    context.push('/export', extra: <String>[document.id]);
  }

  void _copyOcrToClipboard(String text, AppLocalizations l10n) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).copiedToClipboard), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _shareOcrText(String text) async {
    try {
      await _shareService.shareText(text: text);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    final border = isDark ? AppColors.borderSubtleDark : AppColors.borderSubtleLight;

    return Scaffold(
      bottomNavigationBar: const ConditionalBanner(),
      backgroundColor: bg,
      body: ListenableBuilder(
        listenable: _scanProvider.documents,
        builder: (context, _) {
          final document = _document;
          if (document == null) {
            return SafeArea(
              child: Column(
                children: [
                  AppBar(backgroundColor: bg, elevation: 0),
                  Expanded(child: Center(child: Text(l10n.scanUnavailable))),
                ],
              ),
            );
          }

          return Column(
            children: [
              AppBar(
                backgroundColor: bg,
                elevation: 0,
                title: GestureDetector(
                  onTap: () => _editTitle(document, l10n),
                  child: Text(
                    document.title,
                    style: TextStyle(color: textPrimary, fontSize: AppTypography.title2Size),
                  ),
                ),
                actions: [
                  IconButton(
                    icon: Icon(document.isFavorite ? Icons.star : Icons.star_border, color: accent),
                    tooltip: AppLocalizations.of(context).favoriteTooltip,
                    onPressed: () => _scanProvider.toggleFavorite(document.id),
                  ),
                  IconButton(
                    icon: Icon(Icons.drive_file_move_outlined, color: textSecondary),
                    tooltip: l10n.moveToFolderTooltip,
                    onPressed: () => _moveToFolder(document, l10n),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: textSecondary),
                    tooltip: l10n.deleteTooltip,
                    onPressed: () => _delete(document, l10n),
                  ),
                ],
              ),
              Container(
                color: bg,
                child: TabBar(
                  controller: _tabController,
                  labelColor: accent,
                  unselectedLabelColor: textSecondary,
                  indicatorColor: accent,
                  tabs: const [
                    Tab(text: 'Image'),
                    Tab(text: 'OCR Text'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    Stack(
                      children: [
                        Positioned.fill(
                          child: ScanPreviewCard(
                            document: document,
                            pagePaths: document.pagePaths,
                            onPageChanged: (index) => setState(() => _currentPageIndex = index),
                            inkController: _inkController,
                            annotateLayers: document.annotateLayers,
                            editMode: _editMode,
                            autoSelectAnnotatePath: _lastAddedAnnotatePath,
                            autoSelectWatermarkText: _lastAddedWatermarkText,
                            autoSelectStampId: _lastAddedStampId,
                            onSignatureSelect: () => setState(() => _editMode = TrayEditMode.signature),
                            onAnnotateSelect: () => setState(() => _editMode = TrayEditMode.annotate),
                            onDoneEditing: _closeEditor,
                            onAnnotateLayerUpdate: (pageIndex, layer) {
                              final doc = _document;
                              if (doc != null) _scanProvider.updateAnnotateLayer(doc.id, layer);
                            },
                            onAnnotateThisPage: (pageIndex) => addAnnotateToPage(pageIndex),
                            onCopyAnnotateToAllPages: copyAnnotateToAllPages,
                            onClearAnnotatePage: clearAnnotatePage,
                            onClearAllAnnotateLayers: clearAllAnnotateLayers,
                            watermarkLayers: document.watermarkLayers,
                            onWatermarkSelect: () => setState(() => _editMode = TrayEditMode.watermark),
                            onWatermarkLayerUpdate: (pageIndex, layer) {
                              final doc = _document;
                              if (doc != null) _scanProvider.updateWatermarkLayer(doc.id, layer);
                            },
                            onCopyWatermarkToAllPages: copyWatermarkToAllPages,
                            onClearWatermarkPage: clearWatermarkPage,
                            onClearAllWatermarkLayers: clearAllWatermarkLayers,
                            stampLayers: document.stampLayers,
                            onStampSelect: (layer) => setState(() => _editMode = layer.kind == 'text' ? TrayEditMode.text : (layer.kind == 'note' ? TrayEditMode.note : (layer.kind == 'date' ? TrayEditMode.date : (layer.kind == 'checkbox' ? TrayEditMode.checkbox : TrayEditMode.seal)))),
                            onStampLayerUpdate: (pageIndex, layer) {
                              final doc = _document;
                              if (doc != null) _scanProvider.updateStampLayer(doc.id, layer);
                            },
                            onCopyStampToAllPages: copyStampToAllPages,
                            onClearStampPage: clearStampPage,
                            onClearAllStampLayers: clearAllStampLayers,
                            onEditFullscreen: () => context.push('/edit/${document.id}'),
                            pageTransforms: document.pageTransforms,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: border, width: 0.5)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              TextButton.icon(
                                onPressed: () => _copyOcrToClipboard(document.ocrText, l10n),
                                icon: const Icon(Icons.copy, size: 18),
                                label: Text(AppLocalizations.of(context).commonCopy),
                              ),
                              TextButton.icon(
                                onPressed: () => _shareOcrText(document.ocrText),
                                icon: const Icon(Icons.ios_share, size: 18),
                                label: Text(AppLocalizations.of(context).commonShare),
                              ),
                              TextButton.icon(
                                onPressed: () => _export(document),
                                icon: const Icon(Icons.file_download_outlined, size: 18),
                                label: Text(AppLocalizations.of(context).exportTitle),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: SelectableText(
                              document.ocrText.isEmpty ? l10n.noTextRecognized : document.ocrText,
                              style: TextStyle(color: textSecondary, fontSize: 15, height: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_tabController.index == 0)
              EditTray(
                compact: true,
                onMarkup: () { _closeEditor(); annotateCurrentPage(); },
                onSign: signFromTray,
                onWatermark: () { _closeEditor(); addWatermarkNow(); },
                onOcr: () { _closeEditor(); regionOcr(); },
                onConvert: () { _closeEditor(); exportDocument(); },
                onCompress: () { _closeEditor(); context.push('/export', extra: <String, dynamic>{'ids': <String>[document.id], 'format': 'jpg'}); },
                onRotate: () { _closeEditor(); rotatePage(); },
                onResize: () { _closeEditor(); resizePage(); },
                onPages: () { _closeEditor(); openPagesManager(); },
                onFilter: () { _closeEditor(); applyFilterToPage(); },
                onCrop: () { _closeEditor(); cropCurrentPage(); },
                onText: () { _closeEditor(); addStampNow('text'); },
                onNote: () { _closeEditor(); addStampNow('note'); },
                onDate: () { _closeEditor(); addStampNow('date'); },
                onCheckbox: () { _closeEditor(); addStampNow('checkbox'); },
                onSeal: () { _closeEditor(); addStampNow('seal'); },
                onRevert: document.pageTransforms[_currentPageIndex]?.isEmpty == false ? () { _closeEditor(); revertPage(); } : null,
                onPrint: () { _closeEditor(); printDocument(); },
                onEmail: () { _closeEditor(); emailDocument(); },
                onErase: () { _closeEditor(); erasePage(); },
                onFill: () { _closeEditor(); context.push('/edit/${document.id}', extra: <String, dynamic>{'fill': true}); },
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(color: bg, border: Border(top: BorderSide(color: border, width: 0.5))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      TextButton.icon(
                        onPressed: () => _share(document),
                        icon: const Icon(Icons.ios_share, size: 18),
                        label: Text(l10n.shareTooltip, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: accent)),
                      ),
                      TextButton.icon(
                        onPressed: () => _export(document),
                        icon: const Icon(Icons.file_download_outlined, size: 18),
                        label: Text(l10n.exportTooltip, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: accent)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FolderPickerSheet extends StatelessWidget {
  const _FolderPickerSheet({required this.folders});
  final List<Folder> folders;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.moveToFolderTooltip, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (folders.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(AppLocalizations.of(context).noFoldersYet),
              )
            else
              ...folders.map((folder) => ListTile(title: Text(folder.name), onTap: () => Navigator.of(context).pop(folder.id))),
          ],
        ),
      ),
    );
  }
}
