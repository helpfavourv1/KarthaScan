import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/models/export_job.dart';
import 'screens/convert_screen.dart';
import 'screens/debug_logs_screen.dart';
import 'screens/export_screen.dart';
import 'screens/folder_screen.dart';
import 'screens/home_screen.dart';
import 'screens/manual_crop_screen.dart';
import 'screens/migration_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/paywall_screen.dart';
import 'screens/scan_detail_screen.dart';
import 'screens/full_screen_edit_screen.dart';
import 'screens/settings_screen.dart';

GoRouter buildRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
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
        path: '/edit/:id',
        builder: (BuildContext context, GoRouterState state) {
          final String id = state.pathParameters['id']!;
          return FullScreenEditScreen(documentId: id);
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
          final Object? extra = state.extra;
          List<String> documentIds = const <String>[];
          ExportFormat? initialFormat;
          if (extra is List<String>) {
            documentIds = extra;
          } else if (extra is Map<String, dynamic>) {
            documentIds = (extra['ids'] as List<String>?) ?? const <String>[];
            final String? formatName = extra['format'] as String?;
            if (formatName != null) {
              initialFormat = ExportFormat.values.firstWhere(
                (ExportFormat e) => e.name == formatName,
                orElse: () => ExportFormat.pdf,
              );
            }
          }
          return ExportScreen(documentIds: documentIds, initialFormat: initialFormat);
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
        path: '/convert',
        builder: (BuildContext context, GoRouterState state) {
          final String path = state.uri.queryParameters['path'] ?? '';
          final String type = state.uri.queryParameters['type'] ?? 'unknown';
          return ConvertScreen(sourcePath: path, sourceType: type);
        },
      ),
      GoRoute(
        path: '/debug-logs',
        builder: (BuildContext context, GoRouterState state) => const DebugLogsScreen(),
      ),
    ],
  );
}
