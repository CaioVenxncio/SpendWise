import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../data/drift/connection.dart';
import '../data/drift/database.dart';
import '../migration/json_to_drift_migration.dart';
import '../platform/platform_services.dart';
import '../repositories/drift_expense_repository.dart';
import '../repositories/expense_repository.dart';
import '../repositories/json_expense_repository.dart';
import '../services/expense_storage.dart';
import 'app_config.dart';

/// Opens the SQLite executor for [name]; replaceable in tests.
typedef DriftExecutorFactory = QueryExecutor Function(
  String name,
  void Function(WebStorageReport report) onWebResult,
);

QueryExecutor defaultDriftExecutor(
  String name,
  void Function(WebStorageReport report) onWebResult,
) => openSpendWiseConnection(name: name, onWebResult: onWebResult);

/// How the SQLite database is stored, as far as known.
enum StorageSafety {
  /// Browser storage that persists and is coordinated across tabs.
  ok,

  /// Persistent, but tabs are not coordinated: use one tab only.
  singleTabOnly,

  /// Not persistent: everything is lost when the page closes.
  temporary,

  /// A database file on a native platform (not a browser).
  native,

  /// A browser storage mode this version does not recognise.
  unknown,
}

extension StorageSafetyRules on StorageSafety {
  /// Whether a migration may run. Fails closed for anything not known to
  /// be persistent and coordinated: a migration into temporary storage
  /// would be lost, and uncoordinated tabs could interleave writes.
  bool get allowsMigration =>
      this == StorageSafety.ok || this == StorageSafety.native;
}

/// [isWeb] defaults to the current platform; tests pass it explicitly.
StorageSafety storageSafetyOf(
  WebStorageReport? report, {
  bool isWeb = kIsWeb,
}) => switch (report?.implementation) {
  null => isWeb ? StorageSafety.unknown : StorageSafety.native,
  'inMemory' => StorageSafety.temporary,
  'unsafeIndexedDb' => StorageSafety.singleTabOnly,
  'opfsShared' || 'opfsLocks' || 'sharedIndexedDb' => StorageSafety.ok,
  _ => StorageSafety.unknown,
};

/// What a browser storage mode means for the user.
String describeStorageMode(String? implementation) => switch (implementation) {
  'opfsShared' =>
    'Origin-private file system, shared by all tabs through one worker. '
        'Persistent and coordinated.',
  'opfsLocks' =>
    'Origin-private file system with cross-tab locks (needs the page to be '
        'cross-origin isolated). Persistent and coordinated.',
  'sharedIndexedDb' =>
    'IndexedDB inside a shared worker. Persistent and coordinated; slower '
        'than the file system modes.',
  'unsafeIndexedDb' =>
    'IndexedDB without coordination between tabs. Using SpendWise in '
        'several tabs at once can lose changes.',
  'inMemory' =>
    'Memory only (for example in a private window). Everything is lost when '
        'the tab closes.',
  null => 'Not a browser: a database file on this device.',
  _ => 'Unrecognised storage mode "$implementation".',
};

/// The opened storage for one app session.
class AppBackend {
  AppBackend._({
    required this.config,
    required this.jsonStorage,
    required this.repository,
    this.database,
    this.migration,
    this.storageReport,
  });

  final AppConfig config;

  /// The JSON store: the active store for [StorageBackend.json], and the
  /// read-only migration source for [StorageBackend.drift].
  final ExpenseStorage jsonStorage;

  final ExpenseRepository repository;

  final SpendWiseDatabase? database;

  final JsonToDriftMigration? migration;

  final WebStorageReport? storageReport;

  StorageSafety get storageSafety => config.backend == StorageBackend.json
      ? StorageSafety.ok
      : storageSafetyOf(storageReport);

  Future<void> dispose() async => database?.close();

  /// JSON backend: synchronous, nothing to initialize.
  static AppBackend json(AppConfig config, ExpenseStorage storage) =>
      AppBackend._(
        config: config,
        jsonStorage: storage,
        repository: JsonExpenseRepository(storage),
      );

  /// Opens the SQLite backend and checks that the database works.
  ///
  /// Throws if the configuration is not allowed or the database cannot be
  /// opened; it never substitutes an empty or different store.
  static Future<AppBackend> openDrift({
    required AppConfig config,
    required PlatformServices platform,
    ExpenseStorage? jsonStorage,
    DriftExecutorFactory openExecutor = defaultDriftExecutor,
    DateTime Function()? clock,
  }) async {
    config.validate();
    if (config.backend != StorageBackend.drift) {
      throw ArgumentError('Not a Drift configuration: $config');
    }
    WebStorageReport? report;
    final db = SpendWiseDatabase(
      openExecutor(config.databaseName, (r) => report = r),
    );
    try {
      // Opens the database, runs schema migrations and the version guard.
      await db.customSelect('SELECT COUNT(*) FROM expenses').get();
    } catch (_) {
      await db.close().catchError((Object _) {});
      rethrow;
    }
    final source =
        jsonStorage ??
        SharedPreferencesExpenseStorage(
          lock: platform.lock,
          namespace: config.namespace,
          rawStorage: platform.rawStorage,
        );
    return AppBackend._(
      config: config,
      jsonStorage: source,
      repository: DriftExpenseRepository(db),
      database: db,
      migration: JsonToDriftMigration(source: source, target: db, clock: clock),
      storageReport: report,
    );
  }
}
