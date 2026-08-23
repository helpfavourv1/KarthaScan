// lib/router.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/debug_logs_screen.dart';
import 'screens/export_screen.dart';
import 'screens/folder_screen.dart';
import 'screens/home_screen.dart';
import 'screens/manual_crop_screen.dart';
import 'screens/migration_screen.dart';
import 'screens/onboarding_screen.dart';
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
        path: '/onboarding',
        builder: (BuildContext context, GoRouterState state) => const OnboardingScreen(),
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
      GoRoute(
        path: '/debug-logs',
        builder: (BuildContext context, GoRouterState state) => const DebugLogsScreen(),
      ),
    ],
  );
}
