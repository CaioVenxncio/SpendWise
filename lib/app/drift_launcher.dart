import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../backup/expense_backup.dart';
import '../migration/migration_controller.dart';
import '../platform/platform_services.dart';
import '../repositories/expense_repository.dart';
import '../services/expense_storage.dart';
import '../widgets/app_frame.dart';
import '../widgets/migration_screen.dart';
import '../widgets/state_views.dart';
import 'app_config.dart';
import 'backend.dart';
import 'tab_coordinator.dart';

/// Builds the backend; replaceable in tests.
typedef BackendLoader = Future<AppBackend> Function();

/// Everything the SQLite launch needs from the app.
class DriftLaunchRequest {
  DriftLaunchRequest({
    required this.config,
    required this.services,
    required this.jsonStorage,
    required this.shellBuilder,
    this.tabs,
    this.clock,
    this.driftExecutor,
    this.backendLoader,
  });

  final AppConfig config;
  final PlatformServices services;
  final ExpenseStorage jsonStorage;

  /// Builds the expense app once the backend is ready.
  final Widget Function(AppBackend backend, MigrationController migration)
  shellBuilder;

  final TabCoordinator? tabs;
  final DateTime Function()? clock;
  final DriftExecutorFactory? driftExecutor;
  final BackendLoader? backendLoader;
}

/// Entry point used by `main()` only in Drift builds, so the default JSON
/// build can leave all SQLite code out.
Widget buildDriftLauncher(DriftLaunchRequest request) =>
    DriftLauncher(request: request);

enum _LaunchPhase { opening, failed, migration, ready }

/// Opens the SQLite backend and decides whether a migration must come
/// first. Never falls back to another store or an empty database.
class DriftLauncher extends StatefulWidget {
  const DriftLauncher({super.key, required this.request});

  final DriftLaunchRequest request;

  @override
  State<DriftLauncher> createState() => _DriftLauncherState();
}

class _DriftLauncherState extends State<DriftLauncher> {
  _LaunchPhase _phase = _LaunchPhase.opening;
  AppBackend? _backend;
  MigrationController? _migration;
  bool _disposed = false;

  DriftLaunchRequest get _r => widget.request;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    if (mounted) setState(() => _phase = _LaunchPhase.opening);
    await _release();
    try {
      final backend =
          await (_r.backendLoader?.call() ??
              AppBackend.openDrift(
                config: _r.config,
                platform: _r.services,
                jsonStorage: _r.jsonStorage,
                openExecutor: _r.driftExecutor ?? defaultDriftExecutor,
                clock: _r.clock,
              ));
      if (_disposed) {
        await backend.dispose();
        return;
      }
      final migration = MigrationController(
        backend,
        clock: _r.clock,
        tabs: _r.tabs,
      );
      await migration.refresh();
      if (_disposed) {
        migration.dispose();
        await backend.dispose();
        return;
      }
      _backend = backend;
      _migration = migration;
      setState(() {
        _phase = migration.phase == MigrationPhase.ready && migration.mayOpenApp
            ? _LaunchPhase.ready
            : _LaunchPhase.migration;
      });
    } catch (e) {
      debugPrint('Opening the SQLite backend failed: ${e.runtimeType}');
      if (!_disposed) setState(() => _phase = _LaunchPhase.failed);
    }
  }

  Future<void> _release() async {
    _migration?.dispose();
    _migration = null;
    final backend = _backend;
    _backend = null;
    await backend?.dispose();
  }

  Future<void> _exportJsonSource(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final storage = _r.jsonStorage;
      final text = encodeRawExport(
        RawExpenseData.fromStored(await storage.readStoredText()),
        exportedAt: DateTime.now(),
      );
      await _r.services.files.saveText(rawExportFileName(DateTime.now()), text);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Original data exported. It contains your financial data; keep '
            'it somewhere private.',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not export the original data.')),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _LaunchPhase.opening:
        return spendWiseMaterialApp(
          const Scaffold(body: LoadingView(label: 'Opening storage')),
        );
      case _LaunchPhase.failed:
        return spendWiseMaterialApp(
          Builder(
            builder: (context) => ErrorPage(
              title: 'Could not open the new storage',
              body:
                  'SpendWise did not open any other storage instead, so none '
                  'of your expenses are hidden or replaced. Nothing was '
                  'changed. Try again, or export your original data.',
              actions: [
                FilledButton(onPressed: _open, child: const Text('Try again')),
                if (_r.services.files.isSupported)
                  OutlinedButton(
                    onPressed: () => _exportJsonSource(context),
                    child: const Text('Export original data'),
                  ),
              ],
            ),
          ),
        );
      case _LaunchPhase.migration:
        return MultiProvider(
          providers: [
            Provider.value(value: _r.services),
            ChangeNotifierProvider<MigrationController>.value(
              value: _migration!,
            ),
          ],
          child: spendWiseMaterialApp(
            MigrationScreen(
              onContinue: () => setState(() => _phase = _LaunchPhase.ready),
            ),
          ),
        );
      case _LaunchPhase.ready:
        return _r.shellBuilder(_backend!, _migration!);
    }
  }
}
