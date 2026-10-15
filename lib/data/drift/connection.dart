import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// Name of the production database. Not opened by the app yet (M2 Stage 2);
/// the app still stores expenses as JSON.
const spendWiseDatabaseName = 'spendwise';

/// Which browser storage Drift chose, reported through [onWebResult].
typedef WebStorageReport = ({String implementation, List<String> missing});

/// Opens the SQLite database for the current platform.
///
/// On the web it needs `web/sqlite3.wasm` and `web/drift_worker.js`
/// (see `tool/web_assets.dart`). Drift then picks the best storage the
/// browser offers (OPFS, IndexedDB, or in-memory as a last resort).
QueryExecutor openSpendWiseConnection({
  String name = spendWiseDatabaseName,
  void Function(WebStorageReport report)? onWebResult,
}) => driftDatabase(
  name: name,
  web: DriftWebOptions(
    sqlite3Wasm: Uri.parse('sqlite3.wasm'),
    driftWorker: Uri.parse('drift_worker.js'),
    onResult: (result) => onWebResult?.call((
      implementation: result.chosenImplementation.name,
      missing: [for (final f in result.missingFeatures) f.name],
    )),
  ),
);
