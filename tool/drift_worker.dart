import 'package:drift/wasm.dart';

// Entry point of web/drift_worker.js. Rebuild with:
//   dart run tool/web_assets.dart build
void main() => WasmDatabase.workerMainForOpen();
