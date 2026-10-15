import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../platform/platform_services.dart';
import 'app_config.dart';
import 'version.dart';

/// Another open tab running this version of SpendWise or later.
class PeerTab {
  PeerTab({
    required this.tabId,
    required this.version,
    required this.backend,
    required this.namespace,
  });

  final String tabId;
  final String version;
  final String backend;
  final String? namespace;
}

/// Knows about other tabs and about changes they make.
///
/// * Tabs of this version announce themselves over a `BroadcastChannel`
///   (`hello` / `here` / `bye`) and report completed migrations.
/// * Writes to the JSON keys by **any** tab, including older versions that
///   know nothing about this, arrive as browser `storage` events.
///
/// It only informs; it cannot stop another tab. Older versions do not
/// announce themselves, and a tab that crashed may stay listed until the
/// next [refresh]. Source fingerprints and the migration transaction remain
/// the actual safety mechanisms.
class TabCoordinator with ChangeNotifier {
  TabCoordinator({
    required this.channel,
    required this.config,
    required Set<String> watchedStorageKeys,
    String? tabId,
  }) : _watched = watchedStorageKeys,
       tabId = tabId ?? 'tab-${Random().nextInt(1 << 31)}' {
    _subs.add(channel.messages.listen(_onMessage));
    _subs.add(channel.storageChanges.listen(_onStorage));
    channel.setGoodbye(_message('bye'));
    channel.post(_message('hello'));
  }

  final TabChannel channel;
  final AppConfig config;
  final Set<String> _watched;
  final String tabId;
  final _subs = <StreamSubscription<Object?>>[];
  final _peers = <String, PeerTab>{};
  final _sourceChanges = StreamController<void>.broadcast();
  final _migrations = StreamController<void>.broadcast();
  bool _disposed = false;

  /// Other tabs of this version using the same data set.
  List<PeerTab> get peers => List.unmodifiable(_peers.values);

  /// Fires when another tab changed the JSON data (any version).
  Stream<void> get sourceChanges => _sourceChanges.stream;

  /// Fires when another tab completed a migration of the same data set.
  Stream<void> get migrationsElsewhere => _migrations.stream;

  /// Whether another tab reported a completed migration this session.
  bool get migratedElsewhere => _migratedElsewhere;
  bool _migratedElsewhere = false;

  /// Forgets known tabs and asks all open ones to answer again.
  void refresh() {
    _peers.clear();
    _notify();
    channel.post(_message('hello'));
  }

  /// Tells other tabs that this tab completed a migration.
  void announceMigration() => channel.post(_message('migrated'));

  Map<String, Object?> _message(String type) => {
    'protocol': tabProtocolVersion,
    'type': type,
    'tabId': tabId,
    'version': appBuildVersion,
    'backend': config.backend.name,
    'namespace': config.namespace,
  };

  void _onMessage(Map<String, Object?> m) {
    final from = m['tabId'];
    if (from is! String || from == tabId) return;
    if (m['namespace'] != config.namespace) return; // other data set
    switch (m['type']) {
      case 'hello':
        _remember(m, from);
        channel.post(_message('here'));
      case 'here':
        _remember(m, from);
      case 'bye':
        if (_peers.remove(from) != null) _notify();
      case 'migrated':
        _remember(m, from);
        _migratedElsewhere = true;
        _migrations.add(null);
        _notify();
    }
  }

  void _remember(Map<String, Object?> m, String from) {
    _peers[from] = PeerTab(
      tabId: from,
      version: '${m['version']}',
      backend: '${m['backend']}',
      namespace: m['namespace'] as String?,
    );
    _notify();
  }

  void _onStorage(String? key) {
    // `null` means localStorage was cleared.
    if (key == null || _watched.contains(key)) _sourceChanges.add(null);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    channel.post(_message('bye'));
    for (final s in _subs) {
      s.cancel();
    }
    _sourceChanges.close();
    _migrations.close();
    super.dispose();
  }
}
