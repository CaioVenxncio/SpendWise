/// Which store holds the expenses.
enum StorageBackend { json, drift }

/// Thrown when the build configuration is not allowed.
class AppConfigException implements Exception {
  const AppConfigException(this.message);

  final String message;

  @override
  String toString() => 'AppConfigException: $message';
}

/// Build-time configuration, read from `--dart-define` values:
///
/// * `SPENDWISE_BACKEND`: `json` (default) or `drift`.
/// * `SPENDWISE_NAMESPACE`: isolates all storage (JSON keys, database name,
///   locks) under a test namespace. Empty means the user's real data.
///
/// Until real-data migration is approved (M2 Stage 4B), the Drift backend
/// is only allowed together with a namespace, so it can never open, migrate
/// or hide a user's real expenses.
class AppConfig {
  const AppConfig({this.backend = StorageBackend.json, this.namespace});

  factory AppConfig.fromEnvironment() => AppConfig.parse(
    backend: const String.fromEnvironment(
      'SPENDWISE_BACKEND',
      defaultValue: 'json',
    ),
    namespace: const String.fromEnvironment('SPENDWISE_NAMESPACE'),
  );

  /// Parses raw values. Throws [AppConfigException] for unknown values.
  factory AppConfig.parse({required String backend, String namespace = ''}) {
    final parsed = switch (backend) {
      'json' => StorageBackend.json,
      'drift' => StorageBackend.drift,
      _ => throw AppConfigException('Unknown backend "$backend".'),
    };
    if (namespace.isNotEmpty && !_namespacePattern.hasMatch(namespace)) {
      throw const AppConfigException(
        'The namespace must be 1–32 characters: a–z, 0–9 or _.',
      );
    }
    return AppConfig(
      backend: parsed,
      namespace: namespace.isEmpty ? null : namespace,
    );
  }

  static final _namespacePattern = RegExp(r'^[a-z0-9_]{1,32}$');

  final StorageBackend backend;

  /// `null` means the user's real data.
  final String? namespace;

  bool get usesRealData => namespace == null;

  /// Name of the SQLite database for this configuration.
  String get databaseName =>
      namespace == null ? 'spendwise' : 'spendwise_ns_$namespace';

  /// Throws [AppConfigException] if this configuration must not run.
  void validate() {
    if (backend == StorageBackend.drift && usesRealData) {
      throw const AppConfigException(
        'The SQLite backend is not enabled for real data in this version. '
        'It can only be used with a test namespace.',
      );
    }
  }

  @override
  String toString() =>
      'AppConfig(${backend.name}, ${namespace ?? 'real data'})';
}
