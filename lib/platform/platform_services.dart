import 'dart:async';
import 'dart:typed_data';

import 'platform_services_stub.dart'
    if (dart.library.js_interop) 'platform_services_web.dart'
    as impl;

/// How [CrossTabLock] protects storage writes.
enum LockKind {
  /// Browser Web Locks API: exclusive across tabs of this origin that also
  /// use the lock.
  webLocks,

  /// Only serializes operations within this app instance.
  inProcess,
}

/// Runs actions under an exclusive lock.
abstract interface class CrossTabLock {
  LockKind get kind;

  /// Runs [action] while holding the lock called [name]. The lock is released
  /// when the returned future completes, also on error.
  Future<T> run<T>(String name, Future<T> Function() action);
}

/// Whether the browser has granted persistent storage.
enum PersistenceStatus {
  /// The platform has no persistent-storage API (or it is unavailable here).
  unsupported,

  /// The browser reports storage as persistent.
  persisted,

  /// The browser reports storage as best-effort: it may be cleared.
  notPersisted,
}

/// Browser persistent-storage API (`navigator.storage`).
abstract interface class PersistentStorage {
  Future<PersistenceStatus> status();

  /// Asks the browser to make storage persistent. Browsers may refuse without
  /// telling the user, and some may show a prompt.
  Future<PersistenceStatus> request();
}

/// A file the user chose to open.
class PickedFile {
  PickedFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Thrown when a picked file is larger than allowed. The file is not read.
class FileTooLargeException implements Exception {
  FileTooLargeException(this.sizeBytes, this.maxBytes);

  final int sizeBytes;
  final int maxBytes;

  @override
  String toString() =>
      'FileTooLargeException: $sizeBytes bytes exceeds $maxBytes bytes';
}

/// Saving and opening files on the user's device.
abstract interface class FileTransfer {
  bool get isSupported;

  /// Offers [text] to the user as a download named [fileName].
  Future<void> saveText(String fileName, String text, {String mimeType});

  /// Lets the user choose one file. Returns `null` if they cancel.
  ///
  /// Throws [FileTooLargeException] before reading any content if the file is
  /// larger than [maxBytes].
  Future<PickedFile?> pickFile({required int maxBytes, String accept});
}

/// Signals from other tabs of the same origin.
///
/// * [storageChanges]: keys changed in localStorage by another tab, from the
///   browser's `storage` event. Fires for every app version that writes
///   there, including old ones; never for this tab's own writes.
/// * [messages]: JSON messages from tabs running this version or later
///   (`BroadcastChannel`). Older versions do not send them.
abstract interface class TabChannel {
  Stream<String?> get storageChanges;

  Stream<Map<String, Object?>> get messages;

  void post(Map<String, Object?> message);

  /// Message posted when this page is hidden or closed, if supported.
  void setGoodbye(Map<String, Object?> message);

  void close();
}

/// No other tabs (non-web platforms).
class NoTabChannel implements TabChannel {
  const NoTabChannel();

  @override
  Stream<String?> get storageChanges => const Stream.empty();

  @override
  Stream<Map<String, Object?>> get messages => const Stream.empty();

  @override
  void post(Map<String, Object?> message) {}

  @override
  void setGoodbye(Map<String, Object?> message) {}

  @override
  void close() {}
}

/// Thrown when the browser's key-value storage cannot be accessed at all
/// (for example when site data is blocked). Never carries stored content.
class RawStorageAccessException implements Exception {
  const RawStorageAccessException();

  @override
  String toString() => 'RawStorageAccessException: storage is not accessible';
}

/// Read-only access to stored values exactly as the platform keeps them,
/// below the shared_preferences layer.
///
/// On the web, shared_preferences silently skips a localStorage value it
/// cannot decode, which makes damaged data look absent. Reading the value
/// directly tells "absent" from "present but unreadable".
abstract interface class RawStorage {
  /// Whether raw values can be read on this platform.
  bool get isSupported;

  /// The exact stored value of [key] (a full platform key, such as
  /// `flutter.expenses`), or `null` if the key is absent. Throws
  /// [RawStorageAccessException] if storage cannot be accessed and
  /// [UnsupportedError] if [isSupported] is false.
  String? read(String key);
}

/// No raw access (non-web platforms store typed values natively, so a
/// value never disappears in decoding there).
class UnsupportedRawStorage implements RawStorage {
  const UnsupportedRawStorage();

  @override
  bool get isSupported => false;

  @override
  String? read(String key) =>
      throw UnsupportedError('Raw storage access is not supported here');
}

class PlatformServices {
  const PlatformServices({
    required this.lock,
    required this.files,
    required this.persistence,
    this.tabs = const NoTabChannel(),
    this.rawStorage = const UnsupportedRawStorage(),
  });

  /// Real implementations for the current platform.
  factory PlatformServices.current() => impl.createPlatformServices();

  /// The current platform's [RawStorage], without the other services.
  static RawStorage currentRawStorage() => impl.createRawStorage();

  final CrossTabLock lock;
  final FileTransfer files;
  final PersistentStorage persistence;

  final TabChannel tabs;

  final RawStorage rawStorage;
}

/// Serializes actions within one app instance.
class InProcessLock implements CrossTabLock {
  Future<void> _tail = Future.value();

  @override
  LockKind get kind => LockKind.inProcess;

  @override
  Future<T> run<T>(String name, Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }
}
