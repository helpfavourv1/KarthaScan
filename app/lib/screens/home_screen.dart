import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import '../core/models/folder.dart';
import '../core/models/scan_document.dart';
import '../core/providers/folder_provider.dart';
import '../core/providers/scan_provider.dart';
import '../core/providers/settings_provider.dart';
import '../core/services/share_service.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';
import '../widgets/empty_state.dart';
import '../widgets/folder_list_tile.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/services/ocr_service.dart';
import '../widgets/annotation_overlay.dart';
import '../widgets/scan_list_tile.dart';
import '../widgets/tool_tile.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedIds = <String>{};
  List<ScanDocument>? _searchResults;
  bool _selectionMode = false;
  int _selectedFilter = 0;
  final ShareService _shareService = ShareService();

  late final ScanProvider _scanProvider;
  late final FolderProvider _folderProvider;
  late final SettingsProvider _settingsProvider;

  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _scanProvider = Provider.of<ScanProvider>(context, listen: false);
    _folderProvider = Provider.of<FolderProvider>(context, listen: false);
    _settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    _initBannerAd();
  }

  void _initBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-3940256099942544/6300978111',
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('$ad loaded.');
          if (mounted) setState(() => _isAdLoaded = true);
        },
        onAdFailedToLoad: (ad, err) {
          debugPrint('BannerAd failed to load: $err');
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _onSearchChanged(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = null);
      return;
    }
    final List<ScanDocument> results = await _scanProvider.search(query);
    if (!mounted) return;
    setState(() => _searchResults = results);
  }

  Future<void> _onScanPressed() async {
    if (!mounted) return;
    context.push('/manual-crop');
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Create')),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) {
      await _folderProvider.createFolder(name.trim());
    }
  }

  // App Language picker
  Future<void> _pickLanguage() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => _LanguagePickerSheet(current: _settingsProvider.settings.value.language),
    );
    if (chosen != null) await _settingsProvider.setLanguage(chosen);
  }

  // Signature shortcut: let user pick document
  Future<void> _openSignatureShortcut() async {
    if (_scanProvider.documents.value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan a document first to add a signature.')),
      );
      return;
    }
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => _DocumentPickerSheet(documents: _scanProvider.documents.value),
    );
    if (selectedId != null && mounted) {
      context.push('/export', extra: <String>[selectedId]);
    }
  }

  // Batch export: show hint if no docs
  void _startBatchExport() {
    if (_scanProvider.documents.value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No documents to batch export. Scan some first.')),
      );
      return;
    }
    setState(() {
      _selectionMode = true;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _enterSelectionMode(String id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _deleteSelected() async {
    for (final id in _selectedIds.toList()) {
      await _scanProvider.deleteDocument(id);
      await _folderProvider.removeDocumentFromAllFolders(id);
    }
    _exitSelectionMode();
  }

  void _handleMenuAction(String action, ScanDocument document) {
    final l10n = AppLocalizations.of(context);
    switch (action) {
      case 'favorite':
        _scanProvider.toggleFavorite(document.id);
        break;
      case 'rename':
        _renameDocument(document, l10n);
        break;
      case 'folder':
        _moveToFolder(document, l10n);
        break;
      case 'tags':
        _addTags(document, l10n);
        break;
      case 'export':
        context.push('/export', extra: <String>[document.id]);
        break;
      case 'share':
        _shareDocument(document);
        break;
      case 'delete':
        _deleteDocument(document, l10n);
        break;
    }
  }

  Future<void> _renameDocument(ScanDocument document, AppLocalizations l10n) async {
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

  Future<void> _addTags(ScanDocument document, AppLocalizations l10n) async {
    final controller = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.addTagTitle),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(l10n.commonAdd)),
        ],
      ),
    );
    controller.dispose();
    final trimmed = tag?.trim() ?? '';
    if (trimmed.isEmpty) return;
    final updated = {...document.tags, trimmed}.toList();
    await _scanProvider.updateTags(document.id, updated);
  }

  Future<void> _shareDocument(ScanDocument document) async {
    try {
      await _shareService.shareFiles(filePaths: document.pagePaths);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).genericErrorMessage)),
      );
    }
  }

  Future<void> _deleteDocument(ScanDocument document, AppLocalizations l10n) async {
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
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    final localeCode = _settingsProvider.settings.value.language;

    return Scaffold(
      backgroundColor: bg,
      appBar: _selectionMode ? _buildSelectionAppBar(bg, l10n) : _buildDefaultAppBar(bg, textPrimary, textSecondary, accent, l10n),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: l10n.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppShape.textInputRadius),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            _buildFilterChips(),
            Expanded(
              child: _searchResults != null
                  ? _buildSearchResults(localeCode, l10n)
                  : _buildDefaultContent(localeCode, l10n),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _bannerAd != null && _isAdLoaded
          ? SafeArea(
              child: SizedBox(
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
            )
          : null,
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton(
              backgroundColor: accent,
              onPressed: _onScanPressed,
              child: const Icon(Icons.camera_alt_outlined, color: Colors.white),
            ),
    );
  }

  Widget _buildFilterChips() {
    final filters = <String>['All', 'Folders', 'Recent', 'Favorites'];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: filters.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isSelected = _selectedFilter == index;
          return GestureDetector(
            onTap: () => setState(() => _selectedFilter = index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? accent : surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                filters[index],
                style: TextStyle(
                  color: isSelected ? Colors.white : textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }


  Future<void> _pickDocumentForExport(String? formatHint) async {
    if (_scanProvider.documents.value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scan a document first.')));
      return;
    }
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => _DocumentPickerSheet(documents: _scanProvider.documents.value),
    );
    if (selectedId != null && mounted) {
      if (formatHint == null) {
        context.push('/export', extra: <String>[selectedId]);
      } else {
        context.push('/export', extra: <String, dynamic>{'ids': <String>[selectedId], 'format': formatHint});
      }
    }
  }

  Future<void> _openAnnotate() async {
    if (_scanProvider.documents.value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scan a document first.')));
      return;
    }
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => _DocumentPickerSheet(documents: _scanProvider.documents.value),
    );
    if (selectedId == null || !mounted) return;
    final doc = _scanProvider.documents.value.firstWhere((d) => d.id == selectedId);
    if (doc.pagePaths.isEmpty) return;

    final annotationKey = GlobalKey<AnnotationOverlayState>();
    final bytes = await showModalBottomSheet<Uint8List?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => _HomeAnnotationSheet(annotationKey: annotationKey),
    );
    if (bytes == null || !mounted) return;
    await _compositeOverlayOnPage(doc, 0, bytes);
  }

  Future<void> _openRegionOcr() async {
    if (_scanProvider.documents.value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scan a document first.')));
      return;
    }
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => _DocumentPickerSheet(documents: _scanProvider.documents.value),
    );
    if (selectedId == null || !mounted) return;
    final doc = _scanProvider.documents.value.firstWhere((d) => d.id == selectedId);
    if (doc.pagePaths.isEmpty) return;

    final rect = await showModalBottomSheet<Rect?>(
      context: context,
      isScrollControlled: true,
      builder: (c) => _HomeRegionSelectSheet(imagePath: doc.pagePaths.first),
    );
    if (rect == null || !mounted) return;

    try {
      final originalBytes = await File(doc.pagePaths.first).readAsBytes();
      final originalImage = img.decodeImage(originalBytes);
      if (originalImage == null) return;
      final x = rect.left.toInt().clamp(0, originalImage.width);
      final y = rect.top.toInt().clamp(0, originalImage.height);
      final w = rect.width.toInt().clamp(0, originalImage.width - x);
      final h = rect.height.toInt().clamp(0, originalImage.height - y);
      if (w <= 0 || h <= 0) return;
      final cropped = img.copyCrop(originalImage, x: x, y: y, width: w, height: h);
      final tempDir = await getTemporaryDirectory();
      final tempPath = p.join(tempDir.path, 'home_region_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await File(tempPath).writeAsBytes(Uint8List.fromList(img.encodeJpg(cropped)));
      final ocr = OcrService();
      final result = await ocr.recognizeText(imagePath: tempPath, script: OcrScript.latin);
      await ocr.dispose();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Extracted Text'),
          content: SelectableText(result.fullText.isEmpty ? 'No text found' : result.fullText),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
            TextButton(onPressed: () { Clipboard.setData(ClipboardData(text: result.fullText)); Navigator.pop(c); }, child: const Text('Copy')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Region OCR failed: $e')));
    }
  }

  Future<void> _compositeOverlayOnPage(ScanDocument doc, int pageIndex, Uint8List overlayBytes) async {
    try {
      final originalBytes = await File(doc.pagePaths[pageIndex]).readAsBytes();
      final originalImage = img.decodeImage(originalBytes);
      if (originalImage == null) return;
      var overlayImage = img.decodePng(overlayBytes);
      if (overlayImage == null) return;
      overlayImage = img.copyResize(overlayImage, width: originalImage.width, height: originalImage.height);
      final composite = img.compositeImage(originalImage, overlayImage);
      final finalBytes = Uint8List.fromList(img.encodeJpg(composite, quality: 95));
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(appDir.path, 'annotated_pages'));
      await dir.create(recursive: true);
      final newPath = p.join(dir.path, 'ann_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await File(newPath).writeAsBytes(finalBytes);
      final newPaths = List<String>.from(doc.pagePaths);
      newPaths[pageIndex] = newPath;
      await _scanProvider.updateDocumentPages(doc.id, newPaths);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Annotation saved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  PreferredSizeWidget _buildDefaultAppBar(Color bg, Color textPrimary, Color textSecondary, Color accent, AppLocalizations l10n) {
    return AppBar(
      backgroundColor: bg,
      elevation: 0,
      title: Text(
        l10n.appTitle,
        style: TextStyle(color: textPrimary, fontSize: AppTypography.title1Size, fontWeight: FontWeight.w700, letterSpacing: -0.6),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.translate_outlined),
          tooltip: 'App Language',
          onPressed: _pickLanguage,
        ),
        // Signature shortcut (kept)
        IconButton(
          icon: const Icon(Icons.draw_outlined),
          tooltip: 'Signature',
          onPressed: _openSignatureShortcut,
        ),
        // Batch export shortcut (kept)
        IconButton(
          icon: const Icon(Icons.select_all_outlined),
          tooltip: 'Batch Export',
          onPressed: _startBatchExport,
        ),
        IconButton(
          icon: const Icon(Icons.create_new_folder_outlined),
          tooltip: 'New Folder',
          onPressed: _createFolder,
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: l10n.settingsTooltip,
          onPressed: () => context.push('/settings'),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(Color bg, AppLocalizations l10n) {
    return AppBar(
      backgroundColor: bg,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelectionMode,
      ),
      title: Text(l10n.selectedCount(_selectedIds.length)),
      actions: [
        IconButton(
          icon: const Icon(Icons.ios_share),
          tooltip: l10n.batchExportTooltip,
          onPressed: _selectedIds.isEmpty ? null : () => context.push('/export', extra: _selectedIds.toList()),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: l10n.deleteTooltip,
          onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
        ),
      ],
    );
  }

  Widget _buildSearchResults(String localeCode, AppLocalizations l10n) {
    final results = _searchResults!;
    if (results.isEmpty) return const EmptyState(message: 'No scans match your search.');
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      itemCount: results.length,
      separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, index) => _scanTile(results[index], localeCode),
    );
  }

  Widget _buildDefaultContent(String localeCode, AppLocalizations l10n) {
    return ListenableBuilder(
      listenable: Listenable.merge([_scanProvider.documents, _scanProvider.isLoading, _folderProvider.folders]),
      builder: (context, _) {
        if (_scanProvider.isLoading.value) return const Center(child: CircularProgressIndicator());
        final allDocuments = _scanProvider.documents.value;
        final allFolders = _folderProvider.folders.value;

        if (_selectedFilter == 1) {
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            children: [
              if (allFolders.isNotEmpty) ...[
                _sectionHeader(l10n.foldersSectionHeader),
                ...allFolders.map((folder) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: FolderListTile(folder: folder, onTap: () => context.push('/folder/${folder.id}')),
                )),
              ] else
                const EmptyState(message: 'No folders yet. Tap the folder icon to create one.'),
            ],
          );
        }

        List<ScanDocument> documents = allDocuments;
        if (_selectedFilter == 3) {
          documents = allDocuments.where((d) => d.isFavorite).toList();
        }

        if (documents.isEmpty && allFolders.isEmpty) return const EmptyState();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  ToolTile(icon: PhosphorIconsRegular.highlighter, label: 'Annotate', onTap: _openAnnotate),
                  ToolTile(icon: PhosphorIconsRegular.pen, label: 'Sign', onTap: () => _pickDocumentForExport(null)),
                  ToolTile(icon: PhosphorIconsRegular.fileText, label: 'Convert', onTap: () => _pickDocumentForExport(null)),
                  ToolTile(icon: PhosphorIconsRegular.arrowsIn, label: 'Compress', onTap: () => _pickDocumentForExport('jpg')),
                  ToolTile(icon: PhosphorIconsRegular.scan, label: 'ID Copy', onTap: () => context.push('/manual-crop')),
                  ToolTile(icon: PhosphorIconsRegular.fileText, label: 'Batch Export', onTap: _startBatchExport),
                  ToolTile(icon: PhosphorIconsRegular.crop, label: 'Region OCR', onTap: _openRegionOcr),
                  ToolTile(icon: PhosphorIconsRegular.scan, label: 'Scan ID', onTap: () => context.push('/manual-crop')),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                children: [
            if (_selectedFilter != 1 && allFolders.isNotEmpty) ...[
              _sectionHeader(l10n.foldersSectionHeader),
              ...allFolders.map((folder) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: FolderListTile(folder: folder, onTap: () => context.push('/folder/${folder.id}')),
              )),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (_selectedFilter != 1 && documents.isNotEmpty) ...[
              _sectionHeader(l10n.documentsSectionHeader),
              ...documents.map((doc) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: _scanTile(doc, localeCode),
              )),
            ] else if (_selectedFilter == 3 && documents.isEmpty) ...[
              const EmptyState(message: 'No favorites yet. Tap the star icon on a document to add it.'),
            ],
            ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionHeader(String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Text(label, style: TextStyle(color: textSecondary, fontSize: AppTypography.footnoteSize, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
    );
  }

  Widget _scanTile(ScanDocument document, String localeCode) {
    final isSelected = _selectedIds.contains(document.id);
    return ScanListTile(
      document: document,
      localeCode: localeCode,
      isSelected: isSelected,
      onTap: _selectionMode ? () => _toggleSelection(document.id) : () => context.push('/scan/${document.id}'),
      onLongPress: _selectionMode ? null : () => _enterSelectionMode(document.id),
      onMenuAction: (action) => _handleMenuAction(action, document),
    );
  }
}

class _FolderPickerSheet extends StatelessWidget {
  const _FolderPickerSheet({required this.folders});
  final List<Folder> folders;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.only(topLeft: Radius.circular(AppShape.bottomSheetTopRadius), topRight: Radius.circular(AppShape.bottomSheetTopRadius))),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Move to Folder', style: TextStyle(color: textPrimary, fontSize: AppTypography.title1Size, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            if (folders.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.md), child: Text('No folders yet. Create one from the home screen.'))
            else
              ...folders.map((folder) => ListTile(title: Text(folder.name), trailing: Icon(Icons.folder_outlined, color: accent), onTap: () => Navigator.of(context).pop(folder.id))),
          ],
        ),
      ),
    );
  }
}

