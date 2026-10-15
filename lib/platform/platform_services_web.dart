import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'platform_services.dart';

PlatformServices createPlatformServices() => PlatformServices(
  lock: _hasNavigatorProperty('locks') ? WebLocksLock() : InProcessLock(),
  files: WebFileTransfer(),
  persistence: WebPersistentStorage(),
  tabs: WebTabChannel(),
  rawStorage: const WebRawStorage(),
);

RawStorage createRawStorage() => const WebRawStorage();

/// `window.localStorage`, read only.
class WebRawStorage implements RawStorage {
  const WebRawStorage();

  @override
  bool get isSupported => true;

  @override
  String? read(String key) {
    try {
      return web.window.localStorage.getItem(key);
    } catch (_) {
      // e.g. SecurityError when site data is blocked. Unknown is not absent.
      throw const RawStorageAccessException();
    }
  }
}

/// `storage` events plus a `BroadcastChannel` named `spendwise.tabs`.
class WebTabChannel implements TabChannel {
  WebTabChannel() {
    web.window.addEventListener('storage', _onStorage);
    if ((web.window as JSObject).has('BroadcastChannel')) {
      final channel = web.BroadcastChannel('spendwise.tabs');
      channel.onmessage = ((web.MessageEvent e) {
        final data = e.data;
        if (data == null || !data.isA<JSString>()) return;
        try {
          final decoded = json.decode((data as JSString).toDart);
          if (decoded is Map<String, Object?>) _messages.add(decoded);
        } catch (_) {}
      }).toJS;
      _channel = channel;
    }
    web.window.addEventListener('pagehide', _onPageHide);
  }

  final _storage = StreamController<String?>.broadcast();
  final _messages = StreamController<Map<String, Object?>>.broadcast();
  web.BroadcastChannel? _channel;

  Map<String, Object?>? _goodbye;

  @override
  void setGoodbye(Map<String, Object?> message) => _goodbye = message;

  late final JSFunction _onStorage = ((web.StorageEvent e) {
    _storage.add(e.key);
  }).toJS;

  late final JSFunction _onPageHide = ((web.Event _) {
    final bye = _goodbye;
    if (bye != null) post(bye);
  }).toJS;

  @override
  Stream<String?> get storageChanges => _storage.stream;

  @override
  Stream<Map<String, Object?>> get messages => _messages.stream;

  @override
  void post(Map<String, Object?> message) =>
      _channel?.postMessage(json.encode(message).toJS);

  @override
  void close() {
    web.window.removeEventListener('storage', _onStorage);
    web.window.removeEventListener('pagehide', _onPageHide);
    _channel?.close();
    _storage.close();
    _messages.close();
  }
}

/// `navigator.locks` and `navigator.storage` only exist in secure contexts
/// (HTTPS or localhost) and in supporting browsers.
bool _hasNavigatorProperty(String name) {
  final navigator = web.window.navigator as JSObject;
  return navigator.has(name) && navigator[name] != null;
}

/// Exclusive lock shared by all same-origin tabs that request the same name.
class WebLocksLock implements CrossTabLock {
  @override
  LockKind get kind => LockKind.webLocks;

  @override
  Future<T> run<T>(String name, Future<T> Function() action) {
    final completer = Completer<T>();
    JSPromise<JSAny?> onGranted(JSAny? _) {
      // The lock is held until this promise settles.
      return action()
          .then<void>(
            completer.complete,
            onError: (Object e, StackTrace s) => completer.completeError(e, s),
          )
          .toJS;
    }

    web.window.navigator.locks
        .request(name, onGranted.toJS)
        .toDart
        .then<void>(
          (_) {},
          onError: (Object e, StackTrace s) {
            if (!completer.isCompleted) completer.completeError(e, s);
          },
        );
    return completer.future;
  }
}

class WebPersistentStorage implements PersistentStorage {
  bool get _supported => _hasNavigatorProperty('storage');

  @override
  Future<PersistenceStatus> status() async {
    if (!_supported) return PersistenceStatus.unsupported;
    final persisted = await web.window.navigator.storage.persisted().toDart;
    return persisted.toDart
        ? PersistenceStatus.persisted
        : PersistenceStatus.notPersisted;
  }

  @override
  Future<PersistenceStatus> request() async {
    if (!_supported) return PersistenceStatus.unsupported;
    final granted = await web.window.navigator.storage.persist().toDart;
    return granted.toDart
        ? PersistenceStatus.persisted
        : PersistenceStatus.notPersisted;
  }
}

class WebFileTransfer implements FileTransfer {
  @override
  bool get isSupported => true;

  @override
  Future<void> saveText(
    String fileName,
    String text, {
    String mimeType = 'application/json',
  }) async {
    final blob = web.Blob(
      [text.toJS].toJS,
      web.BlobPropertyBag(type: '$mimeType;charset=utf-8'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    web.document.body!.append(anchor);
    anchor.click();
    anchor.remove();
    // Give the browser time to start the download before revoking.
    Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  }

  @override
  Future<PickedFile?> pickFile({
    required int maxBytes,
    String accept = '.json',
  }) async {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = accept;
    final chosen = Completer<web.File?>();
    input.addEventListener(
      'change',
      ((web.Event _) {
        final files = input.files;
        if (!chosen.isCompleted) {
          chosen.complete(
            files != null && files.length > 0 ? files.item(0) : null,
          );
        }
      }).toJS,
    );
    input.addEventListener(
      'cancel',
      ((web.Event _) {
        if (!chosen.isCompleted) chosen.complete(null);
      }).toJS,
    );
    input.click();

    final file = await chosen.future;
    if (file == null) return null;
    // Check the size before reading anything into memory.
    if (file.size > maxBytes) throw FileTooLargeException(file.size, maxBytes);
    final buffer = await file.arrayBuffer().toDart;
    return PickedFile(name: file.name, bytes: buffer.toDart.asUint8List());
  }
}
