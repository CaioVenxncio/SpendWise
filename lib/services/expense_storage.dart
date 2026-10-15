import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/expense.dart';
import '../platform/platform_services.dart';

/// Thrown when expenses cannot be written to persistent storage.
class ExpenseStorageException implements Exception {
  ExpenseStorageException(this.message);

  final String message;

  @override
  String toString() => 'ExpenseStorageException: $message';
}

/// Why a stored value could not be read.
enum UnreadableReason {
  /// Present, but not in the storage layer's encoding (e.g. truncated or
  /// edited by hand).
  notDecodable('is present but cannot be decoded'),

  /// Decoded, but not text (e.g. a number or a list).
  unexpectedType('is present but is not text'),

  /// Storage could not be accessed, so presence is unknown.
  inaccessible('could not be accessed');

  const UnreadableReason(this.description);

  final String description;
}

/// Thrown when a stored value exists, or may exist, but cannot be read as
/// text. Such data is never treated as absent and nothing is written over
/// it. Carries the key name only, never stored content.
class ExpenseStorageUnreadableException implements Exception {
  const ExpenseStorageUnreadableException(this.key, this.reason);

  /// The app's key, e.g. `expenses` (with any namespace prefix).
  final String key;
  final UnreadableReason reason;

  @override
  String toString() =>
      'ExpenseStorageUnreadableException: "$key" ${reason.description}';
}

/// A stored value the app could not read, as found in platform storage.
class UnreadableStoredValue {
  const UnreadableStoredValue({
    required this.platformKey,
    required this.reason,
    required this.exactValue,
  });

  /// The key in platform storage, e.g. `flutter.expenses`.
  final String platformKey;

  final UnreadableReason reason;

  /// The value exactly as kept by the platform (on the web: the
  /// localStorage text, in the storage layer's own encoding), or `null`
  /// if it could not be retrieved.
  final String? exactValue;
}

/// Both stored values without interpretation, for recovery exports.
class StoredExpenseText {
  const StoredExpenseText({
    required this.expenses,
    required this.legacyBackup,
    this.unreadable = const {},
  });

  /// The collection as text, or `null` if absent or unreadable.
  final String? expenses;

  /// The legacy backup as text, or `null` if absent or unreadable.
  final String? legacyBackup;

  /// Values that are present (or may be) but unreadable, by the app's key
  /// name ([SharedPreferencesExpenseStorage.storageKey] or
  /// [SharedPreferencesExpenseStorage.legacyBackupKey]).
  final Map<String, UnreadableStoredValue> unreadable;
}

/// Reads and writes the serialized expense collection.
///
/// Kept as a small interface so repositories can be tested without a real
/// storage backend.
abstract class ExpenseStorage {
  /// Returns the stored JSON string as currently persisted (not a cached
  /// copy), or `null` if nothing has been saved yet. Throws
  /// [ExpenseStorageUnreadableException] if a value is present but cannot
  /// be read, so damaged data is never mistaken for an empty store.
  Future<String?> read();

  /// Replaces the stored JSON string with [data].
  Future<void> write(String data);

  /// Keeps a copy of [data], the original legacy-format collection, before
  /// it is first rewritten in the current format. Must not replace an
  /// existing backup, so the oldest original is always the one kept; an
  /// existing but unreadable backup makes it throw
  /// [ExpenseStorageUnreadableException] instead.
  Future<void> backupLegacyData(String data);

  /// Returns the legacy backup written by [backupLegacyData], if any. Same
  /// unreadable-value behaviour as [read].
  Future<String?> readLegacyBackup();

  /// Both stored values for a recovery export. Never throws for damaged
  /// values; they are reported in [StoredExpenseText.unreadable].
  Future<StoredExpenseText> readStoredText();

  /// Name of the key holding the expense collection (recorded in
  /// migration snapshots).
  String get sourceKey;

  /// The keys as they appear in browser `storage` events, so another tab's
  /// writes to this store can be recognised.
  Set<String> get watchKeys;

  /// How [exclusive] protects against other tabs.
  LockKind get lockKind;

  /// Runs [action] while holding the storage lock, so that a read followed
  /// by a write is not interleaved with other holders of the lock.
  Future<T> exclusive<T>(Future<T> Function() action);
}

class SharedPreferencesExpenseStorage implements ExpenseStorage {
  /// Uses the app's real keys, or isolated keys when [namespace] is given
  /// (development and testing only).
  SharedPreferencesExpenseStorage({
    CrossTabLock? lock,
    String? namespace,
    RawStorage? rawStorage,
  }) : _lock = lock ?? PlatformServices.current().lock,
       _raw = rawStorage ?? PlatformServices.currentRawStorage(),
       _prefix = namespace == null ? '' : 'spendwise_ns.$namespace.';

  /// Storage key used since the first version of the app. Changing it would
  /// orphan existing user data.
  static const storageKey = 'expenses';

  /// Copy of the collection as it was before amounts moved to integer cents.
  static const legacyBackupKey = 'expenses_legacy_backup';

  /// Name of the cross-tab lock guarding [storageKey].
  static const lockName = 'spendwise.expenses';

  final CrossTabLock _lock;

  /// The platform's own copy of the values, to tell absent from damaged.
  final RawStorage _raw;
  final String _prefix;

  String get _key => '$_prefix$storageKey';

  String get _legacyKey => '$_prefix$legacyBackupKey';

  @override
  String get sourceKey => _key;

  /// shared_preferences stores keys in localStorage with this prefix.
  static const platformKeyPrefix = 'flutter.';

  @override
  Set<String> get watchKeys => {
    '$platformKeyPrefix$_key',
    '$platformKeyPrefix$_legacyKey',
  };

