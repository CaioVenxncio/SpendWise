import 'platform_services.dart';

/// Non-web platforms: no browser APIs yet.
PlatformServices createPlatformServices() => PlatformServices(
  lock: InProcessLock(),
  files: const UnsupportedFileTransfer(),
  persistence: const UnsupportedPersistentStorage(),
);

RawStorage createRawStorage() => const UnsupportedRawStorage();

class UnsupportedFileTransfer implements FileTransfer {
  const UnsupportedFileTransfer();

  @override
  bool get isSupported => false;

  @override
  Future<void> saveText(
    String fileName,
    String text, {
    String mimeType = 'application/json',
  }) => throw UnsupportedError('File export is not supported here');

  @override
  Future<PickedFile?> pickFile({
    required int maxBytes,
    String accept = '.json',
  }) => throw UnsupportedError('File import is not supported here');
}

class UnsupportedPersistentStorage implements PersistentStorage {
  const UnsupportedPersistentStorage();

  @override
  Future<PersistenceStatus> status() async => PersistenceStatus.unsupported;

  @override
  Future<PersistenceStatus> request() async => PersistenceStatus.unsupported;
}