class _LanguagePickerSheet extends StatelessWidget {
  const _LanguagePickerSheet({required this.current});
  final String current;

  static const Map<String, String> _labels = {
    'en': 'English', 'es': 'Español', 'fr': 'Français', 'de': 'Deutsch', 'pt': 'Português',
    'ar': 'العربية', 'hi': 'हिन्दी', 'ja': '日本語', 'ko': '한국어', 'zh': '中文', 'he': 'עברית',
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.only(topLeft: Radius.circular(AppShape.bottomSheetTopRadius), topRight: Radius.circular(AppShape.bottomSheetTopRadius))),
        padding: const EdgeInsets.all(AppSpacing.md),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('App Language', style: TextStyle(color: textPrimary, fontSize: AppTypography.title1Size, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: AppLocales.supportedLanguageCodes.map((code) => ListTile(title: Text(_labels[code] ?? code, style: TextStyle(color: textPrimary)), trailing: code == current ? Icon(Icons.check, color: accent) : null, onTap: () => Navigator.of(context).pop(code))).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _DocumentPickerSheet extends StatelessWidget {
  const _DocumentPickerSheet({required this.documents});
  final List<ScanDocument> documents;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.only(topLeft: Radius.circular(AppShape.bottomSheetTopRadius), topRight: Radius.circular(AppShape.bottomSheetTopRadius))),
        padding: const EdgeInsets.all(AppSpacing.md),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select Document', style: TextStyle(color: textPrimary, fontSize: AppTypography.title1Size, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: documents.map((doc) => ListTile(
                    title: Text(doc.title, style: TextStyle(color: textPrimary)),
                    trailing: Icon(Icons.description_outlined, color: accent),
                    onTap: () => Navigator.of(context).pop(doc.id),
                  )).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _HomeAnnotationSheet extends StatelessWidget {
  const _HomeAnnotationSheet({required this.annotationKey});
  final GlobalKey<AnnotationOverlayState> annotationKey;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Annotate', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
            Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Container(decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)), child: AnnotationOverlay(key: annotationKey)))),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 12),
                  ElevatedButton(onPressed: () async { final bytes = await annotationKey.currentState?.exportPng(); if (context.mounted) Navigator.pop(context, bytes); }, child: const Text('Save')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeRegionSelectSheet extends StatefulWidget {
  const _HomeRegionSelectSheet({required this.imagePath});
  final String imagePath;

  @override
  State<_HomeRegionSelectSheet> createState() => _HomeRegionSelectSheetState();
}

class _HomeRegionSelectSheetState extends State<_HomeRegionSelectSheet> {
  Rect? _selectedRect;
  Offset? _startPos;
  img.Image? _originalImage;
  bool _loading = true;
  double _displayW = 0;
  double _displayH = 0;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      _originalImage = img.decodeImage(bytes);
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Select Region', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
            Expanded(
              child: _loading || _originalImage == null
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final imgW = _originalImage!.width;
                        final imgH = _originalImage!.height;
                        final aspect = imgW / imgH;
                        double displayW = constraints.maxWidth;
                        double displayH = displayW / aspect;
                        if (displayH > constraints.maxHeight) {
                          displayH = constraints.maxHeight;
                          displayW = displayH * aspect;
                        }
                        _displayW = displayW;
                        _displayH = displayH;
                        return Center(
                          child: SizedBox(
                            width: displayW,
                            height: displayH,
                            child: GestureDetector(
                              onPanStart: (d) => setState(() => _startPos = d.localPosition),
                              onPanUpdate: (d) {
                                if (_startPos == null) return;
                                setState(() {
                                  final left = _startPos!.dx < d.localPosition.dx ? _startPos!.dx : d.localPosition.dx;
                                  final top = _startPos!.dy < d.localPosition.dy ? _startPos!.dy : d.localPosition.dy;
                                  final width = (d.localPosition.dx - _startPos!.dx).abs();
                                  final height = (d.localPosition.dy - _startPos!.dy).abs();
                                  _selectedRect = Rect.fromLTWH(left, top, width, height);
                                });
                              },
                              child: Stack(
                                children: [
                                  Image.file(File(widget.imagePath), fit: BoxFit.fill),
                                  if (_selectedRect != null)
                                    Positioned.fromRect(
                                      rect: _selectedRect!,
                                      child: Container(decoration: BoxDecoration(border: Border.all(color: Colors.blue, width: 2), color: Colors.blue.withValues(alpha: 0.2))),
                                    ),
                                ],
                              ),
                            ),
                          ),
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
                    onPressed: _selectedRect == null || _displayW == 0 || _displayH == 0
                        ? null
                        : () {
                            final scaleX = _originalImage!.width / _displayW;
                            final scaleY = _originalImage!.height / _displayH;
                            Navigator.pop(context, Rect.fromLTRB(_selectedRect!.left * scaleX, _selectedRect!.top * scaleY, _selectedRect!.right * scaleX, _selectedRect!.bottom * scaleY));
                          },
                    child: const Text('Extract'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
