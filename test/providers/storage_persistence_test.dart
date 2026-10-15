import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/platform/platform_services.dart';
import 'package:spendwise/providers/storage_persistence.dart';

import '../support/fake_platform_services.dart';

void main() {
  test('requests once when storage is best-effort', () async {
    final storage = FakePersistentStorage(grant: true);
    final persistence = StoragePersistence(storage);

    await persistence.requestAfterUserSave();
    await persistence.requestAfterUserSave();

    expect(storage.requestCount, 1);
    expect(persistence.status, PersistenceStatus.persisted);
  });

  test('reports a refused request honestly', () async {
    final storage = FakePersistentStorage(grant: false);
    final persistence = StoragePersistence(storage);

    await persistence.requestAfterUserSave();

    expect(storage.requestCount, 1);
    expect(persistence.status, PersistenceStatus.notPersisted);
  });

  test('does not request when already persistent', () async {
    final storage = FakePersistentStorage(current: PersistenceStatus.persisted);
    await StoragePersistence(storage).requestAfterUserSave();
    expect(storage.requestCount, 0);
  });

  test('does not request when unsupported', () async {
    final storage = FakePersistentStorage(
      current: PersistenceStatus.unsupported,
    );
    final persistence = StoragePersistence(storage);
    await persistence.requestAfterUserSave();
    expect(storage.requestCount, 0);
    expect(persistence.status, PersistenceStatus.unsupported);
  });

  test('API errors are treated as unsupported', () async {
    final storage = FakePersistentStorage()..throwOnCall = true;
    final persistence = StoragePersistence(storage);
    await persistence.refresh();
    expect(persistence.status, PersistenceStatus.unsupported);
  });

  test('refresh never requests', () async {
    final storage = FakePersistentStorage();
    await StoragePersistence(storage).refresh();
    expect(storage.requestCount, 0);
  });
}
