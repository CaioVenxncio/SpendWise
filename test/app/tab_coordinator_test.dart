import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/app_config.dart';
import 'package:spendwise/app/tab_coordinator.dart';
import 'package:spendwise/app/version.dart';
import 'package:spendwise/main.dart';
import 'package:spendwise/services/expense_storage.dart';

import '../support/fake_expense_storage.dart';
import '../support/fake_platform_services.dart';

const _ns = AppConfig(backend: StorageBackend.json, namespace: 'n1');

Map<String, Object?> _msg(
  String type, {
  String tabId = 'other',
  String? namespace = 'n1',
  String backend = 'json',
}) => {
  'protocol': tabProtocolVersion,
  'type': type,
  'tabId': tabId,
  'version': '9.9.9',
  'backend': backend,
  'namespace': namespace,
};

void main() {
  group('TabCoordinator', () {
    late FakeTabChannel channel;
    late TabCoordinator tabs;

    setUp(() {
      channel = FakeTabChannel();
      tabs = TabCoordinator(
        channel: channel,
        config: _ns,
        watchedStorageKeys: {'flutter.spendwise_ns.n1.expenses'},
        tabId: 'me',
      );
    });

    test('announces itself and prepares a goodbye', () {
      expect(channel.postedTypes, ['hello']);
      final hello = channel.posted.single;
      expect(hello['version'], appBuildVersion);
      expect(hello['namespace'], 'n1');
      expect(hello['backend'], 'json');
      expect(channel.goodbye?['type'], 'bye');
    });

    test('learns about other tabs and answers a hello', () {
      channel.receive(_msg('hello'));
      expect(tabs.peers.single.tabId, 'other');
      expect(channel.postedTypes.last, 'here');

      channel.receive(_msg('here', tabId: 'third', backend: 'drift'));
      expect(tabs.peers.map((p) => p.backend), ['json', 'drift']);

      channel.receive(_msg('bye'));
      expect(tabs.peers.map((p) => p.tabId), ['third']);
    });

    test('ignores itself and other data sets', () {
      channel.receive(_msg('hello', tabId: 'me'));
      channel.receive(_msg('hello', namespace: 'other_ns'));
      channel.receive(_msg('hello', namespace: null));
      expect(tabs.peers, isEmpty);
    });

    test('ignores malformed messages', () {
      channel.receive({'type': 'hello'});
      channel.receive({'tabId': 42, 'type': 'hello'});
      expect(tabs.peers, isEmpty);
    });

    test('reports migrations elsewhere', () async {
      final events = <void>[];
      tabs.migrationsElsewhere.listen(events.add);
      channel.receive(_msg('migrated', backend: 'drift'));
      await Future<void>.delayed(Duration.zero);
      expect(tabs.migratedElsewhere, isTrue);
      expect(events, hasLength(1));
    });

    test('reports writes to the watched keys only', () async {
      var changes = 0;
      tabs.sourceChanges.listen((_) => changes++);
      channel.storageEvent('flutter.spendwise_ns.n1.expenses');
      channel.storageEvent('flutter.something_else');
      channel.storageEvent(null); // localStorage.clear()
      await Future<void>.delayed(Duration.zero);
      expect(changes, 2);
    });

    test('refresh forgets tabs and asks again', () {
      channel.receive(_msg('hello'));
      tabs.refresh();
      expect(tabs.peers, isEmpty);
      expect(channel.postedTypes.last, 'hello');
    });

    test('says goodbye when disposed', () {
      tabs.dispose();
      expect(channel.postedTypes.last, 'bye');
    });
  });

  test('the real storage watches its exact browser keys', () {
    expect(SharedPreferencesExpenseStorage(namespace: 'n1').watchKeys, {
      'flutter.spendwise_ns.n1.expenses',
      'flutter.spendwise_ns.n1.expenses_legacy_backup',
    });
    expect(SharedPreferencesExpenseStorage().watchKeys, {
      'flutter.expenses',
      'flutter.expenses_legacy_backup',
    });
  });

  group('JSON app and other tabs', () {
    const data =
        '[{"id":"a","amountCents":300,"description":"Gum","category":"Food",'
        '"date":"2026-10-01T00:00:00.000"}]';

    Future<(FakeExpenseStorage, FakeTabChannel)> start(
      WidgetTester tester,
    ) async {
      final storage = FakeExpenseStorage(data: data);
      final channel = FakeTabChannel();
      await tester.pumpWidget(
        SpendWiseApp(
          storage: storage,
          clock: () => DateTime(2026, 10, 15),
          platform: fakePlatform(tabs: channel),
        ),
      );
      await tester.pumpAndSettle();
      return (storage, channel);
    }

    testWidgets('a write in another tab pauses edits before any conflict', (
      tester,
    ) async {
      final (storage, channel) = await start(tester);
      expect(find.text('Gum'), findsOneWidget);

      storage.data =
          '[{"id":"b","amountCents":1,"description":"Other","category":"x",'
          '"date":"2026-10-02T00:00:00.000"}]';
      channel.storageEvent('flutter.expenses');
      await tester.pumpAndSettle();

      expect(find.textContaining('changed in another tab'), findsOneWidget);
      expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .onPressed,
        isNull,
      );
      expect(storage.writeCount, 0);

      await tester.tap(find.text('Reload'));
      await tester.pumpAndSettle();
      expect(find.text('Other'), findsOneWidget);
    });

    testWidgets('unrelated keys do not pause edits', (tester) async {
      final (_, channel) = await start(tester);
      channel.storageEvent('flutter.unrelated');
      await tester.pumpAndSettle();
      expect(find.textContaining('changed in another tab'), findsNothing);
    });

    testWidgets('a migration in another tab is reported', (tester) async {
      final (_, channel) = await start(tester);
      channel.receive(_msg('migrated', namespace: null, backend: 'drift'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('moved to the new storage in another tab'),
        findsOneWidget,
      );
    });
  });

  testWidgets('the default build has no SQLite launcher', (tester) async {
    expect(kDriftBackendBuild, isFalse);
  });
}
