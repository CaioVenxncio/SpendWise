// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ExpenseRowsTable extends ExpenseRows
    with TableInfo<$ExpenseRowsTable, ExpenseRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExpenseRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _amountCentsMeta = const VerificationMeta(
    'amountCents',
  );
  @override
  late final GeneratedColumn<int> amountCents = GeneratedColumn<int>(
    'amount_cents',
    aliasedName,
    false,
    check: () =>
        ComparableExpr(amountCents)
            .isBetweenValues(Money.minCents, Money.maxCents),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<String> occurredAt = GeneratedColumn<String>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    seq,
    id,
    amountCents,
    description,
    category,
    occurredAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'expenses';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExpenseRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('amount_cents')) {
      context.handle(
        _amountCentsMeta,
        amountCents.isAcceptableOrUnknown(
          data['amount_cents']!,
          _amountCentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountCentsMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {seq};
  @override
  ExpenseRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExpenseRow(
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      amountCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_cents'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}occurred_at'],
      )!,
    );
  }

  @override
  $ExpenseRowsTable createAlias(String alias) {
    return $ExpenseRowsTable(attachedDatabase, alias);
  }
}

class ExpenseRow extends DataClass implements Insertable<ExpenseRow> {
  final int seq;
  final String id;
  final int amountCents;
  final String description;
  final String category;

