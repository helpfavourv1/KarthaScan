// lib/router.dart
//
// GoRouter: home → scan detail → folder → settings → export → migration
// → paywall (Section 16 file #43).
//
// Route paths here are the contract every Phase 5 screen's context.push()
// call was written against — see each screen's file header for the paths
// it depends on. Changing a path here without updating the corresponding
// push() calls (and vice versa) breaks navigation silently at runtime,
// not at compile time, since go_router paths are plain strings, not
// checked references.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/export_screen.dart';
import 'screens/folder_screen.dart';
import 'screens/home_screen.dart';
import 'screens/manual_crop_screen.dart';
import 'screens/migration_screen.dart';
import 'screens/paywall_screen.dart';
import 'screens/scan_detail_screen.dart';
import 'screens/settings_screen.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/scan/:id',
        builder: (BuildContext context, GoRouterState state) {
          final String id = state.pathParameters['id']!;
          return ScanDetailScreen(documentId: id);
        },
      ),
      GoRoute(
        path: '/folder/:id',
        builder: (BuildContext context, GoRouterState state) {
          final String id = state.pathParameters['id']!;
          return FolderScreen(folderId: id);
        },
      ),
      GoRoute(
        path: '/settings',
        builder: (BuildContext context, GoRouterState state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/export',
        // Populated by every context.push('/export', extra: <String>[...])
        // call site (home_screen.dart batch select, scan_detail_screen.dart
        // single-document export) — always a List<String> of document ids,
        // never encoded in the path itself.
        builder: (BuildContext context, GoRouterState state) {
          final List<String> documentIds = (state.extra as List<String>?) ?? const <String>[];
          return ExportScreen(documentIds: documentIds);
        },
      ),
      GoRoute(
        path: '/migration',
        builder: (BuildContext context, GoRouterState state) => const MigrationScreen(),
      ),
      GoRoute(
        path: '/manual-crop',
        builder: (BuildContext context, GoRouterState state) => const ManualCropScreen(),
      ),
      GoRoute(
        path: '/paywall',
        builder: (BuildContext context, GoRouterState state) => const PaywallScreen(),
      ),
    ],
  );
}
