import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import '../core/models/folder.dart';
import '../core/models/scan_document.dart';
import '../core/providers/folder_provider.dart';
import '../core/providers/scan_provider.dart';
import '../core/providers/settings_provider.dart';
import '../core/providers/theme_provider.dart';
import '../core/services/share_service.dart';
import '../core/utils/constants.dart';
import '../l10n/app_localizations.dart';
import '../widgets/empty_state.dart';
import '../widgets/folder_list_tile.dart';
import '../widgets/scan_list_tile.dart';

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
        title: Text(AppLocalizations.of(context).newFolderTitle),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context).commonCancel)),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(AppLocalizations.of(context).commonCreate)),
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

  // Batch export: show hint if no docs
  void _startBatchExport() {
    if (_scanProvider.documents.value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).batchExportEmptyMessage)),
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
      case 'edit':
        context.push('/scan/${document.id}');
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
            _buildUnifiedRow(),
            const SizedBox(height: 4),
            const _FeatureTicker(),
            const SizedBox(height: 4),
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
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              onPressed: _onScanPressed,
              child: const Icon(Icons.camera_alt_outlined, color: Colors.white),
            ),
    );
  }

  Widget _buildUnifiedRow() {
    const filters = <String>['All', 'Folders', 'Recent', 'Favorites'];
    return ListenableBuilder(
      listenable: _folderProvider.folders,
      builder: (context, _) {
        final allFolders = _folderProvider.folders.value;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
        final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
        final accent = isDark ? AppColors.accentDark : AppColors.accentLight;

        Widget chip({required String label, IconData? icon, bool filled = false, required VoidCallback onTap}) {
          return GestureDetector(
            onTap: onTap,
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: filled ? accent : surface,
                borderRadius: BorderRadius.circular(8),
                boxShadow: AppShadows.ambient,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: filled ? Colors.white : accent, size: 12),
                    const SizedBox(width: 3),
                  ],
                  Text(label, style: TextStyle(color: filled ? Colors.white : textPrimary, fontSize: 10, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (int i = 0; i < filters.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: chip(label: filters[i], filled: _selectedFilter == i, onTap: () => setState(() => _selectedFilter = i)),
                  ),
                ...allFolders.map((folder) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: chip(label: folder.name, icon: Icons.folder_outlined, onTap: () => context.push('/folder/${folder.id}')),
                    )),
                if (allFolders.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: chip(label: 'All Folders', icon: Icons.folder_open_outlined, filled: true, onTap: () => setState(() => _selectedFilter = 1)),
                  ),
                chip(label: 'Select Multiple', icon: Icons.checklist_rounded, filled: true, onTap: _startBatchExport),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAccentPicker() async {
    final picked = await showModalBottomSheet<AccentPalette>(
      context: context,
      builder: (ctx) => _AccentPickerSheet(current: _settingsProvider.settings.value.accentColor),
    );
    if (picked != null && mounted) {
      Provider.of<ThemeProvider>(context, listen: false).setAccentColor(picked.light);
    }
  }

  PreferredSizeWidget _buildDefaultAppBar(Color bg, Color textPrimary, Color textSecondary, Color accent, AppLocalizations l10n) {
    return AppBar(
      backgroundColor: bg,
      elevation: 0,
      titleSpacing: 0,
      title: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: AppTypography.title1Size, fontWeight: FontWeight.w800, letterSpacing: -0.8),
          children: <TextSpan>[
            TextSpan(text: 'Kathar', style: TextStyle(color: textPrimary)),
            TextSpan(text: 'Scan', style: TextStyle(color: accent)),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.translate_outlined),
          tooltip: AppLocalizations.of(context).homeLanguageTooltip,
          onPressed: _pickLanguage,
        ),
        IconButton(
          icon: const Icon(Icons.create_new_folder_outlined),
          tooltip: AppLocalizations.of(context).newFolderTooltip,
          onPressed: _createFolder,
        ),
        IconButton(
          icon: const Icon(Icons.palette_outlined),
          tooltip: AppLocalizations.of(context).accentColorTooltip,
          onPressed: _openAccentPicker,
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
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                children: [
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
            Text(AppLocalizations.of(context).moveToFolderTitle, style: TextStyle(color: textPrimary, fontSize: AppTypography.title1Size, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            if (folders.isEmpty)
              Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.md), child: Text(AppLocalizations.of(context).noFoldersYetHomeMessage))
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
            Text(AppLocalizations.of(context).appLanguageTitle, style: TextStyle(color: textPrimary, fontSize: AppTypography.title1Size, fontWeight: FontWeight.w600)),
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

class _AccentPickerSheet extends StatelessWidget {
  const _AccentPickerSheet({required this.current});
  final Color current;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(AppShape.bottomSheetTopRadius))),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context).accentColorTitle, style: TextStyle(color: textPrimary, fontSize: AppTypography.title1Size, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: kAccentPalettes.map((p) {
                final isSelected = p.light == current;
                return GestureDetector(
                  onTap: () => Navigator.of(context).pop(p),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: p.light,
                          shape: BoxShape.circle,
                          border: Border.all(color: isSelected ? textPrimary : Colors.transparent, width: 3),
                        ),
                        child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                      ),
                      const SizedBox(height: 6),
                      Text(p.name, style: TextStyle(color: textPrimary, fontSize: 11, fontWeight: FontWeight.w500)),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class _FeatureTicker extends StatefulWidget {
  const _FeatureTicker();

  @override
  State<_FeatureTicker> createState() => _FeatureTickerState();
}

class _FeatureTickerState extends State<_FeatureTicker> with SingleTickerProviderStateMixin {
  static const List<String> _features = <String>[
    'FREE UNLIMITED OCR',
    '100% ON-DEVICE PRIVACY',
    'NO ACCOUNT',
    'NO WATERMARKS',
    '21-TOOL EDIT SUITE',
    'NON-DESTRUCTIVE EDITING',
    'UNDO/REDO',
    'REVERT TO ORIGINAL',
    'TAP-TO-TYPE FILLING',
    'E-SIGN',
    'CUSTOM SEALS',
    'TEXT STAMPS',
    'NOTE STAMPS',
    'SEARCHABLE PDF',
    'REGION OCR',
    'AUTO-COPY OCR',
    'ID CARD MODE',
    'PASSPORT MODE',
    'GALLERY IMPORT',
    'PDF EXPORT',
    'WORD EXPORT',
    'JPG EXPORT',
    'PNG EXPORT',
    'BATCH EXPORT',
    'FOLDERS',
    'TAGS',
    'FAVORITES',
    'SEARCH',
    '12 LANGUAGES',
    'DARK MODE',
    'ACCENT THEMES',
    'DEVICE MIGRATION',
  ];

  static const Set<String> _highlighted = <String>{
    'FREE UNLIMITED OCR',
    '21-TOOL EDIT SUITE',
    'NON-DESTRUCTIVE EDITING',
    'SEARCHABLE PDF',
    'CUSTOM SEALS',
    'REVERT TO ORIGINAL',
    'E-SIGN',
    'BATCH EXPORT',
    'NO WATERMARKS',
    '100% ON-DEVICE PRIVACY',
    'TAP-TO-TYPE FILLING',
  };

  // Keep original speed. Do not increase without explicit approval.
  static const double _pxPerSecond = 32.0;

  late final AnimationController _controller;
  double _segmentWidth = 1;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 90));

    final tp = TextPainter(
      text: TextSpan(
        children: _spans(
          const Color(0xFF8E8E93),
          const Color(0xFF8E8E93),
          const Color(0xFF8E8E93),
          AppLocalizations.of(context),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    _segmentWidth = tp.width > 0 ? tp.width : 1;
    _controller.duration = Duration(milliseconds: (_segmentWidth / _pxPerSecond * 1000).round());
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<TextSpan> _spans(Color base, Color accent, Color separator, AppLocalizations l10n) {
    final baseStyle = TextStyle(
      color: base,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      height: 1.2,
      fontFamily: 'SF Pro Display',
    );
    final accentStyle = TextStyle(
      color: accent,
      fontSize: 16,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.5,
      height: 1.2,
      fontFamily: 'SF Pro Display',
    );
    final separatorStyle = TextStyle(
      color: separator,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
      height: 1.2,
    );

    final spans = <TextSpan>[];
    for (final feature in _features) {
      final localized = _localizeTickerFeature(feature, l10n);
      spans.add(TextSpan(
        text: '  $localized  ',
        style: _highlighted.contains(feature) ? accentStyle : baseStyle,
      ));
      spans.add(TextSpan(text: '•', style: separatorStyle));
    }
    return spans;
  }

  String _localizeTickerFeature(String feature, AppLocalizations l10n) {
    final map = <String, String Function()>{
      'FREE UNLIMITED OCR': () => l10n.tickerFreeUnlimitedOcr,
      '100% ON-DEVICE PRIVACY': () => l10n.ticker100OnDevicePrivacy,
      'NO ACCOUNT': () => l10n.tickerNoAccount,
      'NO WATERMARKS': () => l10n.tickerNoWatermarks,
      '21-TOOL EDIT SUITE': () => l10n.ticker21ToolEditSuite,
      'NON-DESTRUCTIVE EDITING': () => l10n.tickerNonDestructiveEditing,
      'UNDO/REDO': () => l10n.tickerUndoRedo,
      'REVERT TO ORIGINAL': () => l10n.tickerRevertToOriginal,
      'TAP-TO-TYPE FILLING': () => l10n.tickerTapToTypeFilling,
      'E-SIGN': () => l10n.tickerESign,
      'CUSTOM SEALS': () => l10n.tickerCustomSeals,
      'TEXT STAMPS': () => l10n.tickerTextStamps,
      'NOTE STAMPS': () => l10n.tickerNoteStamps,
      'SEARCHABLE PDF': () => l10n.tickerSearchablePdf,
      'REGION OCR': () => l10n.tickerRegionOcr,
      'AUTO-COPY OCR': () => l10n.tickerAutoCopyOcr,
      'ID CARD MODE': () => l10n.tickerIdCardMode,
      'PASSPORT MODE': () => l10n.tickerPassportMode,
      'GALLERY IMPORT': () => l10n.tickerGalleryImport,
      'PDF EXPORT': () => l10n.tickerPdfExport,
      'WORD EXPORT': () => l10n.tickerWordExport,
      'JPG EXPORT': () => l10n.tickerJpgExport,
      'PNG EXPORT': () => l10n.tickerPngExport,
      'BATCH EXPORT': () => l10n.tickerBatchExport,
      'FOLDERS': () => l10n.tickerFolders,
      'TAGS': () => l10n.tickerTags,
      'FAVORITES': () => l10n.tickerFavorites,
      'SEARCH': () => l10n.tickerSearch,
      '12 LANGUAGES': () => l10n.ticker12Languages,
      'DARK MODE': () => l10n.tickerDarkMode,
      'ACCENT THEMES': () => l10n.tickerAccentThemes,
      'DEVICE MIGRATION': () => l10n.tickerDeviceMigration,
    };
    return map[feature]?.call() ?? feature;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    final separator = textSecondary.withValues(alpha: 0.42);
    final l10n = AppLocalizations.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    if (reduceMotion && _controller.isAnimating) {
      _controller.stop();
    } else if (!reduceMotion && !_controller.isAnimating) {
      _controller.repeat();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
      child: Semantics(
        label: 'Feature ticker: ${_features.map((f) => _localizeTickerFeature(f, l10n)).join(', ')}',
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: surface.withValues(alpha: 0.2), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.08),
                offset: const Offset(0, 2),
                blurRadius: 8,
              ),
            ],
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? <Color>[
                      surface.withValues(alpha: 0.98),
                      surface.withValues(alpha: 0.88),
                    ]
                  : <Color>[
                      surface.withValues(alpha: 0.98),
                      bg.withValues(alpha: 0.42),
                    ],
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final double dx = -_controller.value * _segmentWidth;

                  Widget segment(double left) {
                    return Positioned(
                      left: left,
                      top: 0,
                      bottom: 0,
                      child: SizedBox(
                        width: _segmentWidth,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: RichText(
                            maxLines: 1,
                            softWrap: false,
                            text: TextSpan(children: _spans(textSecondary, accent, separator, l10n)),
                          ),
                        ),
                      ),
                    );
                  }

                  return Stack(
                    children: [
                      segment(dx),
                      segment(dx + _segmentWidth),
                      Positioned(
                        left: 0, top: 0, bottom: 0, width: 18,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [surface, surface.withValues(alpha: 0.0)],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0, top: 0, bottom: 0, width: 18,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerRight,
                                end: Alignment.centerLeft,
                                colors: [surface, surface.withValues(alpha: 0.0)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