  /// The original ISO-8601 text, stored verbatim.
  final String occurredAt;
  const ExpenseRow({
    required this.seq,
    required this.id,
    required this.amountCents,
    required this.description,
    required this.category,
    required this.occurredAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['seq'] = Variable<int>(seq);
    map['id'] = Variable<String>(id);
    map['amount_cents'] = Variable<int>(amountCents);
    map['description'] = Variable<String>(description);
    map['category'] = Variable<String>(category);
    map['occurred_at'] = Variable<String>(occurredAt);
    return map;
  }

  ExpenseRowsCompanion toCompanion(bool nullToAbsent) {
    return ExpenseRowsCompanion(
      seq: Value(seq),
      id: Value(id),
      amountCents: Value(amountCents),
      description: Value(description),
      category: Value(category),
      occurredAt: Value(occurredAt),
    );
  }

  factory ExpenseRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExpenseRow(
      seq: serializer.fromJson<int>(json['seq']),
      id: serializer.fromJson<String>(json['id']),
      amountCents: serializer.fromJson<int>(json['amountCents']),
      description: serializer.fromJson<String>(json['description']),
      category: serializer.fromJson<String>(json['category']),
      occurredAt: serializer.fromJson<String>(json['occurredAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'seq': serializer.toJson<int>(seq),
      'id': serializer.toJson<String>(id),
      'amountCents': serializer.toJson<int>(amountCents),
      'description': serializer.toJson<String>(description),
      'category': serializer.toJson<String>(category),
      'occurredAt': serializer.toJson<String>(occurredAt),
    };
  }

  ExpenseRow copyWith({
    int? seq,
    String? id,
    int? amountCents,
    String? description,
    String? category,
    String? occurredAt,
  }) => ExpenseRow(
    seq: seq ?? this.seq,
    id: id ?? this.id,
    amountCents: amountCents ?? this.amountCents,
    description: description ?? this.description,
    category: category ?? this.category,
    occurredAt: occurredAt ?? this.occurredAt,
  );
  ExpenseRow copyWithCompanion(ExpenseRowsCompanion data) {
    return ExpenseRow(
      seq: data.seq.present ? data.seq.value : this.seq,
      id: data.id.present ? data.id.value : this.id,
      amountCents: data.amountCents.present
          ? data.amountCents.value
          : this.amountCents,
      description: data.description.present
          ? data.description.value
          : this.description,
      category: data.category.present ? data.category.value : this.category,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExpenseRow(')
          ..write('seq: $seq, ')
          ..write('id: $id, ')
          ..write('amountCents: $amountCents, ')
          ..write('description: $description, ')
          ..write('category: $category, ')
          ..write('occurredAt: $occurredAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(seq, id, amountCents, description, category, occurredAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExpenseRow &&
          other.seq == this.seq &&
          other.id == this.id &&
          other.amountCents == this.amountCents &&
          other.description == this.description &&
          other.category == this.category &&
          other.occurredAt == this.occurredAt);
}

class ExpenseRowsCompanion extends UpdateCompanion<ExpenseRow> {
  final Value<int> seq;
  final Value<String> id;
  final Value<int> amountCents;
  final Value<String> description;
  final Value<String> category;
  final Value<String> occurredAt;
  const ExpenseRowsCompanion({
    this.seq = const Value.absent(),
    this.id = const Value.absent(),
    this.amountCents = const Value.absent(),
    this.description = const Value.absent(),
    this.category = const Value.absent(),
    this.occurredAt = const Value.absent(),
  });
  ExpenseRowsCompanion.insert({
    this.seq = const Value.absent(),
    required String id,
    required int amountCents,
    required String description,
    required String category,
    required String occurredAt,
  }) : id = Value(id),
       amountCents = Value(amountCents),
       description = Value(description),
       category = Value(category),
       occurredAt = Value(occurredAt);
  static Insertable<ExpenseRow> custom({
    Expression<int>? seq,
    Expression<String>? id,
    Expression<int>? amountCents,
    Expression<String>? description,
    Expression<String>? category,
    Expression<String>? occurredAt,
  }) {
    return RawValuesInsertable({
      if (seq != null) 'seq': seq,
      if (id != null) 'id': id,
      if (amountCents != null) 'amount_cents': amountCents,
      if (description != null) 'description': description,
      if (category != null) 'category': category,
      if (occurredAt != null) 'occurred_at': occurredAt,
    });
  }

  ExpenseRowsCompanion copyWith({
    Value<int>? seq,
    Value<String>? id,
    Value<int>? amountCents,
    Value<String>? description,
    Value<String>? category,
    Value<String>? occurredAt,
  }) {
    return ExpenseRowsCompanion(
      seq: seq ?? this.seq,
      id: id ?? this.id,
      amountCents: amountCents ?? this.amountCents,
      description: description ?? this.description,
      category: category ?? this.category,
      occurredAt: occurredAt ?? this.occurredAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (amountCents.present) {
      map['amount_cents'] = Variable<int>(amountCents.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<String>(occurredAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExpenseRowsCompanion(')
          ..write('seq: $seq, ')
          ..write('id: $id, ')
          ..write('amountCents: $amountCents, ')
          ..write('description: $description, ')
          ..write('category: $category, ')
          ..write('occurredAt: $occurredAt')
          ..write(')'))
        .toString();
  }
}

class $MigrationSnapshotsTable extends MigrationSnapshots
    with TableInfo<$MigrationSnapshotsTable, MigrationSnapshot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MigrationSnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sourceKeyMeta = const VerificationMeta(
    'sourceKey',
  );
  @override
  late final GeneratedColumn<String> sourceKey = GeneratedColumn<String>(
    'source_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _rawTextMeta = const VerificationMeta(
    'rawText',
  );
  @override
  late final GeneratedColumn<String> rawText = GeneratedColumn<String>(
    'raw_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _legacyBackupTextMeta = const VerificationMeta(
    'legacyBackupText',
  );
  @override
  late final GeneratedColumn<String> legacyBackupText = GeneratedColumn<String>(
    'legacy_backup_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _capturedAtMeta = const VerificationMeta(
    'capturedAt',
  );
  @override
  late final GeneratedColumn<String> capturedAt = GeneratedColumn<String>(
    'captured_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sourceKey,
    fingerprint,
    rawText,
    legacyBackupText,
    capturedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'migration_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<MigrationSnapshot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('source_key')) {
      context.handle(
        _sourceKeyMeta,
        sourceKey.isAcceptableOrUnknown(data['source_key']!, _sourceKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceKeyMeta);
    }
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    if (data.containsKey('raw_text')) {
      context.handle(
        _rawTextMeta,
        rawText.isAcceptableOrUnknown(data['raw_text']!, _rawTextMeta),
      );
    }
    if (data.containsKey('legacy_backup_text')) {
      context.handle(
        _legacyBackupTextMeta,
        legacyBackupText.isAcceptableOrUnknown(
          data['legacy_backup_text']!,
          _legacyBackupTextMeta,
        ),
      );
    }
    if (data.containsKey('captured_at')) {
      context.handle(
        _capturedAtMeta,
        capturedAt.isAcceptableOrUnknown(data['captured_at']!, _capturedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_capturedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MigrationSnapshot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MigrationSnapshot(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sourceKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_key'],
      )!,
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      rawText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_text'],
      ),
      legacyBackupText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}legacy_backup_text'],
      ),
      capturedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}captured_at'],
      )!,
    );
  }

  @override
  $MigrationSnapshotsTable createAlias(String alias) {
    return $MigrationSnapshotsTable(attachedDatabase, alias);
  }
}

class MigrationSnapshot extends DataClass
    implements Insertable<MigrationSnapshot> {
  final int id;

  /// Storage key the source was read from, e.g. `expenses`.
  final String sourceKey;

  /// `sha256:<hex>` of the exact source text, or `absent`. Unique, so the
  /// same source can never be migrated twice.
  final String fingerprint;

  /// The source text exactly as read; `null` when the key was absent.
  final String? rawText;

  /// The legacy backup key's text at migration time, if any.
  final String? legacyBackupText;
  final String capturedAt;
  const MigrationSnapshot({
    required this.id,
    required this.sourceKey,
    required this.fingerprint,
    this.rawText,
    this.legacyBackupText,
    required this.capturedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['source_key'] = Variable<String>(sourceKey);
    map['fingerprint'] = Variable<String>(fingerprint);
    if (!nullToAbsent || rawText != null) {
      map['raw_text'] = Variable<String>(rawText);
    }
    if (!nullToAbsent || legacyBackupText != null) {
      map['legacy_backup_text'] = Variable<String>(legacyBackupText);
    }
    map['captured_at'] = Variable<String>(capturedAt);
    return map;
  }

  MigrationSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return MigrationSnapshotsCompanion(
      id: Value(id),
      sourceKey: Value(sourceKey),
      fingerprint: Value(fingerprint),
      rawText: rawText == null && nullToAbsent
          ? const Value.absent()
          : Value(rawText),
      legacyBackupText: legacyBackupText == null && nullToAbsent
          ? const Value.absent()
          : Value(legacyBackupText),
      capturedAt: Value(capturedAt),
    );
  }

  factory MigrationSnapshot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MigrationSnapshot(
      id: serializer.fromJson<int>(json['id']),
      sourceKey: serializer.fromJson<String>(json['sourceKey']),
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      rawText: serializer.fromJson<String?>(json['rawText']),
      legacyBackupText: serializer.fromJson<String?>(json['legacyBackupText']),
      capturedAt: serializer.fromJson<String>(json['capturedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sourceKey': serializer.toJson<String>(sourceKey),
      'fingerprint': serializer.toJson<String>(fingerprint),
      'rawText': serializer.toJson<String?>(rawText),
      'legacyBackupText': serializer.toJson<String?>(legacyBackupText),
      'capturedAt': serializer.toJson<String>(capturedAt),
    };
  }

  MigrationSnapshot copyWith({
    int? id,
    String? sourceKey,
    String? fingerprint,
    Value<String?> rawText = const Value.absent(),
    Value<String?> legacyBackupText = const Value.absent(),
    String? capturedAt,
  }) => MigrationSnapshot(
    id: id ?? this.id,
    sourceKey: sourceKey ?? this.sourceKey,
    fingerprint: fingerprint ?? this.fingerprint,
    rawText: rawText.present ? rawText.value : this.rawText,
    legacyBackupText: legacyBackupText.present
        ? legacyBackupText.value
        : this.legacyBackupText,
    capturedAt: capturedAt ?? this.capturedAt,
  );
  MigrationSnapshot copyWithCompanion(MigrationSnapshotsCompanion data) {
    return MigrationSnapshot(
      id: data.id.present ? data.id.value : this.id,
      sourceKey: data.sourceKey.present ? data.sourceKey.value : this.sourceKey,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      rawText: data.rawText.present ? data.rawText.value : this.rawText,
      legacyBackupText: data.legacyBackupText.present
          ? data.legacyBackupText.value
          : this.legacyBackupText,
      capturedAt: data.capturedAt.present
          ? data.capturedAt.value
          : this.capturedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MigrationSnapshot(')
          ..write('id: $id, ')
          ..write('sourceKey: $sourceKey, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('rawText: $rawText, ')
          ..write('legacyBackupText: $legacyBackupText, ')
          ..write('capturedAt: $capturedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sourceKey,
    fingerprint,
    rawText,
    legacyBackupText,
    capturedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MigrationSnapshot &&
          other.id == this.id &&
          other.sourceKey == this.sourceKey &&
          other.fingerprint == this.fingerprint &&
          other.rawText == this.rawText &&
          other.legacyBackupText == this.legacyBackupText &&
          other.capturedAt == this.capturedAt);
}

class MigrationSnapshotsCompanion extends UpdateCompanion<MigrationSnapshot> {
  final Value<int> id;
  final Value<String> sourceKey;
  final Value<String> fingerprint;
  final Value<String?> rawText;
  final Value<String?> legacyBackupText;
  final Value<String> capturedAt;
  const MigrationSnapshotsCompanion({
    this.id = const Value.absent(),
    this.sourceKey = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.rawText = const Value.absent(),
    this.legacyBackupText = const Value.absent(),
    this.capturedAt = const Value.absent(),
  });
  MigrationSnapshotsCompanion.insert({
    this.id = const Value.absent(),
    required String sourceKey,
    required String fingerprint,
    this.rawText = const Value.absent(),
    this.legacyBackupText = const Value.absent(),
    required String capturedAt,
  }) : sourceKey = Value(sourceKey),
       fingerprint = Value(fingerprint),
       capturedAt = Value(capturedAt);
  static Insertable<MigrationSnapshot> custom({
    Expression<int>? id,
    Expression<String>? sourceKey,
    Expression<String>? fingerprint,
    Expression<String>? rawText,
    Expression<String>? legacyBackupText,
    Expression<String>? capturedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceKey != null) 'source_key': sourceKey,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (rawText != null) 'raw_text': rawText,
      if (legacyBackupText != null) 'legacy_backup_text': legacyBackupText,
      if (capturedAt != null) 'captured_at': capturedAt,
    });
  }

  MigrationSnapshotsCompanion copyWith({
    Value<int>? id,
    Value<String>? sourceKey,
    Value<String>? fingerprint,
    Value<String?>? rawText,
    Value<String?>? legacyBackupText,
    Value<String>? capturedAt,
  }) {
    return MigrationSnapshotsCompanion(
      id: id ?? this.id,
      sourceKey: sourceKey ?? this.sourceKey,
      fingerprint: fingerprint ?? this.fingerprint,
      rawText: rawText ?? this.rawText,
      legacyBackupText: legacyBackupText ?? this.legacyBackupText,
      capturedAt: capturedAt ?? this.capturedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sourceKey.present) {
      map['source_key'] = Variable<String>(sourceKey.value);
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (rawText.present) {
      map['raw_text'] = Variable<String>(rawText.value);
    }
    if (legacyBackupText.present) {
      map['legacy_backup_text'] = Variable<String>(legacyBackupText.value);
    }
    if (capturedAt.present) {
      map['captured_at'] = Variable<String>(capturedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MigrationSnapshotsCompanion(')
          ..write('id: $id, ')
          ..write('sourceKey: $sourceKey, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('rawText: $rawText, ')
          ..write('legacyBackupText: $legacyBackupText, ')
          ..write('capturedAt: $capturedAt')
          ..write(')'))
        .toString();
  }
}

class $MigrationRunsTable extends MigrationRuns
    with TableInfo<$MigrationRunsTable, MigrationRun> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MigrationRunsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _snapshotIdMeta = const VerificationMeta(
    'snapshotId',
  );
  @override
  late final GeneratedColumn<int> snapshotId = GeneratedColumn<int>(
    'snapshot_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'UNIQUE REFERENCES migration_snapshots (id)',
    ),
  );
  static const VerificationMeta _algorithmVersionMeta = const VerificationMeta(
    'algorithmVersion',
  );
  @override
  late final GeneratedColumn<int> algorithmVersion = GeneratedColumn<int>(
    'algorithm_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceRecordsMeta = const VerificationMeta(
    'sourceRecords',
  );
  @override
  late final GeneratedColumn<int> sourceRecords = GeneratedColumn<int>(
    'source_records',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _importedRecordsMeta = const VerificationMeta(
    'importedRecords',
  );
  @override
  late final GeneratedColumn<int> importedRecords = GeneratedColumn<int>(
    'imported_records',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _alreadyPresentMeta = const VerificationMeta(
    'alreadyPresent',
  );
  @override
  late final GeneratedColumn<int> alreadyPresent = GeneratedColumn<int>(
    'already_present',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _duplicatesCollapsedMeta =
      const VerificationMeta('duplicatesCollapsed');
  @override
  late final GeneratedColumn<int> duplicatesCollapsed = GeneratedColumn<int>(
    'duplicates_collapsed',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hadLegacyRecordsMeta = const VerificationMeta(
    'hadLegacyRecords',
  );
  @override
  late final GeneratedColumn<bool> hadLegacyRecords = GeneratedColumn<bool>(
    'had_legacy_records',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("had_legacy_records" IN (0, 1))',
    ),
  );
  static const VerificationMeta _totalCentsMeta = const VerificationMeta(
    'totalCents',
  );
  @override
  late final GeneratedColumn<String> totalCents = GeneratedColumn<String>(
    'total_cents',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _approvedChangedSourceMeta =
      const VerificationMeta('approvedChangedSource');
  @override
  late final GeneratedColumn<bool> approvedChangedSource =
      GeneratedColumn<bool>(
        'approved_changed_source',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("approved_changed_source" IN (0, 1))',
        ),
      );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<String> completedAt = GeneratedColumn<String>(
    'completed_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    snapshotId,
    algorithmVersion,
    sourceRecords,
    importedRecords,
    alreadyPresent,
    duplicatesCollapsed,
    hadLegacyRecords,
    totalCents,
    approvedChangedSource,
    completedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'migration_runs';
  @override
  VerificationContext validateIntegrity(
    Insertable<MigrationRun> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('snapshot_id')) {
      context.handle(
        _snapshotIdMeta,
        snapshotId.isAcceptableOrUnknown(data['snapshot_id']!, _snapshotIdMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotIdMeta);
    }
    if (data.containsKey('algorithm_version')) {
      context.handle(
        _algorithmVersionMeta,
        algorithmVersion.isAcceptableOrUnknown(
          data['algorithm_version']!,
          _algorithmVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_algorithmVersionMeta);
    }
    if (data.containsKey('source_records')) {
      context.handle(
        _sourceRecordsMeta,
        sourceRecords.isAcceptableOrUnknown(
          data['source_records']!,
          _sourceRecordsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceRecordsMeta);
    }
    if (data.containsKey('imported_records')) {
      context.handle(
        _importedRecordsMeta,
        importedRecords.isAcceptableOrUnknown(
          data['imported_records']!,
          _importedRecordsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_importedRecordsMeta);
    }
    if (data.containsKey('already_present')) {
      context.handle(
        _alreadyPresentMeta,
        alreadyPresent.isAcceptableOrUnknown(
          data['already_present']!,
          _alreadyPresentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_alreadyPresentMeta);
    }
    if (data.containsKey('duplicates_collapsed')) {
      context.handle(
        _duplicatesCollapsedMeta,
        duplicatesCollapsed.isAcceptableOrUnknown(
          data['duplicates_collapsed']!,
          _duplicatesCollapsedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_duplicatesCollapsedMeta);
    }
    if (data.containsKey('had_legacy_records')) {
      context.handle(
        _hadLegacyRecordsMeta,
        hadLegacyRecords.isAcceptableOrUnknown(
          data['had_legacy_records']!,
          _hadLegacyRecordsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_hadLegacyRecordsMeta);
    }
    if (data.containsKey('total_cents')) {
      context.handle(
        _totalCentsMeta,
        totalCents.isAcceptableOrUnknown(data['total_cents']!, _totalCentsMeta),
      );
    } else if (isInserting) {
      context.missing(_totalCentsMeta);
    }
    if (data.containsKey('approved_changed_source')) {
      context.handle(
        _approvedChangedSourceMeta,
        approvedChangedSource.isAcceptableOrUnknown(
          data['approved_changed_source']!,
          _approvedChangedSourceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_approvedChangedSourceMeta);
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_completedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MigrationRun map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MigrationRun(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      snapshotId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}snapshot_id'],
      )!,
      algorithmVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}algorithm_version'],
      )!,
      sourceRecords: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_records'],
      )!,
      importedRecords: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}imported_records'],
      )!,
      alreadyPresent: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}already_present'],
      )!,
      duplicatesCollapsed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duplicates_collapsed'],
      )!,
      hadLegacyRecords: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}had_legacy_records'],
      )!,
      totalCents: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}total_cents'],
      )!,
      approvedChangedSource: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}approved_changed_source'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}completed_at'],
      )!,
    );
  }

  @override
  $MigrationRunsTable createAlias(String alias) {
    return $MigrationRunsTable(attachedDatabase, alias);
  }
}

class MigrationRun extends DataClass implements Insertable<MigrationRun> {
  final int id;
  final int snapshotId;

  /// Version of the migration algorithm that produced this run.
  final int algorithmVersion;

  /// Records in the source, before collapsing identical duplicates.
  final int sourceRecords;
  final int importedRecords;

  /// Records identical to rows already in the database (skipped).
  final int alreadyPresent;

  /// Source records that repeated an earlier record exactly.
  final int duplicatesCollapsed;
  final bool hadLegacyRecords;

  /// Exact total of the migrated records in cents, as a decimal string.
  final String totalCents;

  /// Whether the user explicitly approved importing a changed source.
  final bool approvedChangedSource;
  final String completedAt;
  const MigrationRun({
    required this.id,
    required this.snapshotId,
    required this.algorithmVersion,
    required this.sourceRecords,
    required this.importedRecords,
    required this.alreadyPresent,
    required this.duplicatesCollapsed,
    required this.hadLegacyRecords,
    required this.totalCents,
    required this.approvedChangedSource,
    required this.completedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['snapshot_id'] = Variable<int>(snapshotId);
    map['algorithm_version'] = Variable<int>(algorithmVersion);
    map['source_records'] = Variable<int>(sourceRecords);
    map['imported_records'] = Variable<int>(importedRecords);
    map['already_present'] = Variable<int>(alreadyPresent);
    map['duplicates_collapsed'] = Variable<int>(duplicatesCollapsed);
    map['had_legacy_records'] = Variable<bool>(hadLegacyRecords);
    map['total_cents'] = Variable<String>(totalCents);
    map['approved_changed_source'] = Variable<bool>(approvedChangedSource);
    map['completed_at'] = Variable<String>(completedAt);
    return map;
  }

  MigrationRunsCompanion toCompanion(bool nullToAbsent) {
    return MigrationRunsCompanion(
      id: Value(id),
      snapshotId: Value(snapshotId),
      algorithmVersion: Value(algorithmVersion),
      sourceRecords: Value(sourceRecords),
      importedRecords: Value(importedRecords),
      alreadyPresent: Value(alreadyPresent),
      duplicatesCollapsed: Value(duplicatesCollapsed),
      hadLegacyRecords: Value(hadLegacyRecords),
      totalCents: Value(totalCents),
      approvedChangedSource: Value(approvedChangedSource),
      completedAt: Value(completedAt),
    );
  }

  factory MigrationRun.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MigrationRun(
      id: serializer.fromJson<int>(json['id']),
      snapshotId: serializer.fromJson<int>(json['snapshotId']),
      algorithmVersion: serializer.fromJson<int>(json['algorithmVersion']),
      sourceRecords: serializer.fromJson<int>(json['sourceRecords']),
      importedRecords: serializer.fromJson<int>(json['importedRecords']),
      alreadyPresent: serializer.fromJson<int>(json['alreadyPresent']),
      duplicatesCollapsed: serializer.fromJson<int>(
        json['duplicatesCollapsed'],
      ),
      hadLegacyRecords: serializer.fromJson<bool>(json['hadLegacyRecords']),
      totalCents: serializer.fromJson<String>(json['totalCents']),
      approvedChangedSource: serializer.fromJson<bool>(
        json['approvedChangedSource'],
      ),
      completedAt: serializer.fromJson<String>(json['completedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'snapshotId': serializer.toJson<int>(snapshotId),
      'algorithmVersion': serializer.toJson<int>(algorithmVersion),
      'sourceRecords': serializer.toJson<int>(sourceRecords),
      'importedRecords': serializer.toJson<int>(importedRecords),
      'alreadyPresent': serializer.toJson<int>(alreadyPresent),
      'duplicatesCollapsed': serializer.toJson<int>(duplicatesCollapsed),
      'hadLegacyRecords': serializer.toJson<bool>(hadLegacyRecords),
      'totalCents': serializer.toJson<String>(totalCents),
      'approvedChangedSource': serializer.toJson<bool>(approvedChangedSource),
      'completedAt': serializer.toJson<String>(completedAt),
    };
  }

  MigrationRun copyWith({
    int? id,
    int? snapshotId,
    int? algorithmVersion,
    int? sourceRecords,
    int? importedRecords,
    int? alreadyPresent,
    int? duplicatesCollapsed,
    bool? hadLegacyRecords,
    String? totalCents,
    bool? approvedChangedSource,
    String? completedAt,
  }) => MigrationRun(
    id: id ?? this.id,
    snapshotId: snapshotId ?? this.snapshotId,
    algorithmVersion: algorithmVersion ?? this.algorithmVersion,
    sourceRecords: sourceRecords ?? this.sourceRecords,
    importedRecords: importedRecords ?? this.importedRecords,
    alreadyPresent: alreadyPresent ?? this.alreadyPresent,
    duplicatesCollapsed: duplicatesCollapsed ?? this.duplicatesCollapsed,
    hadLegacyRecords: hadLegacyRecords ?? this.hadLegacyRecords,
    totalCents: totalCents ?? this.totalCents,
    approvedChangedSource: approvedChangedSource ?? this.approvedChangedSource,
    completedAt: completedAt ?? this.completedAt,
  );
  MigrationRun copyWithCompanion(MigrationRunsCompanion data) {
    return MigrationRun(
      id: data.id.present ? data.id.value : this.id,
      snapshotId: data.snapshotId.present
          ? data.snapshotId.value
          : this.snapshotId,
      algorithmVersion: data.algorithmVersion.present
          ? data.algorithmVersion.value
          : this.algorithmVersion,
      sourceRecords: data.sourceRecords.present
          ? data.sourceRecords.value
          : this.sourceRecords,
      importedRecords: data.importedRecords.present
          ? data.importedRecords.value
          : this.importedRecords,
      alreadyPresent: data.alreadyPresent.present
          ? data.alreadyPresent.value
          : this.alreadyPresent,
      duplicatesCollapsed: data.duplicatesCollapsed.present
          ? data.duplicatesCollapsed.value
          : this.duplicatesCollapsed,
      hadLegacyRecords: data.hadLegacyRecords.present
          ? data.hadLegacyRecords.value
          : this.hadLegacyRecords,
      totalCents: data.totalCents.present
          ? data.totalCents.value
          : this.totalCents,
      approvedChangedSource: data.approvedChangedSource.present
          ? data.approvedChangedSource.value
          : this.approvedChangedSource,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MigrationRun(')
          ..write('id: $id, ')
          ..write('snapshotId: $snapshotId, ')
          ..write('algorithmVersion: $algorithmVersion, ')
          ..write('sourceRecords: $sourceRecords, ')
          ..write('importedRecords: $importedRecords, ')
          ..write('alreadyPresent: $alreadyPresent, ')
          ..write('duplicatesCollapsed: $duplicatesCollapsed, ')
          ..write('hadLegacyRecords: $hadLegacyRecords, ')
          ..write('totalCents: $totalCents, ')
          ..write('approvedChangedSource: $approvedChangedSource, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    snapshotId,
    algorithmVersion,
    sourceRecords,
    importedRecords,
    alreadyPresent,
    duplicatesCollapsed,
    hadLegacyRecords,
    totalCents,
    approvedChangedSource,
    completedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MigrationRun &&
          other.id == this.id &&
          other.snapshotId == this.snapshotId &&
          other.algorithmVersion == this.algorithmVersion &&
          other.sourceRecords == this.sourceRecords &&
          other.importedRecords == this.importedRecords &&
          other.alreadyPresent == this.alreadyPresent &&
          other.duplicatesCollapsed == this.duplicatesCollapsed &&
          other.hadLegacyRecords == this.hadLegacyRecords &&
          other.totalCents == this.totalCents &&
          other.approvedChangedSource == this.approvedChangedSource &&
          other.completedAt == this.completedAt);
}

class MigrationRunsCompanion extends UpdateCompanion<MigrationRun> {
  final Value<int> id;
  final Value<int> snapshotId;
  final Value<int> algorithmVersion;
  final Value<int> sourceRecords;
  final Value<int> importedRecords;
  final Value<int> alreadyPresent;
  final Value<int> duplicatesCollapsed;
  final Value<bool> hadLegacyRecords;
  final Value<String> totalCents;
  final Value<bool> approvedChangedSource;
  final Value<String> completedAt;
  const MigrationRunsCompanion({
    this.id = const Value.absent(),
    this.snapshotId = const Value.absent(),
    this.algorithmVersion = const Value.absent(),
    this.sourceRecords = const Value.absent(),
    this.importedRecords = const Value.absent(),
    this.alreadyPresent = const Value.absent(),
    this.duplicatesCollapsed = const Value.absent(),
    this.hadLegacyRecords = const Value.absent(),
    this.totalCents = const Value.absent(),
    this.approvedChangedSource = const Value.absent(),
    this.completedAt = const Value.absent(),
  });
  MigrationRunsCompanion.insert({
    this.id = const Value.absent(),
    required int snapshotId,
    required int algorithmVersion,
    required int sourceRecords,
    required int importedRecords,
    required int alreadyPresent,
    required int duplicatesCollapsed,
    required bool hadLegacyRecords,
    required String totalCents,
    required bool approvedChangedSource,
    required String completedAt,
  }) : snapshotId = Value(snapshotId),
       algorithmVersion = Value(algorithmVersion),
       sourceRecords = Value(sourceRecords),
       importedRecords = Value(importedRecords),
       alreadyPresent = Value(alreadyPresent),
       duplicatesCollapsed = Value(duplicatesCollapsed),
       hadLegacyRecords = Value(hadLegacyRecords),
       totalCents = Value(totalCents),
       approvedChangedSource = Value(approvedChangedSource),
       completedAt = Value(completedAt);
  static Insertable<MigrationRun> custom({
    Expression<int>? id,
    Expression<int>? snapshotId,
    Expression<int>? algorithmVersion,
    Expression<int>? sourceRecords,
    Expression<int>? importedRecords,
    Expression<int>? alreadyPresent,
    Expression<int>? duplicatesCollapsed,
    Expression<bool>? hadLegacyRecords,
    Expression<String>? totalCents,
    Expression<bool>? approvedChangedSource,
    Expression<String>? completedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (snapshotId != null) 'snapshot_id': snapshotId,
      if (algorithmVersion != null) 'algorithm_version': algorithmVersion,
      if (sourceRecords != null) 'source_records': sourceRecords,
      if (importedRecords != null) 'imported_records': importedRecords,
      if (alreadyPresent != null) 'already_present': alreadyPresent,
      if (duplicatesCollapsed != null)
        'duplicates_collapsed': duplicatesCollapsed,
      if (hadLegacyRecords != null) 'had_legacy_records': hadLegacyRecords,
      if (totalCents != null) 'total_cents': totalCents,
      if (approvedChangedSource != null)
        'approved_changed_source': approvedChangedSource,
      if (completedAt != null) 'completed_at': completedAt,
    });
  }

  MigrationRunsCompanion copyWith({
    Value<int>? id,
    Value<int>? snapshotId,
    Value<int>? algorithmVersion,
    Value<int>? sourceRecords,
    Value<int>? importedRecords,
    Value<int>? alreadyPresent,
    Value<int>? duplicatesCollapsed,
    Value<bool>? hadLegacyRecords,
    Value<String>? totalCents,
    Value<bool>? approvedChangedSource,
    Value<String>? completedAt,
  }) {
    return MigrationRunsCompanion(
      id: id ?? this.id,
      snapshotId: snapshotId ?? this.snapshotId,
      algorithmVersion: algorithmVersion ?? this.algorithmVersion,
      sourceRecords: sourceRecords ?? this.sourceRecords,
      importedRecords: importedRecords ?? this.importedRecords,
      alreadyPresent: alreadyPresent ?? this.alreadyPresent,
      duplicatesCollapsed: duplicatesCollapsed ?? this.duplicatesCollapsed,
      hadLegacyRecords: hadLegacyRecords ?? this.hadLegacyRecords,
      totalCents: totalCents ?? this.totalCents,
      approvedChangedSource:
          approvedChangedSource ?? this.approvedChangedSource,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (snapshotId.present) {
      map['snapshot_id'] = Variable<int>(snapshotId.value);
    }
    if (algorithmVersion.present) {
      map['algorithm_version'] = Variable<int>(algorithmVersion.value);
    }
    if (sourceRecords.present) {
      map['source_records'] = Variable<int>(sourceRecords.value);
    }
    if (importedRecords.present) {
      map['imported_records'] = Variable<int>(importedRecords.value);
    }
    if (alreadyPresent.present) {
      map['already_present'] = Variable<int>(alreadyPresent.value);
    }
    if (duplicatesCollapsed.present) {
      map['duplicates_collapsed'] = Variable<int>(duplicatesCollapsed.value);
    }
    if (hadLegacyRecords.present) {
      map['had_legacy_records'] = Variable<bool>(hadLegacyRecords.value);
    }
    if (totalCents.present) {
      map['total_cents'] = Variable<String>(totalCents.value);
    }
    if (approvedChangedSource.present) {
      map['approved_changed_source'] = Variable<bool>(
        approvedChangedSource.value,
      );
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<String>(completedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MigrationRunsCompanion(')
          ..write('id: $id, ')
          ..write('snapshotId: $snapshotId, ')
          ..write('algorithmVersion: $algorithmVersion, ')
          ..write('sourceRecords: $sourceRecords, ')
          ..write('importedRecords: $importedRecords, ')
          ..write('alreadyPresent: $alreadyPresent, ')
          ..write('duplicatesCollapsed: $duplicatesCollapsed, ')
          ..write('hadLegacyRecords: $hadLegacyRecords, ')
          ..write('totalCents: $totalCents, ')
          ..write('approvedChangedSource: $approvedChangedSource, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$SpendWiseDatabase extends GeneratedDatabase {
  _$SpendWiseDatabase(QueryExecutor e) : super(e);
  $SpendWiseDatabaseManager get managers => $SpendWiseDatabaseManager(this);
  late final $ExpenseRowsTable expenseRows = $ExpenseRowsTable(this);
  late final $MigrationSnapshotsTable migrationSnapshots =
      $MigrationSnapshotsTable(this);
  late final $MigrationRunsTable migrationRuns = $MigrationRunsTable(this);
  late final Index expensesOccurredAt = Index(
    'expenses_occurred_at',
    'CREATE INDEX expenses_occurred_at ON expenses (occurred_at)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    expenseRows,
    migrationSnapshots,
    migrationRuns,
    expensesOccurredAt,
  ];
}

typedef $$ExpenseRowsTableCreateCompanionBuilder =
    ExpenseRowsCompanion Function({
      Value<int> seq,
      required String id,
      required int amountCents,
      required String description,
      required String category,
      required String occurredAt,
    });
typedef $$ExpenseRowsTableUpdateCompanionBuilder =
    ExpenseRowsCompanion Function({
      Value<int> seq,
      Value<String> id,
      Value<int> amountCents,
      Value<String> description,
      Value<String> category,
      Value<String> occurredAt,
    });

class $$ExpenseRowsTableFilterComposer
    extends Composer<_$SpendWiseDatabase, $ExpenseRowsTable> {
  $$ExpenseRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ExpenseRowsTableOrderingComposer
    extends Composer<_$SpendWiseDatabase, $ExpenseRowsTable> {
  $$ExpenseRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ExpenseRowsTableAnnotationComposer
    extends Composer<_$SpendWiseDatabase, $ExpenseRowsTable> {
  $$ExpenseRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );
}

class $$ExpenseRowsTableTableManager
    extends
        RootTableManager<
          _$SpendWiseDatabase,
          $ExpenseRowsTable,
          ExpenseRow,
          $$ExpenseRowsTableFilterComposer,
          $$ExpenseRowsTableOrderingComposer,
          $$ExpenseRowsTableAnnotationComposer,
          $$ExpenseRowsTableCreateCompanionBuilder,
          $$ExpenseRowsTableUpdateCompanionBuilder,
          (
            ExpenseRow,
            BaseReferences<_$SpendWiseDatabase, $ExpenseRowsTable, ExpenseRow>,
          ),
          ExpenseRow,
          PrefetchHooks Function()
        > {
  $$ExpenseRowsTableTableManager(
    _$SpendWiseDatabase db,
    $ExpenseRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExpenseRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExpenseRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExpenseRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> seq = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<int> amountCents = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String> occurredAt = const Value.absent(),
              }) => ExpenseRowsCompanion(
                seq: seq,
                id: id,
                amountCents: amountCents,
                description: description,
                category: category,
                occurredAt: occurredAt,
              ),
          createCompanionCallback:
              ({
                Value<int> seq = const Value.absent(),
                required String id,
                required int amountCents,
                required String description,
                required String category,
                required String occurredAt,
              }) => ExpenseRowsCompanion.insert(
                seq: seq,
                id: id,
                amountCents: amountCents,
                description: description,
                category: category,
                occurredAt: occurredAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ExpenseRowsTable, ExpenseRow>(table),
                  BaseReferences<
                    _$SpendWiseDatabase,
                    $ExpenseRowsTable,
                    ExpenseRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ExpenseRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$SpendWiseDatabase,
      $ExpenseRowsTable,
      ExpenseRow,
      $$ExpenseRowsTableFilterComposer,
      $$ExpenseRowsTableOrderingComposer,
      $$ExpenseRowsTableAnnotationComposer,
      $$ExpenseRowsTableCreateCompanionBuilder,
      $$ExpenseRowsTableUpdateCompanionBuilder,
      (
        ExpenseRow,
        BaseReferences<_$SpendWiseDatabase, $ExpenseRowsTable, ExpenseRow>,
      ),
      ExpenseRow,
      PrefetchHooks Function()
    >;
typedef $$MigrationSnapshotsTableCreateCompanionBuilder =
    MigrationSnapshotsCompanion Function({
      Value<int> id,
      required String sourceKey,
      required String fingerprint,
      Value<String?> rawText,
      Value<String?> legacyBackupText,
      required String capturedAt,
    });
typedef $$MigrationSnapshotsTableUpdateCompanionBuilder =
    MigrationSnapshotsCompanion Function({
      Value<int> id,
      Value<String> sourceKey,
      Value<String> fingerprint,
      Value<String?> rawText,
      Value<String?> legacyBackupText,
      Value<String> capturedAt,
    });

final class $$MigrationSnapshotsTableReferences
    extends
        BaseReferences<
          _$SpendWiseDatabase,
          $MigrationSnapshotsTable,
          MigrationSnapshot
        > {
  $$MigrationSnapshotsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$MigrationRunsTable, List<MigrationRun>>
  _migrationRunsRefsTable(_$SpendWiseDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.migrationRuns,
        aliasName: 'migration_snapshots__id__migration_runs__snapshot_id',
      );

  $$MigrationRunsTableProcessedTableManager get migrationRunsRefs {
    final manager = $$MigrationRunsTableTableManager(
      $_db,
      $_db.migrationRuns,
    ).filter((f) => f.snapshotId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_migrationRunsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MigrationSnapshotsTableFilterComposer
    extends Composer<_$SpendWiseDatabase, $MigrationSnapshotsTable> {
  $$MigrationSnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceKey => $composableBuilder(
    column: $table.sourceKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawText => $composableBuilder(
    column: $table.rawText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get legacyBackupText => $composableBuilder(
    column: $table.legacyBackupText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> migrationRunsRefs(
    Expression<bool> Function($$MigrationRunsTableFilterComposer f) f,
  ) {
    final $$MigrationRunsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.migrationRuns,
      getReferencedColumn: (t) => t.snapshotId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MigrationRunsTableFilterComposer(
            $db: $db,
            $table: $db.migrationRuns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MigrationSnapshotsTableOrderingComposer
    extends Composer<_$SpendWiseDatabase, $MigrationSnapshotsTable> {
  $$MigrationSnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceKey => $composableBuilder(
    column: $table.sourceKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawText => $composableBuilder(
    column: $table.rawText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get legacyBackupText => $composableBuilder(
    column: $table.legacyBackupText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MigrationSnapshotsTableAnnotationComposer
    extends Composer<_$SpendWiseDatabase, $MigrationSnapshotsTable> {
  $$MigrationSnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceKey =>
      $composableBuilder(column: $table.sourceKey, builder: (column) => column);

  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rawText =>
      $composableBuilder(column: $table.rawText, builder: (column) => column);

  GeneratedColumn<String> get legacyBackupText => $composableBuilder(
    column: $table.legacyBackupText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => column,
  );

  Expression<T> migrationRunsRefs<T extends Object>(
    Expression<T> Function($$MigrationRunsTableAnnotationComposer a) f,
  ) {
    final $$MigrationRunsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.migrationRuns,
      getReferencedColumn: (t) => t.snapshotId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MigrationRunsTableAnnotationComposer(
            $db: $db,
            $table: $db.migrationRuns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MigrationSnapshotsTableTableManager
    extends
        RootTableManager<
          _$SpendWiseDatabase,
          $MigrationSnapshotsTable,
          MigrationSnapshot,
          $$MigrationSnapshotsTableFilterComposer,
          $$MigrationSnapshotsTableOrderingComposer,
          $$MigrationSnapshotsTableAnnotationComposer,
          $$MigrationSnapshotsTableCreateCompanionBuilder,
          $$MigrationSnapshotsTableUpdateCompanionBuilder,
          (MigrationSnapshot, $$MigrationSnapshotsTableReferences),
          MigrationSnapshot,
          PrefetchHooks Function({bool migrationRunsRefs})
        > {
  $$MigrationSnapshotsTableTableManager(
    _$SpendWiseDatabase db,
    $MigrationSnapshotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MigrationSnapshotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MigrationSnapshotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MigrationSnapshotsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> sourceKey = const Value.absent(),
                Value<String> fingerprint = const Value.absent(),
                Value<String?> rawText = const Value.absent(),
                Value<String?> legacyBackupText = const Value.absent(),
                Value<String> capturedAt = const Value.absent(),
              }) => MigrationSnapshotsCompanion(
                id: id,
                sourceKey: sourceKey,
                fingerprint: fingerprint,
                rawText: rawText,
                legacyBackupText: legacyBackupText,
                capturedAt: capturedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String sourceKey,
                required String fingerprint,
                Value<String?> rawText = const Value.absent(),
                Value<String?> legacyBackupText = const Value.absent(),
                required String capturedAt,
              }) => MigrationSnapshotsCompanion.insert(
                id: id,
                sourceKey: sourceKey,
                fingerprint: fingerprint,
                rawText: rawText,
                legacyBackupText: legacyBackupText,
                capturedAt: capturedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MigrationSnapshotsTable, MigrationSnapshot>(
                    table,
                  ),
                  $$MigrationSnapshotsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({migrationRunsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (migrationRunsRefs) db.migrationRuns,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (migrationRunsRefs)
                    await $_getPrefetchedData<
                      MigrationSnapshot,
                      $MigrationSnapshotsTable,
                      MigrationRun
                    >(
                      currentTable: table,
                      referencedTable: $$MigrationSnapshotsTableReferences
                          ._migrationRunsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$MigrationSnapshotsTableReferences(
                            db,
                            table,
                            p0,
                          ).migrationRunsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.snapshotId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$MigrationSnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$SpendWiseDatabase,
      $MigrationSnapshotsTable,
      MigrationSnapshot,
      $$MigrationSnapshotsTableFilterComposer,
      $$MigrationSnapshotsTableOrderingComposer,
      $$MigrationSnapshotsTableAnnotationComposer,
      $$MigrationSnapshotsTableCreateCompanionBuilder,
      $$MigrationSnapshotsTableUpdateCompanionBuilder,
      (MigrationSnapshot, $$MigrationSnapshotsTableReferences),
      MigrationSnapshot,
      PrefetchHooks Function({bool migrationRunsRefs})
    >;
typedef $$MigrationRunsTableCreateCompanionBuilder =
    MigrationRunsCompanion Function({
      Value<int> id,
      required int snapshotId,
      required int algorithmVersion,
      required int sourceRecords,
      required int importedRecords,
      required int alreadyPresent,
      required int duplicatesCollapsed,
      required bool hadLegacyRecords,
      required String totalCents,
      required bool approvedChangedSource,
      required String completedAt,
    });
typedef $$MigrationRunsTableUpdateCompanionBuilder =
    MigrationRunsCompanion Function({
      Value<int> id,
      Value<int> snapshotId,
      Value<int> algorithmVersion,
      Value<int> sourceRecords,
      Value<int> importedRecords,
      Value<int> alreadyPresent,
      Value<int> duplicatesCollapsed,
      Value<bool> hadLegacyRecords,
      Value<String> totalCents,
      Value<bool> approvedChangedSource,
      Value<String> completedAt,
    });

final class $$MigrationRunsTableReferences
    extends
        BaseReferences<_$SpendWiseDatabase, $MigrationRunsTable, MigrationRun> {
  $$MigrationRunsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $MigrationSnapshotsTable _snapshotIdTable(_$SpendWiseDatabase db) => db
      .migrationSnapshots
      .createAlias('migration_runs__snapshot_id__migration_snapshots__id');

  $$MigrationSnapshotsTableProcessedTableManager get snapshotId {
    final $_column = $_itemColumn<int>('snapshot_id')!;

    final manager = $$MigrationSnapshotsTableTableManager(
      $_db,
      $_db.migrationSnapshots,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_snapshotIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MigrationRunsTableFilterComposer
    extends Composer<_$SpendWiseDatabase, $MigrationRunsTable> {
  $$MigrationRunsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get algorithmVersion => $composableBuilder(
    column: $table.algorithmVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sourceRecords => $composableBuilder(
    column: $table.sourceRecords,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get importedRecords => $composableBuilder(
    column: $table.importedRecords,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get alreadyPresent => $composableBuilder(
    column: $table.alreadyPresent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get duplicatesCollapsed => $composableBuilder(
    column: $table.duplicatesCollapsed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hadLegacyRecords => $composableBuilder(
    column: $table.hadLegacyRecords,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get totalCents => $composableBuilder(
    column: $table.totalCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get approvedChangedSource => $composableBuilder(
    column: $table.approvedChangedSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$MigrationSnapshotsTableFilterComposer get snapshotId {
    final $$MigrationSnapshotsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.snapshotId,
      referencedTable: $db.migrationSnapshots,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MigrationSnapshotsTableFilterComposer(
            $db: $db,
            $table: $db.migrationSnapshots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MigrationRunsTableOrderingComposer
    extends Composer<_$SpendWiseDatabase, $MigrationRunsTable> {
  $$MigrationRunsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get algorithmVersion => $composableBuilder(
    column: $table.algorithmVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sourceRecords => $composableBuilder(
    column: $table.sourceRecords,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get importedRecords => $composableBuilder(
    column: $table.importedRecords,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get alreadyPresent => $composableBuilder(
    column: $table.alreadyPresent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get duplicatesCollapsed => $composableBuilder(
    column: $table.duplicatesCollapsed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hadLegacyRecords => $composableBuilder(
    column: $table.hadLegacyRecords,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get totalCents => $composableBuilder(
    column: $table.totalCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get approvedChangedSource => $composableBuilder(
    column: $table.approvedChangedSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$MigrationSnapshotsTableOrderingComposer get snapshotId {
    final $$MigrationSnapshotsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.snapshotId,
      referencedTable: $db.migrationSnapshots,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MigrationSnapshotsTableOrderingComposer(
            $db: $db,
            $table: $db.migrationSnapshots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MigrationRunsTableAnnotationComposer
    extends Composer<_$SpendWiseDatabase, $MigrationRunsTable> {
  $$MigrationRunsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get algorithmVersion => $composableBuilder(
    column: $table.algorithmVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sourceRecords => $composableBuilder(
    column: $table.sourceRecords,
    builder: (column) => column,
  );

  GeneratedColumn<int> get importedRecords => $composableBuilder(
    column: $table.importedRecords,
    builder: (column) => column,
  );

  GeneratedColumn<int> get alreadyPresent => $composableBuilder(
    column: $table.alreadyPresent,
    builder: (column) => column,
  );

  GeneratedColumn<int> get duplicatesCollapsed => $composableBuilder(
    column: $table.duplicatesCollapsed,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hadLegacyRecords => $composableBuilder(
    column: $table.hadLegacyRecords,
    builder: (column) => column,
  );

  GeneratedColumn<String> get totalCents => $composableBuilder(
    column: $table.totalCents,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get approvedChangedSource => $composableBuilder(
    column: $table.approvedChangedSource,
    builder: (column) => column,
  );

  GeneratedColumn<String> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  $$MigrationSnapshotsTableAnnotationComposer get snapshotId {
    final $$MigrationSnapshotsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.snapshotId,
          referencedTable: $db.migrationSnapshots,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$MigrationSnapshotsTableAnnotationComposer(
                $db: $db,
                $table: $db.migrationSnapshots,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$MigrationRunsTableTableManager
    extends
        RootTableManager<
          _$SpendWiseDatabase,
          $MigrationRunsTable,
          MigrationRun,
          $$MigrationRunsTableFilterComposer,
          $$MigrationRunsTableOrderingComposer,
          $$MigrationRunsTableAnnotationComposer,
          $$MigrationRunsTableCreateCompanionBuilder,
          $$MigrationRunsTableUpdateCompanionBuilder,
          (MigrationRun, $$MigrationRunsTableReferences),
          MigrationRun,
          PrefetchHooks Function({bool snapshotId})
        > {
  $$MigrationRunsTableTableManager(
    _$SpendWiseDatabase db,
    $MigrationRunsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MigrationRunsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MigrationRunsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MigrationRunsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> snapshotId = const Value.absent(),
                Value<int> algorithmVersion = const Value.absent(),
                Value<int> sourceRecords = const Value.absent(),
                Value<int> importedRecords = const Value.absent(),
                Value<int> alreadyPresent = const Value.absent(),
                Value<int> duplicatesCollapsed = const Value.absent(),
                Value<bool> hadLegacyRecords = const Value.absent(),
                Value<String> totalCents = const Value.absent(),
                Value<bool> approvedChangedSource = const Value.absent(),
                Value<String> completedAt = const Value.absent(),
              }) => MigrationRunsCompanion(
                id: id,
                snapshotId: snapshotId,
                algorithmVersion: algorithmVersion,
                sourceRecords: sourceRecords,
                importedRecords: importedRecords,
                alreadyPresent: alreadyPresent,
                duplicatesCollapsed: duplicatesCollapsed,
                hadLegacyRecords: hadLegacyRecords,
                totalCents: totalCents,
                approvedChangedSource: approvedChangedSource,
                completedAt: completedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int snapshotId,
                required int algorithmVersion,
                required int sourceRecords,
                required int importedRecords,
                required int alreadyPresent,
                required int duplicatesCollapsed,
                required bool hadLegacyRecords,
                required String totalCents,
                required bool approvedChangedSource,
                required String completedAt,
              }) => MigrationRunsCompanion.insert(
                id: id,
                snapshotId: snapshotId,
                algorithmVersion: algorithmVersion,
                sourceRecords: sourceRecords,
                importedRecords: importedRecords,
                alreadyPresent: alreadyPresent,
                duplicatesCollapsed: duplicatesCollapsed,
                hadLegacyRecords: hadLegacyRecords,
                totalCents: totalCents,
                approvedChangedSource: approvedChangedSource,
                completedAt: completedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MigrationRunsTable, MigrationRun>(table),
                  $$MigrationRunsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({snapshotId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (snapshotId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.snapshotId,
                        referencedTable: $$MigrationRunsTableReferences
                            ._snapshotIdTable(db),
                        referencedColumn: $$MigrationRunsTableReferences
                            ._snapshotIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MigrationRunsTableProcessedTableManager =
    ProcessedTableManager<
      _$SpendWiseDatabase,
      $MigrationRunsTable,
      MigrationRun,
      $$MigrationRunsTableFilterComposer,
      $$MigrationRunsTableOrderingComposer,
      $$MigrationRunsTableAnnotationComposer,
      $$MigrationRunsTableCreateCompanionBuilder,
      $$MigrationRunsTableUpdateCompanionBuilder,
      (MigrationRun, $$MigrationRunsTableReferences),
      MigrationRun,
      PrefetchHooks Function({bool snapshotId})
    >;

class $SpendWiseDatabaseManager {
  final _$SpendWiseDatabase _db;
  $SpendWiseDatabaseManager(this._db);
  $$ExpenseRowsTableTableManager get expenseRows =>
      $$ExpenseRowsTableTableManager(_db, _db.expenseRows);
  $$MigrationSnapshotsTableTableManager get migrationSnapshots =>
      $$MigrationSnapshotsTableTableManager(_db, _db.migrationSnapshots);
  $$MigrationRunsTableTableManager get migrationRuns =>
      $$MigrationRunsTableTableManager(_db, _db.migrationRuns);
}
