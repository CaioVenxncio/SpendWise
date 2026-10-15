// Reproducible Drift web assets: web/sqlite3.wasm and web/drift_worker.js.
//
//   dart run tool/web_assets.dart fetch   # download sqlite3.wasm, verify
//   dart run tool/web_assets.dart build   # compile drift_worker.js
//   dart run tool/web_assets.dart verify  # check both against the lock
//
// sqlite3.wasm must come from the GitHub release matching the locked
// package:sqlite3 version; its SHA-256 must equal the hash that package
// pins in lib/src/hook/asset_hashes.dart. The worker is compiled from the
// locked package:drift. Versions and hashes are recorded in
// web/web_assets.lock.json.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

const _manifestPath = 'web/web_assets.lock.json';
const _wasmPath = 'web/sqlite3.wasm';
const _workerPath = 'web/drift_worker.js';
const _workerSource = 'tool/drift_worker.dart';

Future<void> main(List<String> args) async {
  final command = args.isEmpty ? 'verify' : args.first;
  try {
    switch (command) {
      case 'fetch':
        await _fetch();
      case 'build':
        await _build();
      case 'verify':
        await _verify();
      default:
        _fail('Unknown command "$command". Use fetch, build or verify.');
    }
  } on _Failure catch (e) {
    stderr.writeln('web_assets: ${e.message}');
    exitCode = 1;
  }
}

Future<void> _fetch() async {
  final pinned = await _pinnedSqlite();
  final url = Uri.parse(
    'https://github.com/simolus3/sqlite3.dart/releases/download/'
    '${pinned.releaseTag}/sqlite3.wasm',
  );
  stdout.writeln('Downloading $url');
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != 200) {
      _fail('Download failed: HTTP ${response.statusCode}');
    }
    final bytes = await response.fold<List<int>>(
      [],
      (all, chunk) => all..addAll(chunk),
    );
    final hash = sha256.convert(bytes).toString();
    if (hash != pinned.wasmSha256) {
      _fail(
        'Downloaded sqlite3.wasm hash $hash != pinned ${pinned.wasmSha256}',
      );
    }
    await File(_wasmPath).writeAsBytes(bytes, flush: true);
  } finally {
    client.close();
  }
  await _updateManifest((m) {
    m['sqlite3'] = {
      'version': pinned.version,
      'releaseTag': pinned.releaseTag,
      'sha256': pinned.wasmSha256,
    };
  });
  stdout.writeln('Wrote $_wasmPath (sha256 ${pinned.wasmSha256})');
}

Future<void> _build() async {
  final drift = _lockedVersion('drift');
  final result = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'js',
    '-O4',
    '--no-source-maps',
    '-o',
    _workerPath,
    _workerSource,
  ]);
  if (result.exitCode != 0) {
    _fail('Worker compilation failed:\n${result.stdout}\n${result.stderr}');
  }
  for (final extra in ['$_workerPath.deps', '$_workerPath.map']) {
    final f = File(extra);
    if (f.existsSync()) f.deleteSync();
  }
  final hash = _sha256Of(_workerPath);
  await _updateManifest((m) {
    m['driftWorker'] = {
      'driftVersion': drift,
      'dartVersion': Platform.version.split(' ').first,
      'sha256': hash,
    };
  });
  stdout.writeln('Wrote $_workerPath (sha256 $hash)');
}

Future<void> _verify() async {
  final manifest = _readManifest();
  final pinned = await _pinnedSqlite();

  final sqlite = manifest['sqlite3'] as Map<String, dynamic>?;
  if (sqlite == null) _fail('Manifest has no sqlite3 entry. Run fetch.');
  if (sqlite['version'] != pinned.version) {
    _fail(
      'sqlite3.wasm is for package:sqlite3 ${sqlite['version']} but '
      '${pinned.version} is locked. Run fetch.',
    );
  }
  if (sqlite['sha256'] != pinned.wasmSha256) {
    _fail('Manifest sqlite3.wasm hash differs from the package pin.');
  }
  if (_sha256Of(_wasmPath) != pinned.wasmSha256) {
    _fail('$_wasmPath does not match the pinned hash. Run fetch.');
  }

  final worker = manifest['driftWorker'] as Map<String, dynamic>?;
  if (worker == null) _fail('Manifest has no driftWorker entry. Run build.');
  final drift = _lockedVersion('drift');
  if (worker['driftVersion'] != drift) {
    _fail(
      'drift_worker.js was built for drift ${worker['driftVersion']} but '
      '$drift is locked. Run build.',
    );
  }
  if (_sha256Of(_workerPath) != worker['sha256']) {
    _fail('$_workerPath differs from the manifest. Run build.');
  }
  stdout.writeln(
    'OK: sqlite3.wasm ${pinned.version}, drift_worker.js for drift $drift',
  );
}

class _PinnedSqlite {
  _PinnedSqlite(this.version, this.releaseTag, this.wasmSha256);

  final String version;
  final String releaseTag;
  final String wasmSha256;
}

/// Reads the release tag and wasm hash pinned by the locked package:sqlite3.
Future<_PinnedSqlite> _pinnedSqlite() async {
  final version = _lockedVersion('sqlite3');
  final lib = await Isolate.resolvePackageUri(
    Uri.parse('package:sqlite3/sqlite3.dart'),
  );
  if (lib == null) _fail('package:sqlite3 is not resolvable. Run pub get.');
  final hashesFile = File.fromUri(lib.resolve('src/hook/asset_hashes.dart'));
  if (!hashesFile.existsSync()) {
    _fail('Cannot find ${hashesFile.path}; package layout changed.');
  }
  final source = hashesFile.readAsStringSync();
  final tag = RegExp(r"releaseTag = '([^']+)'").firstMatch(source)?.group(1);
  final hash = RegExp(r"'sqlite3\.wasm':\s*'([0-9a-f]{64})'")
      .firstMatch(source)
      ?.group(1);
  if (tag == null || hash == null) {
    _fail('Cannot read the pinned sqlite3.wasm hash from package:sqlite3.');
  }
  if (tag != 'sqlite3-$version') {
    _fail('package:sqlite3 release tag $tag does not match $version.');
  }
  return _PinnedSqlite(version, tag, hash);
}

String _lockedVersion(String package) {
  final lock = File('pubspec.lock').readAsLinesSync();
  final start = lock.indexOf('  $package:');
  if (start < 0) _fail('$package is not in pubspec.lock.');
  for (var i = start + 1; i < lock.length && i < start + 10; i++) {
    final match = RegExp(r'^    version: "([^"]+)"').firstMatch(lock[i]);
    if (match != null) return match.group(1)!;
  }
  _fail('No version for $package in pubspec.lock.');
}

String _sha256Of(String path) {
  final file = File(path);
  if (!file.existsSync()) _fail('$path is missing.');
  return sha256.convert(file.readAsBytesSync()).toString();
}

Map<String, dynamic> _readManifest() {
  final file = File(_manifestPath);
  if (!file.existsSync()) return {};
  return json.decode(file.readAsStringSync()) as Map<String, dynamic>;
}

Future<void> _updateManifest(void Function(Map<String, dynamic>) edit) async {
  final manifest = _readManifest();
  edit(manifest);
  await File(
    _manifestPath,
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(manifest)}\n');
}

Never _fail(String message) => throw _Failure(message);

class _Failure implements Exception {
  _Failure(this.message);

  final String message;
}
