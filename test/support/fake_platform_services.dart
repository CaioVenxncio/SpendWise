import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spendwise/platform/platform_services.dart';

class SavedFile {
  SavedFile(this.name, this.text, this.mimeType);

  final String name;
  final String text;
  final String mimeType;
}

/// Records saved files and returns a preset file when picking.
class FakeFileTransfer implements FileTransfer {
  final saved = <SavedFile>[];

  /// What [pickFile] returns; `null` simulates cancelling.
  Uint8List? nextPick;

  /// Size reported for [nextPick] (defaults to its length).
  int? nextPickSize;

  int pickCount = 0;

  void pickText(String text) =>
      nextPick = Uint8List.fromList(utf8.encode(text));

  @override
  bool get isSupported => true;

  @override
  Future<void> saveText(
    String fileName,
    String text, {
    String mimeType = 'application/json',
  }) async {
    saved.add(SavedFile(fileName, text, mimeType));
  }

  @override
  Future<PickedFile?> pickFile({
    required int maxBytes,
    String accept = '.json',
  }) async {
    pickCount++;
    final bytes = nextPick;
    if (bytes == null) return null;
    final size = nextPickSize ?? bytes.length;
    if (size > maxBytes) throw FileTooLargeException(size, maxBytes);
    return PickedFile(name: 'backup.json', bytes: bytes);
  }
}

class FakePersistentStorage implements PersistentStorage {
  FakePersistentStorage({
    this.current = PersistenceStatus.notPersisted,
    this.grant = false,
  });

  PersistenceStatus current;
  bool grant;
  int requestCount = 0;
  bool throwOnCall = false;

  @override
  Future<PersistenceStatus> status() async {
    if (throwOnCall) throw StateError('unavailable');
    return current;
  }

  @override
  Future<PersistenceStatus> request() async {
    if (throwOnCall) throw StateError('unavailable');
    requestCount++;
    if (grant) current = PersistenceStatus.persisted;
    return current;
  }
}

/// Records posted messages; tests inject what other tabs would send.
class FakeTabChannel implements TabChannel {
  final posted = <Map<String, Object?>>[];
  Map<String, Object?>? goodbye;
  final _storage = StreamController<String?>.broadcast(sync: true);
  final _messages = StreamController<Map<String, Object?>>.broadcast(
    sync: true,
  );

  /// Simulates another tab writing [key] in localStorage.
  void storageEvent(String? key) => _storage.add(key);

  /// Simulates a message from another tab.
  void receive(Map<String, Object?> message) => _messages.add(message);

  List<String> get postedTypes => [for (final m in posted) '${m['type']}'];

  @override
  Stream<String?> get storageChanges => _storage.stream;

  @override
  Stream<Map<String, Object?>> get messages => _messages.stream;

  @override
  void post(Map<String, Object?> message) => posted.add(message);

  @override
  void setGoodbye(Map<String, Object?> message) => goodbye = message;

  @override
  void close() {}
}

/// Platform storage as seen below shared_preferences: set [values] to what
/// localStorage holds (synthetic test data only).
class FakeRawStorage implements RawStorage {
  FakeRawStorage([Map<String, String>? values]) : values = values ?? {};

  final Map<String, String> values;

  /// Simulates blocked site data (SecurityError).
  bool inaccessible = false;

  @override
  bool get isSupported => true;

  @override
  String? read(String key) {
    if (inaccessible) throw const RawStorageAccessException();
    return values[key];
  }
}

PlatformServices fakePlatform({
  FakeFileTransfer? files,
  FakePersistentStorage? persistence,
  TabChannel? tabs,
  RawStorage? rawStorage,
}) => PlatformServices(
  lock: InProcessLock(),
  files: files ?? FakeFileTransfer(),
  persistence: persistence ?? FakePersistentStorage(),
  tabs: tabs ?? const NoTabChannel(),
  rawStorage: rawStorage ?? const UnsupportedRawStorage(),
);
