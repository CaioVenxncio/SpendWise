import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/app_config.dart';
import 'package:spendwise/app/backend.dart';

void main() {
  test('the build default is JSON on real data', () {
    // No --dart-define values are passed to `flutter test`.
    final config = AppConfig.fromEnvironment();
    expect(config.backend, StorageBackend.json);
    expect(config.usesRealData, isTrue);
    expect(config.validate, returnsNormally);
  });

  test('parses explicit values', () {
    final c = AppConfig.parse(backend: 'drift', namespace: 'qa_1');
    expect(c.backend, StorageBackend.drift);
    expect(c.namespace, 'qa_1');
    expect(c.databaseName, 'spendwise_ns_qa_1');
    expect(c.validate, returnsNormally);
  });

  test('real data keeps the original database name', () {
    expect(const AppConfig().databaseName, 'spendwise');
  });

  test('Drift on real data is refused (fail closed)', () {
    final c = AppConfig.parse(backend: 'drift');
    expect(c.usesRealData, isTrue);
    expect(c.validate, throwsA(isA<AppConfigException>()));
  });

  test('JSON with a namespace is allowed for test data', () {
    final c = AppConfig.parse(backend: 'json', namespace: 'seed');
    expect(c.validate, returnsNormally);
  });

  for (final bad in ['sqlite', 'JSON', '', 'drift ']) {
    test('unknown backend "$bad" is refused', () {
      expect(
        () => AppConfig.parse(backend: bad),
        throwsA(isA<AppConfigException>()),
      );
    });
  }

  for (final bad in ['Has-Caps', 'a.b', 'x' * 33, '../etc', 'spaces here']) {
    test('invalid namespace "$bad" is refused', () {
      expect(
        () => AppConfig.parse(backend: 'drift', namespace: bad),
        throwsA(isA<AppConfigException>()),
      );
    });
  }

  group('storage safety from the browser report', () {
    const cases = {
      'opfsShared': StorageSafety.ok,
      'opfsLocks': StorageSafety.ok,
      'sharedIndexedDb': StorageSafety.ok,
      'unsafeIndexedDb': StorageSafety.singleTabOnly,
      'inMemory': StorageSafety.temporary,
      'somethingNew': StorageSafety.unknown,
    };
    cases.forEach((implementation, safety) {
      test(implementation, () {
        expect(
          storageSafetyOf((
            implementation: implementation,
            missing: const [],
          ), isWeb: true),
          safety,
        );
      });
    });

    test('no report outside a browser is a native database file', () {
      expect(storageSafetyOf(null, isWeb: false), StorageSafety.native);
    });

    test('no report inside a browser is unknown (fails closed)', () {
      expect(storageSafetyOf(null, isWeb: true), StorageSafety.unknown);
    });

    test('only coordinated persistent modes allow migration', () {
      expect(
        {for (final s in StorageSafety.values) s: s.allowsMigration},
        {
          StorageSafety.ok: true,
          StorageSafety.native: true,
          StorageSafety.singleTabOnly: false,
          StorageSafety.temporary: false,
          StorageSafety.unknown: false,
        },
      );
    });
  });
}
