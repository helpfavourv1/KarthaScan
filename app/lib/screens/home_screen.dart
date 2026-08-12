// lib/screens/home_screen.dart
//
// Document list + folders + search bar. No ads. Clean UI. (Section 16
// file #34).
//
// NAVIGATION: uses go_router's context.push(...) — not
// Navigator.pushNamed(...), which is the plain-MaterialApp routing system
// and isn't how a GoRouter-based app (Section 16 file #43) actually
// navigates between top-level routes. Route paths used here
// (/scan/:id, /folder/:id, /settings, /export, /paywall) are the
// contract router.dart (Phase 6) must implement with matching GoRoute
// entries.
//
// STATE WIRING: Provider.of(context, listen:false) for DI +
// ListenableBuilder for reactivity — the MANDATORY pattern from
// constants.dart. No Consumer, no context.watch, no
// ChangeNotifierProvider.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/models/folder.dart';
import '../core/models/scan_document.dart';
import '../core/providers/folder_provider.dart';
import '../core/providers/scan_provider.dart';
import '../core/providers/settings_provider.dart';
import '../core/services/ocr_service.dart' show OcrScript;
import '../core/utils/constants.dart';
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

  late final ScanProvider _scanProvider;
  late final FolderProvider _folderProvider;
  late final SettingsProvider _settingsProvider;

  @override
  void initState() {
    super.initState();
    _scanProvider = Provider.of<ScanProvider>(context, listen: false);
    _folderProvider = Provider.of<FolderProvider>(context, listen: false);
    _settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
  }

  @override
  void dispose() {
    _searchController.dispose();
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
    final String ocrLanguage = _settingsProvider.settings.value.ocrLanguage;
    final OcrScript script = _ocrScriptFromSettingsValue(ocrLanguage);
    final ScanDocument? document =
        await _scanProvider.captureNewDocument(ocrScript: script);
    if (!mounted || document == null) return;
    context.push('/scan/${document.id}');
  }

  OcrScript _ocrScriptFromSettingsValue(String value) {
    for (final OcrScript script in OcrScript.values) {
      if (script.name == value) return script;
    }
    return OcrScript.latin;
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

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.bgPrimaryDark : AppColors.bgPrimaryLight;
    final Color surface = isDark ? AppColors.bgSecondaryDark : AppColors.bgSecondaryLight;
    final Color textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final Color accent = isDark ? AppColors.accentDark : AppColors.accentLight;
    final String localeCode = _settingsProvider.settings.value.language;

    return Scaffold(
      backgroundColor: bg,
      appBar: _selectionMode ? _buildSelectionAppBar(bg) : _buildDefaultAppBar(bg, textPrimary, textSecondary),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search your scans',
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
            Expanded(
              child: _searchResults != null
                  ? _buildSearchResults(localeCode)
                  : _buildDefaultContent(localeCode),
            ),
          ],
        ),
      ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton(
              backgroundColor: accent,
              onPressed: _onScanPressed,
              child: const Icon(Icons.camera_alt_outlined, color: Colors.white),
            ),
    );
  }

  PreferredSizeWidget _buildDefaultAppBar(Color bg, Color textPrimary, Color textSecondary) {
    return AppBar(
      backgroundColor: bg,
      elevation: 0,
      title: Text(
        'KatharScan',
        style: TextStyle(
          color: textPrimary,
          fontSize: AppTypography.title1Size,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: <Widget>[
        IconButton(
          icon: Icon(Icons.settings_outlined, color: textSecondary),
          tooltip: 'Settings',
          onPressed: () => context.push('/settings'),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(Color bg) {
    return AppBar(
      backgroundColor: bg,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelectionMode,
      ),
      title: Text('${_selectedIds.length} selected'),
      actions: <Widget>[
        IconButton(
          icon: const Icon(Icons.ios_share),
          tooltip: 'Batch export',
          onPressed: _selectedIds.isEmpty
              ? null
              // Batch export is Pro-gated per Section 19 — the actual
              // entitlement check happens in export_screen.dart, which
              // routes to paywall_screen.dart if needed. This screen just
              // hands off the selected IDs.
              : () => context.push('/export', extra: _selectedIds.toList()),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete',
          onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
        ),
      ],
    );
  }

  Widget _buildSearchResults(String localeCode) {
    final List<ScanDocument> results = _searchResults!;
    if (results.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        message: 'No scans match your search.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      itemCount: results.length,
      separatorBuilder: (BuildContext context, int index) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (BuildContext context, int index) => _scanTile(results[index], localeCode),
    );
  }

  Widget _buildDefaultContent(String localeCode) {
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
        final List<ScanDocument> documents = _scanProvider.documents.value;
        final List<Folder> folders = _folderProvider.folders.value;

        if (documents.isEmpty && folders.isEmpty) {
          return const EmptyState();
        }

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          children: <Widget>[
            if (folders.isNotEmpty) ...<Widget>[
              _sectionHeader('Folders'),
              ...folders.map(
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
            if (documents.isNotEmpty)
              ...<Widget>[
                _sectionHeader('Documents'),
                ...documents.map(
                  (ScanDocument doc) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: _scanTile(doc, localeCode),
                  ),
                ),
              ]
            else
              const EmptyState(),
          ],
        );
      },
    );
  }

  Widget _sectionHeader(String label) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
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
      onLongPress: _selectionMode ? null : () => _enterSelectionMode(document.id),
    );
  }
}
