import 'package:flutter/foundation.dart';

import '../platform/platform_services.dart';

/// Tracks the browser's persistent-storage state.
///
/// Persistence is only requested after the user has saved data, and at most
/// once per session. A granted request lowers the chance that the browser
/// clears data under storage pressure; it does not stop the user, the
/// browser's privacy features, or site-data clearing from removing it.
class StoragePersistence with ChangeNotifier {
  StoragePersistence(this._storage);

  final PersistentStorage _storage;

  PersistenceStatus? _status;
  bool _requested = false;

  /// `null` until checked.
  PersistenceStatus? get status => _status;

  Future<void> refresh() async {
    _status = await _safely(_storage.status);
    notifyListeners();
  }

  /// Requests persistence once, if supported and not already granted.
  Future<void> requestAfterUserSave() async {
    if (_requested) return;
    _requested = true;
    final current = await _safely(_storage.status);
    _status = current == PersistenceStatus.notPersisted
        ? await _safely(_storage.request)
        : current;
    notifyListeners();
  }

  Future<PersistenceStatus> _safely(
    Future<PersistenceStatus> Function() call,
  ) async {
    try {
      return await call();
    } catch (_) {
      return PersistenceStatus.unsupported;
    }
  }
}