  @override
  LockKind get lockKind => _lock.kind;

  @override
  Future<T> exclusive<T>(Future<T> Function() action) =>
      _lock.run('$lockName$_prefix', action);

  /// Returns the shared preferences re-read from the platform, so values
  /// written by other tabs are seen.
  Future<SharedPreferences> _fresh() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs;
  }

  @override
  Future<String?> read() => _readText(_key);

  @override
  Future<String?> readLegacyBackup() => _readText(_legacyKey);

  /// The text stored under [key]; `null` only if the key is really absent.
  Future<String?> _readText(String key) async {
    final Object? value;
    try {
      value = (await _fresh()).get(key);
    } catch (_) {
      throw ExpenseStorageUnreadableException(
        key,
        UnreadableReason.inaccessible,
      );
    }
    if (value is String) return value;
    if (value != null) {
      throw ExpenseStorageUnreadableException(
        key,
        UnreadableReason.unexpectedType,
      );
    }
    return _confirmAbsent(key);
  }

  /// shared_preferences on the web skips a localStorage value it cannot
  /// decode, as if the key were absent. Checks the platform's own copy, so
  /// damaged data is never taken for "nothing saved yet".
  String? _confirmAbsent(String key) {
    if (!_raw.isSupported) return null;
    final String? raw;
    try {
      raw = _raw.read('$platformKeyPrefix$key');
    } on RawStorageAccessException {
      throw ExpenseStorageUnreadableException(
        key,
        UnreadableReason.inaccessible,
      );
    }
    if (raw == null) return null;
    // A valid value written by another tab after the reload above: the
    // web plugin stores strings JSON-encoded, so this is the same text the
    // plugin would have returned.
    Object? decoded;
    try {
      decoded = json.decode(raw);
    } on FormatException {
      throw ExpenseStorageUnreadableException(
        key,
        UnreadableReason.notDecodable,
      );
    }
    if (decoded is String) return decoded;
    throw ExpenseStorageUnreadableException(
      key,
      decoded == null
          ? UnreadableReason.notDecodable
          : UnreadableReason.unexpectedType,
    );
  }

  /// The platform's exact value of [key], or `null` if it cannot be read.
  String? _exactValue(String key) {
    if (!_raw.isSupported) return null;
    try {
      return _raw.read('$platformKeyPrefix$key');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<StoredExpenseText> readStoredText() async {
    final unreadable = <String, UnreadableStoredValue>{};
    Future<String?> one(String name, String key) async {
      try {
        return await _readText(key);
      } on ExpenseStorageUnreadableException catch (e) {
        unreadable[name] = UnreadableStoredValue(
          platformKey: '$platformKeyPrefix$key',
          reason: e.reason,
          exactValue: _exactValue(key),
        );
        return null;
      }
    }

    final expenses = await one(storageKey, _key);
    final legacyBackup = await one(legacyBackupKey, _legacyKey);
    return StoredExpenseText(
      expenses: expenses,
      legacyBackup: legacyBackup,
      unreadable: unreadable,
    );
  }

  @override
  Future<void> write(String data) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(_key, data);
    if (!saved) {
      throw ExpenseStorageException('Failed to save expenses');
    }
  }

  @override
  Future<void> backupLegacyData(String data) async {
    // An existing backup, readable or not, is never replaced; an
    // unreadable one throws here and stops the rewrite that needed it.
    if (await _readText(_legacyKey) != null) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(_legacyKey, data);
    if (!saved) {
      throw ExpenseStorageException('Failed to back up legacy expenses');
    }
  }
}

String encodeExpenses(List<Expense> expenses) =>
    json.encode(expenses.map((e) => e.toMap()).toList());

/// Whether [a] and [b] serialize identically (same id and content).
bool sameExpense(Expense a, Expense b) =>
    json.encode(a.toMap()) == json.encode(b.toMap());

/// Result of decoding a stored expense collection.
class DecodedExpenses {
  DecodedExpenses(
    this.expenses, {
    required this.hasLegacyRecords,
    this.duplicateIds = const {},
  });

  final List<Expense> expenses;

  /// Whether any record used the legacy floating-point amount format.
  final bool hasLegacyRecords;

  /// IDs that occur on more than one record. All records are kept.
  final Set<String> duplicateIds;
}

/// Decodes a stored expense collection in the current or legacy format.
///
/// Throws a [FormatException] naming the first invalid record if [data] is
/// not a valid expense list. Never skips or merges records; IDs used more
/// than once are reported in [DecodedExpenses.duplicateIds].
DecodedExpenses decodeExpenses(String data) {
  final decoded = json.decode(data);
  if (decoded is! List) {
    throw const FormatException('Expected a JSON list of expenses');
  }
  var hasLegacyRecords = false;
  final expenses = <Expense>[];
  final seen = <String>{};
  final duplicateIds = <String>{};
  for (var i = 0; i < decoded.length; i++) {
    final item = decoded[i];
    if (item is! Map<String, dynamic>) {
      throw FormatException('Expense at index $i is not an object');
    }
    final Expense expense;
    try {
      expense = Expense.fromMap(item);
    } on FormatException catch (e) {
      // The message only; the source would expose the stored record.
      throw FormatException('Expense at index $i: ${e.message}');
    }
    expenses.add(expense);
    if (!seen.add(expense.id)) duplicateIds.add(expense.id);
    hasLegacyRecords |= Expense.isLegacyMap(item);
  }
  return DecodedExpenses(
    expenses,
    hasLegacyRecords: hasLegacyRecords,
    duplicateIds: duplicateIds,
  );
}
