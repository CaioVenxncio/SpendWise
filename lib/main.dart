import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app_config.dart';
import 'app/backend.dart';
import 'app/drift_launcher.dart';
import 'app/tab_coordinator.dart';
import 'migration/migration_controller.dart';
import 'pages/home_page.dart';
import 'platform/platform_services.dart';
import 'providers/expense_provider.dart';
import 'providers/storage_persistence.dart';
import 'services/expense_storage.dart';
import 'widgets/app_frame.dart';

export 'pages/home_page.dart' show HomePage;

/// True only in builds made with `--dart-define=SPENDWISE_BACKEND=drift`.
/// A compile-time constant, so the default build drops all SQLite code.
const kDriftBackendBuild =
    String.fromEnvironment('SPENDWISE_BACKEND') == 'drift';

void main() => runApp(
  const SpendWiseApp(
    driftLauncher: kDriftBackendBuild ? buildDriftLauncher : null,
  ),
);

class SpendWiseApp extends StatefulWidget {
  const SpendWiseApp({
    super.key,
    this.storage,
    this.clock,
    this.platform,
    this.config,
    this.driftExecutor,
    this.backendLoader,
    this.driftLauncher,
  });

  /// Overrides the default shared_preferences storage, e.g. in tests.
  final ExpenseStorage? storage;

  /// Overrides the current time used for the monthly total, e.g. in tests.
  final DateTime Function()? clock;

  /// Overrides browser services (locks, files, persistence), e.g. in tests.
  final PlatformServices? platform;

  /// Overrides the build configuration (`--dart-define` values).
  final AppConfig? config;

  /// Overrides how the SQLite database is opened, e.g. in tests.
  final DriftExecutorFactory? driftExecutor;

  /// Overrides opening the Drift backend entirely, e.g. in tests.
  final BackendLoader? backendLoader;

  /// Provides the SQLite launch screen; `null` in builds without SQLite.
  final Widget Function(DriftLaunchRequest request)? driftLauncher;

  @override
  State<SpendWiseApp> createState() => _SpendWiseAppState();
}

class _SpendWiseAppState extends State<SpendWiseApp> {
  late final PlatformServices _services;
  AppConfig? _config;
  String? _configError;
  ExpenseStorage? _jsonStorage;
  AppBackend? _jsonBackend;
  TabCoordinator? _tabs;

  @override
  void initState() {
    super.initState();
    _services = widget.platform ?? PlatformServices.current();
    try {
      final config = widget.config ?? AppConfig.fromEnvironment();
      config.validate();
      if (config.backend == StorageBackend.drift &&
          widget.driftLauncher == null) {
        throw const AppConfigException(
          'This build does not include the SQLite backend.',
        );
      }
      _config = config;
      final storage =
          widget.storage ??
          SharedPreferencesExpenseStorage(
            lock: _services.lock,
            namespace: config.namespace,
            rawStorage: _services.rawStorage,
          );
      _jsonStorage = storage;
      _tabs = TabCoordinator(
        channel: _services.tabs,
        config: config,
        watchedStorageKeys: storage.watchKeys,
      );
      if (config.backend == StorageBackend.json) {
        _jsonBackend = AppBackend.json(config, storage);
      }
    } on AppConfigException catch (e) {
      _configError = e.message;
    }
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _configError;
    if (error != null) {
      // Fail closed: no storage is opened for an invalid configuration.
      return spendWiseMaterialApp(
        ErrorPage(
          title: 'SpendWise cannot start with this configuration',
          body: '$error\n\nNo data was opened or changed.',
        ),
      );
    }
    final json = _jsonBackend;
    if (json != null) {
      return AppShell(
        backend: json,
        services: _services,
        clock: widget.clock,
        tabs: _tabs,
      );
    }
    return widget.driftLauncher!(
      DriftLaunchRequest(
        config: _config!,
        services: _services,
        jsonStorage: _jsonStorage!,
        tabs: _tabs,
        clock: widget.clock,
        driftExecutor: widget.driftExecutor,
        backendLoader: widget.backendLoader,
        shellBuilder: (backend, migration) => AppShell(
          backend: backend,
          services: _services,
          clock: widget.clock,
          migration: migration,
          tabs: _tabs,
        ),
      ),
    );
  }
}

/// The expense app on top of an opened [AppBackend].
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.backend,
    required this.services,
    this.clock,
    this.migration,
    this.tabs,
  });

  final AppBackend backend;
  final PlatformServices services;
  final DateTime Function()? clock;
  final MigrationController? migration;
  final TabCoordinator? tabs;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: services),
        Provider.value(value: backend),
        ChangeNotifierProvider(
          create: (_) => StoragePersistence(services.persistence),
        ),
        if (migration != null)
          ChangeNotifierProvider<MigrationController>.value(value: migration!),
        if (tabs != null)
          ChangeNotifierProvider<TabCoordinator>.value(value: tabs!),
        ChangeNotifierProvider(
          create: (_) {
            final provider = ExpenseProvider(
              repository: backend.repository,
              clock: clock,
            )..loadExpenses();
            if (backend.config.backend == StorageBackend.json) {
              // Another tab (any version) wrote the JSON data this tab
              // shows: pause edits here until the user reloads.
              final sub = tabs?.sourceChanges.listen(
                (_) => provider.markExternalChange(),
              );
              provider.onDispose = () => sub?.cancel();
            }
            return provider;
          },
        ),
      ],
      child: spendWiseMaterialApp(const HomePage()),
    );
  }
}
