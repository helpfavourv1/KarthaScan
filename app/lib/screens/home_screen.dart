// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import '../core/models/folder.dart';
import '../core/models/scan_document.dart';
import '../core/providers/folder_provider.dart';
import '../core/providers/scan_provider.dart';
import '../core/providers/settings_provider.dart';
import '../core/services/debug_log_service.dart';
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
  int _selectedFilter = 0; // 0=All, 1=Folders, 2=Recent, 3=Favorites

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
          if (mounted) {
            setState(() => _isAdLoaded = true);
          }
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
    DebugLogService().log('HOME', 'FAB tapped → routing to /manual-crop');
    if (!mounted) return;
    context.push('/manual-crop');
  }

  Future<void> _createFolder() async {
    final TextEditingController controller = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) {
      await _folderProvider.createFolder(name.trim());
    }
  }


  Future<void> _pickOcrLanguage() async {
    final String? chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext context) => _OcrLanguagePickerSheet(
        current: _settingsProvider.settings.value.ocrLanguage,
      ),
    );
    if (chosen != null) {
      await _settingsProvider.setOcrLanguage(chosen);
    }
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
    for (final String id in _selectedIds.toList()) {
      await _scanProvider.deleteDocument(id);
      await _folderProvider.removeDocumentFromAllFolders(id);
    }
    _exitSelectionMode();
  }

  void _handleMenuAction(String action, ScanDocument document) {
    final AppLocalizations l10n = AppLocalizations.of(context);
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
    final TextEditingController controller = TextEditingController(text: document.title);
    final String? newTitle = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.renameDocumentTitle),
        content: TextField(controller: controller, autofocus: true),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(controller.text), child: Text(l10n.commonSave)),
        ],
      ),
    );
    controller.dispose();
    if (newTitle != null && newTitle.trim().isNotEmpty) {
      await _scanProvider.renameDocument(document.id, newTitle);
    }
  }

  Future<void> _moveToFolder(ScanDocument document, AppLocalizations l10n) async {
    final List<Folder> folders = _folderProvider.folders.value;
    final String? chosenFolderId = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext context) => _FolderPickerSheet(folders: folders),
    );
    if (chosenFolderId == null) return;
    await _folderProvider.addDocumentToFolder(chosenFolderId, document.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.movedToFolderMessage)),
    );
  }

  Future<void> _addTags(ScanDocument document, AppLocalizations l10n) async {
    final TextEditingController controller = TextEditingController();
    final String? tag = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.addTagTitle),
        content: TextField(controller: controller, autofocus: true),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(controller.text), child: Text(l10n.commonAdd)),
        ],
      ),
    );
    controller.dispose();
    final String trimmed = tag?.trim() ?? '';
    if (trimmed.isEmpty) return;
    final List<String> updated = <String>{...document.tags, trimmed}.toList();
    await _scanProvider.updateTags(document.id, updated);
  }

  Future<void> _shareDocument(ScanDocument document) async {
    // Since ShareService needs a BuildContext, we'll just navigate to export/share
    context.push('/export', extra: <String>[document.id]);
  }

  Future<void> _deleteDocument(ScanDocument document, AppLocalizations l10n) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.deleteScanTitle),
        content: Text(l10n.deleteScanMessage),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.commonDelete)),
        ],
      ),
    );
    if (confirmed != true) return;
    await _scanProvider.deleteDocument(document.id);
    await _folderProvider.removeDocumentFromAllFolders(document.id);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final Color textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    final String localeCode = _settingsProvider.settings.value.language;

    return Scaffold(
      backgroundColor: bg,
      appBar: _selectionMode
          ? _buildSelectionAppBar(bg, l10n)
          : _buildDefaultAppBar(bg, textPrimary, textSecondary, l10n),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
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
            // Filter Chips
            _buildFilterChips(),
            // Expanded Content
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
    final List<String> filters = <String>['All', 'Folders', 'Recent', 'Favorites'];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: filters.length,
        separatorBuilder: (BuildContext context, int index) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final bool isSelected = _selectedFilter == index;
          return GestureDetector(
            onTap: () => setState(() => _selectedFilter = index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                filters[index],
                style: TextStyle(
                  color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
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

  PreferredSizeWidget _buildDefaultAppBar(
    Color bg,
    Color textPrimary,
    Color textSecondary,
    AppLocalizations l10n,
  ) {
    return AppBar(
      backgroundColor: bg,
      elevation: 0,
      title: Text(
        l10n.appTitle,
        style: TextStyle(
          color: textPrimary,
          fontSize: AppTypography.title1Size,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: <Widget>[
        IconButton(
          icon: Icon(Icons.language_outlined, color: textSecondary),
          tooltip: 'Language',
          onPressed: _pickOcrLanguage,
        ),
        IconButton(
          icon: Icon(Icons.create_new_folder_outlined, color: textSecondary),
          tooltip: 'New Folder',
          onPressed: _createFolder,
        ),
        IconButton(
          icon: Icon(Icons.settings_outlined, color: textSecondary),
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
      actions: <Widget>[
        IconButton(
          icon: const Icon(Icons.ios_share),
          tooltip: l10n.batchExportTooltip,
          onPressed: _selectedIds.isEmpty
              ? null
              : () => context.push('/export', extra: _selectedIds.toList()),
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
    final List<ScanDocument> results = _searchResults!;
    if (results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        message: l10n.noSearchResults,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      itemCount: results.length,
      separatorBuilder: (BuildContext context, int index) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (BuildContext context, int index) => _scanTile(results[index], localeCode),
    );
  }

  Widget _buildDefaultContent(String localeCode, AppLocalizations l10n) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        _scanProvider.documents,
        _scanProvider.isLoading,
        _folderProvider.folders,
      ]),
      builder: (BuildContext context, Widget? _) {
        if (_scanProvider.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        final List<ScanDocument> allDocuments = _scanProvider.documents.value;
        final List<Folder> allFolders = _folderProvider.folders.value;

        // Filter based on selected chip
        List<ScanDocument> documents = allDocuments;
        if (_selectedFilter == 1) {
          // Folders: show only folders
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            children: <Widget>[
              if (allFolders.isNotEmpty) ...<Widget>[
                _sectionHeader(l10n.foldersSectionHeader),
                ...allFolders.map(
                  (Folder folder) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: FolderListTile(
                      folder: folder,
                      onTap: () => context.push('/folder/${folder.id}'),
                    ),
                  ),
                ),
              ] else
                const EmptyState(message: 'No folders yet. Tap the folder icon to create one.'),
            ],
          );
        } else if (_selectedFilter == 2) {
          // Recent: sort by updatedAt (already sorted by storage)
          documents = allDocuments;
        } else if (_selectedFilter == 3) {
          // Favorites: filter by isFavorite
          documents = allDocuments.where((ScanDocument d) => d.isFavorite).toList();
        }

        if (documents.isEmpty && allFolders.isEmpty) {
          return const EmptyState();
        }

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          children: <Widget>[
            if (_selectedFilter != 1 && allFolders.isNotEmpty) ...<Widget>[
              _sectionHeader(l10n.foldersSectionHeader),
              ...allFolders.map(
                (Folder folder) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: FolderListTile(
                    folder: folder,
                    onTap: () => context.push('/folder/${folder.id}'),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (_selectedFilter != 1 && documents.isNotEmpty) ...<Widget>[
              _sectionHeader(l10n.documentsSectionHeader),
              ...documents.map(
                (ScanDocument doc) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: _scanTile(doc, localeCode),
                ),
              ),
            ] else if (_selectedFilter == 3 && documents.isEmpty) ...<Widget>[
              const EmptyState(message: 'No favorites yet. Tap the star icon on a document to add it.'),
            ],
          ],
        );
      },
    );
  }

  Widget _sectionHeader(String label) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Text(
        label,
        style: TextStyle(
          color: textSecondary,
          fontSize: AppTypography.footnoteSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _scanTile(ScanDocument document, String localeCode) {
    final bool isSelected = _selectedIds.contains(document.id);
    return ScanListTile(
      document: document,
      localeCode: localeCode,
      isSelected: isSelected,
      onTap: _selectionMode
          ? () => _toggleSelection(document.id)
          : () => context.push('/scan/${document.id}'),
      onLongPress:
          _selectionMode ? null : () => _enterSelectionMode(document.id),
      onMenuAction: (String action) => _handleMenuAction(action, document),
    );
  }
}

class _FolderPickerSheet extends StatelessWidget {
  const _FolderPickerSheet({required this.folders});

  final List<Folder> folders;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppShape.bottomSheetTopRadius),
            topRight: Radius.circular(AppShape.bottomSheetTopRadius),
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Move to Folder',
              style: TextStyle(
                color: textPrimary,
                fontSize: AppTypography.title1Size,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (folders.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text('No folders yet. Create one from the home screen.'),
              )
            else
              ...folders.map(
                (Folder folder) => ListTile(
                  title: Text(folder.name),
                  trailing: Icon(Icons.folder_outlined, color: accent),
                  onTap: () => Navigator.of(context).pop(folder.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LanguagePickerSheet extends StatelessWidget {
  const _LanguagePickerSheet({required this.current});

  final String current;

  static const Map<String, String> _labels = <String, String>{
    'en': 'English',
    'es': 'Español',
    'fr': 'Français',
    'de': 'Deutsch',
    'pt': 'Português',
    'ar': 'العربية',
    'hi': 'हिन्दी',
    'ja': '日本語',
    'ko': '한국어',
    'zh': '中文',
    'he': 'עברית',
  };

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppShape.bottomSheetTopRadius),
            topRight: Radius.circular(AppShape.bottomSheetTopRadius),
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'App Language',
              style: TextStyle(
                color: textPrimary,
                fontSize: AppTypography.title1Size,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ...AppLocales.supportedLanguageCodes.map(
              (String code) => ListTile(
                title: Text(_labels[code] ?? code, style: TextStyle(color: textPrimary)),
                trailing: code == current ? Icon(Icons.check, color: accent) : null,
                onTap: () => Navigator.of(context).pop(code),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OcrLanguagePickerSheet extends StatelessWidget {
  const _OcrLanguagePickerSheet({required this.current});

  final String current;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;

    final Map<String, String> labels = <String, String>{
      'latin': 'Latin (default)',
      'chinese': 'Chinese',
      'devanagari': 'Devanagari (Hindi)',
      'japanese': 'Japanese',
      'korean': 'Korean',
    };

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppShape.bottomSheetTopRadius),
            topRight: Radius.circular(AppShape.bottomSheetTopRadius),
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'OCR Language',
              style: TextStyle(
                color: textPrimary,
                fontSize: AppTypography.title1Size,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ...labels.keys.map(
              (String key) => ListTile(
                title: Text(labels[key]!, style: TextStyle(color: textPrimary)),
                trailing: key == current ? Icon(Icons.check, color: accent) : null,
                onTap: () => Navigator.of(context).pop(key),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
