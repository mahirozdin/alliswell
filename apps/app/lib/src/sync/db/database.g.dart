// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ProjectsTable extends Projects
    with TableInfo<$ProjectsTable, ProjectRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorRgbMeta = const VerificationMeta(
    'colorRgb',
  );
  @override
  late final GeneratedColumn<String> colorRgb = GeneratedColumn<String>(
    'color_rgb',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('#2563EB'),
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _startAtMeta = const VerificationMeta(
    'startAt',
  );
  @override
  late final GeneratedColumn<DateTime> startAt = GeneratedColumn<DateTime>(
    'start_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueAtMeta = const VerificationMeta('dueAt');
  @override
  late final GeneratedColumn<DateTime> dueAt = GeneratedColumn<DateTime>(
    'due_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _readmeNoteIdMeta = const VerificationMeta(
    'readmeNoteId',
  );
  @override
  late final GeneratedColumn<String> readmeNoteId = GeneratedColumn<String>(
    'readme_note_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameFoldMeta = const VerificationMeta(
    'nameFold',
  );
  @override
  late final GeneratedColumn<String> nameFold = GeneratedColumn<String>(
    'name_fold',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionFoldMeta = const VerificationMeta(
    'descriptionFold',
  );
  @override
  late final GeneratedColumn<String> descriptionFold = GeneratedColumn<String>(
    'description_fold',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    name,
    description,
    colorRgb,
    icon,
    status,
    startAt,
    dueAt,
    sortOrder,
    isFavorite,
    readmeNoteId,
    nameFold,
    descriptionFold,
    revision,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'projects';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProjectRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('color_rgb')) {
      context.handle(
        _colorRgbMeta,
        colorRgb.isAcceptableOrUnknown(data['color_rgb']!, _colorRgbMeta),
      );
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('start_at')) {
      context.handle(
        _startAtMeta,
        startAt.isAcceptableOrUnknown(data['start_at']!, _startAtMeta),
      );
    }
    if (data.containsKey('due_at')) {
      context.handle(
        _dueAtMeta,
        dueAt.isAcceptableOrUnknown(data['due_at']!, _dueAtMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    }
    if (data.containsKey('readme_note_id')) {
      context.handle(
        _readmeNoteIdMeta,
        readmeNoteId.isAcceptableOrUnknown(
          data['readme_note_id']!,
          _readmeNoteIdMeta,
        ),
      );
    }
    if (data.containsKey('name_fold')) {
      context.handle(
        _nameFoldMeta,
        nameFold.isAcceptableOrUnknown(data['name_fold']!, _nameFoldMeta),
      );
    }
    if (data.containsKey('description_fold')) {
      context.handle(
        _descriptionFoldMeta,
        descriptionFold.isAcceptableOrUnknown(
          data['description_fold']!,
          _descriptionFoldMeta,
        ),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProjectRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProjectRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      colorRgb: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_rgb'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      startAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_at'],
      ),
      dueAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_at'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
      readmeNoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}readme_note_id'],
      ),
      nameFold: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_fold'],
      ),
      descriptionFold: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description_fold'],
      ),
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $ProjectsTable createAlias(String alias) {
    return $ProjectsTable(attachedDatabase, alias);
  }
}

class ProjectRecord extends DataClass implements Insertable<ProjectRecord> {
  final String id;
  final String workspaceId;
  final String name;
  final String? description;
  final String colorRgb;
  final String? icon;
  final String status;
  final DateTime? startAt;
  final DateTime? dueAt;
  final int sortOrder;
  final bool isFavorite;
  final String? readmeNoteId;
  final String? nameFold;
  final String? descriptionFold;
  final int revision;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const ProjectRecord({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.description,
    required this.colorRgb,
    this.icon,
    required this.status,
    this.startAt,
    this.dueAt,
    required this.sortOrder,
    required this.isFavorite,
    this.readmeNoteId,
    this.nameFold,
    this.descriptionFold,
    required this.revision,
    this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['color_rgb'] = Variable<String>(colorRgb);
    if (!nullToAbsent || icon != null) {
      map['icon'] = Variable<String>(icon);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || startAt != null) {
      map['start_at'] = Variable<DateTime>(startAt);
    }
    if (!nullToAbsent || dueAt != null) {
      map['due_at'] = Variable<DateTime>(dueAt);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    map['is_favorite'] = Variable<bool>(isFavorite);
    if (!nullToAbsent || readmeNoteId != null) {
      map['readme_note_id'] = Variable<String>(readmeNoteId);
    }
    if (!nullToAbsent || nameFold != null) {
      map['name_fold'] = Variable<String>(nameFold);
    }
    if (!nullToAbsent || descriptionFold != null) {
      map['description_fold'] = Variable<String>(descriptionFold);
    }
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  ProjectsCompanion toCompanion(bool nullToAbsent) {
    return ProjectsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      colorRgb: Value(colorRgb),
      icon: icon == null && nullToAbsent ? const Value.absent() : Value(icon),
      status: Value(status),
      startAt: startAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startAt),
      dueAt: dueAt == null && nullToAbsent
          ? const Value.absent()
          : Value(dueAt),
      sortOrder: Value(sortOrder),
      isFavorite: Value(isFavorite),
      readmeNoteId: readmeNoteId == null && nullToAbsent
          ? const Value.absent()
          : Value(readmeNoteId),
      nameFold: nameFold == null && nullToAbsent
          ? const Value.absent()
          : Value(nameFold),
      descriptionFold: descriptionFold == null && nullToAbsent
          ? const Value.absent()
          : Value(descriptionFold),
      revision: Value(revision),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory ProjectRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProjectRecord(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      colorRgb: serializer.fromJson<String>(json['colorRgb']),
      icon: serializer.fromJson<String?>(json['icon']),
      status: serializer.fromJson<String>(json['status']),
      startAt: serializer.fromJson<DateTime?>(json['startAt']),
      dueAt: serializer.fromJson<DateTime?>(json['dueAt']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      readmeNoteId: serializer.fromJson<String?>(json['readmeNoteId']),
      nameFold: serializer.fromJson<String?>(json['nameFold']),
      descriptionFold: serializer.fromJson<String?>(json['descriptionFold']),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'colorRgb': serializer.toJson<String>(colorRgb),
      'icon': serializer.toJson<String?>(icon),
      'status': serializer.toJson<String>(status),
      'startAt': serializer.toJson<DateTime?>(startAt),
      'dueAt': serializer.toJson<DateTime?>(dueAt),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'readmeNoteId': serializer.toJson<String?>(readmeNoteId),
      'nameFold': serializer.toJson<String?>(nameFold),
      'descriptionFold': serializer.toJson<String?>(descriptionFold),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  ProjectRecord copyWith({
    String? id,
    String? workspaceId,
    String? name,
    Value<String?> description = const Value.absent(),
    String? colorRgb,
    Value<String?> icon = const Value.absent(),
    String? status,
    Value<DateTime?> startAt = const Value.absent(),
    Value<DateTime?> dueAt = const Value.absent(),
    int? sortOrder,
    bool? isFavorite,
    Value<String?> readmeNoteId = const Value.absent(),
    Value<String?> nameFold = const Value.absent(),
    Value<String?> descriptionFold = const Value.absent(),
    int? revision,
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => ProjectRecord(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    colorRgb: colorRgb ?? this.colorRgb,
    icon: icon.present ? icon.value : this.icon,
    status: status ?? this.status,
    startAt: startAt.present ? startAt.value : this.startAt,
    dueAt: dueAt.present ? dueAt.value : this.dueAt,
    sortOrder: sortOrder ?? this.sortOrder,
    isFavorite: isFavorite ?? this.isFavorite,
    readmeNoteId: readmeNoteId.present ? readmeNoteId.value : this.readmeNoteId,
    nameFold: nameFold.present ? nameFold.value : this.nameFold,
    descriptionFold: descriptionFold.present
        ? descriptionFold.value
        : this.descriptionFold,
    revision: revision ?? this.revision,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  ProjectRecord copyWithCompanion(ProjectsCompanion data) {
    return ProjectRecord(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      colorRgb: data.colorRgb.present ? data.colorRgb.value : this.colorRgb,
      icon: data.icon.present ? data.icon.value : this.icon,
      status: data.status.present ? data.status.value : this.status,
      startAt: data.startAt.present ? data.startAt.value : this.startAt,
      dueAt: data.dueAt.present ? data.dueAt.value : this.dueAt,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
      readmeNoteId: data.readmeNoteId.present
          ? data.readmeNoteId.value
          : this.readmeNoteId,
      nameFold: data.nameFold.present ? data.nameFold.value : this.nameFold,
      descriptionFold: data.descriptionFold.present
          ? data.descriptionFold.value
          : this.descriptionFold,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProjectRecord(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('colorRgb: $colorRgb, ')
          ..write('icon: $icon, ')
          ..write('status: $status, ')
          ..write('startAt: $startAt, ')
          ..write('dueAt: $dueAt, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('readmeNoteId: $readmeNoteId, ')
          ..write('nameFold: $nameFold, ')
          ..write('descriptionFold: $descriptionFold, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    name,
    description,
    colorRgb,
    icon,
    status,
    startAt,
    dueAt,
    sortOrder,
    isFavorite,
    readmeNoteId,
    nameFold,
    descriptionFold,
    revision,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectRecord &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.name == this.name &&
          other.description == this.description &&
          other.colorRgb == this.colorRgb &&
          other.icon == this.icon &&
          other.status == this.status &&
          other.startAt == this.startAt &&
          other.dueAt == this.dueAt &&
          other.sortOrder == this.sortOrder &&
          other.isFavorite == this.isFavorite &&
          other.readmeNoteId == this.readmeNoteId &&
          other.nameFold == this.nameFold &&
          other.descriptionFold == this.descriptionFold &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ProjectsCompanion extends UpdateCompanion<ProjectRecord> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> name;
  final Value<String?> description;
  final Value<String> colorRgb;
  final Value<String?> icon;
  final Value<String> status;
  final Value<DateTime?> startAt;
  final Value<DateTime?> dueAt;
  final Value<int> sortOrder;
  final Value<bool> isFavorite;
  final Value<String?> readmeNoteId;
  final Value<String?> nameFold;
  final Value<String?> descriptionFold;
  final Value<int> revision;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const ProjectsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.colorRgb = const Value.absent(),
    this.icon = const Value.absent(),
    this.status = const Value.absent(),
    this.startAt = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.readmeNoteId = const Value.absent(),
    this.nameFold = const Value.absent(),
    this.descriptionFold = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProjectsCompanion.insert({
    required String id,
    required String workspaceId,
    required String name,
    this.description = const Value.absent(),
    this.colorRgb = const Value.absent(),
    this.icon = const Value.absent(),
    this.status = const Value.absent(),
    this.startAt = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.readmeNoteId = const Value.absent(),
    this.nameFold = const Value.absent(),
    this.descriptionFold = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       name = Value(name);
  static Insertable<ProjectRecord> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? colorRgb,
    Expression<String>? icon,
    Expression<String>? status,
    Expression<DateTime>? startAt,
    Expression<DateTime>? dueAt,
    Expression<int>? sortOrder,
    Expression<bool>? isFavorite,
    Expression<String>? readmeNoteId,
    Expression<String>? nameFold,
    Expression<String>? descriptionFold,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (colorRgb != null) 'color_rgb': colorRgb,
      if (icon != null) 'icon': icon,
      if (status != null) 'status': status,
      if (startAt != null) 'start_at': startAt,
      if (dueAt != null) 'due_at': dueAt,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (readmeNoteId != null) 'readme_note_id': readmeNoteId,
      if (nameFold != null) 'name_fold': nameFold,
      if (descriptionFold != null) 'description_fold': descriptionFold,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProjectsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? name,
    Value<String?>? description,
    Value<String>? colorRgb,
    Value<String?>? icon,
    Value<String>? status,
    Value<DateTime?>? startAt,
    Value<DateTime?>? dueAt,
    Value<int>? sortOrder,
    Value<bool>? isFavorite,
    Value<String?>? readmeNoteId,
    Value<String?>? nameFold,
    Value<String?>? descriptionFold,
    Value<int>? revision,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return ProjectsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      description: description ?? this.description,
      colorRgb: colorRgb ?? this.colorRgb,
      icon: icon ?? this.icon,
      status: status ?? this.status,
      startAt: startAt ?? this.startAt,
      dueAt: dueAt ?? this.dueAt,
      sortOrder: sortOrder ?? this.sortOrder,
      isFavorite: isFavorite ?? this.isFavorite,
      readmeNoteId: readmeNoteId ?? this.readmeNoteId,
      nameFold: nameFold ?? this.nameFold,
      descriptionFold: descriptionFold ?? this.descriptionFold,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (colorRgb.present) {
      map['color_rgb'] = Variable<String>(colorRgb.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (startAt.present) {
      map['start_at'] = Variable<DateTime>(startAt.value);
    }
    if (dueAt.present) {
      map['due_at'] = Variable<DateTime>(dueAt.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (readmeNoteId.present) {
      map['readme_note_id'] = Variable<String>(readmeNoteId.value);
    }
    if (nameFold.present) {
      map['name_fold'] = Variable<String>(nameFold.value);
    }
    if (descriptionFold.present) {
      map['description_fold'] = Variable<String>(descriptionFold.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('colorRgb: $colorRgb, ')
          ..write('icon: $icon, ')
          ..write('status: $status, ')
          ..write('startAt: $startAt, ')
          ..write('dueAt: $dueAt, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('readmeNoteId: $readmeNoteId, ')
          ..write('nameFold: $nameFold, ')
          ..write('descriptionFold: $descriptionFold, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, TagRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _slugMeta = const VerificationMeta('slug');
  @override
  late final GeneratedColumn<String> slug = GeneratedColumn<String>(
    'slug',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorRgbMeta = const VerificationMeta(
    'colorRgb',
  );
  @override
  late final GeneratedColumn<String> colorRgb = GeneratedColumn<String>(
    'color_rgb',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('#64748B'),
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameFoldMeta = const VerificationMeta(
    'nameFold',
  );
  @override
  late final GeneratedColumn<String> nameFold = GeneratedColumn<String>(
    'name_fold',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    name,
    slug,
    colorRgb,
    icon,
    nameFold,
    revision,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<TagRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('slug')) {
      context.handle(
        _slugMeta,
        slug.isAcceptableOrUnknown(data['slug']!, _slugMeta),
      );
    } else if (isInserting) {
      context.missing(_slugMeta);
    }
    if (data.containsKey('color_rgb')) {
      context.handle(
        _colorRgbMeta,
        colorRgb.isAcceptableOrUnknown(data['color_rgb']!, _colorRgbMeta),
      );
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    }
    if (data.containsKey('name_fold')) {
      context.handle(
        _nameFoldMeta,
        nameFold.isAcceptableOrUnknown(data['name_fold']!, _nameFoldMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TagRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TagRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      slug: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}slug'],
      )!,
      colorRgb: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_rgb'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      ),
      nameFold: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_fold'],
      ),
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }
}

class TagRecord extends DataClass implements Insertable<TagRecord> {
  final String id;
  final String workspaceId;
  final String name;
  final String slug;
  final String colorRgb;
  final String? icon;
  final String? nameFold;
  final int revision;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const TagRecord({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.slug,
    required this.colorRgb,
    this.icon,
    this.nameFold,
    required this.revision,
    this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['name'] = Variable<String>(name);
    map['slug'] = Variable<String>(slug);
    map['color_rgb'] = Variable<String>(colorRgb);
    if (!nullToAbsent || icon != null) {
      map['icon'] = Variable<String>(icon);
    }
    if (!nullToAbsent || nameFold != null) {
      map['name_fold'] = Variable<String>(nameFold);
    }
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      name: Value(name),
      slug: Value(slug),
      colorRgb: Value(colorRgb),
      icon: icon == null && nullToAbsent ? const Value.absent() : Value(icon),
      nameFold: nameFold == null && nullToAbsent
          ? const Value.absent()
          : Value(nameFold),
      revision: Value(revision),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory TagRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TagRecord(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      name: serializer.fromJson<String>(json['name']),
      slug: serializer.fromJson<String>(json['slug']),
      colorRgb: serializer.fromJson<String>(json['colorRgb']),
      icon: serializer.fromJson<String?>(json['icon']),
      nameFold: serializer.fromJson<String?>(json['nameFold']),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'name': serializer.toJson<String>(name),
      'slug': serializer.toJson<String>(slug),
      'colorRgb': serializer.toJson<String>(colorRgb),
      'icon': serializer.toJson<String?>(icon),
      'nameFold': serializer.toJson<String?>(nameFold),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  TagRecord copyWith({
    String? id,
    String? workspaceId,
    String? name,
    String? slug,
    String? colorRgb,
    Value<String?> icon = const Value.absent(),
    Value<String?> nameFold = const Value.absent(),
    int? revision,
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => TagRecord(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    name: name ?? this.name,
    slug: slug ?? this.slug,
    colorRgb: colorRgb ?? this.colorRgb,
    icon: icon.present ? icon.value : this.icon,
    nameFold: nameFold.present ? nameFold.value : this.nameFold,
    revision: revision ?? this.revision,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  TagRecord copyWithCompanion(TagsCompanion data) {
    return TagRecord(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      name: data.name.present ? data.name.value : this.name,
      slug: data.slug.present ? data.slug.value : this.slug,
      colorRgb: data.colorRgb.present ? data.colorRgb.value : this.colorRgb,
      icon: data.icon.present ? data.icon.value : this.icon,
      nameFold: data.nameFold.present ? data.nameFold.value : this.nameFold,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TagRecord(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('name: $name, ')
          ..write('slug: $slug, ')
          ..write('colorRgb: $colorRgb, ')
          ..write('icon: $icon, ')
          ..write('nameFold: $nameFold, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    name,
    slug,
    colorRgb,
    icon,
    nameFold,
    revision,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TagRecord &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.name == this.name &&
          other.slug == this.slug &&
          other.colorRgb == this.colorRgb &&
          other.icon == this.icon &&
          other.nameFold == this.nameFold &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TagsCompanion extends UpdateCompanion<TagRecord> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> name;
  final Value<String> slug;
  final Value<String> colorRgb;
  final Value<String?> icon;
  final Value<String?> nameFold;
  final Value<int> revision;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.name = const Value.absent(),
    this.slug = const Value.absent(),
    this.colorRgb = const Value.absent(),
    this.icon = const Value.absent(),
    this.nameFold = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TagsCompanion.insert({
    required String id,
    required String workspaceId,
    required String name,
    required String slug,
    this.colorRgb = const Value.absent(),
    this.icon = const Value.absent(),
    this.nameFold = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       name = Value(name),
       slug = Value(slug);
  static Insertable<TagRecord> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? name,
    Expression<String>? slug,
    Expression<String>? colorRgb,
    Expression<String>? icon,
    Expression<String>? nameFold,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (name != null) 'name': name,
      if (slug != null) 'slug': slug,
      if (colorRgb != null) 'color_rgb': colorRgb,
      if (icon != null) 'icon': icon,
      if (nameFold != null) 'name_fold': nameFold,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TagsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? name,
    Value<String>? slug,
    Value<String>? colorRgb,
    Value<String?>? icon,
    Value<String?>? nameFold,
    Value<int>? revision,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return TagsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      colorRgb: colorRgb ?? this.colorRgb,
      icon: icon ?? this.icon,
      nameFold: nameFold ?? this.nameFold,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (slug.present) {
      map['slug'] = Variable<String>(slug.value);
    }
    if (colorRgb.present) {
      map['color_rgb'] = Variable<String>(colorRgb.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (nameFold.present) {
      map['name_fold'] = Variable<String>(nameFold.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('name: $name, ')
          ..write('slug: $slug, ')
          ..write('colorRgb: $colorRgb, ')
          ..write('icon: $icon, ')
          ..write('nameFold: $nameFold, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TasksTable extends Tasks with TableInfo<$TasksTable, TaskRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parentTaskIdMeta = const VerificationMeta(
    'parentTaskId',
  );
  @override
  late final GeneratedColumn<String> parentTaskId = GeneratedColumn<String>(
    'parent_task_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('open'),
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<String> priority = GeneratedColumn<String>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('none'),
  );
  static const VerificationMeta _colorRgbMeta = const VerificationMeta(
    'colorRgb',
  );
  @override
  late final GeneratedColumn<String> colorRgb = GeneratedColumn<String>(
    'color_rgb',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startAtMeta = const VerificationMeta(
    'startAt',
  );
  @override
  late final GeneratedColumn<DateTime> startAt = GeneratedColumn<DateTime>(
    'start_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueAtMeta = const VerificationMeta('dueAt');
  @override
  late final GeneratedColumn<DateTime> dueAt = GeneratedColumn<DateTime>(
    'due_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scheduledStartAtMeta = const VerificationMeta(
    'scheduledStartAt',
  );
  @override
  late final GeneratedColumn<DateTime> scheduledStartAt =
      GeneratedColumn<DateTime>(
        'scheduled_start_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _scheduledEndAtMeta = const VerificationMeta(
    'scheduledEndAt',
  );
  @override
  late final GeneratedColumn<DateTime> scheduledEndAt =
      GeneratedColumn<DateTime>(
        'scheduled_end_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _remindAtMeta = const VerificationMeta(
    'remindAt',
  );
  @override
  late final GeneratedColumn<DateTime> remindAt = GeneratedColumn<DateTime>(
    'remind_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _snoozedUntilMeta = const VerificationMeta(
    'snoozedUntil',
  );
  @override
  late final GeneratedColumn<DateTime> snoozedUntil = GeneratedColumn<DateTime>(
    'snoozed_until',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _alarmsMutedAtMeta = const VerificationMeta(
    'alarmsMutedAt',
  );
  @override
  late final GeneratedColumn<DateTime> alarmsMutedAt =
      GeneratedColumn<DateTime>(
        'alarms_muted_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _timezoneMeta = const VerificationMeta(
    'timezone',
  );
  @override
  late final GeneratedColumn<String> timezone = GeneratedColumn<String>(
    'timezone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Europe/Istanbul'),
  );
  static const VerificationMeta _isUrgentMeta = const VerificationMeta(
    'isUrgent',
  );
  @override
  late final GeneratedColumn<bool> isUrgent = GeneratedColumn<bool>(
    'is_urgent',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_urgent" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _requiresAcknowledgementMeta =
      const VerificationMeta('requiresAcknowledgement');
  @override
  late final GeneratedColumn<bool> requiresAcknowledgement =
      GeneratedColumn<bool>(
        'requires_acknowledgement',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("requires_acknowledgement" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _repeatRuleMeta = const VerificationMeta(
    'repeatRule',
  );
  @override
  late final GeneratedColumn<String> repeatRule = GeneratedColumn<String>(
    'repeat_rule',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<String> seriesId = GeneratedColumn<String>(
    'series_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _occurrenceDateMeta = const VerificationMeta(
    'occurrenceDate',
  );
  @override
  late final GeneratedColumn<String> occurrenceDate = GeneratedColumn<String>(
    'occurrence_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _estimatedMinutesMeta = const VerificationMeta(
    'estimatedMinutes',
  );
  @override
  late final GeneratedColumn<int> estimatedMinutes = GeneratedColumn<int>(
    'estimated_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _actualMinutesMeta = const VerificationMeta(
    'actualMinutes',
  );
  @override
  late final GeneratedColumn<int> actualMinutes = GeneratedColumn<int>(
    'actual_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _calendarMirrorEnabledMeta =
      const VerificationMeta('calendarMirrorEnabled');
  @override
  late final GeneratedColumn<bool> calendarMirrorEnabled =
      GeneratedColumn<bool>(
        'calendar_mirror_enabled',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("calendar_mirror_enabled" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleFoldMeta = const VerificationMeta(
    'titleFold',
  );
  @override
  late final GeneratedColumn<String> titleFold = GeneratedColumn<String>(
    'title_fold',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionFoldMeta = const VerificationMeta(
    'descriptionFold',
  );
  @override
  late final GeneratedColumn<String> descriptionFold = GeneratedColumn<String>(
    'description_fold',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    projectId,
    parentTaskId,
    title,
    description,
    status,
    priority,
    colorRgb,
    startAt,
    dueAt,
    scheduledStartAt,
    scheduledEndAt,
    remindAt,
    snoozedUntil,
    alarmsMutedAt,
    timezone,
    isUrgent,
    requiresAcknowledgement,
    repeatRule,
    seriesId,
    occurrenceDate,
    estimatedMinutes,
    actualMinutes,
    sortOrder,
    calendarMirrorEnabled,
    completedAt,
    titleFold,
    descriptionFold,
    revision,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    }
    if (data.containsKey('parent_task_id')) {
      context.handle(
        _parentTaskIdMeta,
        parentTaskId.isAcceptableOrUnknown(
          data['parent_task_id']!,
          _parentTaskIdMeta,
        ),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('color_rgb')) {
      context.handle(
        _colorRgbMeta,
        colorRgb.isAcceptableOrUnknown(data['color_rgb']!, _colorRgbMeta),
      );
    }
    if (data.containsKey('start_at')) {
      context.handle(
        _startAtMeta,
        startAt.isAcceptableOrUnknown(data['start_at']!, _startAtMeta),
      );
    }
    if (data.containsKey('due_at')) {
      context.handle(
        _dueAtMeta,
        dueAt.isAcceptableOrUnknown(data['due_at']!, _dueAtMeta),
      );
    }
    if (data.containsKey('scheduled_start_at')) {
      context.handle(
        _scheduledStartAtMeta,
        scheduledStartAt.isAcceptableOrUnknown(
          data['scheduled_start_at']!,
          _scheduledStartAtMeta,
        ),
      );
    }
    if (data.containsKey('scheduled_end_at')) {
      context.handle(
        _scheduledEndAtMeta,
        scheduledEndAt.isAcceptableOrUnknown(
          data['scheduled_end_at']!,
          _scheduledEndAtMeta,
        ),
      );
    }
    if (data.containsKey('remind_at')) {
      context.handle(
        _remindAtMeta,
        remindAt.isAcceptableOrUnknown(data['remind_at']!, _remindAtMeta),
      );
    }
    if (data.containsKey('snoozed_until')) {
      context.handle(
        _snoozedUntilMeta,
        snoozedUntil.isAcceptableOrUnknown(
          data['snoozed_until']!,
          _snoozedUntilMeta,
        ),
      );
    }
    if (data.containsKey('alarms_muted_at')) {
      context.handle(
        _alarmsMutedAtMeta,
        alarmsMutedAt.isAcceptableOrUnknown(
          data['alarms_muted_at']!,
          _alarmsMutedAtMeta,
        ),
      );
    }
    if (data.containsKey('timezone')) {
      context.handle(
        _timezoneMeta,
        timezone.isAcceptableOrUnknown(data['timezone']!, _timezoneMeta),
      );
    }
    if (data.containsKey('is_urgent')) {
      context.handle(
        _isUrgentMeta,
        isUrgent.isAcceptableOrUnknown(data['is_urgent']!, _isUrgentMeta),
      );
    }
    if (data.containsKey('requires_acknowledgement')) {
      context.handle(
        _requiresAcknowledgementMeta,
        requiresAcknowledgement.isAcceptableOrUnknown(
          data['requires_acknowledgement']!,
          _requiresAcknowledgementMeta,
        ),
      );
    }
    if (data.containsKey('repeat_rule')) {
      context.handle(
        _repeatRuleMeta,
        repeatRule.isAcceptableOrUnknown(data['repeat_rule']!, _repeatRuleMeta),
      );
    }
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    }
    if (data.containsKey('occurrence_date')) {
      context.handle(
        _occurrenceDateMeta,
        occurrenceDate.isAcceptableOrUnknown(
          data['occurrence_date']!,
          _occurrenceDateMeta,
        ),
      );
    }
    if (data.containsKey('estimated_minutes')) {
      context.handle(
        _estimatedMinutesMeta,
        estimatedMinutes.isAcceptableOrUnknown(
          data['estimated_minutes']!,
          _estimatedMinutesMeta,
        ),
      );
    }
    if (data.containsKey('actual_minutes')) {
      context.handle(
        _actualMinutesMeta,
        actualMinutes.isAcceptableOrUnknown(
          data['actual_minutes']!,
          _actualMinutesMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('calendar_mirror_enabled')) {
      context.handle(
        _calendarMirrorEnabledMeta,
        calendarMirrorEnabled.isAcceptableOrUnknown(
          data['calendar_mirror_enabled']!,
          _calendarMirrorEnabledMeta,
        ),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('title_fold')) {
      context.handle(
        _titleFoldMeta,
        titleFold.isAcceptableOrUnknown(data['title_fold']!, _titleFoldMeta),
      );
    }
    if (data.containsKey('description_fold')) {
      context.handle(
        _descriptionFoldMeta,
        descriptionFold.isAcceptableOrUnknown(
          data['description_fold']!,
          _descriptionFoldMeta,
        ),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      ),
      parentTaskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_task_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}priority'],
      )!,
      colorRgb: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_rgb'],
      ),
      startAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_at'],
      ),
      dueAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_at'],
      ),
      scheduledStartAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}scheduled_start_at'],
      ),
      scheduledEndAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}scheduled_end_at'],
      ),
      remindAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}remind_at'],
      ),
      snoozedUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}snoozed_until'],
      ),
      alarmsMutedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}alarms_muted_at'],
      ),
      timezone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timezone'],
      )!,
      isUrgent: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_urgent'],
      )!,
      requiresAcknowledgement: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}requires_acknowledgement'],
      )!,
      repeatRule: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}repeat_rule'],
      ),
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_id'],
      ),
      occurrenceDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}occurrence_date'],
      ),
      estimatedMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}estimated_minutes'],
      ),
      actualMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}actual_minutes'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      calendarMirrorEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}calendar_mirror_enabled'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      titleFold: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_fold'],
      ),
      descriptionFold: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description_fold'],
      ),
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }
}

class TaskRecord extends DataClass implements Insertable<TaskRecord> {
  final String id;
  final String workspaceId;
  final String? projectId;
  final String? parentTaskId;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final String? colorRgb;
  final DateTime? startAt;
  final DateTime? dueAt;
  final DateTime? scheduledStartAt;
  final DateTime? scheduledEndAt;
  final DateTime? remindAt;
  final DateTime? snoozedUntil;

  /// Silenced indefinitely since this instant (OPH-178); null = alarms live.
  /// A muted task keeps its dates and stays OPEN — silence is not completion.
  final DateTime? alarmsMutedAt;
  final String timezone;
  final bool isUrgent;
  final bool requiresAcknowledgement;

  /// Frozen since OPH-205 (ADR-0020 §7): recurrence lives in [TaskSeries] now.
  /// The column stays because the server's does; nothing reads or writes it.
  final String? repeatRule;

  /// Which series produced this task, and which day of it this is (v14,
  /// OPH-205). Server-owned: the client never writes them, it learns them from
  /// the pull. `occurrenceDate` is the series SLOT (`YYYY-MM-DD`, immutable) —
  /// `dueAt` is when the occurrence actually happens and may be moved.
  final String? seriesId;
  final String? occurrenceDate;
  final int? estimatedMinutes;
  final int? actualMinutes;
  final int sortOrder;
  final bool calendarMirrorEnabled;
  final DateTime? completedAt;
  final String? titleFold;
  final String? descriptionFold;
  final int revision;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const TaskRecord({
    required this.id,
    required this.workspaceId,
    this.projectId,
    this.parentTaskId,
    required this.title,
    this.description,
    required this.status,
    required this.priority,
    this.colorRgb,
    this.startAt,
    this.dueAt,
    this.scheduledStartAt,
    this.scheduledEndAt,
    this.remindAt,
    this.snoozedUntil,
    this.alarmsMutedAt,
    required this.timezone,
    required this.isUrgent,
    required this.requiresAcknowledgement,
    this.repeatRule,
    this.seriesId,
    this.occurrenceDate,
    this.estimatedMinutes,
    this.actualMinutes,
    required this.sortOrder,
    required this.calendarMirrorEnabled,
    this.completedAt,
    this.titleFold,
    this.descriptionFold,
    required this.revision,
    this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    if (!nullToAbsent || projectId != null) {
      map['project_id'] = Variable<String>(projectId);
    }
    if (!nullToAbsent || parentTaskId != null) {
      map['parent_task_id'] = Variable<String>(parentTaskId);
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['status'] = Variable<String>(status);
    map['priority'] = Variable<String>(priority);
    if (!nullToAbsent || colorRgb != null) {
      map['color_rgb'] = Variable<String>(colorRgb);
    }
    if (!nullToAbsent || startAt != null) {
      map['start_at'] = Variable<DateTime>(startAt);
    }
    if (!nullToAbsent || dueAt != null) {
      map['due_at'] = Variable<DateTime>(dueAt);
    }
    if (!nullToAbsent || scheduledStartAt != null) {
      map['scheduled_start_at'] = Variable<DateTime>(scheduledStartAt);
    }
    if (!nullToAbsent || scheduledEndAt != null) {
      map['scheduled_end_at'] = Variable<DateTime>(scheduledEndAt);
    }
    if (!nullToAbsent || remindAt != null) {
      map['remind_at'] = Variable<DateTime>(remindAt);
    }
    if (!nullToAbsent || snoozedUntil != null) {
      map['snoozed_until'] = Variable<DateTime>(snoozedUntil);
    }
    if (!nullToAbsent || alarmsMutedAt != null) {
      map['alarms_muted_at'] = Variable<DateTime>(alarmsMutedAt);
    }
    map['timezone'] = Variable<String>(timezone);
    map['is_urgent'] = Variable<bool>(isUrgent);
    map['requires_acknowledgement'] = Variable<bool>(requiresAcknowledgement);
    if (!nullToAbsent || repeatRule != null) {
      map['repeat_rule'] = Variable<String>(repeatRule);
    }
    if (!nullToAbsent || seriesId != null) {
      map['series_id'] = Variable<String>(seriesId);
    }
    if (!nullToAbsent || occurrenceDate != null) {
      map['occurrence_date'] = Variable<String>(occurrenceDate);
    }
    if (!nullToAbsent || estimatedMinutes != null) {
      map['estimated_minutes'] = Variable<int>(estimatedMinutes);
    }
    if (!nullToAbsent || actualMinutes != null) {
      map['actual_minutes'] = Variable<int>(actualMinutes);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    map['calendar_mirror_enabled'] = Variable<bool>(calendarMirrorEnabled);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    if (!nullToAbsent || titleFold != null) {
      map['title_fold'] = Variable<String>(titleFold);
    }
    if (!nullToAbsent || descriptionFold != null) {
      map['description_fold'] = Variable<String>(descriptionFold);
    }
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      projectId: projectId == null && nullToAbsent
          ? const Value.absent()
          : Value(projectId),
      parentTaskId: parentTaskId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentTaskId),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      status: Value(status),
      priority: Value(priority),
      colorRgb: colorRgb == null && nullToAbsent
          ? const Value.absent()
          : Value(colorRgb),
      startAt: startAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startAt),
      dueAt: dueAt == null && nullToAbsent
          ? const Value.absent()
          : Value(dueAt),
      scheduledStartAt: scheduledStartAt == null && nullToAbsent
          ? const Value.absent()
          : Value(scheduledStartAt),
      scheduledEndAt: scheduledEndAt == null && nullToAbsent
          ? const Value.absent()
          : Value(scheduledEndAt),
      remindAt: remindAt == null && nullToAbsent
          ? const Value.absent()
          : Value(remindAt),
      snoozedUntil: snoozedUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(snoozedUntil),
      alarmsMutedAt: alarmsMutedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(alarmsMutedAt),
      timezone: Value(timezone),
      isUrgent: Value(isUrgent),
      requiresAcknowledgement: Value(requiresAcknowledgement),
      repeatRule: repeatRule == null && nullToAbsent
          ? const Value.absent()
          : Value(repeatRule),
      seriesId: seriesId == null && nullToAbsent
          ? const Value.absent()
          : Value(seriesId),
      occurrenceDate: occurrenceDate == null && nullToAbsent
          ? const Value.absent()
          : Value(occurrenceDate),
      estimatedMinutes: estimatedMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(estimatedMinutes),
      actualMinutes: actualMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(actualMinutes),
      sortOrder: Value(sortOrder),
      calendarMirrorEnabled: Value(calendarMirrorEnabled),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      titleFold: titleFold == null && nullToAbsent
          ? const Value.absent()
          : Value(titleFold),
      descriptionFold: descriptionFold == null && nullToAbsent
          ? const Value.absent()
          : Value(descriptionFold),
      revision: Value(revision),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory TaskRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskRecord(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      projectId: serializer.fromJson<String?>(json['projectId']),
      parentTaskId: serializer.fromJson<String?>(json['parentTaskId']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      status: serializer.fromJson<String>(json['status']),
      priority: serializer.fromJson<String>(json['priority']),
      colorRgb: serializer.fromJson<String?>(json['colorRgb']),
      startAt: serializer.fromJson<DateTime?>(json['startAt']),
      dueAt: serializer.fromJson<DateTime?>(json['dueAt']),
      scheduledStartAt: serializer.fromJson<DateTime?>(
        json['scheduledStartAt'],
      ),
      scheduledEndAt: serializer.fromJson<DateTime?>(json['scheduledEndAt']),
      remindAt: serializer.fromJson<DateTime?>(json['remindAt']),
      snoozedUntil: serializer.fromJson<DateTime?>(json['snoozedUntil']),
      alarmsMutedAt: serializer.fromJson<DateTime?>(json['alarmsMutedAt']),
      timezone: serializer.fromJson<String>(json['timezone']),
      isUrgent: serializer.fromJson<bool>(json['isUrgent']),
      requiresAcknowledgement: serializer.fromJson<bool>(
        json['requiresAcknowledgement'],
      ),
      repeatRule: serializer.fromJson<String?>(json['repeatRule']),
      seriesId: serializer.fromJson<String?>(json['seriesId']),
      occurrenceDate: serializer.fromJson<String?>(json['occurrenceDate']),
      estimatedMinutes: serializer.fromJson<int?>(json['estimatedMinutes']),
      actualMinutes: serializer.fromJson<int?>(json['actualMinutes']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      calendarMirrorEnabled: serializer.fromJson<bool>(
        json['calendarMirrorEnabled'],
      ),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      titleFold: serializer.fromJson<String?>(json['titleFold']),
      descriptionFold: serializer.fromJson<String?>(json['descriptionFold']),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'projectId': serializer.toJson<String?>(projectId),
      'parentTaskId': serializer.toJson<String?>(parentTaskId),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'status': serializer.toJson<String>(status),
      'priority': serializer.toJson<String>(priority),
      'colorRgb': serializer.toJson<String?>(colorRgb),
      'startAt': serializer.toJson<DateTime?>(startAt),
      'dueAt': serializer.toJson<DateTime?>(dueAt),
      'scheduledStartAt': serializer.toJson<DateTime?>(scheduledStartAt),
      'scheduledEndAt': serializer.toJson<DateTime?>(scheduledEndAt),
      'remindAt': serializer.toJson<DateTime?>(remindAt),
      'snoozedUntil': serializer.toJson<DateTime?>(snoozedUntil),
      'alarmsMutedAt': serializer.toJson<DateTime?>(alarmsMutedAt),
      'timezone': serializer.toJson<String>(timezone),
      'isUrgent': serializer.toJson<bool>(isUrgent),
      'requiresAcknowledgement': serializer.toJson<bool>(
        requiresAcknowledgement,
      ),
      'repeatRule': serializer.toJson<String?>(repeatRule),
      'seriesId': serializer.toJson<String?>(seriesId),
      'occurrenceDate': serializer.toJson<String?>(occurrenceDate),
      'estimatedMinutes': serializer.toJson<int?>(estimatedMinutes),
      'actualMinutes': serializer.toJson<int?>(actualMinutes),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'calendarMirrorEnabled': serializer.toJson<bool>(calendarMirrorEnabled),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'titleFold': serializer.toJson<String?>(titleFold),
      'descriptionFold': serializer.toJson<String?>(descriptionFold),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  TaskRecord copyWith({
    String? id,
    String? workspaceId,
    Value<String?> projectId = const Value.absent(),
    Value<String?> parentTaskId = const Value.absent(),
    String? title,
    Value<String?> description = const Value.absent(),
    String? status,
    String? priority,
    Value<String?> colorRgb = const Value.absent(),
    Value<DateTime?> startAt = const Value.absent(),
    Value<DateTime?> dueAt = const Value.absent(),
    Value<DateTime?> scheduledStartAt = const Value.absent(),
    Value<DateTime?> scheduledEndAt = const Value.absent(),
    Value<DateTime?> remindAt = const Value.absent(),
    Value<DateTime?> snoozedUntil = const Value.absent(),
    Value<DateTime?> alarmsMutedAt = const Value.absent(),
    String? timezone,
    bool? isUrgent,
    bool? requiresAcknowledgement,
    Value<String?> repeatRule = const Value.absent(),
    Value<String?> seriesId = const Value.absent(),
    Value<String?> occurrenceDate = const Value.absent(),
    Value<int?> estimatedMinutes = const Value.absent(),
    Value<int?> actualMinutes = const Value.absent(),
    int? sortOrder,
    bool? calendarMirrorEnabled,
    Value<DateTime?> completedAt = const Value.absent(),
    Value<String?> titleFold = const Value.absent(),
    Value<String?> descriptionFold = const Value.absent(),
    int? revision,
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => TaskRecord(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    projectId: projectId.present ? projectId.value : this.projectId,
    parentTaskId: parentTaskId.present ? parentTaskId.value : this.parentTaskId,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    colorRgb: colorRgb.present ? colorRgb.value : this.colorRgb,
    startAt: startAt.present ? startAt.value : this.startAt,
    dueAt: dueAt.present ? dueAt.value : this.dueAt,
    scheduledStartAt: scheduledStartAt.present
        ? scheduledStartAt.value
        : this.scheduledStartAt,
    scheduledEndAt: scheduledEndAt.present
        ? scheduledEndAt.value
        : this.scheduledEndAt,
    remindAt: remindAt.present ? remindAt.value : this.remindAt,
    snoozedUntil: snoozedUntil.present ? snoozedUntil.value : this.snoozedUntil,
    alarmsMutedAt: alarmsMutedAt.present
        ? alarmsMutedAt.value
        : this.alarmsMutedAt,
    timezone: timezone ?? this.timezone,
    isUrgent: isUrgent ?? this.isUrgent,
    requiresAcknowledgement:
        requiresAcknowledgement ?? this.requiresAcknowledgement,
    repeatRule: repeatRule.present ? repeatRule.value : this.repeatRule,
    seriesId: seriesId.present ? seriesId.value : this.seriesId,
    occurrenceDate: occurrenceDate.present
        ? occurrenceDate.value
        : this.occurrenceDate,
    estimatedMinutes: estimatedMinutes.present
        ? estimatedMinutes.value
        : this.estimatedMinutes,
    actualMinutes: actualMinutes.present
        ? actualMinutes.value
        : this.actualMinutes,
    sortOrder: sortOrder ?? this.sortOrder,
    calendarMirrorEnabled: calendarMirrorEnabled ?? this.calendarMirrorEnabled,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    titleFold: titleFold.present ? titleFold.value : this.titleFold,
    descriptionFold: descriptionFold.present
        ? descriptionFold.value
        : this.descriptionFold,
    revision: revision ?? this.revision,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  TaskRecord copyWithCompanion(TasksCompanion data) {
    return TaskRecord(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      parentTaskId: data.parentTaskId.present
          ? data.parentTaskId.value
          : this.parentTaskId,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      status: data.status.present ? data.status.value : this.status,
      priority: data.priority.present ? data.priority.value : this.priority,
      colorRgb: data.colorRgb.present ? data.colorRgb.value : this.colorRgb,
      startAt: data.startAt.present ? data.startAt.value : this.startAt,
      dueAt: data.dueAt.present ? data.dueAt.value : this.dueAt,
      scheduledStartAt: data.scheduledStartAt.present
          ? data.scheduledStartAt.value
          : this.scheduledStartAt,
      scheduledEndAt: data.scheduledEndAt.present
          ? data.scheduledEndAt.value
          : this.scheduledEndAt,
      remindAt: data.remindAt.present ? data.remindAt.value : this.remindAt,
      snoozedUntil: data.snoozedUntil.present
          ? data.snoozedUntil.value
          : this.snoozedUntil,
      alarmsMutedAt: data.alarmsMutedAt.present
          ? data.alarmsMutedAt.value
          : this.alarmsMutedAt,
      timezone: data.timezone.present ? data.timezone.value : this.timezone,
      isUrgent: data.isUrgent.present ? data.isUrgent.value : this.isUrgent,
      requiresAcknowledgement: data.requiresAcknowledgement.present
          ? data.requiresAcknowledgement.value
          : this.requiresAcknowledgement,
      repeatRule: data.repeatRule.present
          ? data.repeatRule.value
          : this.repeatRule,
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      occurrenceDate: data.occurrenceDate.present
          ? data.occurrenceDate.value
          : this.occurrenceDate,
      estimatedMinutes: data.estimatedMinutes.present
          ? data.estimatedMinutes.value
          : this.estimatedMinutes,
      actualMinutes: data.actualMinutes.present
          ? data.actualMinutes.value
          : this.actualMinutes,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      calendarMirrorEnabled: data.calendarMirrorEnabled.present
          ? data.calendarMirrorEnabled.value
          : this.calendarMirrorEnabled,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      titleFold: data.titleFold.present ? data.titleFold.value : this.titleFold,
      descriptionFold: data.descriptionFold.present
          ? data.descriptionFold.value
          : this.descriptionFold,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskRecord(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('projectId: $projectId, ')
          ..write('parentTaskId: $parentTaskId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('colorRgb: $colorRgb, ')
          ..write('startAt: $startAt, ')
          ..write('dueAt: $dueAt, ')
          ..write('scheduledStartAt: $scheduledStartAt, ')
          ..write('scheduledEndAt: $scheduledEndAt, ')
          ..write('remindAt: $remindAt, ')
          ..write('snoozedUntil: $snoozedUntil, ')
          ..write('alarmsMutedAt: $alarmsMutedAt, ')
          ..write('timezone: $timezone, ')
          ..write('isUrgent: $isUrgent, ')
          ..write('requiresAcknowledgement: $requiresAcknowledgement, ')
          ..write('repeatRule: $repeatRule, ')
          ..write('seriesId: $seriesId, ')
          ..write('occurrenceDate: $occurrenceDate, ')
          ..write('estimatedMinutes: $estimatedMinutes, ')
          ..write('actualMinutes: $actualMinutes, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('calendarMirrorEnabled: $calendarMirrorEnabled, ')
          ..write('completedAt: $completedAt, ')
          ..write('titleFold: $titleFold, ')
          ..write('descriptionFold: $descriptionFold, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    workspaceId,
    projectId,
    parentTaskId,
    title,
    description,
    status,
    priority,
    colorRgb,
    startAt,
    dueAt,
    scheduledStartAt,
    scheduledEndAt,
    remindAt,
    snoozedUntil,
    alarmsMutedAt,
    timezone,
    isUrgent,
    requiresAcknowledgement,
    repeatRule,
    seriesId,
    occurrenceDate,
    estimatedMinutes,
    actualMinutes,
    sortOrder,
    calendarMirrorEnabled,
    completedAt,
    titleFold,
    descriptionFold,
    revision,
    createdAt,
    updatedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskRecord &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.projectId == this.projectId &&
          other.parentTaskId == this.parentTaskId &&
          other.title == this.title &&
          other.description == this.description &&
          other.status == this.status &&
          other.priority == this.priority &&
          other.colorRgb == this.colorRgb &&
          other.startAt == this.startAt &&
          other.dueAt == this.dueAt &&
          other.scheduledStartAt == this.scheduledStartAt &&
          other.scheduledEndAt == this.scheduledEndAt &&
          other.remindAt == this.remindAt &&
          other.snoozedUntil == this.snoozedUntil &&
          other.alarmsMutedAt == this.alarmsMutedAt &&
          other.timezone == this.timezone &&
          other.isUrgent == this.isUrgent &&
          other.requiresAcknowledgement == this.requiresAcknowledgement &&
          other.repeatRule == this.repeatRule &&
          other.seriesId == this.seriesId &&
          other.occurrenceDate == this.occurrenceDate &&
          other.estimatedMinutes == this.estimatedMinutes &&
          other.actualMinutes == this.actualMinutes &&
          other.sortOrder == this.sortOrder &&
          other.calendarMirrorEnabled == this.calendarMirrorEnabled &&
          other.completedAt == this.completedAt &&
          other.titleFold == this.titleFold &&
          other.descriptionFold == this.descriptionFold &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TasksCompanion extends UpdateCompanion<TaskRecord> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String?> projectId;
  final Value<String?> parentTaskId;
  final Value<String> title;
  final Value<String?> description;
  final Value<String> status;
  final Value<String> priority;
  final Value<String?> colorRgb;
  final Value<DateTime?> startAt;
  final Value<DateTime?> dueAt;
  final Value<DateTime?> scheduledStartAt;
  final Value<DateTime?> scheduledEndAt;
  final Value<DateTime?> remindAt;
  final Value<DateTime?> snoozedUntil;
  final Value<DateTime?> alarmsMutedAt;
  final Value<String> timezone;
  final Value<bool> isUrgent;
  final Value<bool> requiresAcknowledgement;
  final Value<String?> repeatRule;
  final Value<String?> seriesId;
  final Value<String?> occurrenceDate;
  final Value<int?> estimatedMinutes;
  final Value<int?> actualMinutes;
  final Value<int> sortOrder;
  final Value<bool> calendarMirrorEnabled;
  final Value<DateTime?> completedAt;
  final Value<String?> titleFold;
  final Value<String?> descriptionFold;
  final Value<int> revision;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const TasksCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.projectId = const Value.absent(),
    this.parentTaskId = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    this.priority = const Value.absent(),
    this.colorRgb = const Value.absent(),
    this.startAt = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.scheduledStartAt = const Value.absent(),
    this.scheduledEndAt = const Value.absent(),
    this.remindAt = const Value.absent(),
    this.snoozedUntil = const Value.absent(),
    this.alarmsMutedAt = const Value.absent(),
    this.timezone = const Value.absent(),
    this.isUrgent = const Value.absent(),
    this.requiresAcknowledgement = const Value.absent(),
    this.repeatRule = const Value.absent(),
    this.seriesId = const Value.absent(),
    this.occurrenceDate = const Value.absent(),
    this.estimatedMinutes = const Value.absent(),
    this.actualMinutes = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.calendarMirrorEnabled = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.titleFold = const Value.absent(),
    this.descriptionFold = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TasksCompanion.insert({
    required String id,
    required String workspaceId,
    this.projectId = const Value.absent(),
    this.parentTaskId = const Value.absent(),
    required String title,
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    this.priority = const Value.absent(),
    this.colorRgb = const Value.absent(),
    this.startAt = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.scheduledStartAt = const Value.absent(),
    this.scheduledEndAt = const Value.absent(),
    this.remindAt = const Value.absent(),
    this.snoozedUntil = const Value.absent(),
    this.alarmsMutedAt = const Value.absent(),
    this.timezone = const Value.absent(),
    this.isUrgent = const Value.absent(),
    this.requiresAcknowledgement = const Value.absent(),
    this.repeatRule = const Value.absent(),
    this.seriesId = const Value.absent(),
    this.occurrenceDate = const Value.absent(),
    this.estimatedMinutes = const Value.absent(),
    this.actualMinutes = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.calendarMirrorEnabled = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.titleFold = const Value.absent(),
    this.descriptionFold = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       title = Value(title);
  static Insertable<TaskRecord> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? projectId,
    Expression<String>? parentTaskId,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? status,
    Expression<String>? priority,
    Expression<String>? colorRgb,
    Expression<DateTime>? startAt,
    Expression<DateTime>? dueAt,
    Expression<DateTime>? scheduledStartAt,
    Expression<DateTime>? scheduledEndAt,
    Expression<DateTime>? remindAt,
    Expression<DateTime>? snoozedUntil,
    Expression<DateTime>? alarmsMutedAt,
    Expression<String>? timezone,
    Expression<bool>? isUrgent,
    Expression<bool>? requiresAcknowledgement,
    Expression<String>? repeatRule,
    Expression<String>? seriesId,
    Expression<String>? occurrenceDate,
    Expression<int>? estimatedMinutes,
    Expression<int>? actualMinutes,
    Expression<int>? sortOrder,
    Expression<bool>? calendarMirrorEnabled,
    Expression<DateTime>? completedAt,
    Expression<String>? titleFold,
    Expression<String>? descriptionFold,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (projectId != null) 'project_id': projectId,
      if (parentTaskId != null) 'parent_task_id': parentTaskId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (status != null) 'status': status,
      if (priority != null) 'priority': priority,
      if (colorRgb != null) 'color_rgb': colorRgb,
      if (startAt != null) 'start_at': startAt,
      if (dueAt != null) 'due_at': dueAt,
      if (scheduledStartAt != null) 'scheduled_start_at': scheduledStartAt,
      if (scheduledEndAt != null) 'scheduled_end_at': scheduledEndAt,
      if (remindAt != null) 'remind_at': remindAt,
      if (snoozedUntil != null) 'snoozed_until': snoozedUntil,
      if (alarmsMutedAt != null) 'alarms_muted_at': alarmsMutedAt,
      if (timezone != null) 'timezone': timezone,
      if (isUrgent != null) 'is_urgent': isUrgent,
      if (requiresAcknowledgement != null)
        'requires_acknowledgement': requiresAcknowledgement,
      if (repeatRule != null) 'repeat_rule': repeatRule,
      if (seriesId != null) 'series_id': seriesId,
      if (occurrenceDate != null) 'occurrence_date': occurrenceDate,
      if (estimatedMinutes != null) 'estimated_minutes': estimatedMinutes,
      if (actualMinutes != null) 'actual_minutes': actualMinutes,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (calendarMirrorEnabled != null)
        'calendar_mirror_enabled': calendarMirrorEnabled,
      if (completedAt != null) 'completed_at': completedAt,
      if (titleFold != null) 'title_fold': titleFold,
      if (descriptionFold != null) 'description_fold': descriptionFold,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TasksCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String?>? projectId,
    Value<String?>? parentTaskId,
    Value<String>? title,
    Value<String?>? description,
    Value<String>? status,
    Value<String>? priority,
    Value<String?>? colorRgb,
    Value<DateTime?>? startAt,
    Value<DateTime?>? dueAt,
    Value<DateTime?>? scheduledStartAt,
    Value<DateTime?>? scheduledEndAt,
    Value<DateTime?>? remindAt,
    Value<DateTime?>? snoozedUntil,
    Value<DateTime?>? alarmsMutedAt,
    Value<String>? timezone,
    Value<bool>? isUrgent,
    Value<bool>? requiresAcknowledgement,
    Value<String?>? repeatRule,
    Value<String?>? seriesId,
    Value<String?>? occurrenceDate,
    Value<int?>? estimatedMinutes,
    Value<int?>? actualMinutes,
    Value<int>? sortOrder,
    Value<bool>? calendarMirrorEnabled,
    Value<DateTime?>? completedAt,
    Value<String?>? titleFold,
    Value<String?>? descriptionFold,
    Value<int>? revision,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return TasksCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      projectId: projectId ?? this.projectId,
      parentTaskId: parentTaskId ?? this.parentTaskId,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      colorRgb: colorRgb ?? this.colorRgb,
      startAt: startAt ?? this.startAt,
      dueAt: dueAt ?? this.dueAt,
      scheduledStartAt: scheduledStartAt ?? this.scheduledStartAt,
      scheduledEndAt: scheduledEndAt ?? this.scheduledEndAt,
      remindAt: remindAt ?? this.remindAt,
      snoozedUntil: snoozedUntil ?? this.snoozedUntil,
      alarmsMutedAt: alarmsMutedAt ?? this.alarmsMutedAt,
      timezone: timezone ?? this.timezone,
      isUrgent: isUrgent ?? this.isUrgent,
      requiresAcknowledgement:
          requiresAcknowledgement ?? this.requiresAcknowledgement,
      repeatRule: repeatRule ?? this.repeatRule,
      seriesId: seriesId ?? this.seriesId,
      occurrenceDate: occurrenceDate ?? this.occurrenceDate,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      actualMinutes: actualMinutes ?? this.actualMinutes,
      sortOrder: sortOrder ?? this.sortOrder,
      calendarMirrorEnabled:
          calendarMirrorEnabled ?? this.calendarMirrorEnabled,
      completedAt: completedAt ?? this.completedAt,
      titleFold: titleFold ?? this.titleFold,
      descriptionFold: descriptionFold ?? this.descriptionFold,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (parentTaskId.present) {
      map['parent_task_id'] = Variable<String>(parentTaskId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (priority.present) {
      map['priority'] = Variable<String>(priority.value);
    }
    if (colorRgb.present) {
      map['color_rgb'] = Variable<String>(colorRgb.value);
    }
    if (startAt.present) {
      map['start_at'] = Variable<DateTime>(startAt.value);
    }
    if (dueAt.present) {
      map['due_at'] = Variable<DateTime>(dueAt.value);
    }
    if (scheduledStartAt.present) {
      map['scheduled_start_at'] = Variable<DateTime>(scheduledStartAt.value);
    }
    if (scheduledEndAt.present) {
      map['scheduled_end_at'] = Variable<DateTime>(scheduledEndAt.value);
    }
    if (remindAt.present) {
      map['remind_at'] = Variable<DateTime>(remindAt.value);
    }
    if (snoozedUntil.present) {
      map['snoozed_until'] = Variable<DateTime>(snoozedUntil.value);
    }
    if (alarmsMutedAt.present) {
      map['alarms_muted_at'] = Variable<DateTime>(alarmsMutedAt.value);
    }
    if (timezone.present) {
      map['timezone'] = Variable<String>(timezone.value);
    }
    if (isUrgent.present) {
      map['is_urgent'] = Variable<bool>(isUrgent.value);
    }
    if (requiresAcknowledgement.present) {
      map['requires_acknowledgement'] = Variable<bool>(
        requiresAcknowledgement.value,
      );
    }
    if (repeatRule.present) {
      map['repeat_rule'] = Variable<String>(repeatRule.value);
    }
    if (seriesId.present) {
      map['series_id'] = Variable<String>(seriesId.value);
    }
    if (occurrenceDate.present) {
      map['occurrence_date'] = Variable<String>(occurrenceDate.value);
    }
    if (estimatedMinutes.present) {
      map['estimated_minutes'] = Variable<int>(estimatedMinutes.value);
    }
    if (actualMinutes.present) {
      map['actual_minutes'] = Variable<int>(actualMinutes.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (calendarMirrorEnabled.present) {
      map['calendar_mirror_enabled'] = Variable<bool>(
        calendarMirrorEnabled.value,
      );
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (titleFold.present) {
      map['title_fold'] = Variable<String>(titleFold.value);
    }
    if (descriptionFold.present) {
      map['description_fold'] = Variable<String>(descriptionFold.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('projectId: $projectId, ')
          ..write('parentTaskId: $parentTaskId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('colorRgb: $colorRgb, ')
          ..write('startAt: $startAt, ')
          ..write('dueAt: $dueAt, ')
          ..write('scheduledStartAt: $scheduledStartAt, ')
          ..write('scheduledEndAt: $scheduledEndAt, ')
          ..write('remindAt: $remindAt, ')
          ..write('snoozedUntil: $snoozedUntil, ')
          ..write('alarmsMutedAt: $alarmsMutedAt, ')
          ..write('timezone: $timezone, ')
          ..write('isUrgent: $isUrgent, ')
          ..write('requiresAcknowledgement: $requiresAcknowledgement, ')
          ..write('repeatRule: $repeatRule, ')
          ..write('seriesId: $seriesId, ')
          ..write('occurrenceDate: $occurrenceDate, ')
          ..write('estimatedMinutes: $estimatedMinutes, ')
          ..write('actualMinutes: $actualMinutes, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('calendarMirrorEnabled: $calendarMirrorEnabled, ')
          ..write('completedAt: $completedAt, ')
          ..write('titleFold: $titleFold, ')
          ..write('descriptionFold: $descriptionFold, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TaskTagRowsTable extends TaskTagRows
    with TableInfo<$TaskTagRowsTable, TaskTagRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskTagRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [taskId, tagId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_tag_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskTagRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {taskId, tagId};
  @override
  TaskTagRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskTagRow(
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_id'],
      )!,
    );
  }

  @override
  $TaskTagRowsTable createAlias(String alias) {
    return $TaskTagRowsTable(attachedDatabase, alias);
  }
}

class TaskTagRow extends DataClass implements Insertable<TaskTagRow> {
  final String taskId;
  final String tagId;
  const TaskTagRow({required this.taskId, required this.tagId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['task_id'] = Variable<String>(taskId);
    map['tag_id'] = Variable<String>(tagId);
    return map;
  }

  TaskTagRowsCompanion toCompanion(bool nullToAbsent) {
    return TaskTagRowsCompanion(taskId: Value(taskId), tagId: Value(tagId));
  }

  factory TaskTagRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskTagRow(
      taskId: serializer.fromJson<String>(json['taskId']),
      tagId: serializer.fromJson<String>(json['tagId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'taskId': serializer.toJson<String>(taskId),
      'tagId': serializer.toJson<String>(tagId),
    };
  }

  TaskTagRow copyWith({String? taskId, String? tagId}) =>
      TaskTagRow(taskId: taskId ?? this.taskId, tagId: tagId ?? this.tagId);
  TaskTagRow copyWithCompanion(TaskTagRowsCompanion data) {
    return TaskTagRow(
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskTagRow(')
          ..write('taskId: $taskId, ')
          ..write('tagId: $tagId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(taskId, tagId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskTagRow &&
          other.taskId == this.taskId &&
          other.tagId == this.tagId);
}

class TaskTagRowsCompanion extends UpdateCompanion<TaskTagRow> {
  final Value<String> taskId;
  final Value<String> tagId;
  final Value<int> rowid;
  const TaskTagRowsCompanion({
    this.taskId = const Value.absent(),
    this.tagId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskTagRowsCompanion.insert({
    required String taskId,
    required String tagId,
    this.rowid = const Value.absent(),
  }) : taskId = Value(taskId),
       tagId = Value(tagId);
  static Insertable<TaskTagRow> custom({
    Expression<String>? taskId,
    Expression<String>? tagId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (taskId != null) 'task_id': taskId,
      if (tagId != null) 'tag_id': tagId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskTagRowsCompanion copyWith({
    Value<String>? taskId,
    Value<String>? tagId,
    Value<int>? rowid,
  }) {
    return TaskTagRowsCompanion(
      taskId: taskId ?? this.taskId,
      tagId: tagId ?? this.tagId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskTagRowsCompanion(')
          ..write('taskId: $taskId, ')
          ..write('tagId: $tagId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChecklistItemsTable extends ChecklistItems
    with TableInfo<$ChecklistItemsTable, ChecklistItemRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChecklistItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isDoneMeta = const VerificationMeta('isDone');
  @override
  late final GeneratedColumn<bool> isDone = GeneratedColumn<bool>(
    'is_done',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_done" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    taskId,
    title,
    isDone,
    sortOrder,
    revision,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'checklist_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChecklistItemRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('is_done')) {
      context.handle(
        _isDoneMeta,
        isDone.isAcceptableOrUnknown(data['is_done']!, _isDoneMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChecklistItemRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChecklistItemRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      isDone: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_done'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $ChecklistItemsTable createAlias(String alias) {
    return $ChecklistItemsTable(attachedDatabase, alias);
  }
}

class ChecklistItemRecord extends DataClass
    implements Insertable<ChecklistItemRecord> {
  final String id;
  final String taskId;
  final String title;
  final bool isDone;
  final int sortOrder;
  final int revision;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const ChecklistItemRecord({
    required this.id,
    required this.taskId,
    required this.title,
    required this.isDone,
    required this.sortOrder,
    required this.revision,
    this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['task_id'] = Variable<String>(taskId);
    map['title'] = Variable<String>(title);
    map['is_done'] = Variable<bool>(isDone);
    map['sort_order'] = Variable<int>(sortOrder);
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  ChecklistItemsCompanion toCompanion(bool nullToAbsent) {
    return ChecklistItemsCompanion(
      id: Value(id),
      taskId: Value(taskId),
      title: Value(title),
      isDone: Value(isDone),
      sortOrder: Value(sortOrder),
      revision: Value(revision),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory ChecklistItemRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChecklistItemRecord(
      id: serializer.fromJson<String>(json['id']),
      taskId: serializer.fromJson<String>(json['taskId']),
      title: serializer.fromJson<String>(json['title']),
      isDone: serializer.fromJson<bool>(json['isDone']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'taskId': serializer.toJson<String>(taskId),
      'title': serializer.toJson<String>(title),
      'isDone': serializer.toJson<bool>(isDone),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  ChecklistItemRecord copyWith({
    String? id,
    String? taskId,
    String? title,
    bool? isDone,
    int? sortOrder,
    int? revision,
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => ChecklistItemRecord(
    id: id ?? this.id,
    taskId: taskId ?? this.taskId,
    title: title ?? this.title,
    isDone: isDone ?? this.isDone,
    sortOrder: sortOrder ?? this.sortOrder,
    revision: revision ?? this.revision,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  ChecklistItemRecord copyWithCompanion(ChecklistItemsCompanion data) {
    return ChecklistItemRecord(
      id: data.id.present ? data.id.value : this.id,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      title: data.title.present ? data.title.value : this.title,
      isDone: data.isDone.present ? data.isDone.value : this.isDone,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChecklistItemRecord(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('title: $title, ')
          ..write('isDone: $isDone, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    taskId,
    title,
    isDone,
    sortOrder,
    revision,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChecklistItemRecord &&
          other.id == this.id &&
          other.taskId == this.taskId &&
          other.title == this.title &&
          other.isDone == this.isDone &&
          other.sortOrder == this.sortOrder &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ChecklistItemsCompanion extends UpdateCompanion<ChecklistItemRecord> {
  final Value<String> id;
  final Value<String> taskId;
  final Value<String> title;
  final Value<bool> isDone;
  final Value<int> sortOrder;
  final Value<int> revision;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const ChecklistItemsCompanion({
    this.id = const Value.absent(),
    this.taskId = const Value.absent(),
    this.title = const Value.absent(),
    this.isDone = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChecklistItemsCompanion.insert({
    required String id,
    required String taskId,
    required String title,
    this.isDone = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       taskId = Value(taskId),
       title = Value(title);
  static Insertable<ChecklistItemRecord> custom({
    Expression<String>? id,
    Expression<String>? taskId,
    Expression<String>? title,
    Expression<bool>? isDone,
    Expression<int>? sortOrder,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (taskId != null) 'task_id': taskId,
      if (title != null) 'title': title,
      if (isDone != null) 'is_done': isDone,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChecklistItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? taskId,
    Value<String>? title,
    Value<bool>? isDone,
    Value<int>? sortOrder,
    Value<int>? revision,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return ChecklistItemsCompanion(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      title: title ?? this.title,
      isDone: isDone ?? this.isDone,
      sortOrder: sortOrder ?? this.sortOrder,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (isDone.present) {
      map['is_done'] = Variable<bool>(isDone.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChecklistItemsCompanion(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('title: $title, ')
          ..write('isDone: $isDone, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NotesTable extends Notes with TableInfo<$NotesTable, NoteRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdFromTaskIdMeta = const VerificationMeta(
    'createdFromTaskId',
  );
  @override
  late final GeneratedColumn<String> createdFromTaskId =
      GeneratedColumn<String>(
        'created_from_task_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentDeltaMeta = const VerificationMeta(
    'contentDelta',
  );
  @override
  late final GeneratedColumn<String> contentDelta = GeneratedColumn<String>(
    'content_delta',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentMarkdownMeta = const VerificationMeta(
    'contentMarkdown',
  );
  @override
  late final GeneratedColumn<String> contentMarkdown = GeneratedColumn<String>(
    'content_markdown',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentFormatMeta = const VerificationMeta(
    'contentFormat',
  );
  @override
  late final GeneratedColumn<String> contentFormat = GeneratedColumn<String>(
    'content_format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('delta'),
  );
  static const VerificationMeta _plainTextMeta = const VerificationMeta(
    'plainText',
  );
  @override
  late final GeneratedColumn<String> plainText = GeneratedColumn<String>(
    'plain_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isPinnedMeta = const VerificationMeta(
    'isPinned',
  );
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
    'is_pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isArchivedMeta = const VerificationMeta(
    'isArchived',
  );
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _titleFoldMeta = const VerificationMeta(
    'titleFold',
  );
  @override
  late final GeneratedColumn<String> titleFold = GeneratedColumn<String>(
    'title_fold',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bodyFoldMeta = const VerificationMeta(
    'bodyFold',
  );
  @override
  late final GeneratedColumn<String> bodyFold = GeneratedColumn<String>(
    'body_fold',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _conflictVersionIdMeta = const VerificationMeta(
    'conflictVersionId',
  );
  @override
  late final GeneratedColumn<String> conflictVersionId =
      GeneratedColumn<String>(
        'conflict_version_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    projectId,
    createdFromTaskId,
    title,
    contentDelta,
    contentMarkdown,
    contentFormat,
    plainText,
    isPinned,
    isArchived,
    titleFold,
    bodyFold,
    revision,
    createdAt,
    updatedAt,
    conflictVersionId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    }
    if (data.containsKey('created_from_task_id')) {
      context.handle(
        _createdFromTaskIdMeta,
        createdFromTaskId.isAcceptableOrUnknown(
          data['created_from_task_id']!,
          _createdFromTaskIdMeta,
        ),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('content_delta')) {
      context.handle(
        _contentDeltaMeta,
        contentDelta.isAcceptableOrUnknown(
          data['content_delta']!,
          _contentDeltaMeta,
        ),
      );
    }
    if (data.containsKey('content_markdown')) {
      context.handle(
        _contentMarkdownMeta,
        contentMarkdown.isAcceptableOrUnknown(
          data['content_markdown']!,
          _contentMarkdownMeta,
        ),
      );
    }
    if (data.containsKey('content_format')) {
      context.handle(
        _contentFormatMeta,
        contentFormat.isAcceptableOrUnknown(
          data['content_format']!,
          _contentFormatMeta,
        ),
      );
    }
    if (data.containsKey('plain_text')) {
      context.handle(
        _plainTextMeta,
        plainText.isAcceptableOrUnknown(data['plain_text']!, _plainTextMeta),
      );
    }
    if (data.containsKey('is_pinned')) {
      context.handle(
        _isPinnedMeta,
        isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta),
      );
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _isArchivedMeta,
        isArchived.isAcceptableOrUnknown(data['is_archived']!, _isArchivedMeta),
      );
    }
    if (data.containsKey('title_fold')) {
      context.handle(
        _titleFoldMeta,
        titleFold.isAcceptableOrUnknown(data['title_fold']!, _titleFoldMeta),
      );
    }
    if (data.containsKey('body_fold')) {
      context.handle(
        _bodyFoldMeta,
        bodyFold.isAcceptableOrUnknown(data['body_fold']!, _bodyFoldMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('conflict_version_id')) {
      context.handle(
        _conflictVersionIdMeta,
        conflictVersionId.isAcceptableOrUnknown(
          data['conflict_version_id']!,
          _conflictVersionIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      ),
      createdFromTaskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_from_task_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      contentDelta: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_delta'],
      ),
      contentMarkdown: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_markdown'],
      ),
      contentFormat: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_format'],
      )!,
      plainText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plain_text'],
      ),
      isPinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pinned'],
      )!,
      isArchived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
      titleFold: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_fold'],
      ),
      bodyFold: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_fold'],
      ),
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
      conflictVersionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conflict_version_id'],
      ),
    );
  }

  @override
  $NotesTable createAlias(String alias) {
    return $NotesTable(attachedDatabase, alias);
  }
}

class NoteRecord extends DataClass implements Insertable<NoteRecord> {
  final String id;
  final String workspaceId;
  final String? projectId;
  final String? createdFromTaskId;
  final String title;

  /// Quill delta ops as a JSON string (canonical content, §9.1).
  final String? contentDelta;
  final String? contentMarkdown;

  /// Which of the two above is CANONICAL (v17, OPH-248, ADR-0028 §1).
  ///
  /// `'delta'` or `'markdown'`. Defaulted rather than nullable so the replica
  /// answers the same way the server does for every row that predates the
  /// column — the migration backfills nothing because it does not have to.
  final String contentFormat;
  final String? plainText;
  final bool isPinned;
  final bool isArchived;
  final String? titleFold;
  final String? bodyFold;
  final int revision;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// The server version row holding a body of THIS note that was refused
  /// (v18, OPH-268). Device-local and never pushed: it is a pointer into the
  /// server's history, not a fact about the note. Its presence is what raises
  /// the conflict banner — and it replaces the automatic sibling copy, which
  /// used to make the decision for the user.
  final String? conflictVersionId;
  const NoteRecord({
    required this.id,
    required this.workspaceId,
    this.projectId,
    this.createdFromTaskId,
    required this.title,
    this.contentDelta,
    this.contentMarkdown,
    required this.contentFormat,
    this.plainText,
    required this.isPinned,
    required this.isArchived,
    this.titleFold,
    this.bodyFold,
    required this.revision,
    this.createdAt,
    this.updatedAt,
    this.conflictVersionId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    if (!nullToAbsent || projectId != null) {
      map['project_id'] = Variable<String>(projectId);
    }
    if (!nullToAbsent || createdFromTaskId != null) {
      map['created_from_task_id'] = Variable<String>(createdFromTaskId);
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || contentDelta != null) {
      map['content_delta'] = Variable<String>(contentDelta);
    }
    if (!nullToAbsent || contentMarkdown != null) {
      map['content_markdown'] = Variable<String>(contentMarkdown);
    }
    map['content_format'] = Variable<String>(contentFormat);
    if (!nullToAbsent || plainText != null) {
      map['plain_text'] = Variable<String>(plainText);
    }
    map['is_pinned'] = Variable<bool>(isPinned);
    map['is_archived'] = Variable<bool>(isArchived);
    if (!nullToAbsent || titleFold != null) {
      map['title_fold'] = Variable<String>(titleFold);
    }
    if (!nullToAbsent || bodyFold != null) {
      map['body_fold'] = Variable<String>(bodyFold);
    }
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    if (!nullToAbsent || conflictVersionId != null) {
      map['conflict_version_id'] = Variable<String>(conflictVersionId);
    }
    return map;
  }

  NotesCompanion toCompanion(bool nullToAbsent) {
    return NotesCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      projectId: projectId == null && nullToAbsent
          ? const Value.absent()
          : Value(projectId),
      createdFromTaskId: createdFromTaskId == null && nullToAbsent
          ? const Value.absent()
          : Value(createdFromTaskId),
      title: Value(title),
      contentDelta: contentDelta == null && nullToAbsent
          ? const Value.absent()
          : Value(contentDelta),
      contentMarkdown: contentMarkdown == null && nullToAbsent
          ? const Value.absent()
          : Value(contentMarkdown),
      contentFormat: Value(contentFormat),
      plainText: plainText == null && nullToAbsent
          ? const Value.absent()
          : Value(plainText),
      isPinned: Value(isPinned),
      isArchived: Value(isArchived),
      titleFold: titleFold == null && nullToAbsent
          ? const Value.absent()
          : Value(titleFold),
      bodyFold: bodyFold == null && nullToAbsent
          ? const Value.absent()
          : Value(bodyFold),
      revision: Value(revision),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      conflictVersionId: conflictVersionId == null && nullToAbsent
          ? const Value.absent()
          : Value(conflictVersionId),
    );
  }

  factory NoteRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteRecord(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      projectId: serializer.fromJson<String?>(json['projectId']),
      createdFromTaskId: serializer.fromJson<String?>(
        json['createdFromTaskId'],
      ),
      title: serializer.fromJson<String>(json['title']),
      contentDelta: serializer.fromJson<String?>(json['contentDelta']),
      contentMarkdown: serializer.fromJson<String?>(json['contentMarkdown']),
      contentFormat: serializer.fromJson<String>(json['contentFormat']),
      plainText: serializer.fromJson<String?>(json['plainText']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      titleFold: serializer.fromJson<String?>(json['titleFold']),
      bodyFold: serializer.fromJson<String?>(json['bodyFold']),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
      conflictVersionId: serializer.fromJson<String?>(
        json['conflictVersionId'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'projectId': serializer.toJson<String?>(projectId),
      'createdFromTaskId': serializer.toJson<String?>(createdFromTaskId),
      'title': serializer.toJson<String>(title),
      'contentDelta': serializer.toJson<String?>(contentDelta),
      'contentMarkdown': serializer.toJson<String?>(contentMarkdown),
      'contentFormat': serializer.toJson<String>(contentFormat),
      'plainText': serializer.toJson<String?>(plainText),
      'isPinned': serializer.toJson<bool>(isPinned),
      'isArchived': serializer.toJson<bool>(isArchived),
      'titleFold': serializer.toJson<String?>(titleFold),
      'bodyFold': serializer.toJson<String?>(bodyFold),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
      'conflictVersionId': serializer.toJson<String?>(conflictVersionId),
    };
  }

  NoteRecord copyWith({
    String? id,
    String? workspaceId,
    Value<String?> projectId = const Value.absent(),
    Value<String?> createdFromTaskId = const Value.absent(),
    String? title,
    Value<String?> contentDelta = const Value.absent(),
    Value<String?> contentMarkdown = const Value.absent(),
    String? contentFormat,
    Value<String?> plainText = const Value.absent(),
    bool? isPinned,
    bool? isArchived,
    Value<String?> titleFold = const Value.absent(),
    Value<String?> bodyFold = const Value.absent(),
    int? revision,
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
    Value<String?> conflictVersionId = const Value.absent(),
  }) => NoteRecord(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    projectId: projectId.present ? projectId.value : this.projectId,
    createdFromTaskId: createdFromTaskId.present
        ? createdFromTaskId.value
        : this.createdFromTaskId,
    title: title ?? this.title,
    contentDelta: contentDelta.present ? contentDelta.value : this.contentDelta,
    contentMarkdown: contentMarkdown.present
        ? contentMarkdown.value
        : this.contentMarkdown,
    contentFormat: contentFormat ?? this.contentFormat,
    plainText: plainText.present ? plainText.value : this.plainText,
    isPinned: isPinned ?? this.isPinned,
    isArchived: isArchived ?? this.isArchived,
    titleFold: titleFold.present ? titleFold.value : this.titleFold,
    bodyFold: bodyFold.present ? bodyFold.value : this.bodyFold,
    revision: revision ?? this.revision,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
    conflictVersionId: conflictVersionId.present
        ? conflictVersionId.value
        : this.conflictVersionId,
  );
  NoteRecord copyWithCompanion(NotesCompanion data) {
    return NoteRecord(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      createdFromTaskId: data.createdFromTaskId.present
          ? data.createdFromTaskId.value
          : this.createdFromTaskId,
      title: data.title.present ? data.title.value : this.title,
      contentDelta: data.contentDelta.present
          ? data.contentDelta.value
          : this.contentDelta,
      contentMarkdown: data.contentMarkdown.present
          ? data.contentMarkdown.value
          : this.contentMarkdown,
      contentFormat: data.contentFormat.present
          ? data.contentFormat.value
          : this.contentFormat,
      plainText: data.plainText.present ? data.plainText.value : this.plainText,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      isArchived: data.isArchived.present
          ? data.isArchived.value
          : this.isArchived,
      titleFold: data.titleFold.present ? data.titleFold.value : this.titleFold,
      bodyFold: data.bodyFold.present ? data.bodyFold.value : this.bodyFold,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      conflictVersionId: data.conflictVersionId.present
          ? data.conflictVersionId.value
          : this.conflictVersionId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteRecord(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('projectId: $projectId, ')
          ..write('createdFromTaskId: $createdFromTaskId, ')
          ..write('title: $title, ')
          ..write('contentDelta: $contentDelta, ')
          ..write('contentMarkdown: $contentMarkdown, ')
          ..write('contentFormat: $contentFormat, ')
          ..write('plainText: $plainText, ')
          ..write('isPinned: $isPinned, ')
          ..write('isArchived: $isArchived, ')
          ..write('titleFold: $titleFold, ')
          ..write('bodyFold: $bodyFold, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('conflictVersionId: $conflictVersionId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    projectId,
    createdFromTaskId,
    title,
    contentDelta,
    contentMarkdown,
    contentFormat,
    plainText,
    isPinned,
    isArchived,
    titleFold,
    bodyFold,
    revision,
    createdAt,
    updatedAt,
    conflictVersionId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteRecord &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.projectId == this.projectId &&
          other.createdFromTaskId == this.createdFromTaskId &&
          other.title == this.title &&
          other.contentDelta == this.contentDelta &&
          other.contentMarkdown == this.contentMarkdown &&
          other.contentFormat == this.contentFormat &&
          other.plainText == this.plainText &&
          other.isPinned == this.isPinned &&
          other.isArchived == this.isArchived &&
          other.titleFold == this.titleFold &&
          other.bodyFold == this.bodyFold &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.conflictVersionId == this.conflictVersionId);
}

class NotesCompanion extends UpdateCompanion<NoteRecord> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String?> projectId;
  final Value<String?> createdFromTaskId;
  final Value<String> title;
  final Value<String?> contentDelta;
  final Value<String?> contentMarkdown;
  final Value<String> contentFormat;
  final Value<String?> plainText;
  final Value<bool> isPinned;
  final Value<bool> isArchived;
  final Value<String?> titleFold;
  final Value<String?> bodyFold;
  final Value<int> revision;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<String?> conflictVersionId;
  final Value<int> rowid;
  const NotesCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.projectId = const Value.absent(),
    this.createdFromTaskId = const Value.absent(),
    this.title = const Value.absent(),
    this.contentDelta = const Value.absent(),
    this.contentMarkdown = const Value.absent(),
    this.contentFormat = const Value.absent(),
    this.plainText = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.titleFold = const Value.absent(),
    this.bodyFold = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.conflictVersionId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NotesCompanion.insert({
    required String id,
    required String workspaceId,
    this.projectId = const Value.absent(),
    this.createdFromTaskId = const Value.absent(),
    required String title,
    this.contentDelta = const Value.absent(),
    this.contentMarkdown = const Value.absent(),
    this.contentFormat = const Value.absent(),
    this.plainText = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.titleFold = const Value.absent(),
    this.bodyFold = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.conflictVersionId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       title = Value(title);
  static Insertable<NoteRecord> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? projectId,
    Expression<String>? createdFromTaskId,
    Expression<String>? title,
    Expression<String>? contentDelta,
    Expression<String>? contentMarkdown,
    Expression<String>? contentFormat,
    Expression<String>? plainText,
    Expression<bool>? isPinned,
    Expression<bool>? isArchived,
    Expression<String>? titleFold,
    Expression<String>? bodyFold,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? conflictVersionId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (projectId != null) 'project_id': projectId,
      if (createdFromTaskId != null) 'created_from_task_id': createdFromTaskId,
      if (title != null) 'title': title,
      if (contentDelta != null) 'content_delta': contentDelta,
      if (contentMarkdown != null) 'content_markdown': contentMarkdown,
      if (contentFormat != null) 'content_format': contentFormat,
      if (plainText != null) 'plain_text': plainText,
      if (isPinned != null) 'is_pinned': isPinned,
      if (isArchived != null) 'is_archived': isArchived,
      if (titleFold != null) 'title_fold': titleFold,
      if (bodyFold != null) 'body_fold': bodyFold,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (conflictVersionId != null) 'conflict_version_id': conflictVersionId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NotesCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String?>? projectId,
    Value<String?>? createdFromTaskId,
    Value<String>? title,
    Value<String?>? contentDelta,
    Value<String?>? contentMarkdown,
    Value<String>? contentFormat,
    Value<String?>? plainText,
    Value<bool>? isPinned,
    Value<bool>? isArchived,
    Value<String?>? titleFold,
    Value<String?>? bodyFold,
    Value<int>? revision,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<String?>? conflictVersionId,
    Value<int>? rowid,
  }) {
    return NotesCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      projectId: projectId ?? this.projectId,
      createdFromTaskId: createdFromTaskId ?? this.createdFromTaskId,
      title: title ?? this.title,
      contentDelta: contentDelta ?? this.contentDelta,
      contentMarkdown: contentMarkdown ?? this.contentMarkdown,
      contentFormat: contentFormat ?? this.contentFormat,
      plainText: plainText ?? this.plainText,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      titleFold: titleFold ?? this.titleFold,
      bodyFold: bodyFold ?? this.bodyFold,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      conflictVersionId: conflictVersionId ?? this.conflictVersionId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (createdFromTaskId.present) {
      map['created_from_task_id'] = Variable<String>(createdFromTaskId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (contentDelta.present) {
      map['content_delta'] = Variable<String>(contentDelta.value);
    }
    if (contentMarkdown.present) {
      map['content_markdown'] = Variable<String>(contentMarkdown.value);
    }
    if (contentFormat.present) {
      map['content_format'] = Variable<String>(contentFormat.value);
    }
    if (plainText.present) {
      map['plain_text'] = Variable<String>(plainText.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (titleFold.present) {
      map['title_fold'] = Variable<String>(titleFold.value);
    }
    if (bodyFold.present) {
      map['body_fold'] = Variable<String>(bodyFold.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (conflictVersionId.present) {
      map['conflict_version_id'] = Variable<String>(conflictVersionId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotesCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('projectId: $projectId, ')
          ..write('createdFromTaskId: $createdFromTaskId, ')
          ..write('title: $title, ')
          ..write('contentDelta: $contentDelta, ')
          ..write('contentMarkdown: $contentMarkdown, ')
          ..write('contentFormat: $contentFormat, ')
          ..write('plainText: $plainText, ')
          ..write('isPinned: $isPinned, ')
          ..write('isArchived: $isArchived, ')
          ..write('titleFold: $titleFold, ')
          ..write('bodyFold: $bodyFold, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('conflictVersionId: $conflictVersionId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NoteLinkRowsTable extends NoteLinkRows
    with TableInfo<$NoteLinkRowsTable, NoteLinkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteLinkRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, noteId, entityType, entityId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_link_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteLinkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteLinkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteLinkRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
    );
  }

  @override
  $NoteLinkRowsTable createAlias(String alias) {
    return $NoteLinkRowsTable(attachedDatabase, alias);
  }
}

class NoteLinkRow extends DataClass implements Insertable<NoteLinkRow> {
  final String id;
  final String noteId;
  final String entityType;
  final String entityId;
  const NoteLinkRow({
    required this.id,
    required this.noteId,
    required this.entityType,
    required this.entityId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['note_id'] = Variable<String>(noteId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    return map;
  }

  NoteLinkRowsCompanion toCompanion(bool nullToAbsent) {
    return NoteLinkRowsCompanion(
      id: Value(id),
      noteId: Value(noteId),
      entityType: Value(entityType),
      entityId: Value(entityId),
    );
  }

  factory NoteLinkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteLinkRow(
      id: serializer.fromJson<String>(json['id']),
      noteId: serializer.fromJson<String>(json['noteId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'noteId': serializer.toJson<String>(noteId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
    };
  }

  NoteLinkRow copyWith({
    String? id,
    String? noteId,
    String? entityType,
    String? entityId,
  }) => NoteLinkRow(
    id: id ?? this.id,
    noteId: noteId ?? this.noteId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
  );
  NoteLinkRow copyWithCompanion(NoteLinkRowsCompanion data) {
    return NoteLinkRow(
      id: data.id.present ? data.id.value : this.id,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteLinkRow(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, noteId, entityType, entityId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteLinkRow &&
          other.id == this.id &&
          other.noteId == this.noteId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId);
}

class NoteLinkRowsCompanion extends UpdateCompanion<NoteLinkRow> {
  final Value<String> id;
  final Value<String> noteId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<int> rowid;
  const NoteLinkRowsCompanion({
    this.id = const Value.absent(),
    this.noteId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteLinkRowsCompanion.insert({
    required String id,
    required String noteId,
    required String entityType,
    required String entityId,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       noteId = Value(noteId),
       entityType = Value(entityType),
       entityId = Value(entityId);
  static Insertable<NoteLinkRow> custom({
    Expression<String>? id,
    Expression<String>? noteId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (noteId != null) 'note_id': noteId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteLinkRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? noteId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<int>? rowid,
  }) {
    return NoteLinkRowsCompanion(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteLinkRowsCompanion(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RemindersTable extends Reminders
    with TableInfo<$RemindersTable, Reminder> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RemindersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('remind'),
  );
  static const VerificationMeta _snoozeCountMeta = const VerificationMeta(
    'snoozeCount',
  );
  @override
  late final GeneratedColumn<int> snoozeCount = GeneratedColumn<int>(
    'snooze_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _remindAtMeta = const VerificationMeta(
    'remindAt',
  );
  @override
  late final GeneratedColumn<DateTime> remindAt = GeneratedColumn<DateTime>(
    'remind_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timezoneMeta = const VerificationMeta(
    'timezone',
  );
  @override
  late final GeneratedColumn<String> timezone = GeneratedColumn<String>(
    'timezone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Europe/Istanbul'),
  );
  static const VerificationMeta _alarmLevelMeta = const VerificationMeta(
    'alarmLevel',
  );
  @override
  late final GeneratedColumn<String> alarmLevel = GeneratedColumn<String>(
    'alarm_level',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('normal'),
  );
  static const VerificationMeta _requiresAcknowledgementMeta =
      const VerificationMeta('requiresAcknowledgement');
  @override
  late final GeneratedColumn<bool> requiresAcknowledgement =
      GeneratedColumn<bool>(
        'requires_acknowledgement',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("requires_acknowledgement" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _repeatRuleMeta = const VerificationMeta(
    'repeatRule',
  );
  @override
  late final GeneratedColumn<String> repeatRule = GeneratedColumn<String>(
    'repeat_rule',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('scheduled'),
  );
  static const VerificationMeta _snoozedUntilMeta = const VerificationMeta(
    'snoozedUntil',
  );
  @override
  late final GeneratedColumn<DateTime> snoozedUntil = GeneratedColumn<DateTime>(
    'snoozed_until',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deliveredAtMeta = const VerificationMeta(
    'deliveredAt',
  );
  @override
  late final GeneratedColumn<DateTime> deliveredAt = GeneratedColumn<DateTime>(
    'delivered_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _acknowledgedAtMeta = const VerificationMeta(
    'acknowledgedAt',
  );
  @override
  late final GeneratedColumn<DateTime> acknowledgedAt =
      GeneratedColumn<DateTime>(
        'acknowledged_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    taskId,
    kind,
    snoozeCount,
    remindAt,
    timezone,
    alarmLevel,
    requiresAcknowledgement,
    repeatRule,
    status,
    snoozedUntil,
    deliveredAt,
    acknowledgedAt,
    revision,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reminders';
  @override
  VerificationContext validateIntegrity(
    Insertable<Reminder> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('snooze_count')) {
      context.handle(
        _snoozeCountMeta,
        snoozeCount.isAcceptableOrUnknown(
          data['snooze_count']!,
          _snoozeCountMeta,
        ),
      );
    }
    if (data.containsKey('remind_at')) {
      context.handle(
        _remindAtMeta,
        remindAt.isAcceptableOrUnknown(data['remind_at']!, _remindAtMeta),
      );
    } else if (isInserting) {
      context.missing(_remindAtMeta);
    }
    if (data.containsKey('timezone')) {
      context.handle(
        _timezoneMeta,
        timezone.isAcceptableOrUnknown(data['timezone']!, _timezoneMeta),
      );
    }
    if (data.containsKey('alarm_level')) {
      context.handle(
        _alarmLevelMeta,
        alarmLevel.isAcceptableOrUnknown(data['alarm_level']!, _alarmLevelMeta),
      );
    }
    if (data.containsKey('requires_acknowledgement')) {
      context.handle(
        _requiresAcknowledgementMeta,
        requiresAcknowledgement.isAcceptableOrUnknown(
          data['requires_acknowledgement']!,
          _requiresAcknowledgementMeta,
        ),
      );
    }
    if (data.containsKey('repeat_rule')) {
      context.handle(
        _repeatRuleMeta,
        repeatRule.isAcceptableOrUnknown(data['repeat_rule']!, _repeatRuleMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('snoozed_until')) {
      context.handle(
        _snoozedUntilMeta,
        snoozedUntil.isAcceptableOrUnknown(
          data['snoozed_until']!,
          _snoozedUntilMeta,
        ),
      );
    }
    if (data.containsKey('delivered_at')) {
      context.handle(
        _deliveredAtMeta,
        deliveredAt.isAcceptableOrUnknown(
          data['delivered_at']!,
          _deliveredAtMeta,
        ),
      );
    }
    if (data.containsKey('acknowledged_at')) {
      context.handle(
        _acknowledgedAtMeta,
        acknowledgedAt.isAcceptableOrUnknown(
          data['acknowledged_at']!,
          _acknowledgedAtMeta,
        ),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Reminder map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Reminder(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      snoozeCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}snooze_count'],
      )!,
      remindAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}remind_at'],
      )!,
      timezone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timezone'],
      )!,
      alarmLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alarm_level'],
      )!,
      requiresAcknowledgement: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}requires_acknowledgement'],
      )!,
      repeatRule: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}repeat_rule'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      snoozedUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}snoozed_until'],
      ),
      deliveredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}delivered_at'],
      ),
      acknowledgedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}acknowledged_at'],
      ),
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $RemindersTable createAlias(String alias) {
    return $RemindersTable(attachedDatabase, alias);
  }
}

class Reminder extends DataClass implements Insertable<Reminder> {
  final String id;
  final String taskId;

  /// Which alarm this is (OPH-175): `remind` (the nudge the user asked for) or
  /// `due` (an urgent task's own deadline). Server-owned; a task can hold one
  /// active row of each.
  final String kind;

  /// How many snooze rounds this alarm has been through (OPH-177) — the
  /// post-snooze alert says WHICH round it is. Reset when the alarm is re-armed
  /// to a new instant: a moved deadline is a new alarm.
  final int snoozeCount;
  final DateTime remindAt;
  final String timezone;
  final String alarmLevel;
  final bool requiresAcknowledgement;
  final String? repeatRule;
  final String status;
  final DateTime? snoozedUntil;
  final DateTime? deliveredAt;
  final DateTime? acknowledgedAt;
  final int revision;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const Reminder({
    required this.id,
    required this.taskId,
    required this.kind,
    required this.snoozeCount,
    required this.remindAt,
    required this.timezone,
    required this.alarmLevel,
    required this.requiresAcknowledgement,
    this.repeatRule,
    required this.status,
    this.snoozedUntil,
    this.deliveredAt,
    this.acknowledgedAt,
    required this.revision,
    this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['task_id'] = Variable<String>(taskId);
    map['kind'] = Variable<String>(kind);
    map['snooze_count'] = Variable<int>(snoozeCount);
    map['remind_at'] = Variable<DateTime>(remindAt);
    map['timezone'] = Variable<String>(timezone);
    map['alarm_level'] = Variable<String>(alarmLevel);
    map['requires_acknowledgement'] = Variable<bool>(requiresAcknowledgement);
    if (!nullToAbsent || repeatRule != null) {
      map['repeat_rule'] = Variable<String>(repeatRule);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || snoozedUntil != null) {
      map['snoozed_until'] = Variable<DateTime>(snoozedUntil);
    }
    if (!nullToAbsent || deliveredAt != null) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt);
    }
    if (!nullToAbsent || acknowledgedAt != null) {
      map['acknowledged_at'] = Variable<DateTime>(acknowledgedAt);
    }
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  RemindersCompanion toCompanion(bool nullToAbsent) {
    return RemindersCompanion(
      id: Value(id),
      taskId: Value(taskId),
      kind: Value(kind),
      snoozeCount: Value(snoozeCount),
      remindAt: Value(remindAt),
      timezone: Value(timezone),
      alarmLevel: Value(alarmLevel),
      requiresAcknowledgement: Value(requiresAcknowledgement),
      repeatRule: repeatRule == null && nullToAbsent
          ? const Value.absent()
          : Value(repeatRule),
      status: Value(status),
      snoozedUntil: snoozedUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(snoozedUntil),
      deliveredAt: deliveredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deliveredAt),
      acknowledgedAt: acknowledgedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(acknowledgedAt),
      revision: Value(revision),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory Reminder.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Reminder(
      id: serializer.fromJson<String>(json['id']),
      taskId: serializer.fromJson<String>(json['taskId']),
      kind: serializer.fromJson<String>(json['kind']),
      snoozeCount: serializer.fromJson<int>(json['snoozeCount']),
      remindAt: serializer.fromJson<DateTime>(json['remindAt']),
      timezone: serializer.fromJson<String>(json['timezone']),
      alarmLevel: serializer.fromJson<String>(json['alarmLevel']),
      requiresAcknowledgement: serializer.fromJson<bool>(
        json['requiresAcknowledgement'],
      ),
      repeatRule: serializer.fromJson<String?>(json['repeatRule']),
      status: serializer.fromJson<String>(json['status']),
      snoozedUntil: serializer.fromJson<DateTime?>(json['snoozedUntil']),
      deliveredAt: serializer.fromJson<DateTime?>(json['deliveredAt']),
      acknowledgedAt: serializer.fromJson<DateTime?>(json['acknowledgedAt']),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'taskId': serializer.toJson<String>(taskId),
      'kind': serializer.toJson<String>(kind),
      'snoozeCount': serializer.toJson<int>(snoozeCount),
      'remindAt': serializer.toJson<DateTime>(remindAt),
      'timezone': serializer.toJson<String>(timezone),
      'alarmLevel': serializer.toJson<String>(alarmLevel),
      'requiresAcknowledgement': serializer.toJson<bool>(
        requiresAcknowledgement,
      ),
      'repeatRule': serializer.toJson<String?>(repeatRule),
      'status': serializer.toJson<String>(status),
      'snoozedUntil': serializer.toJson<DateTime?>(snoozedUntil),
      'deliveredAt': serializer.toJson<DateTime?>(deliveredAt),
      'acknowledgedAt': serializer.toJson<DateTime?>(acknowledgedAt),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  Reminder copyWith({
    String? id,
    String? taskId,
    String? kind,
    int? snoozeCount,
    DateTime? remindAt,
    String? timezone,
    String? alarmLevel,
    bool? requiresAcknowledgement,
    Value<String?> repeatRule = const Value.absent(),
    String? status,
    Value<DateTime?> snoozedUntil = const Value.absent(),
    Value<DateTime?> deliveredAt = const Value.absent(),
    Value<DateTime?> acknowledgedAt = const Value.absent(),
    int? revision,
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => Reminder(
    id: id ?? this.id,
    taskId: taskId ?? this.taskId,
    kind: kind ?? this.kind,
    snoozeCount: snoozeCount ?? this.snoozeCount,
    remindAt: remindAt ?? this.remindAt,
    timezone: timezone ?? this.timezone,
    alarmLevel: alarmLevel ?? this.alarmLevel,
    requiresAcknowledgement:
        requiresAcknowledgement ?? this.requiresAcknowledgement,
    repeatRule: repeatRule.present ? repeatRule.value : this.repeatRule,
    status: status ?? this.status,
    snoozedUntil: snoozedUntil.present ? snoozedUntil.value : this.snoozedUntil,
    deliveredAt: deliveredAt.present ? deliveredAt.value : this.deliveredAt,
    acknowledgedAt: acknowledgedAt.present
        ? acknowledgedAt.value
        : this.acknowledgedAt,
    revision: revision ?? this.revision,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  Reminder copyWithCompanion(RemindersCompanion data) {
    return Reminder(
      id: data.id.present ? data.id.value : this.id,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      kind: data.kind.present ? data.kind.value : this.kind,
      snoozeCount: data.snoozeCount.present
          ? data.snoozeCount.value
          : this.snoozeCount,
      remindAt: data.remindAt.present ? data.remindAt.value : this.remindAt,
      timezone: data.timezone.present ? data.timezone.value : this.timezone,
      alarmLevel: data.alarmLevel.present
          ? data.alarmLevel.value
          : this.alarmLevel,
      requiresAcknowledgement: data.requiresAcknowledgement.present
          ? data.requiresAcknowledgement.value
          : this.requiresAcknowledgement,
      repeatRule: data.repeatRule.present
          ? data.repeatRule.value
          : this.repeatRule,
      status: data.status.present ? data.status.value : this.status,
      snoozedUntil: data.snoozedUntil.present
          ? data.snoozedUntil.value
          : this.snoozedUntil,
      deliveredAt: data.deliveredAt.present
          ? data.deliveredAt.value
          : this.deliveredAt,
      acknowledgedAt: data.acknowledgedAt.present
          ? data.acknowledgedAt.value
          : this.acknowledgedAt,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Reminder(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('kind: $kind, ')
          ..write('snoozeCount: $snoozeCount, ')
          ..write('remindAt: $remindAt, ')
          ..write('timezone: $timezone, ')
          ..write('alarmLevel: $alarmLevel, ')
          ..write('requiresAcknowledgement: $requiresAcknowledgement, ')
          ..write('repeatRule: $repeatRule, ')
          ..write('status: $status, ')
          ..write('snoozedUntil: $snoozedUntil, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('acknowledgedAt: $acknowledgedAt, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    taskId,
    kind,
    snoozeCount,
    remindAt,
    timezone,
    alarmLevel,
    requiresAcknowledgement,
    repeatRule,
    status,
    snoozedUntil,
    deliveredAt,
    acknowledgedAt,
    revision,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Reminder &&
          other.id == this.id &&
          other.taskId == this.taskId &&
          other.kind == this.kind &&
          other.snoozeCount == this.snoozeCount &&
          other.remindAt == this.remindAt &&
          other.timezone == this.timezone &&
          other.alarmLevel == this.alarmLevel &&
          other.requiresAcknowledgement == this.requiresAcknowledgement &&
          other.repeatRule == this.repeatRule &&
          other.status == this.status &&
          other.snoozedUntil == this.snoozedUntil &&
          other.deliveredAt == this.deliveredAt &&
          other.acknowledgedAt == this.acknowledgedAt &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class RemindersCompanion extends UpdateCompanion<Reminder> {
  final Value<String> id;
  final Value<String> taskId;
  final Value<String> kind;
  final Value<int> snoozeCount;
  final Value<DateTime> remindAt;
  final Value<String> timezone;
  final Value<String> alarmLevel;
  final Value<bool> requiresAcknowledgement;
  final Value<String?> repeatRule;
  final Value<String> status;
  final Value<DateTime?> snoozedUntil;
  final Value<DateTime?> deliveredAt;
  final Value<DateTime?> acknowledgedAt;
  final Value<int> revision;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const RemindersCompanion({
    this.id = const Value.absent(),
    this.taskId = const Value.absent(),
    this.kind = const Value.absent(),
    this.snoozeCount = const Value.absent(),
    this.remindAt = const Value.absent(),
    this.timezone = const Value.absent(),
    this.alarmLevel = const Value.absent(),
    this.requiresAcknowledgement = const Value.absent(),
    this.repeatRule = const Value.absent(),
    this.status = const Value.absent(),
    this.snoozedUntil = const Value.absent(),
    this.deliveredAt = const Value.absent(),
    this.acknowledgedAt = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RemindersCompanion.insert({
    required String id,
    required String taskId,
    this.kind = const Value.absent(),
    this.snoozeCount = const Value.absent(),
    required DateTime remindAt,
    this.timezone = const Value.absent(),
    this.alarmLevel = const Value.absent(),
    this.requiresAcknowledgement = const Value.absent(),
    this.repeatRule = const Value.absent(),
    this.status = const Value.absent(),
    this.snoozedUntil = const Value.absent(),
    this.deliveredAt = const Value.absent(),
    this.acknowledgedAt = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       taskId = Value(taskId),
       remindAt = Value(remindAt);
  static Insertable<Reminder> custom({
    Expression<String>? id,
    Expression<String>? taskId,
    Expression<String>? kind,
    Expression<int>? snoozeCount,
    Expression<DateTime>? remindAt,
    Expression<String>? timezone,
    Expression<String>? alarmLevel,
    Expression<bool>? requiresAcknowledgement,
    Expression<String>? repeatRule,
    Expression<String>? status,
    Expression<DateTime>? snoozedUntil,
    Expression<DateTime>? deliveredAt,
    Expression<DateTime>? acknowledgedAt,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (taskId != null) 'task_id': taskId,
      if (kind != null) 'kind': kind,
      if (snoozeCount != null) 'snooze_count': snoozeCount,
      if (remindAt != null) 'remind_at': remindAt,
      if (timezone != null) 'timezone': timezone,
      if (alarmLevel != null) 'alarm_level': alarmLevel,
      if (requiresAcknowledgement != null)
        'requires_acknowledgement': requiresAcknowledgement,
      if (repeatRule != null) 'repeat_rule': repeatRule,
      if (status != null) 'status': status,
      if (snoozedUntil != null) 'snoozed_until': snoozedUntil,
      if (deliveredAt != null) 'delivered_at': deliveredAt,
      if (acknowledgedAt != null) 'acknowledged_at': acknowledgedAt,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RemindersCompanion copyWith({
    Value<String>? id,
    Value<String>? taskId,
    Value<String>? kind,
    Value<int>? snoozeCount,
    Value<DateTime>? remindAt,
    Value<String>? timezone,
    Value<String>? alarmLevel,
    Value<bool>? requiresAcknowledgement,
    Value<String?>? repeatRule,
    Value<String>? status,
    Value<DateTime?>? snoozedUntil,
    Value<DateTime?>? deliveredAt,
    Value<DateTime?>? acknowledgedAt,
    Value<int>? revision,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return RemindersCompanion(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      kind: kind ?? this.kind,
      snoozeCount: snoozeCount ?? this.snoozeCount,
      remindAt: remindAt ?? this.remindAt,
      timezone: timezone ?? this.timezone,
      alarmLevel: alarmLevel ?? this.alarmLevel,
      requiresAcknowledgement:
          requiresAcknowledgement ?? this.requiresAcknowledgement,
      repeatRule: repeatRule ?? this.repeatRule,
      status: status ?? this.status,
      snoozedUntil: snoozedUntil ?? this.snoozedUntil,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (snoozeCount.present) {
      map['snooze_count'] = Variable<int>(snoozeCount.value);
    }
    if (remindAt.present) {
      map['remind_at'] = Variable<DateTime>(remindAt.value);
    }
    if (timezone.present) {
      map['timezone'] = Variable<String>(timezone.value);
    }
    if (alarmLevel.present) {
      map['alarm_level'] = Variable<String>(alarmLevel.value);
    }
    if (requiresAcknowledgement.present) {
      map['requires_acknowledgement'] = Variable<bool>(
        requiresAcknowledgement.value,
      );
    }
    if (repeatRule.present) {
      map['repeat_rule'] = Variable<String>(repeatRule.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (snoozedUntil.present) {
      map['snoozed_until'] = Variable<DateTime>(snoozedUntil.value);
    }
    if (deliveredAt.present) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt.value);
    }
    if (acknowledgedAt.present) {
      map['acknowledged_at'] = Variable<DateTime>(acknowledgedAt.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RemindersCompanion(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('kind: $kind, ')
          ..write('snoozeCount: $snoozeCount, ')
          ..write('remindAt: $remindAt, ')
          ..write('timezone: $timezone, ')
          ..write('alarmLevel: $alarmLevel, ')
          ..write('requiresAcknowledgement: $requiresAcknowledgement, ')
          ..write('repeatRule: $repeatRule, ')
          ..write('status: $status, ')
          ..write('snoozedUntil: $snoozedUntil, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('acknowledgedAt: $acknowledgedAt, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExternalEventsTable extends ExternalEvents
    with TableInfo<$ExternalEventsTable, ExternalEventRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExternalEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startsAtMeta = const VerificationMeta(
    'startsAt',
  );
  @override
  late final GeneratedColumn<DateTime> startsAt = GeneratedColumn<DateTime>(
    'starts_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endsAtMeta = const VerificationMeta('endsAt');
  @override
  late final GeneratedColumn<DateTime> endsAt = GeneratedColumn<DateTime>(
    'ends_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isAllDayMeta = const VerificationMeta(
    'isAllDay',
  );
  @override
  late final GeneratedColumn<bool> isAllDay = GeneratedColumn<bool>(
    'is_all_day',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_all_day" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isBusyMeta = const VerificationMeta('isBusy');
  @override
  late final GeneratedColumn<bool> isBusy = GeneratedColumn<bool>(
    'is_busy',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_busy" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _htmlLinkMeta = const VerificationMeta(
    'htmlLink',
  );
  @override
  late final GeneratedColumn<String> htmlLink = GeneratedColumn<String>(
    'html_link',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _summaryFoldMeta = const VerificationMeta(
    'summaryFold',
  );
  @override
  late final GeneratedColumn<String> summaryFold = GeneratedColumn<String>(
    'summary_fold',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationFoldMeta = const VerificationMeta(
    'locationFold',
  );
  @override
  late final GeneratedColumn<String> locationFold = GeneratedColumn<String>(
    'location_fold',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    summary,
    location,
    startsAt,
    endsAt,
    isAllDay,
    isBusy,
    htmlLink,
    summaryFold,
    locationFold,
    revision,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'external_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExternalEventRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    }
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    }
    if (data.containsKey('starts_at')) {
      context.handle(
        _startsAtMeta,
        startsAt.isAcceptableOrUnknown(data['starts_at']!, _startsAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startsAtMeta);
    }
    if (data.containsKey('ends_at')) {
      context.handle(
        _endsAtMeta,
        endsAt.isAcceptableOrUnknown(data['ends_at']!, _endsAtMeta),
      );
    } else if (isInserting) {
      context.missing(_endsAtMeta);
    }
    if (data.containsKey('is_all_day')) {
      context.handle(
        _isAllDayMeta,
        isAllDay.isAcceptableOrUnknown(data['is_all_day']!, _isAllDayMeta),
      );
    }
    if (data.containsKey('is_busy')) {
      context.handle(
        _isBusyMeta,
        isBusy.isAcceptableOrUnknown(data['is_busy']!, _isBusyMeta),
      );
    }
    if (data.containsKey('html_link')) {
      context.handle(
        _htmlLinkMeta,
        htmlLink.isAcceptableOrUnknown(data['html_link']!, _htmlLinkMeta),
      );
    }
    if (data.containsKey('summary_fold')) {
      context.handle(
        _summaryFoldMeta,
        summaryFold.isAcceptableOrUnknown(
          data['summary_fold']!,
          _summaryFoldMeta,
        ),
      );
    }
    if (data.containsKey('location_fold')) {
      context.handle(
        _locationFoldMeta,
        locationFold.isAcceptableOrUnknown(
          data['location_fold']!,
          _locationFoldMeta,
        ),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExternalEventRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExternalEventRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      ),
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      ),
      startsAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}starts_at'],
      )!,
      endsAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ends_at'],
      )!,
      isAllDay: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_all_day'],
      )!,
      isBusy: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_busy'],
      )!,
      htmlLink: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}html_link'],
      ),
      summaryFold: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary_fold'],
      ),
      locationFold: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_fold'],
      ),
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
    );
  }

  @override
  $ExternalEventsTable createAlias(String alias) {
    return $ExternalEventsTable(attachedDatabase, alias);
  }
}

class ExternalEventRecord extends DataClass
    implements Insertable<ExternalEventRecord> {
  final String id;
  final String workspaceId;
  final String? summary;
  final String? location;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isAllDay;
  final bool isBusy;
  final String? htmlLink;
  final String? summaryFold;
  final String? locationFold;
  final int revision;
  const ExternalEventRecord({
    required this.id,
    required this.workspaceId,
    this.summary,
    this.location,
    required this.startsAt,
    required this.endsAt,
    required this.isAllDay,
    required this.isBusy,
    this.htmlLink,
    this.summaryFold,
    this.locationFold,
    required this.revision,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    if (!nullToAbsent || summary != null) {
      map['summary'] = Variable<String>(summary);
    }
    if (!nullToAbsent || location != null) {
      map['location'] = Variable<String>(location);
    }
    map['starts_at'] = Variable<DateTime>(startsAt);
    map['ends_at'] = Variable<DateTime>(endsAt);
    map['is_all_day'] = Variable<bool>(isAllDay);
    map['is_busy'] = Variable<bool>(isBusy);
    if (!nullToAbsent || htmlLink != null) {
      map['html_link'] = Variable<String>(htmlLink);
    }
    if (!nullToAbsent || summaryFold != null) {
      map['summary_fold'] = Variable<String>(summaryFold);
    }
    if (!nullToAbsent || locationFold != null) {
      map['location_fold'] = Variable<String>(locationFold);
    }
    map['revision'] = Variable<int>(revision);
    return map;
  }

  ExternalEventsCompanion toCompanion(bool nullToAbsent) {
    return ExternalEventsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      summary: summary == null && nullToAbsent
          ? const Value.absent()
          : Value(summary),
      location: location == null && nullToAbsent
          ? const Value.absent()
          : Value(location),
      startsAt: Value(startsAt),
      endsAt: Value(endsAt),
      isAllDay: Value(isAllDay),
      isBusy: Value(isBusy),
      htmlLink: htmlLink == null && nullToAbsent
          ? const Value.absent()
          : Value(htmlLink),
      summaryFold: summaryFold == null && nullToAbsent
          ? const Value.absent()
          : Value(summaryFold),
      locationFold: locationFold == null && nullToAbsent
          ? const Value.absent()
          : Value(locationFold),
      revision: Value(revision),
    );
  }

  factory ExternalEventRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExternalEventRecord(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      summary: serializer.fromJson<String?>(json['summary']),
      location: serializer.fromJson<String?>(json['location']),
      startsAt: serializer.fromJson<DateTime>(json['startsAt']),
      endsAt: serializer.fromJson<DateTime>(json['endsAt']),
      isAllDay: serializer.fromJson<bool>(json['isAllDay']),
      isBusy: serializer.fromJson<bool>(json['isBusy']),
      htmlLink: serializer.fromJson<String?>(json['htmlLink']),
      summaryFold: serializer.fromJson<String?>(json['summaryFold']),
      locationFold: serializer.fromJson<String?>(json['locationFold']),
      revision: serializer.fromJson<int>(json['revision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'summary': serializer.toJson<String?>(summary),
      'location': serializer.toJson<String?>(location),
      'startsAt': serializer.toJson<DateTime>(startsAt),
      'endsAt': serializer.toJson<DateTime>(endsAt),
      'isAllDay': serializer.toJson<bool>(isAllDay),
      'isBusy': serializer.toJson<bool>(isBusy),
      'htmlLink': serializer.toJson<String?>(htmlLink),
      'summaryFold': serializer.toJson<String?>(summaryFold),
      'locationFold': serializer.toJson<String?>(locationFold),
      'revision': serializer.toJson<int>(revision),
    };
  }

  ExternalEventRecord copyWith({
    String? id,
    String? workspaceId,
    Value<String?> summary = const Value.absent(),
    Value<String?> location = const Value.absent(),
    DateTime? startsAt,
    DateTime? endsAt,
    bool? isAllDay,
    bool? isBusy,
    Value<String?> htmlLink = const Value.absent(),
    Value<String?> summaryFold = const Value.absent(),
    Value<String?> locationFold = const Value.absent(),
    int? revision,
  }) => ExternalEventRecord(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    summary: summary.present ? summary.value : this.summary,
    location: location.present ? location.value : this.location,
    startsAt: startsAt ?? this.startsAt,
    endsAt: endsAt ?? this.endsAt,
    isAllDay: isAllDay ?? this.isAllDay,
    isBusy: isBusy ?? this.isBusy,
    htmlLink: htmlLink.present ? htmlLink.value : this.htmlLink,
    summaryFold: summaryFold.present ? summaryFold.value : this.summaryFold,
    locationFold: locationFold.present ? locationFold.value : this.locationFold,
    revision: revision ?? this.revision,
  );
  ExternalEventRecord copyWithCompanion(ExternalEventsCompanion data) {
    return ExternalEventRecord(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      summary: data.summary.present ? data.summary.value : this.summary,
      location: data.location.present ? data.location.value : this.location,
      startsAt: data.startsAt.present ? data.startsAt.value : this.startsAt,
      endsAt: data.endsAt.present ? data.endsAt.value : this.endsAt,
      isAllDay: data.isAllDay.present ? data.isAllDay.value : this.isAllDay,
      isBusy: data.isBusy.present ? data.isBusy.value : this.isBusy,
      htmlLink: data.htmlLink.present ? data.htmlLink.value : this.htmlLink,
      summaryFold: data.summaryFold.present
          ? data.summaryFold.value
          : this.summaryFold,
      locationFold: data.locationFold.present
          ? data.locationFold.value
          : this.locationFold,
      revision: data.revision.present ? data.revision.value : this.revision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExternalEventRecord(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('summary: $summary, ')
          ..write('location: $location, ')
          ..write('startsAt: $startsAt, ')
          ..write('endsAt: $endsAt, ')
          ..write('isAllDay: $isAllDay, ')
          ..write('isBusy: $isBusy, ')
          ..write('htmlLink: $htmlLink, ')
          ..write('summaryFold: $summaryFold, ')
          ..write('locationFold: $locationFold, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    summary,
    location,
    startsAt,
    endsAt,
    isAllDay,
    isBusy,
    htmlLink,
    summaryFold,
    locationFold,
    revision,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExternalEventRecord &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.summary == this.summary &&
          other.location == this.location &&
          other.startsAt == this.startsAt &&
          other.endsAt == this.endsAt &&
          other.isAllDay == this.isAllDay &&
          other.isBusy == this.isBusy &&
          other.htmlLink == this.htmlLink &&
          other.summaryFold == this.summaryFold &&
          other.locationFold == this.locationFold &&
          other.revision == this.revision);
}

class ExternalEventsCompanion extends UpdateCompanion<ExternalEventRecord> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String?> summary;
  final Value<String?> location;
  final Value<DateTime> startsAt;
  final Value<DateTime> endsAt;
  final Value<bool> isAllDay;
  final Value<bool> isBusy;
  final Value<String?> htmlLink;
  final Value<String?> summaryFold;
  final Value<String?> locationFold;
  final Value<int> revision;
  final Value<int> rowid;
  const ExternalEventsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.summary = const Value.absent(),
    this.location = const Value.absent(),
    this.startsAt = const Value.absent(),
    this.endsAt = const Value.absent(),
    this.isAllDay = const Value.absent(),
    this.isBusy = const Value.absent(),
    this.htmlLink = const Value.absent(),
    this.summaryFold = const Value.absent(),
    this.locationFold = const Value.absent(),
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExternalEventsCompanion.insert({
    required String id,
    required String workspaceId,
    this.summary = const Value.absent(),
    this.location = const Value.absent(),
    required DateTime startsAt,
    required DateTime endsAt,
    this.isAllDay = const Value.absent(),
    this.isBusy = const Value.absent(),
    this.htmlLink = const Value.absent(),
    this.summaryFold = const Value.absent(),
    this.locationFold = const Value.absent(),
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       startsAt = Value(startsAt),
       endsAt = Value(endsAt);
  static Insertable<ExternalEventRecord> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? summary,
    Expression<String>? location,
    Expression<DateTime>? startsAt,
    Expression<DateTime>? endsAt,
    Expression<bool>? isAllDay,
    Expression<bool>? isBusy,
    Expression<String>? htmlLink,
    Expression<String>? summaryFold,
    Expression<String>? locationFold,
    Expression<int>? revision,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (summary != null) 'summary': summary,
      if (location != null) 'location': location,
      if (startsAt != null) 'starts_at': startsAt,
      if (endsAt != null) 'ends_at': endsAt,
      if (isAllDay != null) 'is_all_day': isAllDay,
      if (isBusy != null) 'is_busy': isBusy,
      if (htmlLink != null) 'html_link': htmlLink,
      if (summaryFold != null) 'summary_fold': summaryFold,
      if (locationFold != null) 'location_fold': locationFold,
      if (revision != null) 'revision': revision,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExternalEventsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String?>? summary,
    Value<String?>? location,
    Value<DateTime>? startsAt,
    Value<DateTime>? endsAt,
    Value<bool>? isAllDay,
    Value<bool>? isBusy,
    Value<String?>? htmlLink,
    Value<String?>? summaryFold,
    Value<String?>? locationFold,
    Value<int>? revision,
    Value<int>? rowid,
  }) {
    return ExternalEventsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      summary: summary ?? this.summary,
      location: location ?? this.location,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      isAllDay: isAllDay ?? this.isAllDay,
      isBusy: isBusy ?? this.isBusy,
      htmlLink: htmlLink ?? this.htmlLink,
      summaryFold: summaryFold ?? this.summaryFold,
      locationFold: locationFold ?? this.locationFold,
      revision: revision ?? this.revision,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (startsAt.present) {
      map['starts_at'] = Variable<DateTime>(startsAt.value);
    }
    if (endsAt.present) {
      map['ends_at'] = Variable<DateTime>(endsAt.value);
    }
    if (isAllDay.present) {
      map['is_all_day'] = Variable<bool>(isAllDay.value);
    }
    if (isBusy.present) {
      map['is_busy'] = Variable<bool>(isBusy.value);
    }
    if (htmlLink.present) {
      map['html_link'] = Variable<String>(htmlLink.value);
    }
    if (summaryFold.present) {
      map['summary_fold'] = Variable<String>(summaryFold.value);
    }
    if (locationFold.present) {
      map['location_fold'] = Variable<String>(locationFold.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExternalEventsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('summary: $summary, ')
          ..write('location: $location, ')
          ..write('startsAt: $startsAt, ')
          ..write('endsAt: $endsAt, ')
          ..write('isAllDay: $isAllDay, ')
          ..write('isBusy: $isBusy, ')
          ..write('htmlLink: $htmlLink, ')
          ..write('summaryFold: $summaryFold, ')
          ..write('locationFold: $locationFold, ')
          ..write('revision: $revision, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppleEventLinksTable extends AppleEventLinks
    with TableInfo<$AppleEventLinksTable, AppleEventLinkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppleEventLinksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _calendarIdMeta = const VerificationMeta(
    'calendarId',
  );
  @override
  late final GeneratedColumn<String> calendarId = GeneratedColumn<String>(
    'calendar_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _signatureMeta = const VerificationMeta(
    'signature',
  );
  @override
  late final GeneratedColumn<String> signature = GeneratedColumn<String>(
    'signature',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    taskId,
    calendarId,
    eventId,
    signature,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'apple_event_links';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppleEventLinkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('calendar_id')) {
      context.handle(
        _calendarIdMeta,
        calendarId.isAcceptableOrUnknown(data['calendar_id']!, _calendarIdMeta),
      );
    } else if (isInserting) {
      context.missing(_calendarIdMeta);
    }
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('signature')) {
      context.handle(
        _signatureMeta,
        signature.isAcceptableOrUnknown(data['signature']!, _signatureMeta),
      );
    } else if (isInserting) {
      context.missing(_signatureMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {taskId};
  @override
  AppleEventLinkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppleEventLinkRow(
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      calendarId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}calendar_id'],
      )!,
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      signature: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}signature'],
      )!,
    );
  }

  @override
  $AppleEventLinksTable createAlias(String alias) {
    return $AppleEventLinksTable(attachedDatabase, alias);
  }
}

class AppleEventLinkRow extends DataClass
    implements Insertable<AppleEventLinkRow> {
  final String taskId;
  final String calendarId;
  final String eventId;
  final String signature;
  const AppleEventLinkRow({
    required this.taskId,
    required this.calendarId,
    required this.eventId,
    required this.signature,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['task_id'] = Variable<String>(taskId);
    map['calendar_id'] = Variable<String>(calendarId);
    map['event_id'] = Variable<String>(eventId);
    map['signature'] = Variable<String>(signature);
    return map;
  }

  AppleEventLinksCompanion toCompanion(bool nullToAbsent) {
    return AppleEventLinksCompanion(
      taskId: Value(taskId),
      calendarId: Value(calendarId),
      eventId: Value(eventId),
      signature: Value(signature),
    );
  }

  factory AppleEventLinkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppleEventLinkRow(
      taskId: serializer.fromJson<String>(json['taskId']),
      calendarId: serializer.fromJson<String>(json['calendarId']),
      eventId: serializer.fromJson<String>(json['eventId']),
      signature: serializer.fromJson<String>(json['signature']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'taskId': serializer.toJson<String>(taskId),
      'calendarId': serializer.toJson<String>(calendarId),
      'eventId': serializer.toJson<String>(eventId),
      'signature': serializer.toJson<String>(signature),
    };
  }

  AppleEventLinkRow copyWith({
    String? taskId,
    String? calendarId,
    String? eventId,
    String? signature,
  }) => AppleEventLinkRow(
    taskId: taskId ?? this.taskId,
    calendarId: calendarId ?? this.calendarId,
    eventId: eventId ?? this.eventId,
    signature: signature ?? this.signature,
  );
  AppleEventLinkRow copyWithCompanion(AppleEventLinksCompanion data) {
    return AppleEventLinkRow(
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      calendarId: data.calendarId.present
          ? data.calendarId.value
          : this.calendarId,
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      signature: data.signature.present ? data.signature.value : this.signature,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppleEventLinkRow(')
          ..write('taskId: $taskId, ')
          ..write('calendarId: $calendarId, ')
          ..write('eventId: $eventId, ')
          ..write('signature: $signature')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(taskId, calendarId, eventId, signature);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppleEventLinkRow &&
          other.taskId == this.taskId &&
          other.calendarId == this.calendarId &&
          other.eventId == this.eventId &&
          other.signature == this.signature);
}

class AppleEventLinksCompanion extends UpdateCompanion<AppleEventLinkRow> {
  final Value<String> taskId;
  final Value<String> calendarId;
  final Value<String> eventId;
  final Value<String> signature;
  final Value<int> rowid;
  const AppleEventLinksCompanion({
    this.taskId = const Value.absent(),
    this.calendarId = const Value.absent(),
    this.eventId = const Value.absent(),
    this.signature = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppleEventLinksCompanion.insert({
    required String taskId,
    required String calendarId,
    required String eventId,
    required String signature,
    this.rowid = const Value.absent(),
  }) : taskId = Value(taskId),
       calendarId = Value(calendarId),
       eventId = Value(eventId),
       signature = Value(signature);
  static Insertable<AppleEventLinkRow> custom({
    Expression<String>? taskId,
    Expression<String>? calendarId,
    Expression<String>? eventId,
    Expression<String>? signature,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (taskId != null) 'task_id': taskId,
      if (calendarId != null) 'calendar_id': calendarId,
      if (eventId != null) 'event_id': eventId,
      if (signature != null) 'signature': signature,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppleEventLinksCompanion copyWith({
    Value<String>? taskId,
    Value<String>? calendarId,
    Value<String>? eventId,
    Value<String>? signature,
    Value<int>? rowid,
  }) {
    return AppleEventLinksCompanion(
      taskId: taskId ?? this.taskId,
      calendarId: calendarId ?? this.calendarId,
      eventId: eventId ?? this.eventId,
      signature: signature ?? this.signature,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (calendarId.present) {
      map['calendar_id'] = Variable<String>(calendarId.value);
    }
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (signature.present) {
      map['signature'] = Variable<String>(signature.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppleEventLinksCompanion(')
          ..write('taskId: $taskId, ')
          ..write('calendarId: $calendarId, ')
          ..write('eventId: $eventId, ')
          ..write('signature: $signature, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FileRowsTable extends FileRows
    with TableInfo<$FileRowsTable, FileRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FileRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetTypeMeta = const VerificationMeta(
    'targetType',
  );
  @override
  late final GeneratedColumn<String> targetType = GeneratedColumn<String>(
    'target_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeMeta = const VerificationMeta('mime');
  @override
  late final GeneratedColumn<String> mime = GeneratedColumn<String>(
    'mime',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uploadedByMeta = const VerificationMeta(
    'uploadedBy',
  );
  @override
  late final GeneratedColumn<String> uploadedBy = GeneratedColumn<String>(
    'uploaded_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<String> folderId = GeneratedColumn<String>(
    'folder_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    targetType,
    targetId,
    name,
    mime,
    sizeBytes,
    status,
    uploadedBy,
    folderId,
    revision,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'file_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<FileRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('target_type')) {
      context.handle(
        _targetTypeMeta,
        targetType.isAcceptableOrUnknown(data['target_type']!, _targetTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_targetTypeMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_targetIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('mime')) {
      context.handle(
        _mimeMeta,
        mime.isAcceptableOrUnknown(data['mime']!, _mimeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('uploaded_by')) {
      context.handle(
        _uploadedByMeta,
        uploadedBy.isAcceptableOrUnknown(data['uploaded_by']!, _uploadedByMeta),
      );
    }
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FileRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FileRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      targetType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_type'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      mime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      uploadedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uploaded_by'],
      ),
      folderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder_id'],
      ),
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $FileRowsTable createAlias(String alias) {
    return $FileRowsTable(attachedDatabase, alias);
  }
}

class FileRecord extends DataClass implements Insertable<FileRecord> {
  final String id;
  final String workspaceId;

  /// `project` | `task` | `note` — who this file hangs off.
  final String targetType;
  final String targetId;
  final String name;
  final String mime;
  final int sizeBytes;

  /// Always `ready` in practice (uploading rows never sync) — kept so the
  /// shape mirrors the server serializer field-for-field.
  final String status;
  final String? uploadedBy;

  /// Folder membership — workspace-target files only (v7, ADR-0014).
  final String? folderId;
  final int revision;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const FileRecord({
    required this.id,
    required this.workspaceId,
    required this.targetType,
    required this.targetId,
    required this.name,
    required this.mime,
    required this.sizeBytes,
    required this.status,
    this.uploadedBy,
    this.folderId,
    required this.revision,
    this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['target_type'] = Variable<String>(targetType);
    map['target_id'] = Variable<String>(targetId);
    map['name'] = Variable<String>(name);
    map['mime'] = Variable<String>(mime);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || uploadedBy != null) {
      map['uploaded_by'] = Variable<String>(uploadedBy);
    }
    if (!nullToAbsent || folderId != null) {
      map['folder_id'] = Variable<String>(folderId);
    }
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  FileRowsCompanion toCompanion(bool nullToAbsent) {
    return FileRowsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      targetType: Value(targetType),
      targetId: Value(targetId),
      name: Value(name),
      mime: Value(mime),
      sizeBytes: Value(sizeBytes),
      status: Value(status),
      uploadedBy: uploadedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(uploadedBy),
      folderId: folderId == null && nullToAbsent
          ? const Value.absent()
          : Value(folderId),
      revision: Value(revision),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory FileRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FileRecord(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      targetType: serializer.fromJson<String>(json['targetType']),
      targetId: serializer.fromJson<String>(json['targetId']),
      name: serializer.fromJson<String>(json['name']),
      mime: serializer.fromJson<String>(json['mime']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      status: serializer.fromJson<String>(json['status']),
      uploadedBy: serializer.fromJson<String?>(json['uploadedBy']),
      folderId: serializer.fromJson<String?>(json['folderId']),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'targetType': serializer.toJson<String>(targetType),
      'targetId': serializer.toJson<String>(targetId),
      'name': serializer.toJson<String>(name),
      'mime': serializer.toJson<String>(mime),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'status': serializer.toJson<String>(status),
      'uploadedBy': serializer.toJson<String?>(uploadedBy),
      'folderId': serializer.toJson<String?>(folderId),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  FileRecord copyWith({
    String? id,
    String? workspaceId,
    String? targetType,
    String? targetId,
    String? name,
    String? mime,
    int? sizeBytes,
    String? status,
    Value<String?> uploadedBy = const Value.absent(),
    Value<String?> folderId = const Value.absent(),
    int? revision,
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => FileRecord(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    targetType: targetType ?? this.targetType,
    targetId: targetId ?? this.targetId,
    name: name ?? this.name,
    mime: mime ?? this.mime,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    status: status ?? this.status,
    uploadedBy: uploadedBy.present ? uploadedBy.value : this.uploadedBy,
    folderId: folderId.present ? folderId.value : this.folderId,
    revision: revision ?? this.revision,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  FileRecord copyWithCompanion(FileRowsCompanion data) {
    return FileRecord(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      targetType: data.targetType.present
          ? data.targetType.value
          : this.targetType,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      name: data.name.present ? data.name.value : this.name,
      mime: data.mime.present ? data.mime.value : this.mime,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      status: data.status.present ? data.status.value : this.status,
      uploadedBy: data.uploadedBy.present
          ? data.uploadedBy.value
          : this.uploadedBy,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FileRecord(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('targetType: $targetType, ')
          ..write('targetId: $targetId, ')
          ..write('name: $name, ')
          ..write('mime: $mime, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('status: $status, ')
          ..write('uploadedBy: $uploadedBy, ')
          ..write('folderId: $folderId, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    targetType,
    targetId,
    name,
    mime,
    sizeBytes,
    status,
    uploadedBy,
    folderId,
    revision,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FileRecord &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.targetType == this.targetType &&
          other.targetId == this.targetId &&
          other.name == this.name &&
          other.mime == this.mime &&
          other.sizeBytes == this.sizeBytes &&
          other.status == this.status &&
          other.uploadedBy == this.uploadedBy &&
          other.folderId == this.folderId &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class FileRowsCompanion extends UpdateCompanion<FileRecord> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> targetType;
  final Value<String> targetId;
  final Value<String> name;
  final Value<String> mime;
  final Value<int> sizeBytes;
  final Value<String> status;
  final Value<String?> uploadedBy;
  final Value<String?> folderId;
  final Value<int> revision;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const FileRowsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.targetType = const Value.absent(),
    this.targetId = const Value.absent(),
    this.name = const Value.absent(),
    this.mime = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.status = const Value.absent(),
    this.uploadedBy = const Value.absent(),
    this.folderId = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FileRowsCompanion.insert({
    required String id,
    required String workspaceId,
    required String targetType,
    required String targetId,
    required String name,
    required String mime,
    required int sizeBytes,
    required String status,
    this.uploadedBy = const Value.absent(),
    this.folderId = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       targetType = Value(targetType),
       targetId = Value(targetId),
       name = Value(name),
       mime = Value(mime),
       sizeBytes = Value(sizeBytes),
       status = Value(status);
  static Insertable<FileRecord> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? targetType,
    Expression<String>? targetId,
    Expression<String>? name,
    Expression<String>? mime,
    Expression<int>? sizeBytes,
    Expression<String>? status,
    Expression<String>? uploadedBy,
    Expression<String>? folderId,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (targetType != null) 'target_type': targetType,
      if (targetId != null) 'target_id': targetId,
      if (name != null) 'name': name,
      if (mime != null) 'mime': mime,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (status != null) 'status': status,
      if (uploadedBy != null) 'uploaded_by': uploadedBy,
      if (folderId != null) 'folder_id': folderId,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FileRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? targetType,
    Value<String>? targetId,
    Value<String>? name,
    Value<String>? mime,
    Value<int>? sizeBytes,
    Value<String>? status,
    Value<String?>? uploadedBy,
    Value<String?>? folderId,
    Value<int>? revision,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return FileRowsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      targetType: targetType ?? this.targetType,
      targetId: targetId ?? this.targetId,
      name: name ?? this.name,
      mime: mime ?? this.mime,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      status: status ?? this.status,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      folderId: folderId ?? this.folderId,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (targetType.present) {
      map['target_type'] = Variable<String>(targetType.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (mime.present) {
      map['mime'] = Variable<String>(mime.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (uploadedBy.present) {
      map['uploaded_by'] = Variable<String>(uploadedBy.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<String>(folderId.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FileRowsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('targetType: $targetType, ')
          ..write('targetId: $targetId, ')
          ..write('name: $name, ')
          ..write('mime: $mime, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('status: $status, ')
          ..write('uploadedBy: $uploadedBy, ')
          ..write('folderId: $folderId, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FoldersTable extends Folders
    with TableInfo<$FoldersTable, FolderRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoldersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    parentId,
    name,
    revision,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'folders';
  @override
  VerificationContext validateIntegrity(
    Insertable<FolderRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FolderRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FolderRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $FoldersTable createAlias(String alias) {
    return $FoldersTable(attachedDatabase, alias);
  }
}

class FolderRecord extends DataClass implements Insertable<FolderRecord> {
  final String id;
  final String workspaceId;
  final String? parentId;
  final String name;
  final int revision;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const FolderRecord({
    required this.id,
    required this.workspaceId,
    this.parentId,
    required this.name,
    required this.revision,
    this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['name'] = Variable<String>(name);
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  FoldersCompanion toCompanion(bool nullToAbsent) {
    return FoldersCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      name: Value(name),
      revision: Value(revision),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory FolderRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FolderRecord(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      name: serializer.fromJson<String>(json['name']),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'parentId': serializer.toJson<String?>(parentId),
      'name': serializer.toJson<String>(name),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  FolderRecord copyWith({
    String? id,
    String? workspaceId,
    Value<String?> parentId = const Value.absent(),
    String? name,
    int? revision,
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => FolderRecord(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    parentId: parentId.present ? parentId.value : this.parentId,
    name: name ?? this.name,
    revision: revision ?? this.revision,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  FolderRecord copyWithCompanion(FoldersCompanion data) {
    return FolderRecord(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      name: data.name.present ? data.name.value : this.name,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FolderRecord(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    parentId,
    name,
    revision,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FolderRecord &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.parentId == this.parentId &&
          other.name == this.name &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class FoldersCompanion extends UpdateCompanion<FolderRecord> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String?> parentId;
  final Value<String> name;
  final Value<int> revision;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const FoldersCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.parentId = const Value.absent(),
    this.name = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FoldersCompanion.insert({
    required String id,
    required String workspaceId,
    this.parentId = const Value.absent(),
    required String name,
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       name = Value(name);
  static Insertable<FolderRecord> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? parentId,
    Expression<String>? name,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (parentId != null) 'parent_id': parentId,
      if (name != null) 'name': name,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FoldersCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String?>? parentId,
    Value<String>? name,
    Value<int>? revision,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return FoldersCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      parentId: parentId ?? this.parentId,
      name: name ?? this.name,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoldersCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $QuickLinksTable extends QuickLinks
    with TableInfo<$QuickLinksTable, QuickLinkRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QuickLinksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _emojiMeta = const VerificationMeta('emoji');
  @override
  late final GeneratedColumn<String> emoji = GeneratedColumn<String>(
    'emoji',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorRgbMeta = const VerificationMeta(
    'colorRgb',
  );
  @override
  late final GeneratedColumn<String> colorRgb = GeneratedColumn<String>(
    'color_rgb',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    userId,
    kind,
    targetId,
    url,
    title,
    emoji,
    colorRgb,
    sortOrder,
    revision,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'quick_links';
  @override
  VerificationContext validateIntegrity(
    Insertable<QuickLinkRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('emoji')) {
      context.handle(
        _emojiMeta,
        emoji.isAcceptableOrUnknown(data['emoji']!, _emojiMeta),
      );
    }
    if (data.containsKey('color_rgb')) {
      context.handle(
        _colorRgbMeta,
        colorRgb.isAcceptableOrUnknown(data['color_rgb']!, _colorRgbMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  QuickLinkRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QuickLinkRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_id'],
      ),
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      emoji: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}emoji'],
      ),
      colorRgb: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_rgb'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $QuickLinksTable createAlias(String alias) {
    return $QuickLinksTable(attachedDatabase, alias);
  }
}

class QuickLinkRecord extends DataClass implements Insertable<QuickLinkRecord> {
  final String id;
  final String workspaceId;
  final String userId;

  /// `project | task | note | folder | file | url`.
  final String kind;

  /// The entity this points at — null for `url` rows. Stored as an id, never
  /// as a route string (ADR-0016: routes are a client concern).
  final String? targetId;
  final String? url;
  final String title;
  final String? emoji;
  final String? colorRgb;
  final int sortOrder;
  final int revision;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const QuickLinkRecord({
    required this.id,
    required this.workspaceId,
    required this.userId,
    required this.kind,
    this.targetId,
    this.url,
    required this.title,
    this.emoji,
    this.colorRgb,
    required this.sortOrder,
    required this.revision,
    this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['user_id'] = Variable<String>(userId);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || targetId != null) {
      map['target_id'] = Variable<String>(targetId);
    }
    if (!nullToAbsent || url != null) {
      map['url'] = Variable<String>(url);
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || emoji != null) {
      map['emoji'] = Variable<String>(emoji);
    }
    if (!nullToAbsent || colorRgb != null) {
      map['color_rgb'] = Variable<String>(colorRgb);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  QuickLinksCompanion toCompanion(bool nullToAbsent) {
    return QuickLinksCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      userId: Value(userId),
      kind: Value(kind),
      targetId: targetId == null && nullToAbsent
          ? const Value.absent()
          : Value(targetId),
      url: url == null && nullToAbsent ? const Value.absent() : Value(url),
      title: Value(title),
      emoji: emoji == null && nullToAbsent
          ? const Value.absent()
          : Value(emoji),
      colorRgb: colorRgb == null && nullToAbsent
          ? const Value.absent()
          : Value(colorRgb),
      sortOrder: Value(sortOrder),
      revision: Value(revision),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory QuickLinkRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QuickLinkRecord(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      userId: serializer.fromJson<String>(json['userId']),
      kind: serializer.fromJson<String>(json['kind']),
      targetId: serializer.fromJson<String?>(json['targetId']),
      url: serializer.fromJson<String?>(json['url']),
      title: serializer.fromJson<String>(json['title']),
      emoji: serializer.fromJson<String?>(json['emoji']),
      colorRgb: serializer.fromJson<String?>(json['colorRgb']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'userId': serializer.toJson<String>(userId),
      'kind': serializer.toJson<String>(kind),
      'targetId': serializer.toJson<String?>(targetId),
      'url': serializer.toJson<String?>(url),
      'title': serializer.toJson<String>(title),
      'emoji': serializer.toJson<String?>(emoji),
      'colorRgb': serializer.toJson<String?>(colorRgb),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  QuickLinkRecord copyWith({
    String? id,
    String? workspaceId,
    String? userId,
    String? kind,
    Value<String?> targetId = const Value.absent(),
    Value<String?> url = const Value.absent(),
    String? title,
    Value<String?> emoji = const Value.absent(),
    Value<String?> colorRgb = const Value.absent(),
    int? sortOrder,
    int? revision,
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => QuickLinkRecord(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    userId: userId ?? this.userId,
    kind: kind ?? this.kind,
    targetId: targetId.present ? targetId.value : this.targetId,
    url: url.present ? url.value : this.url,
    title: title ?? this.title,
    emoji: emoji.present ? emoji.value : this.emoji,
    colorRgb: colorRgb.present ? colorRgb.value : this.colorRgb,
    sortOrder: sortOrder ?? this.sortOrder,
    revision: revision ?? this.revision,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  QuickLinkRecord copyWithCompanion(QuickLinksCompanion data) {
    return QuickLinkRecord(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      userId: data.userId.present ? data.userId.value : this.userId,
      kind: data.kind.present ? data.kind.value : this.kind,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      url: data.url.present ? data.url.value : this.url,
      title: data.title.present ? data.title.value : this.title,
      emoji: data.emoji.present ? data.emoji.value : this.emoji,
      colorRgb: data.colorRgb.present ? data.colorRgb.value : this.colorRgb,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QuickLinkRecord(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('userId: $userId, ')
          ..write('kind: $kind, ')
          ..write('targetId: $targetId, ')
          ..write('url: $url, ')
          ..write('title: $title, ')
          ..write('emoji: $emoji, ')
          ..write('colorRgb: $colorRgb, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    userId,
    kind,
    targetId,
    url,
    title,
    emoji,
    colorRgb,
    sortOrder,
    revision,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QuickLinkRecord &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.userId == this.userId &&
          other.kind == this.kind &&
          other.targetId == this.targetId &&
          other.url == this.url &&
          other.title == this.title &&
          other.emoji == this.emoji &&
          other.colorRgb == this.colorRgb &&
          other.sortOrder == this.sortOrder &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class QuickLinksCompanion extends UpdateCompanion<QuickLinkRecord> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> userId;
  final Value<String> kind;
  final Value<String?> targetId;
  final Value<String?> url;
  final Value<String> title;
  final Value<String?> emoji;
  final Value<String?> colorRgb;
  final Value<int> sortOrder;
  final Value<int> revision;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const QuickLinksCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.userId = const Value.absent(),
    this.kind = const Value.absent(),
    this.targetId = const Value.absent(),
    this.url = const Value.absent(),
    this.title = const Value.absent(),
    this.emoji = const Value.absent(),
    this.colorRgb = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  QuickLinksCompanion.insert({
    required String id,
    required String workspaceId,
    required String userId,
    required String kind,
    this.targetId = const Value.absent(),
    this.url = const Value.absent(),
    required String title,
    this.emoji = const Value.absent(),
    this.colorRgb = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       userId = Value(userId),
       kind = Value(kind),
       title = Value(title);
  static Insertable<QuickLinkRecord> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? userId,
    Expression<String>? kind,
    Expression<String>? targetId,
    Expression<String>? url,
    Expression<String>? title,
    Expression<String>? emoji,
    Expression<String>? colorRgb,
    Expression<int>? sortOrder,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (userId != null) 'user_id': userId,
      if (kind != null) 'kind': kind,
      if (targetId != null) 'target_id': targetId,
      if (url != null) 'url': url,
      if (title != null) 'title': title,
      if (emoji != null) 'emoji': emoji,
      if (colorRgb != null) 'color_rgb': colorRgb,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  QuickLinksCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? userId,
    Value<String>? kind,
    Value<String?>? targetId,
    Value<String?>? url,
    Value<String>? title,
    Value<String?>? emoji,
    Value<String?>? colorRgb,
    Value<int>? sortOrder,
    Value<int>? revision,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return QuickLinksCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      userId: userId ?? this.userId,
      kind: kind ?? this.kind,
      targetId: targetId ?? this.targetId,
      url: url ?? this.url,
      title: title ?? this.title,
      emoji: emoji ?? this.emoji,
      colorRgb: colorRgb ?? this.colorRgb,
      sortOrder: sortOrder ?? this.sortOrder,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (emoji.present) {
      map['emoji'] = Variable<String>(emoji.value);
    }
    if (colorRgb.present) {
      map['color_rgb'] = Variable<String>(colorRgb.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QuickLinksCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('userId: $userId, ')
          ..write('kind: $kind, ')
          ..write('targetId: $targetId, ')
          ..write('url: $url, ')
          ..write('title: $title, ')
          ..write('emoji: $emoji, ')
          ..write('colorRgb: $colorRgb, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TaskSeriesTable extends TaskSeries
    with TableInfo<$TaskSeriesTable, TaskSeriesRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskSeriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ruleJsonMeta = const VerificationMeta(
    'ruleJson',
  );
  @override
  late final GeneratedColumn<String> ruleJson = GeneratedColumn<String>(
    'rule_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _templateJsonMeta = const VerificationMeta(
    'templateJson',
  );
  @override
  late final GeneratedColumn<String> templateJson = GeneratedColumn<String>(
    'template_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timezoneMeta = const VerificationMeta(
    'timezone',
  );
  @override
  late final GeneratedColumn<String> timezone = GeneratedColumn<String>(
    'timezone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Europe/Istanbul'),
  );
  static const VerificationMeta _anchorAtMeta = const VerificationMeta(
    'anchorAt',
  );
  @override
  late final GeneratedColumn<DateTime> anchorAt = GeneratedColumn<DateTime>(
    'anchor_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    ruleJson,
    templateJson,
    timezone,
    anchorAt,
    revision,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_series';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskSeriesRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('rule_json')) {
      context.handle(
        _ruleJsonMeta,
        ruleJson.isAcceptableOrUnknown(data['rule_json']!, _ruleJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_ruleJsonMeta);
    }
    if (data.containsKey('template_json')) {
      context.handle(
        _templateJsonMeta,
        templateJson.isAcceptableOrUnknown(
          data['template_json']!,
          _templateJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_templateJsonMeta);
    }
    if (data.containsKey('timezone')) {
      context.handle(
        _timezoneMeta,
        timezone.isAcceptableOrUnknown(data['timezone']!, _timezoneMeta),
      );
    }
    if (data.containsKey('anchor_at')) {
      context.handle(
        _anchorAtMeta,
        anchorAt.isAcceptableOrUnknown(data['anchor_at']!, _anchorAtMeta),
      );
    } else if (isInserting) {
      context.missing(_anchorAtMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskSeriesRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskSeriesRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      ruleJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rule_json'],
      )!,
      templateJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}template_json'],
      )!,
      timezone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timezone'],
      )!,
      anchorAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}anchor_at'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $TaskSeriesTable createAlias(String alias) {
    return $TaskSeriesTable(attachedDatabase, alias);
  }
}

class TaskSeriesRecord extends DataClass
    implements Insertable<TaskSeriesRecord> {
  final String id;
  final String workspaceId;

  /// The ADR-0020 rule object, stored as JSON text (drift has no JSON column
  /// and the rule is read and written whole — never field by field).
  final String ruleJson;

  /// Task fields every occurrence inherits (title, project, priority…), JSON.
  final String templateJson;
  final String timezone;

  /// Seed instant: the pattern's first candidate day and the time of day every
  /// occurrence inherits.
  final DateTime anchorAt;
  final int revision;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const TaskSeriesRecord({
    required this.id,
    required this.workspaceId,
    required this.ruleJson,
    required this.templateJson,
    required this.timezone,
    required this.anchorAt,
    required this.revision,
    this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['rule_json'] = Variable<String>(ruleJson);
    map['template_json'] = Variable<String>(templateJson);
    map['timezone'] = Variable<String>(timezone);
    map['anchor_at'] = Variable<DateTime>(anchorAt);
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  TaskSeriesCompanion toCompanion(bool nullToAbsent) {
    return TaskSeriesCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      ruleJson: Value(ruleJson),
      templateJson: Value(templateJson),
      timezone: Value(timezone),
      anchorAt: Value(anchorAt),
      revision: Value(revision),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory TaskSeriesRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskSeriesRecord(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      ruleJson: serializer.fromJson<String>(json['ruleJson']),
      templateJson: serializer.fromJson<String>(json['templateJson']),
      timezone: serializer.fromJson<String>(json['timezone']),
      anchorAt: serializer.fromJson<DateTime>(json['anchorAt']),
      revision: serializer.fromJson<int>(json['revision']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'ruleJson': serializer.toJson<String>(ruleJson),
      'templateJson': serializer.toJson<String>(templateJson),
      'timezone': serializer.toJson<String>(timezone),
      'anchorAt': serializer.toJson<DateTime>(anchorAt),
      'revision': serializer.toJson<int>(revision),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  TaskSeriesRecord copyWith({
    String? id,
    String? workspaceId,
    String? ruleJson,
    String? templateJson,
    String? timezone,
    DateTime? anchorAt,
    int? revision,
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => TaskSeriesRecord(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    ruleJson: ruleJson ?? this.ruleJson,
    templateJson: templateJson ?? this.templateJson,
    timezone: timezone ?? this.timezone,
    anchorAt: anchorAt ?? this.anchorAt,
    revision: revision ?? this.revision,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  TaskSeriesRecord copyWithCompanion(TaskSeriesCompanion data) {
    return TaskSeriesRecord(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      ruleJson: data.ruleJson.present ? data.ruleJson.value : this.ruleJson,
      templateJson: data.templateJson.present
          ? data.templateJson.value
          : this.templateJson,
      timezone: data.timezone.present ? data.timezone.value : this.timezone,
      anchorAt: data.anchorAt.present ? data.anchorAt.value : this.anchorAt,
      revision: data.revision.present ? data.revision.value : this.revision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskSeriesRecord(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('ruleJson: $ruleJson, ')
          ..write('templateJson: $templateJson, ')
          ..write('timezone: $timezone, ')
          ..write('anchorAt: $anchorAt, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    ruleJson,
    templateJson,
    timezone,
    anchorAt,
    revision,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskSeriesRecord &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.ruleJson == this.ruleJson &&
          other.templateJson == this.templateJson &&
          other.timezone == this.timezone &&
          other.anchorAt == this.anchorAt &&
          other.revision == this.revision &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TaskSeriesCompanion extends UpdateCompanion<TaskSeriesRecord> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> ruleJson;
  final Value<String> templateJson;
  final Value<String> timezone;
  final Value<DateTime> anchorAt;
  final Value<int> revision;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const TaskSeriesCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.ruleJson = const Value.absent(),
    this.templateJson = const Value.absent(),
    this.timezone = const Value.absent(),
    this.anchorAt = const Value.absent(),
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskSeriesCompanion.insert({
    required String id,
    required String workspaceId,
    required String ruleJson,
    required String templateJson,
    this.timezone = const Value.absent(),
    required DateTime anchorAt,
    this.revision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       ruleJson = Value(ruleJson),
       templateJson = Value(templateJson),
       anchorAt = Value(anchorAt);
  static Insertable<TaskSeriesRecord> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? ruleJson,
    Expression<String>? templateJson,
    Expression<String>? timezone,
    Expression<DateTime>? anchorAt,
    Expression<int>? revision,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (ruleJson != null) 'rule_json': ruleJson,
      if (templateJson != null) 'template_json': templateJson,
      if (timezone != null) 'timezone': timezone,
      if (anchorAt != null) 'anchor_at': anchorAt,
      if (revision != null) 'revision': revision,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskSeriesCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? ruleJson,
    Value<String>? templateJson,
    Value<String>? timezone,
    Value<DateTime>? anchorAt,
    Value<int>? revision,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return TaskSeriesCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      ruleJson: ruleJson ?? this.ruleJson,
      templateJson: templateJson ?? this.templateJson,
      timezone: timezone ?? this.timezone,
      anchorAt: anchorAt ?? this.anchorAt,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (ruleJson.present) {
      map['rule_json'] = Variable<String>(ruleJson.value);
    }
    if (templateJson.present) {
      map['template_json'] = Variable<String>(templateJson.value);
    }
    if (timezone.present) {
      map['timezone'] = Variable<String>(timezone.value);
    }
    if (anchorAt.present) {
      map['anchor_at'] = Variable<DateTime>(anchorAt.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskSeriesCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('ruleJson: $ruleJson, ')
          ..write('templateJson: $templateJson, ')
          ..write('timezone: $timezone, ')
          ..write('anchorAt: $anchorAt, ')
          ..write('revision: $revision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AlarmEventsTable extends AlarmEvents
    with TableInfo<$AlarmEventsTable, AlarmEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlarmEventsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _atMeta = const VerificationMeta('at');
  @override
  late final GeneratedColumn<DateTime> at = GeneratedColumn<DateTime>(
    'at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventMeta = const VerificationMeta('event');
  @override
  late final GeneratedColumn<String> event = GeneratedColumn<String>(
    'event',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _laneMeta = const VerificationMeta('lane');
  @override
  late final GeneratedColumn<String> lane = GeneratedColumn<String>(
    'lane',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _slotIndexMeta = const VerificationMeta(
    'slotIndex',
  );
  @override
  late final GeneratedColumn<int> slotIndex = GeneratedColumn<int>(
    'slot_index',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _urgentMeta = const VerificationMeta('urgent');
  @override
  late final GeneratedColumn<bool> urgent = GeneratedColumn<bool>(
    'urgent',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("urgent" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _soundMeta = const VerificationMeta('sound');
  @override
  late final GeneratedColumn<String> sound = GeneratedColumn<String>(
    'sound',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<String> level = GeneratedColumn<String>(
    'level',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fireAtMeta = const VerificationMeta('fireAt');
  @override
  late final GeneratedColumn<DateTime> fireAt = GeneratedColumn<DateTime>(
    'fire_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reminderIdMeta = const VerificationMeta(
    'reminderId',
  );
  @override
  late final GeneratedColumn<String> reminderId = GeneratedColumn<String>(
    'reminder_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _detailMeta = const VerificationMeta('detail');
  @override
  late final GeneratedColumn<String> detail = GeneratedColumn<String>(
    'detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    at,
    event,
    lane,
    kind,
    slotIndex,
    urgent,
    sound,
    level,
    fireAt,
    taskId,
    reminderId,
    detail,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'alarm_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<AlarmEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('at')) {
      context.handle(_atMeta, at.isAcceptableOrUnknown(data['at']!, _atMeta));
    } else if (isInserting) {
      context.missing(_atMeta);
    }
    if (data.containsKey('event')) {
      context.handle(
        _eventMeta,
        event.isAcceptableOrUnknown(data['event']!, _eventMeta),
      );
    } else if (isInserting) {
      context.missing(_eventMeta);
    }
    if (data.containsKey('lane')) {
      context.handle(
        _laneMeta,
        lane.isAcceptableOrUnknown(data['lane']!, _laneMeta),
      );
    } else if (isInserting) {
      context.missing(_laneMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('slot_index')) {
      context.handle(
        _slotIndexMeta,
        slotIndex.isAcceptableOrUnknown(data['slot_index']!, _slotIndexMeta),
      );
    }
    if (data.containsKey('urgent')) {
      context.handle(
        _urgentMeta,
        urgent.isAcceptableOrUnknown(data['urgent']!, _urgentMeta),
      );
    }
    if (data.containsKey('sound')) {
      context.handle(
        _soundMeta,
        sound.isAcceptableOrUnknown(data['sound']!, _soundMeta),
      );
    }
    if (data.containsKey('level')) {
      context.handle(
        _levelMeta,
        level.isAcceptableOrUnknown(data['level']!, _levelMeta),
      );
    }
    if (data.containsKey('fire_at')) {
      context.handle(
        _fireAtMeta,
        fireAt.isAcceptableOrUnknown(data['fire_at']!, _fireAtMeta),
      );
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    }
    if (data.containsKey('reminder_id')) {
      context.handle(
        _reminderIdMeta,
        reminderId.isAcceptableOrUnknown(data['reminder_id']!, _reminderIdMeta),
      );
    }
    if (data.containsKey('detail')) {
      context.handle(
        _detailMeta,
        detail.isAcceptableOrUnknown(data['detail']!, _detailMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AlarmEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlarmEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      at: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}at'],
      )!,
      event: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event'],
      )!,
      lane: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lane'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      ),
      slotIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}slot_index'],
      ),
      urgent: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}urgent'],
      )!,
      sound: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sound'],
      ),
      level: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}level'],
      ),
      fireAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fire_at'],
      ),
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      ),
      reminderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reminder_id'],
      ),
      detail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}detail'],
      ),
    );
  }

  @override
  $AlarmEventsTable createAlias(String alias) {
    return $AlarmEventsTable(attachedDatabase, alias);
  }
}

class AlarmEvent extends DataClass implements Insertable<AlarmEvent> {
  final int id;

  /// When we recorded it (UTC).
  final DateTime at;

  /// `scheduled` | `cancelled` | `interacted` | `action` | `ring_shown` |
  /// `degraded`.
  final String event;

  /// `notification` | `alarmkit` | `inapp`.
  final String lane;

  /// The alarm's kind (`remind`/`due`) where one is known.
  final String? kind;

  /// Which slot of the re-alert chain, 0-based.
  final int? slotIndex;
  final bool urgent;

  /// What we ASKED the OS for (see `ScheduledDelivery`).
  final String? sound;
  final String? level;

  /// The instant the alarm was scheduled to fire (UTC), when applicable.
  final DateTime? fireAt;
  final String? taskId;
  final String? reminderId;

  /// Free-form extra (an action id, a degradation reason).
  final String? detail;
  const AlarmEvent({
    required this.id,
    required this.at,
    required this.event,
    required this.lane,
    this.kind,
    this.slotIndex,
    required this.urgent,
    this.sound,
    this.level,
    this.fireAt,
    this.taskId,
    this.reminderId,
    this.detail,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['at'] = Variable<DateTime>(at);
    map['event'] = Variable<String>(event);
    map['lane'] = Variable<String>(lane);
    if (!nullToAbsent || kind != null) {
      map['kind'] = Variable<String>(kind);
    }
    if (!nullToAbsent || slotIndex != null) {
      map['slot_index'] = Variable<int>(slotIndex);
    }
    map['urgent'] = Variable<bool>(urgent);
    if (!nullToAbsent || sound != null) {
      map['sound'] = Variable<String>(sound);
    }
    if (!nullToAbsent || level != null) {
      map['level'] = Variable<String>(level);
    }
    if (!nullToAbsent || fireAt != null) {
      map['fire_at'] = Variable<DateTime>(fireAt);
    }
    if (!nullToAbsent || taskId != null) {
      map['task_id'] = Variable<String>(taskId);
    }
    if (!nullToAbsent || reminderId != null) {
      map['reminder_id'] = Variable<String>(reminderId);
    }
    if (!nullToAbsent || detail != null) {
      map['detail'] = Variable<String>(detail);
    }
    return map;
  }

  AlarmEventsCompanion toCompanion(bool nullToAbsent) {
    return AlarmEventsCompanion(
      id: Value(id),
      at: Value(at),
      event: Value(event),
      lane: Value(lane),
      kind: kind == null && nullToAbsent ? const Value.absent() : Value(kind),
      slotIndex: slotIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(slotIndex),
      urgent: Value(urgent),
      sound: sound == null && nullToAbsent
          ? const Value.absent()
          : Value(sound),
      level: level == null && nullToAbsent
          ? const Value.absent()
          : Value(level),
      fireAt: fireAt == null && nullToAbsent
          ? const Value.absent()
          : Value(fireAt),
      taskId: taskId == null && nullToAbsent
          ? const Value.absent()
          : Value(taskId),
      reminderId: reminderId == null && nullToAbsent
          ? const Value.absent()
          : Value(reminderId),
      detail: detail == null && nullToAbsent
          ? const Value.absent()
          : Value(detail),
    );
  }

  factory AlarmEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AlarmEvent(
      id: serializer.fromJson<int>(json['id']),
      at: serializer.fromJson<DateTime>(json['at']),
      event: serializer.fromJson<String>(json['event']),
      lane: serializer.fromJson<String>(json['lane']),
      kind: serializer.fromJson<String?>(json['kind']),
      slotIndex: serializer.fromJson<int?>(json['slotIndex']),
      urgent: serializer.fromJson<bool>(json['urgent']),
      sound: serializer.fromJson<String?>(json['sound']),
      level: serializer.fromJson<String?>(json['level']),
      fireAt: serializer.fromJson<DateTime?>(json['fireAt']),
      taskId: serializer.fromJson<String?>(json['taskId']),
      reminderId: serializer.fromJson<String?>(json['reminderId']),
      detail: serializer.fromJson<String?>(json['detail']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'at': serializer.toJson<DateTime>(at),
      'event': serializer.toJson<String>(event),
      'lane': serializer.toJson<String>(lane),
      'kind': serializer.toJson<String?>(kind),
      'slotIndex': serializer.toJson<int?>(slotIndex),
      'urgent': serializer.toJson<bool>(urgent),
      'sound': serializer.toJson<String?>(sound),
      'level': serializer.toJson<String?>(level),
      'fireAt': serializer.toJson<DateTime?>(fireAt),
      'taskId': serializer.toJson<String?>(taskId),
      'reminderId': serializer.toJson<String?>(reminderId),
      'detail': serializer.toJson<String?>(detail),
    };
  }

  AlarmEvent copyWith({
    int? id,
    DateTime? at,
    String? event,
    String? lane,
    Value<String?> kind = const Value.absent(),
    Value<int?> slotIndex = const Value.absent(),
    bool? urgent,
    Value<String?> sound = const Value.absent(),
    Value<String?> level = const Value.absent(),
    Value<DateTime?> fireAt = const Value.absent(),
    Value<String?> taskId = const Value.absent(),
    Value<String?> reminderId = const Value.absent(),
    Value<String?> detail = const Value.absent(),
  }) => AlarmEvent(
    id: id ?? this.id,
    at: at ?? this.at,
    event: event ?? this.event,
    lane: lane ?? this.lane,
    kind: kind.present ? kind.value : this.kind,
    slotIndex: slotIndex.present ? slotIndex.value : this.slotIndex,
    urgent: urgent ?? this.urgent,
    sound: sound.present ? sound.value : this.sound,
    level: level.present ? level.value : this.level,
    fireAt: fireAt.present ? fireAt.value : this.fireAt,
    taskId: taskId.present ? taskId.value : this.taskId,
    reminderId: reminderId.present ? reminderId.value : this.reminderId,
    detail: detail.present ? detail.value : this.detail,
  );
  AlarmEvent copyWithCompanion(AlarmEventsCompanion data) {
    return AlarmEvent(
      id: data.id.present ? data.id.value : this.id,
      at: data.at.present ? data.at.value : this.at,
      event: data.event.present ? data.event.value : this.event,
      lane: data.lane.present ? data.lane.value : this.lane,
      kind: data.kind.present ? data.kind.value : this.kind,
      slotIndex: data.slotIndex.present ? data.slotIndex.value : this.slotIndex,
      urgent: data.urgent.present ? data.urgent.value : this.urgent,
      sound: data.sound.present ? data.sound.value : this.sound,
      level: data.level.present ? data.level.value : this.level,
      fireAt: data.fireAt.present ? data.fireAt.value : this.fireAt,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      reminderId: data.reminderId.present
          ? data.reminderId.value
          : this.reminderId,
      detail: data.detail.present ? data.detail.value : this.detail,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AlarmEvent(')
          ..write('id: $id, ')
          ..write('at: $at, ')
          ..write('event: $event, ')
          ..write('lane: $lane, ')
          ..write('kind: $kind, ')
          ..write('slotIndex: $slotIndex, ')
          ..write('urgent: $urgent, ')
          ..write('sound: $sound, ')
          ..write('level: $level, ')
          ..write('fireAt: $fireAt, ')
          ..write('taskId: $taskId, ')
          ..write('reminderId: $reminderId, ')
          ..write('detail: $detail')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    at,
    event,
    lane,
    kind,
    slotIndex,
    urgent,
    sound,
    level,
    fireAt,
    taskId,
    reminderId,
    detail,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AlarmEvent &&
          other.id == this.id &&
          other.at == this.at &&
          other.event == this.event &&
          other.lane == this.lane &&
          other.kind == this.kind &&
          other.slotIndex == this.slotIndex &&
          other.urgent == this.urgent &&
          other.sound == this.sound &&
          other.level == this.level &&
          other.fireAt == this.fireAt &&
          other.taskId == this.taskId &&
          other.reminderId == this.reminderId &&
          other.detail == this.detail);
}

class AlarmEventsCompanion extends UpdateCompanion<AlarmEvent> {
  final Value<int> id;
  final Value<DateTime> at;
  final Value<String> event;
  final Value<String> lane;
  final Value<String?> kind;
  final Value<int?> slotIndex;
  final Value<bool> urgent;
  final Value<String?> sound;
  final Value<String?> level;
  final Value<DateTime?> fireAt;
  final Value<String?> taskId;
  final Value<String?> reminderId;
  final Value<String?> detail;
  const AlarmEventsCompanion({
    this.id = const Value.absent(),
    this.at = const Value.absent(),
    this.event = const Value.absent(),
    this.lane = const Value.absent(),
    this.kind = const Value.absent(),
    this.slotIndex = const Value.absent(),
    this.urgent = const Value.absent(),
    this.sound = const Value.absent(),
    this.level = const Value.absent(),
    this.fireAt = const Value.absent(),
    this.taskId = const Value.absent(),
    this.reminderId = const Value.absent(),
    this.detail = const Value.absent(),
  });
  AlarmEventsCompanion.insert({
    this.id = const Value.absent(),
    required DateTime at,
    required String event,
    required String lane,
    this.kind = const Value.absent(),
    this.slotIndex = const Value.absent(),
    this.urgent = const Value.absent(),
    this.sound = const Value.absent(),
    this.level = const Value.absent(),
    this.fireAt = const Value.absent(),
    this.taskId = const Value.absent(),
    this.reminderId = const Value.absent(),
    this.detail = const Value.absent(),
  }) : at = Value(at),
       event = Value(event),
       lane = Value(lane);
  static Insertable<AlarmEvent> custom({
    Expression<int>? id,
    Expression<DateTime>? at,
    Expression<String>? event,
    Expression<String>? lane,
    Expression<String>? kind,
    Expression<int>? slotIndex,
    Expression<bool>? urgent,
    Expression<String>? sound,
    Expression<String>? level,
    Expression<DateTime>? fireAt,
    Expression<String>? taskId,
    Expression<String>? reminderId,
    Expression<String>? detail,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (at != null) 'at': at,
      if (event != null) 'event': event,
      if (lane != null) 'lane': lane,
      if (kind != null) 'kind': kind,
      if (slotIndex != null) 'slot_index': slotIndex,
      if (urgent != null) 'urgent': urgent,
      if (sound != null) 'sound': sound,
      if (level != null) 'level': level,
      if (fireAt != null) 'fire_at': fireAt,
      if (taskId != null) 'task_id': taskId,
      if (reminderId != null) 'reminder_id': reminderId,
      if (detail != null) 'detail': detail,
    });
  }

  AlarmEventsCompanion copyWith({
    Value<int>? id,
    Value<DateTime>? at,
    Value<String>? event,
    Value<String>? lane,
    Value<String?>? kind,
    Value<int?>? slotIndex,
    Value<bool>? urgent,
    Value<String?>? sound,
    Value<String?>? level,
    Value<DateTime?>? fireAt,
    Value<String?>? taskId,
    Value<String?>? reminderId,
    Value<String?>? detail,
  }) {
    return AlarmEventsCompanion(
      id: id ?? this.id,
      at: at ?? this.at,
      event: event ?? this.event,
      lane: lane ?? this.lane,
      kind: kind ?? this.kind,
      slotIndex: slotIndex ?? this.slotIndex,
      urgent: urgent ?? this.urgent,
      sound: sound ?? this.sound,
      level: level ?? this.level,
      fireAt: fireAt ?? this.fireAt,
      taskId: taskId ?? this.taskId,
      reminderId: reminderId ?? this.reminderId,
      detail: detail ?? this.detail,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (at.present) {
      map['at'] = Variable<DateTime>(at.value);
    }
    if (event.present) {
      map['event'] = Variable<String>(event.value);
    }
    if (lane.present) {
      map['lane'] = Variable<String>(lane.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (slotIndex.present) {
      map['slot_index'] = Variable<int>(slotIndex.value);
    }
    if (urgent.present) {
      map['urgent'] = Variable<bool>(urgent.value);
    }
    if (sound.present) {
      map['sound'] = Variable<String>(sound.value);
    }
    if (level.present) {
      map['level'] = Variable<String>(level.value);
    }
    if (fireAt.present) {
      map['fire_at'] = Variable<DateTime>(fireAt.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (reminderId.present) {
      map['reminder_id'] = Variable<String>(reminderId.value);
    }
    if (detail.present) {
      map['detail'] = Variable<String>(detail.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlarmEventsCompanion(')
          ..write('id: $id, ')
          ..write('at: $at, ')
          ..write('event: $event, ')
          ..write('lane: $lane, ')
          ..write('kind: $kind, ')
          ..write('slotIndex: $slotIndex, ')
          ..write('urgent: $urgent, ')
          ..write('sound: $sound, ')
          ..write('level: $level, ')
          ..write('fireAt: $fireAt, ')
          ..write('taskId: $taskId, ')
          ..write('reminderId: $reminderId, ')
          ..write('detail: $detail')
          ..write(')'))
        .toString();
  }
}

class $AiMessagesTable extends AiMessages
    with TableInfo<$AiMessagesTable, AiMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiMessagesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('done'),
  );
  static const VerificationMeta _contextJsonMeta = const VerificationMeta(
    'contextJson',
  );
  @override
  late final GeneratedColumn<String> contextJson = GeneratedColumn<String>(
    'context_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _requestIdMeta = const VerificationMeta(
    'requestId',
  );
  @override
  late final GeneratedColumn<String> requestId = GeneratedColumn<String>(
    'request_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    role,
    content,
    status,
    contextJson,
    requestId,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<AiMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('context_json')) {
      context.handle(
        _contextJsonMeta,
        contextJson.isAcceptableOrUnknown(
          data['context_json']!,
          _contextJsonMeta,
        ),
      );
    }
    if (data.containsKey('request_id')) {
      context.handle(
        _requestIdMeta,
        requestId.isAcceptableOrUnknown(data['request_id']!, _requestIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AiMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiMessage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      contextJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}context_json'],
      ),
      requestId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $AiMessagesTable createAlias(String alias) {
    return $AiMessagesTable(attachedDatabase, alias);
  }
}

class AiMessage extends DataClass implements Insertable<AiMessage> {
  final int id;
  final String workspaceId;

  /// `user` | `assistant`.
  final String role;

  /// The final text (a stream is buffered in memory; the row is written on
  /// done / cancel / error).
  final String content;

  /// `done` | `cancelled` | `error`.
  final String status;

  /// The packed context bundle summary for the message's context chip (user
  /// rows), as JSON. Null on assistant rows.
  final String? contextJson;

  /// Correlates with the server's requestId, where one exists.
  final String? requestId;
  final DateTime createdAt;
  const AiMessage({
    required this.id,
    required this.workspaceId,
    required this.role,
    required this.content,
    required this.status,
    this.contextJson,
    this.requestId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['role'] = Variable<String>(role);
    map['content'] = Variable<String>(content);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || contextJson != null) {
      map['context_json'] = Variable<String>(contextJson);
    }
    if (!nullToAbsent || requestId != null) {
      map['request_id'] = Variable<String>(requestId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  AiMessagesCompanion toCompanion(bool nullToAbsent) {
    return AiMessagesCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      role: Value(role),
      content: Value(content),
      status: Value(status),
      contextJson: contextJson == null && nullToAbsent
          ? const Value.absent()
          : Value(contextJson),
      requestId: requestId == null && nullToAbsent
          ? const Value.absent()
          : Value(requestId),
      createdAt: Value(createdAt),
    );
  }

  factory AiMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiMessage(
      id: serializer.fromJson<int>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      role: serializer.fromJson<String>(json['role']),
      content: serializer.fromJson<String>(json['content']),
      status: serializer.fromJson<String>(json['status']),
      contextJson: serializer.fromJson<String?>(json['contextJson']),
      requestId: serializer.fromJson<String?>(json['requestId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'role': serializer.toJson<String>(role),
      'content': serializer.toJson<String>(content),
      'status': serializer.toJson<String>(status),
      'contextJson': serializer.toJson<String?>(contextJson),
      'requestId': serializer.toJson<String?>(requestId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  AiMessage copyWith({
    int? id,
    String? workspaceId,
    String? role,
    String? content,
    String? status,
    Value<String?> contextJson = const Value.absent(),
    Value<String?> requestId = const Value.absent(),
    DateTime? createdAt,
  }) => AiMessage(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    role: role ?? this.role,
    content: content ?? this.content,
    status: status ?? this.status,
    contextJson: contextJson.present ? contextJson.value : this.contextJson,
    requestId: requestId.present ? requestId.value : this.requestId,
    createdAt: createdAt ?? this.createdAt,
  );
  AiMessage copyWithCompanion(AiMessagesCompanion data) {
    return AiMessage(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      role: data.role.present ? data.role.value : this.role,
      content: data.content.present ? data.content.value : this.content,
      status: data.status.present ? data.status.value : this.status,
      contextJson: data.contextJson.present
          ? data.contextJson.value
          : this.contextJson,
      requestId: data.requestId.present ? data.requestId.value : this.requestId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiMessage(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('status: $status, ')
          ..write('contextJson: $contextJson, ')
          ..write('requestId: $requestId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    role,
    content,
    status,
    contextJson,
    requestId,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiMessage &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.role == this.role &&
          other.content == this.content &&
          other.status == this.status &&
          other.contextJson == this.contextJson &&
          other.requestId == this.requestId &&
          other.createdAt == this.createdAt);
}

class AiMessagesCompanion extends UpdateCompanion<AiMessage> {
  final Value<int> id;
  final Value<String> workspaceId;
  final Value<String> role;
  final Value<String> content;
  final Value<String> status;
  final Value<String?> contextJson;
  final Value<String?> requestId;
  final Value<DateTime> createdAt;
  const AiMessagesCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.role = const Value.absent(),
    this.content = const Value.absent(),
    this.status = const Value.absent(),
    this.contextJson = const Value.absent(),
    this.requestId = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  AiMessagesCompanion.insert({
    this.id = const Value.absent(),
    required String workspaceId,
    required String role,
    required String content,
    this.status = const Value.absent(),
    this.contextJson = const Value.absent(),
    this.requestId = const Value.absent(),
    required DateTime createdAt,
  }) : workspaceId = Value(workspaceId),
       role = Value(role),
       content = Value(content),
       createdAt = Value(createdAt);
  static Insertable<AiMessage> custom({
    Expression<int>? id,
    Expression<String>? workspaceId,
    Expression<String>? role,
    Expression<String>? content,
    Expression<String>? status,
    Expression<String>? contextJson,
    Expression<String>? requestId,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (role != null) 'role': role,
      if (content != null) 'content': content,
      if (status != null) 'status': status,
      if (contextJson != null) 'context_json': contextJson,
      if (requestId != null) 'request_id': requestId,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  AiMessagesCompanion copyWith({
    Value<int>? id,
    Value<String>? workspaceId,
    Value<String>? role,
    Value<String>? content,
    Value<String>? status,
    Value<String?>? contextJson,
    Value<String?>? requestId,
    Value<DateTime>? createdAt,
  }) {
    return AiMessagesCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      role: role ?? this.role,
      content: content ?? this.content,
      status: status ?? this.status,
      contextJson: contextJson ?? this.contextJson,
      requestId: requestId ?? this.requestId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (contextJson.present) {
      map['context_json'] = Variable<String>(contextJson.value);
    }
    if (requestId.present) {
      map['request_id'] = Variable<String>(requestId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiMessagesCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('status: $status, ')
          ..write('contextJson: $contextJson, ')
          ..write('requestId: $requestId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ShareEventsTable extends ShareEvents
    with TableInfo<$ShareEventsTable, ShareEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShareEventsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _atMeta = const VerificationMeta('at');
  @override
  late final GeneratedColumn<DateTime> at = GeneratedColumn<DateTime>(
    'at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventMeta = const VerificationMeta('event');
  @override
  late final GeneratedColumn<String> event = GeneratedColumn<String>(
    'event',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadKindMeta = const VerificationMeta(
    'payloadKind',
  );
  @override
  late final GeneratedColumn<String> payloadKind = GeneratedColumn<String>(
    'payload_kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<int> bytes = GeneratedColumn<int>(
    'bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _detailMeta = const VerificationMeta('detail');
  @override
  late final GeneratedColumn<String> detail = GeneratedColumn<String>(
    'detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    at,
    event,
    payloadKind,
    bytes,
    detail,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'share_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShareEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('at')) {
      context.handle(_atMeta, at.isAcceptableOrUnknown(data['at']!, _atMeta));
    } else if (isInserting) {
      context.missing(_atMeta);
    }
    if (data.containsKey('event')) {
      context.handle(
        _eventMeta,
        event.isAcceptableOrUnknown(data['event']!, _eventMeta),
      );
    } else if (isInserting) {
      context.missing(_eventMeta);
    }
    if (data.containsKey('payload_kind')) {
      context.handle(
        _payloadKindMeta,
        payloadKind.isAcceptableOrUnknown(
          data['payload_kind']!,
          _payloadKindMeta,
        ),
      );
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    }
    if (data.containsKey('detail')) {
      context.handle(
        _detailMeta,
        detail.isAcceptableOrUnknown(data['detail']!, _detailMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ShareEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShareEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      at: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}at'],
      )!,
      event: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event'],
      )!,
      payloadKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_kind'],
      ),
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bytes'],
      ),
      detail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}detail'],
      ),
    );
  }

  @override
  $ShareEventsTable createAlias(String alias) {
    return $ShareEventsTable(attachedDatabase, alias);
  }
}

class ShareEvent extends DataClass implements Insertable<ShareEvent> {
  final int id;

  /// When we recorded it (UTC).
  final DateTime at;

  /// `initial_share` | `warm_share` | `initial_document` | `warm_document` |
  /// `read_failed` | `consumed`.
  final String event;

  /// `text` | `url` | `markdown`, where the shape is known.
  final String? payloadKind;

  /// How much arrived — never WHAT arrived.
  final int? bytes;

  /// Free-form extra: a file's extension, an error's runtime type. Never
  /// payload text, never a full path.
  final String? detail;
  const ShareEvent({
    required this.id,
    required this.at,
    required this.event,
    this.payloadKind,
    this.bytes,
    this.detail,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['at'] = Variable<DateTime>(at);
    map['event'] = Variable<String>(event);
    if (!nullToAbsent || payloadKind != null) {
      map['payload_kind'] = Variable<String>(payloadKind);
    }
    if (!nullToAbsent || bytes != null) {
      map['bytes'] = Variable<int>(bytes);
    }
    if (!nullToAbsent || detail != null) {
      map['detail'] = Variable<String>(detail);
    }
    return map;
  }

  ShareEventsCompanion toCompanion(bool nullToAbsent) {
    return ShareEventsCompanion(
      id: Value(id),
      at: Value(at),
      event: Value(event),
      payloadKind: payloadKind == null && nullToAbsent
          ? const Value.absent()
          : Value(payloadKind),
      bytes: bytes == null && nullToAbsent
          ? const Value.absent()
          : Value(bytes),
      detail: detail == null && nullToAbsent
          ? const Value.absent()
          : Value(detail),
    );
  }

  factory ShareEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShareEvent(
      id: serializer.fromJson<int>(json['id']),
      at: serializer.fromJson<DateTime>(json['at']),
      event: serializer.fromJson<String>(json['event']),
      payloadKind: serializer.fromJson<String?>(json['payloadKind']),
      bytes: serializer.fromJson<int?>(json['bytes']),
      detail: serializer.fromJson<String?>(json['detail']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'at': serializer.toJson<DateTime>(at),
      'event': serializer.toJson<String>(event),
      'payloadKind': serializer.toJson<String?>(payloadKind),
      'bytes': serializer.toJson<int?>(bytes),
      'detail': serializer.toJson<String?>(detail),
    };
  }

  ShareEvent copyWith({
    int? id,
    DateTime? at,
    String? event,
    Value<String?> payloadKind = const Value.absent(),
    Value<int?> bytes = const Value.absent(),
    Value<String?> detail = const Value.absent(),
  }) => ShareEvent(
    id: id ?? this.id,
    at: at ?? this.at,
    event: event ?? this.event,
    payloadKind: payloadKind.present ? payloadKind.value : this.payloadKind,
    bytes: bytes.present ? bytes.value : this.bytes,
    detail: detail.present ? detail.value : this.detail,
  );
  ShareEvent copyWithCompanion(ShareEventsCompanion data) {
    return ShareEvent(
      id: data.id.present ? data.id.value : this.id,
      at: data.at.present ? data.at.value : this.at,
      event: data.event.present ? data.event.value : this.event,
      payloadKind: data.payloadKind.present
          ? data.payloadKind.value
          : this.payloadKind,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
      detail: data.detail.present ? data.detail.value : this.detail,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShareEvent(')
          ..write('id: $id, ')
          ..write('at: $at, ')
          ..write('event: $event, ')
          ..write('payloadKind: $payloadKind, ')
          ..write('bytes: $bytes, ')
          ..write('detail: $detail')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, at, event, payloadKind, bytes, detail);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShareEvent &&
          other.id == this.id &&
          other.at == this.at &&
          other.event == this.event &&
          other.payloadKind == this.payloadKind &&
          other.bytes == this.bytes &&
          other.detail == this.detail);
}

class ShareEventsCompanion extends UpdateCompanion<ShareEvent> {
  final Value<int> id;
  final Value<DateTime> at;
  final Value<String> event;
  final Value<String?> payloadKind;
  final Value<int?> bytes;
  final Value<String?> detail;
  const ShareEventsCompanion({
    this.id = const Value.absent(),
    this.at = const Value.absent(),
    this.event = const Value.absent(),
    this.payloadKind = const Value.absent(),
    this.bytes = const Value.absent(),
    this.detail = const Value.absent(),
  });
  ShareEventsCompanion.insert({
    this.id = const Value.absent(),
    required DateTime at,
    required String event,
    this.payloadKind = const Value.absent(),
    this.bytes = const Value.absent(),
    this.detail = const Value.absent(),
  }) : at = Value(at),
       event = Value(event);
  static Insertable<ShareEvent> custom({
    Expression<int>? id,
    Expression<DateTime>? at,
    Expression<String>? event,
    Expression<String>? payloadKind,
    Expression<int>? bytes,
    Expression<String>? detail,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (at != null) 'at': at,
      if (event != null) 'event': event,
      if (payloadKind != null) 'payload_kind': payloadKind,
      if (bytes != null) 'bytes': bytes,
      if (detail != null) 'detail': detail,
    });
  }

  ShareEventsCompanion copyWith({
    Value<int>? id,
    Value<DateTime>? at,
    Value<String>? event,
    Value<String?>? payloadKind,
    Value<int?>? bytes,
    Value<String?>? detail,
  }) {
    return ShareEventsCompanion(
      id: id ?? this.id,
      at: at ?? this.at,
      event: event ?? this.event,
      payloadKind: payloadKind ?? this.payloadKind,
      bytes: bytes ?? this.bytes,
      detail: detail ?? this.detail,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (at.present) {
      map['at'] = Variable<DateTime>(at.value);
    }
    if (event.present) {
      map['event'] = Variable<String>(event.value);
    }
    if (payloadKind.present) {
      map['payload_kind'] = Variable<String>(payloadKind.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<int>(bytes.value);
    }
    if (detail.present) {
      map['detail'] = Variable<String>(detail.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShareEventsCompanion(')
          ..write('id: $id, ')
          ..write('at: $at, ')
          ..write('event: $event, ')
          ..write('payloadKind: $payloadKind, ')
          ..write('bytes: $bytes, ')
          ..write('detail: $detail')
          ..write(')'))
        .toString();
  }
}

class $PendingMutationsTable extends PendingMutations
    with TableInfo<$PendingMutationsTable, PendingMutation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingMutationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _patchJsonMeta = const VerificationMeta(
    'patchJson',
  );
  @override
  late final GeneratedColumn<String> patchJson = GeneratedColumn<String>(
    'patch_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localUpdatedAtMeta = const VerificationMeta(
    'localUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> localUpdatedAt =
      GeneratedColumn<DateTime>(
        'local_updated_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _baseRevisionMeta = const VerificationMeta(
    'baseRevision',
  );
  @override
  late final GeneratedColumn<int> baseRevision = GeneratedColumn<int>(
    'base_revision',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    entityType,
    entityId,
    operation,
    patchJson,
    localUpdatedAt,
    createdAt,
    attempts,
    lastError,
    baseRevision,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_mutations';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingMutation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('patch_json')) {
      context.handle(
        _patchJsonMeta,
        patchJson.isAcceptableOrUnknown(data['patch_json']!, _patchJsonMeta),
      );
    }
    if (data.containsKey('local_updated_at')) {
      context.handle(
        _localUpdatedAtMeta,
        localUpdatedAt.isAcceptableOrUnknown(
          data['local_updated_at']!,
          _localUpdatedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localUpdatedAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('base_revision')) {
      context.handle(
        _baseRevisionMeta,
        baseRevision.isAcceptableOrUnknown(
          data['base_revision']!,
          _baseRevisionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingMutation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingMutation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      patchJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}patch_json'],
      ),
      localUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}local_updated_at'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      baseRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_revision'],
      ),
    );
  }

  @override
  $PendingMutationsTable createAlias(String alias) {
    return $PendingMutationsTable(attachedDatabase, alias);
  }
}

class PendingMutation extends DataClass implements Insertable<PendingMutation> {
  final String id;
  final String workspaceId;
  final String entityType;
  final String entityId;

  /// create | update | delete
  final String operation;

  /// JSON-encoded patch (absent for deletes).
  final String? patchJson;
  final DateTime localUpdatedAt;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;

  /// The entity revision this write started from — "what the editor saw"
  /// (v18, OPH-268). The server merges against it instead of comparing the
  /// workspace pull cursor, which is what used to make one body silently
  /// replace another. Nullable: writes that do not carry one behave exactly
  /// as they did before.
  final int? baseRevision;
  const PendingMutation({
    required this.id,
    required this.workspaceId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    this.patchJson,
    required this.localUpdatedAt,
    required this.createdAt,
    required this.attempts,
    this.lastError,
    this.baseRevision,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['operation'] = Variable<String>(operation);
    if (!nullToAbsent || patchJson != null) {
      map['patch_json'] = Variable<String>(patchJson);
    }
    map['local_updated_at'] = Variable<DateTime>(localUpdatedAt);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || baseRevision != null) {
      map['base_revision'] = Variable<int>(baseRevision);
    }
    return map;
  }

  PendingMutationsCompanion toCompanion(bool nullToAbsent) {
    return PendingMutationsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      operation: Value(operation),
      patchJson: patchJson == null && nullToAbsent
          ? const Value.absent()
          : Value(patchJson),
      localUpdatedAt: Value(localUpdatedAt),
      createdAt: Value(createdAt),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      baseRevision: baseRevision == null && nullToAbsent
          ? const Value.absent()
          : Value(baseRevision),
    );
  }

  factory PendingMutation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingMutation(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      operation: serializer.fromJson<String>(json['operation']),
      patchJson: serializer.fromJson<String?>(json['patchJson']),
      localUpdatedAt: serializer.fromJson<DateTime>(json['localUpdatedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      baseRevision: serializer.fromJson<int?>(json['baseRevision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'operation': serializer.toJson<String>(operation),
      'patchJson': serializer.toJson<String?>(patchJson),
      'localUpdatedAt': serializer.toJson<DateTime>(localUpdatedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
      'baseRevision': serializer.toJson<int?>(baseRevision),
    };
  }

  PendingMutation copyWith({
    String? id,
    String? workspaceId,
    String? entityType,
    String? entityId,
    String? operation,
    Value<String?> patchJson = const Value.absent(),
    DateTime? localUpdatedAt,
    DateTime? createdAt,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
    Value<int?> baseRevision = const Value.absent(),
  }) => PendingMutation(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    operation: operation ?? this.operation,
    patchJson: patchJson.present ? patchJson.value : this.patchJson,
    localUpdatedAt: localUpdatedAt ?? this.localUpdatedAt,
    createdAt: createdAt ?? this.createdAt,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
    baseRevision: baseRevision.present ? baseRevision.value : this.baseRevision,
  );
  PendingMutation copyWithCompanion(PendingMutationsCompanion data) {
    return PendingMutation(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      operation: data.operation.present ? data.operation.value : this.operation,
      patchJson: data.patchJson.present ? data.patchJson.value : this.patchJson,
      localUpdatedAt: data.localUpdatedAt.present
          ? data.localUpdatedAt.value
          : this.localUpdatedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      baseRevision: data.baseRevision.present
          ? data.baseRevision.value
          : this.baseRevision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingMutation(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('patchJson: $patchJson, ')
          ..write('localUpdatedAt: $localUpdatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('baseRevision: $baseRevision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    entityType,
    entityId,
    operation,
    patchJson,
    localUpdatedAt,
    createdAt,
    attempts,
    lastError,
    baseRevision,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingMutation &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.operation == this.operation &&
          other.patchJson == this.patchJson &&
          other.localUpdatedAt == this.localUpdatedAt &&
          other.createdAt == this.createdAt &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError &&
          other.baseRevision == this.baseRevision);
}

class PendingMutationsCompanion extends UpdateCompanion<PendingMutation> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> operation;
  final Value<String?> patchJson;
  final Value<DateTime> localUpdatedAt;
  final Value<DateTime> createdAt;
  final Value<int> attempts;
  final Value<String?> lastError;
  final Value<int?> baseRevision;
  final Value<int> rowid;
  const PendingMutationsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.operation = const Value.absent(),
    this.patchJson = const Value.absent(),
    this.localUpdatedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.baseRevision = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingMutationsCompanion.insert({
    required String id,
    required String workspaceId,
    required String entityType,
    required String entityId,
    required String operation,
    this.patchJson = const Value.absent(),
    required DateTime localUpdatedAt,
    required DateTime createdAt,
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.baseRevision = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       operation = Value(operation),
       localUpdatedAt = Value(localUpdatedAt),
       createdAt = Value(createdAt);
  static Insertable<PendingMutation> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? operation,
    Expression<String>? patchJson,
    Expression<DateTime>? localUpdatedAt,
    Expression<DateTime>? createdAt,
    Expression<int>? attempts,
    Expression<String>? lastError,
    Expression<int>? baseRevision,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (operation != null) 'operation': operation,
      if (patchJson != null) 'patch_json': patchJson,
      if (localUpdatedAt != null) 'local_updated_at': localUpdatedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
      if (baseRevision != null) 'base_revision': baseRevision,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingMutationsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? operation,
    Value<String?>? patchJson,
    Value<DateTime>? localUpdatedAt,
    Value<DateTime>? createdAt,
    Value<int>? attempts,
    Value<String?>? lastError,
    Value<int?>? baseRevision,
    Value<int>? rowid,
  }) {
    return PendingMutationsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      patchJson: patchJson ?? this.patchJson,
      localUpdatedAt: localUpdatedAt ?? this.localUpdatedAt,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      baseRevision: baseRevision ?? this.baseRevision,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (patchJson.present) {
      map['patch_json'] = Variable<String>(patchJson.value);
    }
    if (localUpdatedAt.present) {
      map['local_updated_at'] = Variable<DateTime>(localUpdatedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (baseRevision.present) {
      map['base_revision'] = Variable<int>(baseRevision.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingMutationsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('patchJson: $patchJson, ')
          ..write('localUpdatedAt: $localUpdatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RejectedMutationsTable extends RejectedMutations
    with TableInfo<$RejectedMutationsTable, RejectedMutation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RejectedMutationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _patchJsonMeta = const VerificationMeta(
    'patchJson',
  );
  @override
  late final GeneratedColumn<String> patchJson = GeneratedColumn<String>(
    'patch_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorCodeMeta = const VerificationMeta(
    'errorCode',
  );
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rejectedAtMeta = const VerificationMeta(
    'rejectedAt',
  );
  @override
  late final GeneratedColumn<DateTime> rejectedAt = GeneratedColumn<DateTime>(
    'rejected_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    entityType,
    entityId,
    operation,
    patchJson,
    errorCode,
    rejectedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rejected_mutations';
  @override
  VerificationContext validateIntegrity(
    Insertable<RejectedMutation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('patch_json')) {
      context.handle(
        _patchJsonMeta,
        patchJson.isAcceptableOrUnknown(data['patch_json']!, _patchJsonMeta),
      );
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    }
    if (data.containsKey('rejected_at')) {
      context.handle(
        _rejectedAtMeta,
        rejectedAt.isAcceptableOrUnknown(data['rejected_at']!, _rejectedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_rejectedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RejectedMutation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RejectedMutation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      patchJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}patch_json'],
      ),
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      ),
      rejectedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}rejected_at'],
      )!,
    );
  }

  @override
  $RejectedMutationsTable createAlias(String alias) {
    return $RejectedMutationsTable(attachedDatabase, alias);
  }
}

class RejectedMutation extends DataClass
    implements Insertable<RejectedMutation> {
  final String id;
  final String workspaceId;
  final String entityType;
  final String entityId;

  /// create | update | delete
  final String operation;

  /// The JSON patch that was refused — the user's content, kept verbatim.
  final String? patchJson;

  /// The server's stable code, e.g. `PERM_DENIED`.
  final String? errorCode;
  final DateTime rejectedAt;
  const RejectedMutation({
    required this.id,
    required this.workspaceId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    this.patchJson,
    this.errorCode,
    required this.rejectedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['operation'] = Variable<String>(operation);
    if (!nullToAbsent || patchJson != null) {
      map['patch_json'] = Variable<String>(patchJson);
    }
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    map['rejected_at'] = Variable<DateTime>(rejectedAt);
    return map;
  }

  RejectedMutationsCompanion toCompanion(bool nullToAbsent) {
    return RejectedMutationsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      operation: Value(operation),
      patchJson: patchJson == null && nullToAbsent
          ? const Value.absent()
          : Value(patchJson),
      errorCode: errorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(errorCode),
      rejectedAt: Value(rejectedAt),
    );
  }

  factory RejectedMutation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RejectedMutation(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      operation: serializer.fromJson<String>(json['operation']),
      patchJson: serializer.fromJson<String?>(json['patchJson']),
      errorCode: serializer.fromJson<String?>(json['errorCode']),
      rejectedAt: serializer.fromJson<DateTime>(json['rejectedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'operation': serializer.toJson<String>(operation),
      'patchJson': serializer.toJson<String?>(patchJson),
      'errorCode': serializer.toJson<String?>(errorCode),
      'rejectedAt': serializer.toJson<DateTime>(rejectedAt),
    };
  }

  RejectedMutation copyWith({
    String? id,
    String? workspaceId,
    String? entityType,
    String? entityId,
    String? operation,
    Value<String?> patchJson = const Value.absent(),
    Value<String?> errorCode = const Value.absent(),
    DateTime? rejectedAt,
  }) => RejectedMutation(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    operation: operation ?? this.operation,
    patchJson: patchJson.present ? patchJson.value : this.patchJson,
    errorCode: errorCode.present ? errorCode.value : this.errorCode,
    rejectedAt: rejectedAt ?? this.rejectedAt,
  );
  RejectedMutation copyWithCompanion(RejectedMutationsCompanion data) {
    return RejectedMutation(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      operation: data.operation.present ? data.operation.value : this.operation,
      patchJson: data.patchJson.present ? data.patchJson.value : this.patchJson,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
      rejectedAt: data.rejectedAt.present
          ? data.rejectedAt.value
          : this.rejectedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RejectedMutation(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('patchJson: $patchJson, ')
          ..write('errorCode: $errorCode, ')
          ..write('rejectedAt: $rejectedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    entityType,
    entityId,
    operation,
    patchJson,
    errorCode,
    rejectedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RejectedMutation &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.operation == this.operation &&
          other.patchJson == this.patchJson &&
          other.errorCode == this.errorCode &&
          other.rejectedAt == this.rejectedAt);
}

class RejectedMutationsCompanion extends UpdateCompanion<RejectedMutation> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> operation;
  final Value<String?> patchJson;
  final Value<String?> errorCode;
  final Value<DateTime> rejectedAt;
  final Value<int> rowid;
  const RejectedMutationsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.operation = const Value.absent(),
    this.patchJson = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.rejectedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RejectedMutationsCompanion.insert({
    required String id,
    required String workspaceId,
    required String entityType,
    required String entityId,
    required String operation,
    this.patchJson = const Value.absent(),
    this.errorCode = const Value.absent(),
    required DateTime rejectedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       operation = Value(operation),
       rejectedAt = Value(rejectedAt);
  static Insertable<RejectedMutation> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? operation,
    Expression<String>? patchJson,
    Expression<String>? errorCode,
    Expression<DateTime>? rejectedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (operation != null) 'operation': operation,
      if (patchJson != null) 'patch_json': patchJson,
      if (errorCode != null) 'error_code': errorCode,
      if (rejectedAt != null) 'rejected_at': rejectedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RejectedMutationsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? operation,
    Value<String?>? patchJson,
    Value<String?>? errorCode,
    Value<DateTime>? rejectedAt,
    Value<int>? rowid,
  }) {
    return RejectedMutationsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      patchJson: patchJson ?? this.patchJson,
      errorCode: errorCode ?? this.errorCode,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (patchJson.present) {
      map['patch_json'] = Variable<String>(patchJson.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (rejectedAt.present) {
      map['rejected_at'] = Variable<DateTime>(rejectedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RejectedMutationsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('patchJson: $patchJson, ')
          ..write('errorCode: $errorCode, ')
          ..write('rejectedAt: $rejectedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStatesTable extends SyncStates
    with TableInfo<$SyncStatesTable, SyncState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastRevisionMeta = const VerificationMeta(
    'lastRevision',
  );
  @override
  late final GeneratedColumn<int> lastRevision = GeneratedColumn<int>(
    'last_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastPulledAtMeta = const VerificationMeta(
    'lastPulledAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastPulledAt = GeneratedColumn<DateTime>(
    'last_pulled_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    workspaceId,
    clientId,
    lastRevision,
    lastPulledAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncState> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('last_revision')) {
      context.handle(
        _lastRevisionMeta,
        lastRevision.isAcceptableOrUnknown(
          data['last_revision']!,
          _lastRevisionMeta,
        ),
      );
    }
    if (data.containsKey('last_pulled_at')) {
      context.handle(
        _lastPulledAtMeta,
        lastPulledAt.isAcceptableOrUnknown(
          data['last_pulled_at']!,
          _lastPulledAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {workspaceId};
  @override
  SyncState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncState(
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      )!,
      lastRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_revision'],
      )!,
      lastPulledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_pulled_at'],
      ),
    );
  }

  @override
  $SyncStatesTable createAlias(String alias) {
    return $SyncStatesTable(attachedDatabase, alias);
  }
}

class SyncState extends DataClass implements Insertable<SyncState> {
  final String workspaceId;
  final String clientId;
  final int lastRevision;
  final DateTime? lastPulledAt;
  const SyncState({
    required this.workspaceId,
    required this.clientId,
    required this.lastRevision,
    this.lastPulledAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['workspace_id'] = Variable<String>(workspaceId);
    map['client_id'] = Variable<String>(clientId);
    map['last_revision'] = Variable<int>(lastRevision);
    if (!nullToAbsent || lastPulledAt != null) {
      map['last_pulled_at'] = Variable<DateTime>(lastPulledAt);
    }
    return map;
  }

  SyncStatesCompanion toCompanion(bool nullToAbsent) {
    return SyncStatesCompanion(
      workspaceId: Value(workspaceId),
      clientId: Value(clientId),
      lastRevision: Value(lastRevision),
      lastPulledAt: lastPulledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPulledAt),
    );
  }

  factory SyncState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncState(
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      clientId: serializer.fromJson<String>(json['clientId']),
      lastRevision: serializer.fromJson<int>(json['lastRevision']),
      lastPulledAt: serializer.fromJson<DateTime?>(json['lastPulledAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'workspaceId': serializer.toJson<String>(workspaceId),
      'clientId': serializer.toJson<String>(clientId),
      'lastRevision': serializer.toJson<int>(lastRevision),
      'lastPulledAt': serializer.toJson<DateTime?>(lastPulledAt),
    };
  }

  SyncState copyWith({
    String? workspaceId,
    String? clientId,
    int? lastRevision,
    Value<DateTime?> lastPulledAt = const Value.absent(),
  }) => SyncState(
    workspaceId: workspaceId ?? this.workspaceId,
    clientId: clientId ?? this.clientId,
    lastRevision: lastRevision ?? this.lastRevision,
    lastPulledAt: lastPulledAt.present ? lastPulledAt.value : this.lastPulledAt,
  );
  SyncState copyWithCompanion(SyncStatesCompanion data) {
    return SyncState(
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      lastRevision: data.lastRevision.present
          ? data.lastRevision.value
          : this.lastRevision,
      lastPulledAt: data.lastPulledAt.present
          ? data.lastPulledAt.value
          : this.lastPulledAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncState(')
          ..write('workspaceId: $workspaceId, ')
          ..write('clientId: $clientId, ')
          ..write('lastRevision: $lastRevision, ')
          ..write('lastPulledAt: $lastPulledAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(workspaceId, clientId, lastRevision, lastPulledAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncState &&
          other.workspaceId == this.workspaceId &&
          other.clientId == this.clientId &&
          other.lastRevision == this.lastRevision &&
          other.lastPulledAt == this.lastPulledAt);
}

class SyncStatesCompanion extends UpdateCompanion<SyncState> {
  final Value<String> workspaceId;
  final Value<String> clientId;
  final Value<int> lastRevision;
  final Value<DateTime?> lastPulledAt;
  final Value<int> rowid;
  const SyncStatesCompanion({
    this.workspaceId = const Value.absent(),
    this.clientId = const Value.absent(),
    this.lastRevision = const Value.absent(),
    this.lastPulledAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncStatesCompanion.insert({
    required String workspaceId,
    required String clientId,
    this.lastRevision = const Value.absent(),
    this.lastPulledAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : workspaceId = Value(workspaceId),
       clientId = Value(clientId);
  static Insertable<SyncState> custom({
    Expression<String>? workspaceId,
    Expression<String>? clientId,
    Expression<int>? lastRevision,
    Expression<DateTime>? lastPulledAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (clientId != null) 'client_id': clientId,
      if (lastRevision != null) 'last_revision': lastRevision,
      if (lastPulledAt != null) 'last_pulled_at': lastPulledAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncStatesCompanion copyWith({
    Value<String>? workspaceId,
    Value<String>? clientId,
    Value<int>? lastRevision,
    Value<DateTime?>? lastPulledAt,
    Value<int>? rowid,
  }) {
    return SyncStatesCompanion(
      workspaceId: workspaceId ?? this.workspaceId,
      clientId: clientId ?? this.clientId,
      lastRevision: lastRevision ?? this.lastRevision,
      lastPulledAt: lastPulledAt ?? this.lastPulledAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (lastRevision.present) {
      map['last_revision'] = Variable<int>(lastRevision.value);
    }
    if (lastPulledAt.present) {
      map['last_pulled_at'] = Variable<DateTime>(lastPulledAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStatesCompanion(')
          ..write('workspaceId: $workspaceId, ')
          ..write('clientId: $clientId, ')
          ..write('lastRevision: $lastRevision, ')
          ..write('lastPulledAt: $lastPulledAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AwDatabase extends GeneratedDatabase {
  _$AwDatabase(QueryExecutor e) : super(e);
  $AwDatabaseManager get managers => $AwDatabaseManager(this);
  late final $ProjectsTable projects = $ProjectsTable(this);
  late final $TagsTable tags = $TagsTable(this);
  late final $TasksTable tasks = $TasksTable(this);
  late final $TaskTagRowsTable taskTagRows = $TaskTagRowsTable(this);
  late final $ChecklistItemsTable checklistItems = $ChecklistItemsTable(this);
  late final $NotesTable notes = $NotesTable(this);
  late final $NoteLinkRowsTable noteLinkRows = $NoteLinkRowsTable(this);
  late final $RemindersTable reminders = $RemindersTable(this);
  late final $ExternalEventsTable externalEvents = $ExternalEventsTable(this);
  late final $AppleEventLinksTable appleEventLinks = $AppleEventLinksTable(
    this,
  );
  late final $FileRowsTable fileRows = $FileRowsTable(this);
  late final $FoldersTable folders = $FoldersTable(this);
  late final $QuickLinksTable quickLinks = $QuickLinksTable(this);
  late final $TaskSeriesTable taskSeries = $TaskSeriesTable(this);
  late final $AlarmEventsTable alarmEvents = $AlarmEventsTable(this);
  late final $AiMessagesTable aiMessages = $AiMessagesTable(this);
  late final $ShareEventsTable shareEvents = $ShareEventsTable(this);
  late final $PendingMutationsTable pendingMutations = $PendingMutationsTable(
    this,
  );
  late final $RejectedMutationsTable rejectedMutations =
      $RejectedMutationsTable(this);
  late final $SyncStatesTable syncStates = $SyncStatesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    projects,
    tags,
    tasks,
    taskTagRows,
    checklistItems,
    notes,
    noteLinkRows,
    reminders,
    externalEvents,
    appleEventLinks,
    fileRows,
    folders,
    quickLinks,
    taskSeries,
    alarmEvents,
    aiMessages,
    shareEvents,
    pendingMutations,
    rejectedMutations,
    syncStates,
  ];
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$ProjectsTableCreateCompanionBuilder =
    ProjectsCompanion Function({
      required String id,
      required String workspaceId,
      required String name,
      Value<String?> description,
      Value<String> colorRgb,
      Value<String?> icon,
      Value<String> status,
      Value<DateTime?> startAt,
      Value<DateTime?> dueAt,
      Value<int> sortOrder,
      Value<bool> isFavorite,
      Value<String?> readmeNoteId,
      Value<String?> nameFold,
      Value<String?> descriptionFold,
      Value<int> revision,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$ProjectsTableUpdateCompanionBuilder =
    ProjectsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> name,
      Value<String?> description,
      Value<String> colorRgb,
      Value<String?> icon,
      Value<String> status,
      Value<DateTime?> startAt,
      Value<DateTime?> dueAt,
      Value<int> sortOrder,
      Value<bool> isFavorite,
      Value<String?> readmeNoteId,
      Value<String?> nameFold,
      Value<String?> descriptionFold,
      Value<int> revision,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

class $$ProjectsTableFilterComposer
    extends Composer<_$AwDatabase, $ProjectsTable> {
  $$ProjectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorRgb => $composableBuilder(
    column: $table.colorRgb,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startAt => $composableBuilder(
    column: $table.startAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get readmeNoteId => $composableBuilder(
    column: $table.readmeNoteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameFold => $composableBuilder(
    column: $table.nameFold,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get descriptionFold => $composableBuilder(
    column: $table.descriptionFold,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProjectsTableOrderingComposer
    extends Composer<_$AwDatabase, $ProjectsTable> {
  $$ProjectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorRgb => $composableBuilder(
    column: $table.colorRgb,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startAt => $composableBuilder(
    column: $table.startAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get readmeNoteId => $composableBuilder(
    column: $table.readmeNoteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameFold => $composableBuilder(
    column: $table.nameFold,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get descriptionFold => $composableBuilder(
    column: $table.descriptionFold,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProjectsTableAnnotationComposer
    extends Composer<_$AwDatabase, $ProjectsTable> {
  $$ProjectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get colorRgb =>
      $composableBuilder(column: $table.colorRgb, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get startAt =>
      $composableBuilder(column: $table.startAt, builder: (column) => column);

  GeneratedColumn<DateTime> get dueAt =>
      $composableBuilder(column: $table.dueAt, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  GeneratedColumn<String> get readmeNoteId => $composableBuilder(
    column: $table.readmeNoteId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nameFold =>
      $composableBuilder(column: $table.nameFold, builder: (column) => column);

  GeneratedColumn<String> get descriptionFold => $composableBuilder(
    column: $table.descriptionFold,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ProjectsTableTableManager
    extends
        RootTableManager<
          _$AwDatabase,
          $ProjectsTable,
          ProjectRecord,
          $$ProjectsTableFilterComposer,
          $$ProjectsTableOrderingComposer,
          $$ProjectsTableAnnotationComposer,
          $$ProjectsTableCreateCompanionBuilder,
          $$ProjectsTableUpdateCompanionBuilder,
          (
            ProjectRecord,
            BaseReferences<_$AwDatabase, $ProjectsTable, ProjectRecord>,
          ),
          ProjectRecord,
          PrefetchHooks Function()
        > {
  $$ProjectsTableTableManager(_$AwDatabase db, $ProjectsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> colorRgb = const Value.absent(),
                Value<String?> icon = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime?> startAt = const Value.absent(),
                Value<DateTime?> dueAt = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<String?> readmeNoteId = const Value.absent(),
                Value<String?> nameFold = const Value.absent(),
                Value<String?> descriptionFold = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectsCompanion(
                id: id,
                workspaceId: workspaceId,
                name: name,
                description: description,
                colorRgb: colorRgb,
                icon: icon,
                status: status,
                startAt: startAt,
                dueAt: dueAt,
                sortOrder: sortOrder,
                isFavorite: isFavorite,
                readmeNoteId: readmeNoteId,
                nameFold: nameFold,
                descriptionFold: descriptionFold,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String name,
                Value<String?> description = const Value.absent(),
                Value<String> colorRgb = const Value.absent(),
                Value<String?> icon = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime?> startAt = const Value.absent(),
                Value<DateTime?> dueAt = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<String?> readmeNoteId = const Value.absent(),
                Value<String?> nameFold = const Value.absent(),
                Value<String?> descriptionFold = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                name: name,
                description: description,
                colorRgb: colorRgb,
                icon: icon,
                status: status,
                startAt: startAt,
                dueAt: dueAt,
                sortOrder: sortOrder,
                isFavorite: isFavorite,
                readmeNoteId: readmeNoteId,
                nameFold: nameFold,
                descriptionFold: descriptionFold,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProjectsTableProcessedTableManager =
    ProcessedTableManager<
      _$AwDatabase,
      $ProjectsTable,
      ProjectRecord,
      $$ProjectsTableFilterComposer,
      $$ProjectsTableOrderingComposer,
      $$ProjectsTableAnnotationComposer,
      $$ProjectsTableCreateCompanionBuilder,
      $$ProjectsTableUpdateCompanionBuilder,
      (
        ProjectRecord,
        BaseReferences<_$AwDatabase, $ProjectsTable, ProjectRecord>,
      ),
      ProjectRecord,
      PrefetchHooks Function()
    >;
typedef $$TagsTableCreateCompanionBuilder =
    TagsCompanion Function({
      required String id,
      required String workspaceId,
      required String name,
      required String slug,
      Value<String> colorRgb,
      Value<String?> icon,
      Value<String?> nameFold,
      Value<int> revision,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$TagsTableUpdateCompanionBuilder =
    TagsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> name,
      Value<String> slug,
      Value<String> colorRgb,
      Value<String?> icon,
      Value<String?> nameFold,
      Value<int> revision,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

class $$TagsTableFilterComposer extends Composer<_$AwDatabase, $TagsTable> {
  $$TagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorRgb => $composableBuilder(
    column: $table.colorRgb,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameFold => $composableBuilder(
    column: $table.nameFold,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TagsTableOrderingComposer extends Composer<_$AwDatabase, $TagsTable> {
  $$TagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorRgb => $composableBuilder(
    column: $table.colorRgb,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameFold => $composableBuilder(
    column: $table.nameFold,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TagsTableAnnotationComposer extends Composer<_$AwDatabase, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get slug =>
      $composableBuilder(column: $table.slug, builder: (column) => column);

  GeneratedColumn<String> get colorRgb =>
      $composableBuilder(column: $table.colorRgb, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<String> get nameFold =>
      $composableBuilder(column: $table.nameFold, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$TagsTableTableManager
    extends
        RootTableManager<
          _$AwDatabase,
          $TagsTable,
          TagRecord,
          $$TagsTableFilterComposer,
          $$TagsTableOrderingComposer,
          $$TagsTableAnnotationComposer,
          $$TagsTableCreateCompanionBuilder,
          $$TagsTableUpdateCompanionBuilder,
          (TagRecord, BaseReferences<_$AwDatabase, $TagsTable, TagRecord>),
          TagRecord,
          PrefetchHooks Function()
        > {
  $$TagsTableTableManager(_$AwDatabase db, $TagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> slug = const Value.absent(),
                Value<String> colorRgb = const Value.absent(),
                Value<String?> icon = const Value.absent(),
                Value<String?> nameFold = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion(
                id: id,
                workspaceId: workspaceId,
                name: name,
                slug: slug,
                colorRgb: colorRgb,
                icon: icon,
                nameFold: nameFold,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String name,
                required String slug,
                Value<String> colorRgb = const Value.absent(),
                Value<String?> icon = const Value.absent(),
                Value<String?> nameFold = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                name: name,
                slug: slug,
                colorRgb: colorRgb,
                icon: icon,
                nameFold: nameFold,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AwDatabase,
      $TagsTable,
      TagRecord,
      $$TagsTableFilterComposer,
      $$TagsTableOrderingComposer,
      $$TagsTableAnnotationComposer,
      $$TagsTableCreateCompanionBuilder,
      $$TagsTableUpdateCompanionBuilder,
      (TagRecord, BaseReferences<_$AwDatabase, $TagsTable, TagRecord>),
      TagRecord,
      PrefetchHooks Function()
    >;
typedef $$TasksTableCreateCompanionBuilder =
    TasksCompanion Function({
      required String id,
      required String workspaceId,
      Value<String?> projectId,
      Value<String?> parentTaskId,
      required String title,
      Value<String?> description,
      Value<String> status,
      Value<String> priority,
      Value<String?> colorRgb,
      Value<DateTime?> startAt,
      Value<DateTime?> dueAt,
      Value<DateTime?> scheduledStartAt,
      Value<DateTime?> scheduledEndAt,
      Value<DateTime?> remindAt,
      Value<DateTime?> snoozedUntil,
      Value<DateTime?> alarmsMutedAt,
      Value<String> timezone,
      Value<bool> isUrgent,
      Value<bool> requiresAcknowledgement,
      Value<String?> repeatRule,
      Value<String?> seriesId,
      Value<String?> occurrenceDate,
      Value<int?> estimatedMinutes,
      Value<int?> actualMinutes,
      Value<int> sortOrder,
      Value<bool> calendarMirrorEnabled,
      Value<DateTime?> completedAt,
      Value<String?> titleFold,
      Value<String?> descriptionFold,
      Value<int> revision,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$TasksTableUpdateCompanionBuilder =
    TasksCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String?> projectId,
      Value<String?> parentTaskId,
      Value<String> title,
      Value<String?> description,
      Value<String> status,
      Value<String> priority,
      Value<String?> colorRgb,
      Value<DateTime?> startAt,
      Value<DateTime?> dueAt,
      Value<DateTime?> scheduledStartAt,
      Value<DateTime?> scheduledEndAt,
      Value<DateTime?> remindAt,
      Value<DateTime?> snoozedUntil,
      Value<DateTime?> alarmsMutedAt,
      Value<String> timezone,
      Value<bool> isUrgent,
      Value<bool> requiresAcknowledgement,
      Value<String?> repeatRule,
      Value<String?> seriesId,
      Value<String?> occurrenceDate,
      Value<int?> estimatedMinutes,
      Value<int?> actualMinutes,
      Value<int> sortOrder,
      Value<bool> calendarMirrorEnabled,
      Value<DateTime?> completedAt,
      Value<String?> titleFold,
      Value<String?> descriptionFold,
      Value<int> revision,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

class $$TasksTableFilterComposer extends Composer<_$AwDatabase, $TasksTable> {
  $$TasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentTaskId => $composableBuilder(
    column: $table.parentTaskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorRgb => $composableBuilder(
    column: $table.colorRgb,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startAt => $composableBuilder(
    column: $table.startAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get scheduledStartAt => $composableBuilder(
    column: $table.scheduledStartAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get scheduledEndAt => $composableBuilder(
    column: $table.scheduledEndAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get remindAt => $composableBuilder(
    column: $table.remindAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get snoozedUntil => $composableBuilder(
    column: $table.snoozedUntil,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get alarmsMutedAt => $composableBuilder(
    column: $table.alarmsMutedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isUrgent => $composableBuilder(
    column: $table.isUrgent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get requiresAcknowledgement => $composableBuilder(
    column: $table.requiresAcknowledgement,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get repeatRule => $composableBuilder(
    column: $table.repeatRule,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get occurrenceDate => $composableBuilder(
    column: $table.occurrenceDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get estimatedMinutes => $composableBuilder(
    column: $table.estimatedMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get actualMinutes => $composableBuilder(
    column: $table.actualMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get calendarMirrorEnabled => $composableBuilder(
    column: $table.calendarMirrorEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get titleFold => $composableBuilder(
    column: $table.titleFold,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get descriptionFold => $composableBuilder(
    column: $table.descriptionFold,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TasksTableOrderingComposer extends Composer<_$AwDatabase, $TasksTable> {
  $$TasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentTaskId => $composableBuilder(
    column: $table.parentTaskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorRgb => $composableBuilder(
    column: $table.colorRgb,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startAt => $composableBuilder(
    column: $table.startAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get scheduledStartAt => $composableBuilder(
    column: $table.scheduledStartAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get scheduledEndAt => $composableBuilder(
    column: $table.scheduledEndAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get remindAt => $composableBuilder(
    column: $table.remindAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get snoozedUntil => $composableBuilder(
    column: $table.snoozedUntil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get alarmsMutedAt => $composableBuilder(
    column: $table.alarmsMutedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isUrgent => $composableBuilder(
    column: $table.isUrgent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get requiresAcknowledgement => $composableBuilder(
    column: $table.requiresAcknowledgement,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get repeatRule => $composableBuilder(
    column: $table.repeatRule,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get occurrenceDate => $composableBuilder(
    column: $table.occurrenceDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get estimatedMinutes => $composableBuilder(
    column: $table.estimatedMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get actualMinutes => $composableBuilder(
    column: $table.actualMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get calendarMirrorEnabled => $composableBuilder(
    column: $table.calendarMirrorEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get titleFold => $composableBuilder(
    column: $table.titleFold,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get descriptionFold => $composableBuilder(
    column: $table.descriptionFold,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TasksTableAnnotationComposer
    extends Composer<_$AwDatabase, $TasksTable> {
  $$TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

  GeneratedColumn<String> get parentTaskId => $composableBuilder(
    column: $table.parentTaskId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<String> get colorRgb =>
      $composableBuilder(column: $table.colorRgb, builder: (column) => column);

  GeneratedColumn<DateTime> get startAt =>
      $composableBuilder(column: $table.startAt, builder: (column) => column);

  GeneratedColumn<DateTime> get dueAt =>
      $composableBuilder(column: $table.dueAt, builder: (column) => column);

  GeneratedColumn<DateTime> get scheduledStartAt => $composableBuilder(
    column: $table.scheduledStartAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get scheduledEndAt => $composableBuilder(
    column: $table.scheduledEndAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get remindAt =>
      $composableBuilder(column: $table.remindAt, builder: (column) => column);

  GeneratedColumn<DateTime> get snoozedUntil => $composableBuilder(
    column: $table.snoozedUntil,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get alarmsMutedAt => $composableBuilder(
    column: $table.alarmsMutedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get timezone =>
      $composableBuilder(column: $table.timezone, builder: (column) => column);

  GeneratedColumn<bool> get isUrgent =>
      $composableBuilder(column: $table.isUrgent, builder: (column) => column);

  GeneratedColumn<bool> get requiresAcknowledgement => $composableBuilder(
    column: $table.requiresAcknowledgement,
    builder: (column) => column,
  );

  GeneratedColumn<String> get repeatRule => $composableBuilder(
    column: $table.repeatRule,
    builder: (column) => column,
  );

  GeneratedColumn<String> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<String> get occurrenceDate => $composableBuilder(
    column: $table.occurrenceDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get estimatedMinutes => $composableBuilder(
    column: $table.estimatedMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get actualMinutes => $composableBuilder(
    column: $table.actualMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<bool> get calendarMirrorEnabled => $composableBuilder(
    column: $table.calendarMirrorEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get titleFold =>
      $composableBuilder(column: $table.titleFold, builder: (column) => column);

  GeneratedColumn<String> get descriptionFold => $composableBuilder(
    column: $table.descriptionFold,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$TasksTableTableManager
    extends
        RootTableManager<
          _$AwDatabase,
          $TasksTable,
          TaskRecord,
          $$TasksTableFilterComposer,
          $$TasksTableOrderingComposer,
          $$TasksTableAnnotationComposer,
          $$TasksTableCreateCompanionBuilder,
          $$TasksTableUpdateCompanionBuilder,
          (TaskRecord, BaseReferences<_$AwDatabase, $TasksTable, TaskRecord>),
          TaskRecord,
          PrefetchHooks Function()
        > {
  $$TasksTableTableManager(_$AwDatabase db, $TasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String?> projectId = const Value.absent(),
                Value<String?> parentTaskId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> priority = const Value.absent(),
                Value<String?> colorRgb = const Value.absent(),
                Value<DateTime?> startAt = const Value.absent(),
                Value<DateTime?> dueAt = const Value.absent(),
                Value<DateTime?> scheduledStartAt = const Value.absent(),
                Value<DateTime?> scheduledEndAt = const Value.absent(),
                Value<DateTime?> remindAt = const Value.absent(),
                Value<DateTime?> snoozedUntil = const Value.absent(),
                Value<DateTime?> alarmsMutedAt = const Value.absent(),
                Value<String> timezone = const Value.absent(),
                Value<bool> isUrgent = const Value.absent(),
                Value<bool> requiresAcknowledgement = const Value.absent(),
                Value<String?> repeatRule = const Value.absent(),
                Value<String?> seriesId = const Value.absent(),
                Value<String?> occurrenceDate = const Value.absent(),
                Value<int?> estimatedMinutes = const Value.absent(),
                Value<int?> actualMinutes = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> calendarMirrorEnabled = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<String?> titleFold = const Value.absent(),
                Value<String?> descriptionFold = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion(
                id: id,
                workspaceId: workspaceId,
                projectId: projectId,
                parentTaskId: parentTaskId,
                title: title,
                description: description,
                status: status,
                priority: priority,
                colorRgb: colorRgb,
                startAt: startAt,
                dueAt: dueAt,
                scheduledStartAt: scheduledStartAt,
                scheduledEndAt: scheduledEndAt,
                remindAt: remindAt,
                snoozedUntil: snoozedUntil,
                alarmsMutedAt: alarmsMutedAt,
                timezone: timezone,
                isUrgent: isUrgent,
                requiresAcknowledgement: requiresAcknowledgement,
                repeatRule: repeatRule,
                seriesId: seriesId,
                occurrenceDate: occurrenceDate,
                estimatedMinutes: estimatedMinutes,
                actualMinutes: actualMinutes,
                sortOrder: sortOrder,
                calendarMirrorEnabled: calendarMirrorEnabled,
                completedAt: completedAt,
                titleFold: titleFold,
                descriptionFold: descriptionFold,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                Value<String?> projectId = const Value.absent(),
                Value<String?> parentTaskId = const Value.absent(),
                required String title,
                Value<String?> description = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> priority = const Value.absent(),
                Value<String?> colorRgb = const Value.absent(),
                Value<DateTime?> startAt = const Value.absent(),
                Value<DateTime?> dueAt = const Value.absent(),
                Value<DateTime?> scheduledStartAt = const Value.absent(),
                Value<DateTime?> scheduledEndAt = const Value.absent(),
                Value<DateTime?> remindAt = const Value.absent(),
                Value<DateTime?> snoozedUntil = const Value.absent(),
                Value<DateTime?> alarmsMutedAt = const Value.absent(),
                Value<String> timezone = const Value.absent(),
                Value<bool> isUrgent = const Value.absent(),
                Value<bool> requiresAcknowledgement = const Value.absent(),
                Value<String?> repeatRule = const Value.absent(),
                Value<String?> seriesId = const Value.absent(),
                Value<String?> occurrenceDate = const Value.absent(),
                Value<int?> estimatedMinutes = const Value.absent(),
                Value<int?> actualMinutes = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> calendarMirrorEnabled = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<String?> titleFold = const Value.absent(),
                Value<String?> descriptionFold = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                projectId: projectId,
                parentTaskId: parentTaskId,
                title: title,
                description: description,
                status: status,
                priority: priority,
                colorRgb: colorRgb,
                startAt: startAt,
                dueAt: dueAt,
                scheduledStartAt: scheduledStartAt,
                scheduledEndAt: scheduledEndAt,
                remindAt: remindAt,
                snoozedUntil: snoozedUntil,
                alarmsMutedAt: alarmsMutedAt,
                timezone: timezone,
                isUrgent: isUrgent,
                requiresAcknowledgement: requiresAcknowledgement,
                repeatRule: repeatRule,
                seriesId: seriesId,
                occurrenceDate: occurrenceDate,
                estimatedMinutes: estimatedMinutes,
                actualMinutes: actualMinutes,
                sortOrder: sortOrder,
                calendarMirrorEnabled: calendarMirrorEnabled,
                completedAt: completedAt,
                titleFold: titleFold,
                descriptionFold: descriptionFold,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AwDatabase,
      $TasksTable,
      TaskRecord,
      $$TasksTableFilterComposer,
      $$TasksTableOrderingComposer,
      $$TasksTableAnnotationComposer,
      $$TasksTableCreateCompanionBuilder,
      $$TasksTableUpdateCompanionBuilder,
      (TaskRecord, BaseReferences<_$AwDatabase, $TasksTable, TaskRecord>),
      TaskRecord,
      PrefetchHooks Function()
    >;
typedef $$TaskTagRowsTableCreateCompanionBuilder =
    TaskTagRowsCompanion Function({
      required String taskId,
      required String tagId,
      Value<int> rowid,
    });
typedef $$TaskTagRowsTableUpdateCompanionBuilder =
    TaskTagRowsCompanion Function({
      Value<String> taskId,
      Value<String> tagId,
      Value<int> rowid,
    });

class $$TaskTagRowsTableFilterComposer
    extends Composer<_$AwDatabase, $TaskTagRowsTable> {
  $$TaskTagRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TaskTagRowsTableOrderingComposer
    extends Composer<_$AwDatabase, $TaskTagRowsTable> {
  $$TaskTagRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TaskTagRowsTableAnnotationComposer
    extends Composer<_$AwDatabase, $TaskTagRowsTable> {
  $$TaskTagRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get tagId =>
      $composableBuilder(column: $table.tagId, builder: (column) => column);
}

class $$TaskTagRowsTableTableManager
    extends
        RootTableManager<
          _$AwDatabase,
          $TaskTagRowsTable,
          TaskTagRow,
          $$TaskTagRowsTableFilterComposer,
          $$TaskTagRowsTableOrderingComposer,
          $$TaskTagRowsTableAnnotationComposer,
          $$TaskTagRowsTableCreateCompanionBuilder,
          $$TaskTagRowsTableUpdateCompanionBuilder,
          (
            TaskTagRow,
            BaseReferences<_$AwDatabase, $TaskTagRowsTable, TaskTagRow>,
          ),
          TaskTagRow,
          PrefetchHooks Function()
        > {
  $$TaskTagRowsTableTableManager(_$AwDatabase db, $TaskTagRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskTagRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskTagRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskTagRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> taskId = const Value.absent(),
                Value<String> tagId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskTagRowsCompanion(
                taskId: taskId,
                tagId: tagId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String taskId,
                required String tagId,
                Value<int> rowid = const Value.absent(),
              }) => TaskTagRowsCompanion.insert(
                taskId: taskId,
                tagId: tagId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TaskTagRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AwDatabase,
      $TaskTagRowsTable,
      TaskTagRow,
      $$TaskTagRowsTableFilterComposer,
      $$TaskTagRowsTableOrderingComposer,
      $$TaskTagRowsTableAnnotationComposer,
      $$TaskTagRowsTableCreateCompanionBuilder,
      $$TaskTagRowsTableUpdateCompanionBuilder,
      (TaskTagRow, BaseReferences<_$AwDatabase, $TaskTagRowsTable, TaskTagRow>),
      TaskTagRow,
      PrefetchHooks Function()
    >;
typedef $$ChecklistItemsTableCreateCompanionBuilder =
    ChecklistItemsCompanion Function({
      required String id,
      required String taskId,
      required String title,
      Value<bool> isDone,
      Value<int> sortOrder,
      Value<int> revision,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$ChecklistItemsTableUpdateCompanionBuilder =
    ChecklistItemsCompanion Function({
      Value<String> id,
      Value<String> taskId,
      Value<String> title,
      Value<bool> isDone,
      Value<int> sortOrder,
      Value<int> revision,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

class $$ChecklistItemsTableFilterComposer
    extends Composer<_$AwDatabase, $ChecklistItemsTable> {
  $$ChecklistItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDone => $composableBuilder(
    column: $table.isDone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChecklistItemsTableOrderingComposer
    extends Composer<_$AwDatabase, $ChecklistItemsTable> {
  $$ChecklistItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDone => $composableBuilder(
    column: $table.isDone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChecklistItemsTableAnnotationComposer
    extends Composer<_$AwDatabase, $ChecklistItemsTable> {
  $$ChecklistItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<bool> get isDone =>
      $composableBuilder(column: $table.isDone, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ChecklistItemsTableTableManager
    extends
        RootTableManager<
          _$AwDatabase,
          $ChecklistItemsTable,
          ChecklistItemRecord,
          $$ChecklistItemsTableFilterComposer,
          $$ChecklistItemsTableOrderingComposer,
          $$ChecklistItemsTableAnnotationComposer,
          $$ChecklistItemsTableCreateCompanionBuilder,
          $$ChecklistItemsTableUpdateCompanionBuilder,
          (
            ChecklistItemRecord,
            BaseReferences<
              _$AwDatabase,
              $ChecklistItemsTable,
              ChecklistItemRecord
            >,
          ),
          ChecklistItemRecord,
          PrefetchHooks Function()
        > {
  $$ChecklistItemsTableTableManager(_$AwDatabase db, $ChecklistItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChecklistItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChecklistItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChecklistItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> taskId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<bool> isDone = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChecklistItemsCompanion(
                id: id,
                taskId: taskId,
                title: title,
                isDone: isDone,
                sortOrder: sortOrder,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String taskId,
                required String title,
                Value<bool> isDone = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChecklistItemsCompanion.insert(
                id: id,
                taskId: taskId,
                title: title,
                isDone: isDone,
                sortOrder: sortOrder,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChecklistItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AwDatabase,
      $ChecklistItemsTable,
      ChecklistItemRecord,
      $$ChecklistItemsTableFilterComposer,
      $$ChecklistItemsTableOrderingComposer,
      $$ChecklistItemsTableAnnotationComposer,
      $$ChecklistItemsTableCreateCompanionBuilder,
      $$ChecklistItemsTableUpdateCompanionBuilder,
      (
        ChecklistItemRecord,
        BaseReferences<_$AwDatabase, $ChecklistItemsTable, ChecklistItemRecord>,
      ),
      ChecklistItemRecord,
      PrefetchHooks Function()
    >;
typedef $$NotesTableCreateCompanionBuilder =
    NotesCompanion Function({
      required String id,
      required String workspaceId,
      Value<String?> projectId,
      Value<String?> createdFromTaskId,
      required String title,
      Value<String?> contentDelta,
      Value<String?> contentMarkdown,
      Value<String> contentFormat,
      Value<String?> plainText,
      Value<bool> isPinned,
      Value<bool> isArchived,
      Value<String?> titleFold,
      Value<String?> bodyFold,
      Value<int> revision,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<String?> conflictVersionId,
      Value<int> rowid,
    });
typedef $$NotesTableUpdateCompanionBuilder =
    NotesCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String?> projectId,
      Value<String?> createdFromTaskId,
      Value<String> title,
      Value<String?> contentDelta,
      Value<String?> contentMarkdown,
      Value<String> contentFormat,
      Value<String?> plainText,
      Value<bool> isPinned,
      Value<bool> isArchived,
      Value<String?> titleFold,
      Value<String?> bodyFold,
      Value<int> revision,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<String?> conflictVersionId,
      Value<int> rowid,
    });

class $$NotesTableFilterComposer extends Composer<_$AwDatabase, $NotesTable> {
  $$NotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdFromTaskId => $composableBuilder(
    column: $table.createdFromTaskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentDelta => $composableBuilder(
    column: $table.contentDelta,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentMarkdown => $composableBuilder(
    column: $table.contentMarkdown,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentFormat => $composableBuilder(
    column: $table.contentFormat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plainText => $composableBuilder(
    column: $table.plainText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get titleFold => $composableBuilder(
    column: $table.titleFold,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bodyFold => $composableBuilder(
    column: $table.bodyFold,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conflictVersionId => $composableBuilder(
    column: $table.conflictVersionId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NotesTableOrderingComposer extends Composer<_$AwDatabase, $NotesTable> {
  $$NotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdFromTaskId => $composableBuilder(
    column: $table.createdFromTaskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentDelta => $composableBuilder(
    column: $table.contentDelta,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentMarkdown => $composableBuilder(
    column: $table.contentMarkdown,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentFormat => $composableBuilder(
    column: $table.contentFormat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plainText => $composableBuilder(
    column: $table.plainText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get titleFold => $composableBuilder(
    column: $table.titleFold,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bodyFold => $composableBuilder(
    column: $table.bodyFold,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conflictVersionId => $composableBuilder(
    column: $table.conflictVersionId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotesTableAnnotationComposer
    extends Composer<_$AwDatabase, $NotesTable> {
  $$NotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

  GeneratedColumn<String> get createdFromTaskId => $composableBuilder(
    column: $table.createdFromTaskId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get contentDelta => $composableBuilder(
    column: $table.contentDelta,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentMarkdown => $composableBuilder(
    column: $table.contentMarkdown,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentFormat => $composableBuilder(
    column: $table.contentFormat,
    builder: (column) => column,
  );

  GeneratedColumn<String> get plainText =>
      $composableBuilder(column: $table.plainText, builder: (column) => column);

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => column,
  );

  GeneratedColumn<String> get titleFold =>
      $composableBuilder(column: $table.titleFold, builder: (column) => column);

  GeneratedColumn<String> get bodyFold =>
      $composableBuilder(column: $table.bodyFold, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get conflictVersionId => $composableBuilder(
    column: $table.conflictVersionId,
    builder: (column) => column,
  );
}

class $$NotesTableTableManager
    extends
        RootTableManager<
          _$AwDatabase,
          $NotesTable,
          NoteRecord,
          $$NotesTableFilterComposer,
          $$NotesTableOrderingComposer,
          $$NotesTableAnnotationComposer,
          $$NotesTableCreateCompanionBuilder,
          $$NotesTableUpdateCompanionBuilder,
          (NoteRecord, BaseReferences<_$AwDatabase, $NotesTable, NoteRecord>),
          NoteRecord,
          PrefetchHooks Function()
        > {
  $$NotesTableTableManager(_$AwDatabase db, $NotesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String?> projectId = const Value.absent(),
                Value<String?> createdFromTaskId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> contentDelta = const Value.absent(),
                Value<String?> contentMarkdown = const Value.absent(),
                Value<String> contentFormat = const Value.absent(),
                Value<String?> plainText = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<String?> titleFold = const Value.absent(),
                Value<String?> bodyFold = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<String?> conflictVersionId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotesCompanion(
                id: id,
                workspaceId: workspaceId,
                projectId: projectId,
                createdFromTaskId: createdFromTaskId,
                title: title,
                contentDelta: contentDelta,
                contentMarkdown: contentMarkdown,
                contentFormat: contentFormat,
                plainText: plainText,
                isPinned: isPinned,
                isArchived: isArchived,
                titleFold: titleFold,
                bodyFold: bodyFold,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                conflictVersionId: conflictVersionId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                Value<String?> projectId = const Value.absent(),
                Value<String?> createdFromTaskId = const Value.absent(),
                required String title,
                Value<String?> contentDelta = const Value.absent(),
                Value<String?> contentMarkdown = const Value.absent(),
                Value<String> contentFormat = const Value.absent(),
                Value<String?> plainText = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<String?> titleFold = const Value.absent(),
                Value<String?> bodyFold = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<String?> conflictVersionId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotesCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                projectId: projectId,
                createdFromTaskId: createdFromTaskId,
                title: title,
                contentDelta: contentDelta,
                contentMarkdown: contentMarkdown,
                contentFormat: contentFormat,
                plainText: plainText,
                isPinned: isPinned,
                isArchived: isArchived,
                titleFold: titleFold,
                bodyFold: bodyFold,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                conflictVersionId: conflictVersionId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NotesTableProcessedTableManager =
    ProcessedTableManager<
      _$AwDatabase,
      $NotesTable,
      NoteRecord,
      $$NotesTableFilterComposer,
      $$NotesTableOrderingComposer,
      $$NotesTableAnnotationComposer,
      $$NotesTableCreateCompanionBuilder,
      $$NotesTableUpdateCompanionBuilder,
      (NoteRecord, BaseReferences<_$AwDatabase, $NotesTable, NoteRecord>),
      NoteRecord,
      PrefetchHooks Function()
    >;
typedef $$NoteLinkRowsTableCreateCompanionBuilder =
    NoteLinkRowsCompanion Function({
      required String id,
      required String noteId,
      required String entityType,
      required String entityId,
      Value<int> rowid,
    });
typedef $$NoteLinkRowsTableUpdateCompanionBuilder =
    NoteLinkRowsCompanion Function({
      Value<String> id,
      Value<String> noteId,
      Value<String> entityType,
      Value<String> entityId,
      Value<int> rowid,
    });

class $$NoteLinkRowsTableFilterComposer
    extends Composer<_$AwDatabase, $NoteLinkRowsTable> {
  $$NoteLinkRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NoteLinkRowsTableOrderingComposer
    extends Composer<_$AwDatabase, $NoteLinkRowsTable> {
  $$NoteLinkRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NoteLinkRowsTableAnnotationComposer
    extends Composer<_$AwDatabase, $NoteLinkRowsTable> {
  $$NoteLinkRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);
}

class $$NoteLinkRowsTableTableManager
    extends
        RootTableManager<
          _$AwDatabase,
          $NoteLinkRowsTable,
          NoteLinkRow,
          $$NoteLinkRowsTableFilterComposer,
          $$NoteLinkRowsTableOrderingComposer,
          $$NoteLinkRowsTableAnnotationComposer,
          $$NoteLinkRowsTableCreateCompanionBuilder,
          $$NoteLinkRowsTableUpdateCompanionBuilder,
          (
            NoteLinkRow,
            BaseReferences<_$AwDatabase, $NoteLinkRowsTable, NoteLinkRow>,
          ),
          NoteLinkRow,
          PrefetchHooks Function()
        > {
  $$NoteLinkRowsTableTableManager(_$AwDatabase db, $NoteLinkRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteLinkRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteLinkRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteLinkRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> noteId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteLinkRowsCompanion(
                id: id,
                noteId: noteId,
                entityType: entityType,
                entityId: entityId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String noteId,
                required String entityType,
                required String entityId,
                Value<int> rowid = const Value.absent(),
              }) => NoteLinkRowsCompanion.insert(
                id: id,
                noteId: noteId,
                entityType: entityType,
                entityId: entityId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NoteLinkRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AwDatabase,
      $NoteLinkRowsTable,
      NoteLinkRow,
      $$NoteLinkRowsTableFilterComposer,
      $$NoteLinkRowsTableOrderingComposer,
      $$NoteLinkRowsTableAnnotationComposer,
      $$NoteLinkRowsTableCreateCompanionBuilder,
      $$NoteLinkRowsTableUpdateCompanionBuilder,
      (
        NoteLinkRow,
        BaseReferences<_$AwDatabase, $NoteLinkRowsTable, NoteLinkRow>,
      ),
      NoteLinkRow,
      PrefetchHooks Function()
    >;
typedef $$RemindersTableCreateCompanionBuilder =
    RemindersCompanion Function({
      required String id,
      required String taskId,
      Value<String> kind,
      Value<int> snoozeCount,
      required DateTime remindAt,
      Value<String> timezone,
      Value<String> alarmLevel,
      Value<bool> requiresAcknowledgement,
      Value<String?> repeatRule,
      Value<String> status,
      Value<DateTime?> snoozedUntil,
      Value<DateTime?> deliveredAt,
      Value<DateTime?> acknowledgedAt,
      Value<int> revision,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$RemindersTableUpdateCompanionBuilder =
    RemindersCompanion Function({
      Value<String> id,
      Value<String> taskId,
      Value<String> kind,
      Value<int> snoozeCount,
      Value<DateTime> remindAt,
      Value<String> timezone,
      Value<String> alarmLevel,
      Value<bool> requiresAcknowledgement,
      Value<String?> repeatRule,
      Value<String> status,
      Value<DateTime?> snoozedUntil,
      Value<DateTime?> deliveredAt,
      Value<DateTime?> acknowledgedAt,
      Value<int> revision,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

class $$RemindersTableFilterComposer
    extends Composer<_$AwDatabase, $RemindersTable> {
  $$RemindersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get snoozeCount => $composableBuilder(
    column: $table.snoozeCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get remindAt => $composableBuilder(
    column: $table.remindAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get alarmLevel => $composableBuilder(
    column: $table.alarmLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get requiresAcknowledgement => $composableBuilder(
    column: $table.requiresAcknowledgement,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get repeatRule => $composableBuilder(
    column: $table.repeatRule,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get snoozedUntil => $composableBuilder(
    column: $table.snoozedUntil,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get acknowledgedAt => $composableBuilder(
    column: $table.acknowledgedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RemindersTableOrderingComposer
    extends Composer<_$AwDatabase, $RemindersTable> {
  $$RemindersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get snoozeCount => $composableBuilder(
    column: $table.snoozeCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get remindAt => $composableBuilder(
    column: $table.remindAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get alarmLevel => $composableBuilder(
    column: $table.alarmLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get requiresAcknowledgement => $composableBuilder(
    column: $table.requiresAcknowledgement,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get repeatRule => $composableBuilder(
    column: $table.repeatRule,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get snoozedUntil => $composableBuilder(
    column: $table.snoozedUntil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get acknowledgedAt => $composableBuilder(
    column: $table.acknowledgedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RemindersTableAnnotationComposer
    extends Composer<_$AwDatabase, $RemindersTable> {
  $$RemindersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get snoozeCount => $composableBuilder(
    column: $table.snoozeCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get remindAt =>
      $composableBuilder(column: $table.remindAt, builder: (column) => column);

  GeneratedColumn<String> get timezone =>
      $composableBuilder(column: $table.timezone, builder: (column) => column);

  GeneratedColumn<String> get alarmLevel => $composableBuilder(
    column: $table.alarmLevel,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get requiresAcknowledgement => $composableBuilder(
    column: $table.requiresAcknowledgement,
    builder: (column) => column,
  );

  GeneratedColumn<String> get repeatRule => $composableBuilder(
    column: $table.repeatRule,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get snoozedUntil => $composableBuilder(
    column: $table.snoozedUntil,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get acknowledgedAt => $composableBuilder(
    column: $table.acknowledgedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$RemindersTableTableManager
    extends
        RootTableManager<
          _$AwDatabase,
          $RemindersTable,
          Reminder,
          $$RemindersTableFilterComposer,
          $$RemindersTableOrderingComposer,
          $$RemindersTableAnnotationComposer,
          $$RemindersTableCreateCompanionBuilder,
          $$RemindersTableUpdateCompanionBuilder,
          (Reminder, BaseReferences<_$AwDatabase, $RemindersTable, Reminder>),
          Reminder,
          PrefetchHooks Function()
        > {
  $$RemindersTableTableManager(_$AwDatabase db, $RemindersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RemindersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RemindersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RemindersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> taskId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> snoozeCount = const Value.absent(),
                Value<DateTime> remindAt = const Value.absent(),
                Value<String> timezone = const Value.absent(),
                Value<String> alarmLevel = const Value.absent(),
                Value<bool> requiresAcknowledgement = const Value.absent(),
                Value<String?> repeatRule = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime?> snoozedUntil = const Value.absent(),
                Value<DateTime?> deliveredAt = const Value.absent(),
                Value<DateTime?> acknowledgedAt = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RemindersCompanion(
                id: id,
                taskId: taskId,
                kind: kind,
                snoozeCount: snoozeCount,
                remindAt: remindAt,
                timezone: timezone,
                alarmLevel: alarmLevel,
                requiresAcknowledgement: requiresAcknowledgement,
                repeatRule: repeatRule,
                status: status,
                snoozedUntil: snoozedUntil,
                deliveredAt: deliveredAt,
                acknowledgedAt: acknowledgedAt,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String taskId,
                Value<String> kind = const Value.absent(),
                Value<int> snoozeCount = const Value.absent(),
                required DateTime remindAt,
                Value<String> timezone = const Value.absent(),
                Value<String> alarmLevel = const Value.absent(),
                Value<bool> requiresAcknowledgement = const Value.absent(),
                Value<String?> repeatRule = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime?> snoozedUntil = const Value.absent(),
                Value<DateTime?> deliveredAt = const Value.absent(),
                Value<DateTime?> acknowledgedAt = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RemindersCompanion.insert(
                id: id,
                taskId: taskId,
                kind: kind,
                snoozeCount: snoozeCount,
                remindAt: remindAt,
                timezone: timezone,
                alarmLevel: alarmLevel,
                requiresAcknowledgement: requiresAcknowledgement,
                repeatRule: repeatRule,
                status: status,
                snoozedUntil: snoozedUntil,
                deliveredAt: deliveredAt,
                acknowledgedAt: acknowledgedAt,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RemindersTableProcessedTableManager =
    ProcessedTableManager<
      _$AwDatabase,
      $RemindersTable,
      Reminder,
      $$RemindersTableFilterComposer,
      $$RemindersTableOrderingComposer,
      $$RemindersTableAnnotationComposer,
      $$RemindersTableCreateCompanionBuilder,
      $$RemindersTableUpdateCompanionBuilder,
      (Reminder, BaseReferences<_$AwDatabase, $RemindersTable, Reminder>),
      Reminder,
      PrefetchHooks Function()
    >;
typedef $$ExternalEventsTableCreateCompanionBuilder =
    ExternalEventsCompanion Function({
      required String id,
      required String workspaceId,
      Value<String?> summary,
      Value<String?> location,
      required DateTime startsAt,
      required DateTime endsAt,
      Value<bool> isAllDay,
      Value<bool> isBusy,
      Value<String?> htmlLink,
      Value<String?> summaryFold,
      Value<String?> locationFold,
      Value<int> revision,
      Value<int> rowid,
    });
typedef $$ExternalEventsTableUpdateCompanionBuilder =
    ExternalEventsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String?> summary,
      Value<String?> location,
      Value<DateTime> startsAt,
      Value<DateTime> endsAt,
      Value<bool> isAllDay,
      Value<bool> isBusy,
      Value<String?> htmlLink,
      Value<String?> summaryFold,
      Value<String?> locationFold,
      Value<int> revision,
      Value<int> rowid,
    });

class $$ExternalEventsTableFilterComposer
    extends Composer<_$AwDatabase, $ExternalEventsTable> {
  $$ExternalEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startsAt => $composableBuilder(
    column: $table.startsAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endsAt => $composableBuilder(
    column: $table.endsAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isAllDay => $composableBuilder(
    column: $table.isAllDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isBusy => $composableBuilder(
    column: $table.isBusy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get htmlLink => $composableBuilder(
    column: $table.htmlLink,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summaryFold => $composableBuilder(
    column: $table.summaryFold,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locationFold => $composableBuilder(
    column: $table.locationFold,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ExternalEventsTableOrderingComposer
    extends Composer<_$AwDatabase, $ExternalEventsTable> {
  $$ExternalEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startsAt => $composableBuilder(
    column: $table.startsAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endsAt => $composableBuilder(
    column: $table.endsAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isAllDay => $composableBuilder(
    column: $table.isAllDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isBusy => $composableBuilder(
    column: $table.isBusy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get htmlLink => $composableBuilder(
    column: $table.htmlLink,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summaryFold => $composableBuilder(
    column: $table.summaryFold,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locationFold => $composableBuilder(
    column: $table.locationFold,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ExternalEventsTableAnnotationComposer
    extends Composer<_$AwDatabase, $ExternalEventsTable> {
  $$ExternalEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<DateTime> get startsAt =>
      $composableBuilder(column: $table.startsAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endsAt =>
      $composableBuilder(column: $table.endsAt, builder: (column) => column);

  GeneratedColumn<bool> get isAllDay =>
      $composableBuilder(column: $table.isAllDay, builder: (column) => column);

  GeneratedColumn<bool> get isBusy =>
      $composableBuilder(column: $table.isBusy, builder: (column) => column);

  GeneratedColumn<String> get htmlLink =>
      $composableBuilder(column: $table.htmlLink, builder: (column) => column);

  GeneratedColumn<String> get summaryFold => $composableBuilder(
    column: $table.summaryFold,
    builder: (column) => column,
  );

  GeneratedColumn<String> get locationFold => $composableBuilder(
    column: $table.locationFold,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);
}

class $$ExternalEventsTableTableManager
    extends
        RootTableManager<
          _$AwDatabase,
          $ExternalEventsTable,
          ExternalEventRecord,
          $$ExternalEventsTableFilterComposer,
          $$ExternalEventsTableOrderingComposer,
          $$ExternalEventsTableAnnotationComposer,
          $$ExternalEventsTableCreateCompanionBuilder,
          $$ExternalEventsTableUpdateCompanionBuilder,
          (
            ExternalEventRecord,
            BaseReferences<
              _$AwDatabase,
              $ExternalEventsTable,
              ExternalEventRecord
            >,
          ),
          ExternalEventRecord,
          PrefetchHooks Function()
        > {
  $$ExternalEventsTableTableManager(_$AwDatabase db, $ExternalEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExternalEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExternalEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExternalEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String?> summary = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<DateTime> startsAt = const Value.absent(),
                Value<DateTime> endsAt = const Value.absent(),
                Value<bool> isAllDay = const Value.absent(),
                Value<bool> isBusy = const Value.absent(),
                Value<String?> htmlLink = const Value.absent(),
                Value<String?> summaryFold = const Value.absent(),
                Value<String?> locationFold = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExternalEventsCompanion(
                id: id,
                workspaceId: workspaceId,
                summary: summary,
                location: location,
                startsAt: startsAt,
                endsAt: endsAt,
                isAllDay: isAllDay,
                isBusy: isBusy,
                htmlLink: htmlLink,
                summaryFold: summaryFold,
                locationFold: locationFold,
                revision: revision,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                Value<String?> summary = const Value.absent(),
                Value<String?> location = const Value.absent(),
                required DateTime startsAt,
                required DateTime endsAt,
                Value<bool> isAllDay = const Value.absent(),
                Value<bool> isBusy = const Value.absent(),
                Value<String?> htmlLink = const Value.absent(),
                Value<String?> summaryFold = const Value.absent(),
                Value<String?> locationFold = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExternalEventsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                summary: summary,
                location: location,
                startsAt: startsAt,
                endsAt: endsAt,
                isAllDay: isAllDay,
                isBusy: isBusy,
                htmlLink: htmlLink,
                summaryFold: summaryFold,
                locationFold: locationFold,
                revision: revision,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ExternalEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AwDatabase,
      $ExternalEventsTable,
      ExternalEventRecord,
      $$ExternalEventsTableFilterComposer,
      $$ExternalEventsTableOrderingComposer,
      $$ExternalEventsTableAnnotationComposer,
      $$ExternalEventsTableCreateCompanionBuilder,
      $$ExternalEventsTableUpdateCompanionBuilder,
      (
        ExternalEventRecord,
        BaseReferences<_$AwDatabase, $ExternalEventsTable, ExternalEventRecord>,
      ),
      ExternalEventRecord,
      PrefetchHooks Function()
    >;
typedef $$AppleEventLinksTableCreateCompanionBuilder =
    AppleEventLinksCompanion Function({
      required String taskId,
      required String calendarId,
      required String eventId,
      required String signature,
      Value<int> rowid,
    });
typedef $$AppleEventLinksTableUpdateCompanionBuilder =
    AppleEventLinksCompanion Function({
      Value<String> taskId,
      Value<String> calendarId,
      Value<String> eventId,
      Value<String> signature,
      Value<int> rowid,
    });

class $$AppleEventLinksTableFilterComposer
    extends Composer<_$AwDatabase, $AppleEventLinksTable> {
  $$AppleEventLinksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get calendarId => $composableBuilder(
    column: $table.calendarId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get signature => $composableBuilder(
    column: $table.signature,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppleEventLinksTableOrderingComposer
    extends Composer<_$AwDatabase, $AppleEventLinksTable> {
  $$AppleEventLinksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get calendarId => $composableBuilder(
    column: $table.calendarId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get signature => $composableBuilder(
    column: $table.signature,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppleEventLinksTableAnnotationComposer
    extends Composer<_$AwDatabase, $AppleEventLinksTable> {
  $$AppleEventLinksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get calendarId => $composableBuilder(
    column: $table.calendarId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get signature =>
      $composableBuilder(column: $table.signature, builder: (column) => column);
}

class $$AppleEventLinksTableTableManager
    extends
        RootTableManager<
          _$AwDatabase,
          $AppleEventLinksTable,
          AppleEventLinkRow,
          $$AppleEventLinksTableFilterComposer,
          $$AppleEventLinksTableOrderingComposer,
          $$AppleEventLinksTableAnnotationComposer,
          $$AppleEventLinksTableCreateCompanionBuilder,
          $$AppleEventLinksTableUpdateCompanionBuilder,
          (
            AppleEventLinkRow,
            BaseReferences<
              _$AwDatabase,
              $AppleEventLinksTable,
              AppleEventLinkRow
            >,
          ),
          AppleEventLinkRow,
          PrefetchHooks Function()
        > {
  $$AppleEventLinksTableTableManager(
    _$AwDatabase db,
    $AppleEventLinksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppleEventLinksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppleEventLinksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppleEventLinksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> taskId = const Value.absent(),
                Value<String> calendarId = const Value.absent(),
                Value<String> eventId = const Value.absent(),
                Value<String> signature = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppleEventLinksCompanion(
                taskId: taskId,
                calendarId: calendarId,
                eventId: eventId,
                signature: signature,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String taskId,
                required String calendarId,
                required String eventId,
                required String signature,
                Value<int> rowid = const Value.absent(),
              }) => AppleEventLinksCompanion.insert(
                taskId: taskId,
                calendarId: calendarId,
                eventId: eventId,
                signature: signature,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppleEventLinksTableProcessedTableManager =
    ProcessedTableManager<
      _$AwDatabase,
      $AppleEventLinksTable,
      AppleEventLinkRow,
      $$AppleEventLinksTableFilterComposer,
      $$AppleEventLinksTableOrderingComposer,
      $$AppleEventLinksTableAnnotationComposer,
      $$AppleEventLinksTableCreateCompanionBuilder,
      $$AppleEventLinksTableUpdateCompanionBuilder,
      (
        AppleEventLinkRow,
        BaseReferences<_$AwDatabase, $AppleEventLinksTable, AppleEventLinkRow>,
      ),
      AppleEventLinkRow,
      PrefetchHooks Function()
    >;
typedef $$FileRowsTableCreateCompanionBuilder =
    FileRowsCompanion Function({
      required String id,
      required String workspaceId,
      required String targetType,
      required String targetId,
      required String name,
      required String mime,
      required int sizeBytes,
      required String status,
      Value<String?> uploadedBy,
      Value<String?> folderId,
      Value<int> revision,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$FileRowsTableUpdateCompanionBuilder =
    FileRowsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> targetType,
      Value<String> targetId,
      Value<String> name,
      Value<String> mime,
      Value<int> sizeBytes,
      Value<String> status,
      Value<String?> uploadedBy,
      Value<String?> folderId,
      Value<int> revision,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

class $$FileRowsTableFilterComposer
    extends Composer<_$AwDatabase, $FileRowsTable> {
  $$FileRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetType => $composableBuilder(
    column: $table.targetType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uploadedBy => $composableBuilder(
    column: $table.uploadedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FileRowsTableOrderingComposer
    extends Composer<_$AwDatabase, $FileRowsTable> {
  $$FileRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetType => $composableBuilder(
    column: $table.targetType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uploadedBy => $composableBuilder(
    column: $table.uploadedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FileRowsTableAnnotationComposer
    extends Composer<_$AwDatabase, $FileRowsTable> {
  $$FileRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetType => $composableBuilder(
    column: $table.targetType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get mime =>
      $composableBuilder(column: $table.mime, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get uploadedBy => $composableBuilder(
    column: $table.uploadedBy,
    builder: (column) => column,
  );

  GeneratedColumn<String> get folderId =>
      $composableBuilder(column: $table.folderId, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$FileRowsTableTableManager
    extends
        RootTableManager<
          _$AwDatabase,
          $FileRowsTable,
          FileRecord,
          $$FileRowsTableFilterComposer,
          $$FileRowsTableOrderingComposer,
          $$FileRowsTableAnnotationComposer,
          $$FileRowsTableCreateCompanionBuilder,
          $$FileRowsTableUpdateCompanionBuilder,
          (
            FileRecord,
            BaseReferences<_$AwDatabase, $FileRowsTable, FileRecord>,
          ),
          FileRecord,
          PrefetchHooks Function()
        > {
  $$FileRowsTableTableManager(_$AwDatabase db, $FileRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FileRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FileRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FileRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> targetType = const Value.absent(),
                Value<String> targetId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> mime = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> uploadedBy = const Value.absent(),
                Value<String?> folderId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FileRowsCompanion(
                id: id,
                workspaceId: workspaceId,
                targetType: targetType,
                targetId: targetId,
                name: name,
                mime: mime,
                sizeBytes: sizeBytes,
                status: status,
                uploadedBy: uploadedBy,
                folderId: folderId,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String targetType,
                required String targetId,
                required String name,
                required String mime,
                required int sizeBytes,
                required String status,
                Value<String?> uploadedBy = const Value.absent(),
                Value<String?> folderId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FileRowsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                targetType: targetType,
                targetId: targetId,
                name: name,
                mime: mime,
                sizeBytes: sizeBytes,
                status: status,
                uploadedBy: uploadedBy,
                folderId: folderId,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FileRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AwDatabase,
      $FileRowsTable,
      FileRecord,
      $$FileRowsTableFilterComposer,
      $$FileRowsTableOrderingComposer,
      $$FileRowsTableAnnotationComposer,
      $$FileRowsTableCreateCompanionBuilder,
      $$FileRowsTableUpdateCompanionBuilder,
      (FileRecord, BaseReferences<_$AwDatabase, $FileRowsTable, FileRecord>),
      FileRecord,
      PrefetchHooks Function()
    >;
typedef $$FoldersTableCreateCompanionBuilder =
    FoldersCompanion Function({
      required String id,
      required String workspaceId,
      Value<String?> parentId,
      required String name,
      Value<int> revision,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$FoldersTableUpdateCompanionBuilder =
    FoldersCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String?> parentId,
      Value<String> name,
      Value<int> revision,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

class $$FoldersTableFilterComposer
    extends Composer<_$AwDatabase, $FoldersTable> {
  $$FoldersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FoldersTableOrderingComposer
    extends Composer<_$AwDatabase, $FoldersTable> {
  $$FoldersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FoldersTableAnnotationComposer
    extends Composer<_$AwDatabase, $FoldersTable> {
  $$FoldersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$FoldersTableTableManager
    extends
        RootTableManager<
          _$AwDatabase,
          $FoldersTable,
          FolderRecord,
          $$FoldersTableFilterComposer,
          $$FoldersTableOrderingComposer,
          $$FoldersTableAnnotationComposer,
          $$FoldersTableCreateCompanionBuilder,
          $$FoldersTableUpdateCompanionBuilder,
          (
            FolderRecord,
            BaseReferences<_$AwDatabase, $FoldersTable, FolderRecord>,
          ),
          FolderRecord,
          PrefetchHooks Function()
        > {
  $$FoldersTableTableManager(_$AwDatabase db, $FoldersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FoldersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FoldersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FoldersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoldersCompanion(
                id: id,
                workspaceId: workspaceId,
                parentId: parentId,
                name: name,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                Value<String?> parentId = const Value.absent(),
                required String name,
                Value<int> revision = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoldersCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                parentId: parentId,
                name: name,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FoldersTableProcessedTableManager =
    ProcessedTableManager<
      _$AwDatabase,
      $FoldersTable,
      FolderRecord,
      $$FoldersTableFilterComposer,
      $$FoldersTableOrderingComposer,
      $$FoldersTableAnnotationComposer,
      $$FoldersTableCreateCompanionBuilder,
      $$FoldersTableUpdateCompanionBuilder,
      (FolderRecord, BaseReferences<_$AwDatabase, $FoldersTable, FolderRecord>),
      FolderRecord,
      PrefetchHooks Function()
    >;
typedef $$QuickLinksTableCreateCompanionBuilder =
    QuickLinksCompanion Function({
      required String id,
      required String workspaceId,
      required String userId,
      required String kind,
      Value<String?> targetId,
      Value<String?> url,
      required String title,
      Value<String?> emoji,
      Value<String?> colorRgb,
      Value<int> sortOrder,
      Value<int> revision,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$QuickLinksTableUpdateCompanionBuilder =
    QuickLinksCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> userId,
      Value<String> kind,
      Value<String?> targetId,
      Value<String?> url,
      Value<String> title,
      Value<String?> emoji,
      Value<String?> colorRgb,
      Value<int> sortOrder,
      Value<int> revision,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

class $$QuickLinksTableFilterComposer
    extends Composer<_$AwDatabase, $QuickLinksTable> {
  $$QuickLinksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get emoji => $composableBuilder(
    column: $table.emoji,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorRgb => $composableBuilder(
    column: $table.colorRgb,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$QuickLinksTableOrderingComposer
    extends Composer<_$AwDatabase, $QuickLinksTable> {
  $$QuickLinksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get emoji => $composableBuilder(
    column: $table.emoji,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorRgb => $composableBuilder(
    column: $table.colorRgb,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$QuickLinksTableAnnotationComposer
    extends Composer<_$AwDatabase, $QuickLinksTable> {
  $$QuickLinksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get emoji =>
      $composableBuilder(column: $table.emoji, builder: (column) => column);

  GeneratedColumn<String> get colorRgb =>
      $composableBuilder(column: $table.colorRgb, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$QuickLinksTableTableManager
    extends
        RootTableManager<
          _$AwDatabase,
          $QuickLinksTable,
          QuickLinkRecord,
          $$QuickLinksTableFilterComposer,
          $$QuickLinksTableOrderingComposer,
          $$QuickLinksTableAnnotationComposer,
          $$QuickLinksTableCreateCompanionBuilder,
          $$QuickLinksTableUpdateCompanionBuilder,
          (
            QuickLinkRecord,
            BaseReferences<_$AwDatabase, $QuickLinksTable, QuickLinkRecord>,
          ),
          QuickLinkRecord,
          PrefetchHooks Function()
        > {
  $$QuickLinksTableTableManager(_$AwDatabase db, $QuickLinksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QuickLinksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QuickLinksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QuickLinksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> targetId = const Value.absent(),
                Value<String?> url = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> emoji = const Value.absent(),
                Value<String?> colorRgb = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => QuickLinksCompanion(
                id: id,
                workspaceId: workspaceId,
                userId: userId,
                kind: kind,
                targetId: targetId,
                url: url,
                title: title,
                emoji: emoji,
                colorRgb: colorRgb,
                sortOrder: sortOrder,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String userId,
                required String kind,
                Value<String?> targetId = const Value.absent(),
                Value<String?> url = const Value.absent(),
                required String title,
                Value<String?> emoji = const Value.absent(),
                Value<String?> colorRgb = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => QuickLinksCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                userId: userId,
                kind: kind,
                targetId: targetId,
                url: url,
                title: title,
                emoji: emoji,
                colorRgb: colorRgb,
                sortOrder: sortOrder,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$QuickLinksTableProcessedTableManager =
    ProcessedTableManager<
      _$AwDatabase,
      $QuickLinksTable,
      QuickLinkRecord,
      $$QuickLinksTableFilterComposer,
      $$QuickLinksTableOrderingComposer,
      $$QuickLinksTableAnnotationComposer,
      $$QuickLinksTableCreateCompanionBuilder,
      $$QuickLinksTableUpdateCompanionBuilder,
      (
        QuickLinkRecord,
        BaseReferences<_$AwDatabase, $QuickLinksTable, QuickLinkRecord>,
      ),
      QuickLinkRecord,
      PrefetchHooks Function()
    >;
typedef $$TaskSeriesTableCreateCompanionBuilder =
    TaskSeriesCompanion Function({
      required String id,
      required String workspaceId,
      required String ruleJson,
      required String templateJson,
      Value<String> timezone,
      required DateTime anchorAt,
      Value<int> revision,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$TaskSeriesTableUpdateCompanionBuilder =
    TaskSeriesCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> ruleJson,
      Value<String> templateJson,
      Value<String> timezone,
      Value<DateTime> anchorAt,
      Value<int> revision,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

class $$TaskSeriesTableFilterComposer
    extends Composer<_$AwDatabase, $TaskSeriesTable> {
  $$TaskSeriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ruleJson => $composableBuilder(
    column: $table.ruleJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get templateJson => $composableBuilder(
    column: $table.templateJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get anchorAt => $composableBuilder(
    column: $table.anchorAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TaskSeriesTableOrderingComposer
    extends Composer<_$AwDatabase, $TaskSeriesTable> {
  $$TaskSeriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ruleJson => $composableBuilder(
    column: $table.ruleJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get templateJson => $composableBuilder(
    column: $table.templateJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get anchorAt => $composableBuilder(
    column: $table.anchorAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TaskSeriesTableAnnotationComposer
    extends Composer<_$AwDatabase, $TaskSeriesTable> {
  $$TaskSeriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ruleJson =>
      $composableBuilder(column: $table.ruleJson, builder: (column) => column);

  GeneratedColumn<String> get templateJson => $composableBuilder(
    column: $table.templateJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get timezone =>
      $composableBuilder(column: $table.timezone, builder: (column) => column);

  GeneratedColumn<DateTime> get anchorAt =>
      $composableBuilder(column: $table.anchorAt, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$TaskSeriesTableTableManager
    extends
        RootTableManager<
          _$AwDatabase,
          $TaskSeriesTable,
          TaskSeriesRecord,
          $$TaskSeriesTableFilterComposer,
          $$TaskSeriesTableOrderingComposer,
          $$TaskSeriesTableAnnotationComposer,
          $$TaskSeriesTableCreateCompanionBuilder,
          $$TaskSeriesTableUpdateCompanionBuilder,
          (
            TaskSeriesRecord,
            BaseReferences<_$AwDatabase, $TaskSeriesTable, TaskSeriesRecord>,
          ),
          TaskSeriesRecord,
          PrefetchHooks Function()
        > {
  $$TaskSeriesTableTableManager(_$AwDatabase db, $TaskSeriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskSeriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskSeriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskSeriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> ruleJson = const Value.absent(),
                Value<String> templateJson = const Value.absent(),
                Value<String> timezone = const Value.absent(),
                Value<DateTime> anchorAt = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskSeriesCompanion(
                id: id,
                workspaceId: workspaceId,
                ruleJson: ruleJson,
                templateJson: templateJson,
                timezone: timezone,
                anchorAt: anchorAt,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String ruleJson,
                required String templateJson,
                Value<String> timezone = const Value.absent(),
                required DateTime anchorAt,
                Value<int> revision = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskSeriesCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                ruleJson: ruleJson,
                templateJson: templateJson,
                timezone: timezone,
                anchorAt: anchorAt,
                revision: revision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TaskSeriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AwDatabase,
      $TaskSeriesTable,
      TaskSeriesRecord,
      $$TaskSeriesTableFilterComposer,
      $$TaskSeriesTableOrderingComposer,
      $$TaskSeriesTableAnnotationComposer,
      $$TaskSeriesTableCreateCompanionBuilder,
      $$TaskSeriesTableUpdateCompanionBuilder,
      (
        TaskSeriesRecord,
        BaseReferences<_$AwDatabase, $TaskSeriesTable, TaskSeriesRecord>,
      ),
      TaskSeriesRecord,
      PrefetchHooks Function()
    >;
typedef $$AlarmEventsTableCreateCompanionBuilder =
    AlarmEventsCompanion Function({
      Value<int> id,
      required DateTime at,
      required String event,
      required String lane,
      Value<String?> kind,
      Value<int?> slotIndex,
      Value<bool> urgent,
      Value<String?> sound,
      Value<String?> level,
      Value<DateTime?> fireAt,
      Value<String?> taskId,
      Value<String?> reminderId,
      Value<String?> detail,
    });
typedef $$AlarmEventsTableUpdateCompanionBuilder =
    AlarmEventsCompanion Function({
      Value<int> id,
      Value<DateTime> at,
      Value<String> event,
      Value<String> lane,
      Value<String?> kind,
      Value<int?> slotIndex,
      Value<bool> urgent,
      Value<String?> sound,
      Value<String?> level,
      Value<DateTime?> fireAt,
      Value<String?> taskId,
      Value<String?> reminderId,
      Value<String?> detail,
    });

class $$AlarmEventsTableFilterComposer
    extends Composer<_$AwDatabase, $AlarmEventsTable> {
  $$AlarmEventsTableFilterComposer({
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

  ColumnFilters<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get event => $composableBuilder(
    column: $table.event,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lane => $composableBuilder(
    column: $table.lane,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get slotIndex => $composableBuilder(
    column: $table.slotIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get urgent => $composableBuilder(
    column: $table.urgent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sound => $composableBuilder(
    column: $table.sound,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fireAt => $composableBuilder(
    column: $table.fireAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reminderId => $composableBuilder(
    column: $table.reminderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AlarmEventsTableOrderingComposer
    extends Composer<_$AwDatabase, $AlarmEventsTable> {
  $$AlarmEventsTableOrderingComposer({
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

  ColumnOrderings<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get event => $composableBuilder(
    column: $table.event,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lane => $composableBuilder(
    column: $table.lane,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get slotIndex => $composableBuilder(
    column: $table.slotIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get urgent => $composableBuilder(
    column: $table.urgent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sound => $composableBuilder(
    column: $table.sound,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fireAt => $composableBuilder(
    column: $table.fireAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reminderId => $composableBuilder(
    column: $table.reminderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AlarmEventsTableAnnotationComposer
    extends Composer<_$AwDatabase, $AlarmEventsTable> {
  $$AlarmEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get at =>
      $composableBuilder(column: $table.at, builder: (column) => column);

  GeneratedColumn<String> get event =>
      $composableBuilder(column: $table.event, builder: (column) => column);

  GeneratedColumn<String> get lane =>
      $composableBuilder(column: $table.lane, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get slotIndex =>
      $composableBuilder(column: $table.slotIndex, builder: (column) => column);

  GeneratedColumn<bool> get urgent =>
      $composableBuilder(column: $table.urgent, builder: (column) => column);

  GeneratedColumn<String> get sound =>
      $composableBuilder(column: $table.sound, builder: (column) => column);

  GeneratedColumn<String> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumn<DateTime> get fireAt =>
      $composableBuilder(column: $table.fireAt, builder: (column) => column);

  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get reminderId => $composableBuilder(
    column: $table.reminderId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get detail =>
      $composableBuilder(column: $table.detail, builder: (column) => column);
}

class $$AlarmEventsTableTableManager
    extends
        RootTableManager<
          _$AwDatabase,
          $AlarmEventsTable,
          AlarmEvent,
          $$AlarmEventsTableFilterComposer,
          $$AlarmEventsTableOrderingComposer,
          $$AlarmEventsTableAnnotationComposer,
          $$AlarmEventsTableCreateCompanionBuilder,
          $$AlarmEventsTableUpdateCompanionBuilder,
          (
            AlarmEvent,
            BaseReferences<_$AwDatabase, $AlarmEventsTable, AlarmEvent>,
          ),
          AlarmEvent,
          PrefetchHooks Function()
        > {
  $$AlarmEventsTableTableManager(_$AwDatabase db, $AlarmEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlarmEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlarmEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlarmEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<DateTime> at = const Value.absent(),
                Value<String> event = const Value.absent(),
                Value<String> lane = const Value.absent(),
                Value<String?> kind = const Value.absent(),
                Value<int?> slotIndex = const Value.absent(),
                Value<bool> urgent = const Value.absent(),
                Value<String?> sound = const Value.absent(),
                Value<String?> level = const Value.absent(),
                Value<DateTime?> fireAt = const Value.absent(),
                Value<String?> taskId = const Value.absent(),
                Value<String?> reminderId = const Value.absent(),
                Value<String?> detail = const Value.absent(),
              }) => AlarmEventsCompanion(
                id: id,
                at: at,
                event: event,
                lane: lane,
                kind: kind,
                slotIndex: slotIndex,
                urgent: urgent,
                sound: sound,
                level: level,
                fireAt: fireAt,
                taskId: taskId,
                reminderId: reminderId,
                detail: detail,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required DateTime at,
                required String event,
                required String lane,
                Value<String?> kind = const Value.absent(),
                Value<int?> slotIndex = const Value.absent(),
                Value<bool> urgent = const Value.absent(),
                Value<String?> sound = const Value.absent(),
                Value<String?> level = const Value.absent(),
                Value<DateTime?> fireAt = const Value.absent(),
                Value<String?> taskId = const Value.absent(),
                Value<String?> reminderId = const Value.absent(),
                Value<String?> detail = const Value.absent(),
              }) => AlarmEventsCompanion.insert(
                id: id,
                at: at,
                event: event,
                lane: lane,
                kind: kind,
                slotIndex: slotIndex,
                urgent: urgent,
                sound: sound,
                level: level,
                fireAt: fireAt,
                taskId: taskId,
                reminderId: reminderId,
                detail: detail,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AlarmEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AwDatabase,
      $AlarmEventsTable,
      AlarmEvent,
      $$AlarmEventsTableFilterComposer,
      $$AlarmEventsTableOrderingComposer,
      $$AlarmEventsTableAnnotationComposer,
      $$AlarmEventsTableCreateCompanionBuilder,
      $$AlarmEventsTableUpdateCompanionBuilder,
      (AlarmEvent, BaseReferences<_$AwDatabase, $AlarmEventsTable, AlarmEvent>),
      AlarmEvent,
      PrefetchHooks Function()
    >;
typedef $$AiMessagesTableCreateCompanionBuilder =
    AiMessagesCompanion Function({
      Value<int> id,
      required String workspaceId,
      required String role,
      required String content,
      Value<String> status,
      Value<String?> contextJson,
      Value<String?> requestId,
      required DateTime createdAt,
    });
typedef $$AiMessagesTableUpdateCompanionBuilder =
    AiMessagesCompanion Function({
      Value<int> id,
      Value<String> workspaceId,
      Value<String> role,
      Value<String> content,
      Value<String> status,
      Value<String?> contextJson,
      Value<String?> requestId,
      Value<DateTime> createdAt,
    });

class $$AiMessagesTableFilterComposer
    extends Composer<_$AwDatabase, $AiMessagesTable> {
  $$AiMessagesTableFilterComposer({
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

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contextJson => $composableBuilder(
    column: $table.contextJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AiMessagesTableOrderingComposer
    extends Composer<_$AwDatabase, $AiMessagesTable> {
  $$AiMessagesTableOrderingComposer({
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

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contextJson => $composableBuilder(
    column: $table.contextJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AiMessagesTableAnnotationComposer
    extends Composer<_$AwDatabase, $AiMessagesTable> {
  $$AiMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get contextJson => $composableBuilder(
    column: $table.contextJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get requestId =>
      $composableBuilder(column: $table.requestId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$AiMessagesTableTableManager
    extends
        RootTableManager<
          _$AwDatabase,
          $AiMessagesTable,
          AiMessage,
          $$AiMessagesTableFilterComposer,
          $$AiMessagesTableOrderingComposer,
          $$AiMessagesTableAnnotationComposer,
          $$AiMessagesTableCreateCompanionBuilder,
          $$AiMessagesTableUpdateCompanionBuilder,
          (
            AiMessage,
            BaseReferences<_$AwDatabase, $AiMessagesTable, AiMessage>,
          ),
          AiMessage,
          PrefetchHooks Function()
        > {
  $$AiMessagesTableTableManager(_$AwDatabase db, $AiMessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> contextJson = const Value.absent(),
                Value<String?> requestId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => AiMessagesCompanion(
                id: id,
                workspaceId: workspaceId,
                role: role,
                content: content,
                status: status,
                contextJson: contextJson,
                requestId: requestId,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String workspaceId,
                required String role,
                required String content,
                Value<String> status = const Value.absent(),
                Value<String?> contextJson = const Value.absent(),
                Value<String?> requestId = const Value.absent(),
                required DateTime createdAt,
              }) => AiMessagesCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                role: role,
                content: content,
                status: status,
                contextJson: contextJson,
                requestId: requestId,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AiMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AwDatabase,
      $AiMessagesTable,
      AiMessage,
      $$AiMessagesTableFilterComposer,
      $$AiMessagesTableOrderingComposer,
      $$AiMessagesTableAnnotationComposer,
      $$AiMessagesTableCreateCompanionBuilder,
      $$AiMessagesTableUpdateCompanionBuilder,
      (AiMessage, BaseReferences<_$AwDatabase, $AiMessagesTable, AiMessage>),
      AiMessage,
      PrefetchHooks Function()
    >;
typedef $$ShareEventsTableCreateCompanionBuilder =
    ShareEventsCompanion Function({
      Value<int> id,
      required DateTime at,
      required String event,
      Value<String?> payloadKind,
      Value<int?> bytes,
      Value<String?> detail,
    });
typedef $$ShareEventsTableUpdateCompanionBuilder =
    ShareEventsCompanion Function({
      Value<int> id,
      Value<DateTime> at,
      Value<String> event,
      Value<String?> payloadKind,
      Value<int?> bytes,
      Value<String?> detail,
    });

class $$ShareEventsTableFilterComposer
    extends Composer<_$AwDatabase, $ShareEventsTable> {
  $$ShareEventsTableFilterComposer({
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

  ColumnFilters<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get event => $composableBuilder(
    column: $table.event,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadKind => $composableBuilder(
    column: $table.payloadKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ShareEventsTableOrderingComposer
    extends Composer<_$AwDatabase, $ShareEventsTable> {
  $$ShareEventsTableOrderingComposer({
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

  ColumnOrderings<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get event => $composableBuilder(
    column: $table.event,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadKind => $composableBuilder(
    column: $table.payloadKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ShareEventsTableAnnotationComposer
    extends Composer<_$AwDatabase, $ShareEventsTable> {
  $$ShareEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get at =>
      $composableBuilder(column: $table.at, builder: (column) => column);

  GeneratedColumn<String> get event =>
      $composableBuilder(column: $table.event, builder: (column) => column);

  GeneratedColumn<String> get payloadKind => $composableBuilder(
    column: $table.payloadKind,
    builder: (column) => column,
  );

  GeneratedColumn<int> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);

  GeneratedColumn<String> get detail =>
      $composableBuilder(column: $table.detail, builder: (column) => column);
}

class $$ShareEventsTableTableManager
    extends
        RootTableManager<
          _$AwDatabase,
          $ShareEventsTable,
          ShareEvent,
          $$ShareEventsTableFilterComposer,
          $$ShareEventsTableOrderingComposer,
          $$ShareEventsTableAnnotationComposer,
          $$ShareEventsTableCreateCompanionBuilder,
          $$ShareEventsTableUpdateCompanionBuilder,
          (
            ShareEvent,
            BaseReferences<_$AwDatabase, $ShareEventsTable, ShareEvent>,
          ),
          ShareEvent,
          PrefetchHooks Function()
        > {
  $$ShareEventsTableTableManager(_$AwDatabase db, $ShareEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShareEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShareEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShareEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<DateTime> at = const Value.absent(),
                Value<String> event = const Value.absent(),
                Value<String?> payloadKind = const Value.absent(),
                Value<int?> bytes = const Value.absent(),
                Value<String?> detail = const Value.absent(),
              }) => ShareEventsCompanion(
                id: id,
                at: at,
                event: event,
                payloadKind: payloadKind,
                bytes: bytes,
                detail: detail,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required DateTime at,
                required String event,
                Value<String?> payloadKind = const Value.absent(),
                Value<int?> bytes = const Value.absent(),
                Value<String?> detail = const Value.absent(),
              }) => ShareEventsCompanion.insert(
                id: id,
                at: at,
                event: event,
                payloadKind: payloadKind,
                bytes: bytes,
                detail: detail,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ShareEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AwDatabase,
      $ShareEventsTable,
      ShareEvent,
      $$ShareEventsTableFilterComposer,
      $$ShareEventsTableOrderingComposer,
      $$ShareEventsTableAnnotationComposer,
      $$ShareEventsTableCreateCompanionBuilder,
      $$ShareEventsTableUpdateCompanionBuilder,
      (ShareEvent, BaseReferences<_$AwDatabase, $ShareEventsTable, ShareEvent>),
      ShareEvent,
      PrefetchHooks Function()
    >;
typedef $$PendingMutationsTableCreateCompanionBuilder =
    PendingMutationsCompanion Function({
      required String id,
      required String workspaceId,
      required String entityType,
      required String entityId,
      required String operation,
      Value<String?> patchJson,
      required DateTime localUpdatedAt,
      required DateTime createdAt,
      Value<int> attempts,
      Value<String?> lastError,
      Value<int?> baseRevision,
      Value<int> rowid,
    });
typedef $$PendingMutationsTableUpdateCompanionBuilder =
    PendingMutationsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> operation,
      Value<String?> patchJson,
      Value<DateTime> localUpdatedAt,
      Value<DateTime> createdAt,
      Value<int> attempts,
      Value<String?> lastError,
      Value<int?> baseRevision,
      Value<int> rowid,
    });

class $$PendingMutationsTableFilterComposer
    extends Composer<_$AwDatabase, $PendingMutationsTable> {
  $$PendingMutationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get patchJson => $composableBuilder(
    column: $table.patchJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get localUpdatedAt => $composableBuilder(
    column: $table.localUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingMutationsTableOrderingComposer
    extends Composer<_$AwDatabase, $PendingMutationsTable> {
  $$PendingMutationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get patchJson => $composableBuilder(
    column: $table.patchJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get localUpdatedAt => $composableBuilder(
    column: $table.localUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingMutationsTableAnnotationComposer
    extends Composer<_$AwDatabase, $PendingMutationsTable> {
  $$PendingMutationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get patchJson =>
      $composableBuilder(column: $table.patchJson, builder: (column) => column);

  GeneratedColumn<DateTime> get localUpdatedAt => $composableBuilder(
    column: $table.localUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => column,
  );
}

class $$PendingMutationsTableTableManager
    extends
        RootTableManager<
          _$AwDatabase,
          $PendingMutationsTable,
          PendingMutation,
          $$PendingMutationsTableFilterComposer,
          $$PendingMutationsTableOrderingComposer,
          $$PendingMutationsTableAnnotationComposer,
          $$PendingMutationsTableCreateCompanionBuilder,
          $$PendingMutationsTableUpdateCompanionBuilder,
          (
            PendingMutation,
            BaseReferences<
              _$AwDatabase,
              $PendingMutationsTable,
              PendingMutation
            >,
          ),
          PendingMutation,
          PrefetchHooks Function()
        > {
  $$PendingMutationsTableTableManager(
    _$AwDatabase db,
    $PendingMutationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingMutationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingMutationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingMutationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String?> patchJson = const Value.absent(),
                Value<DateTime> localUpdatedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int?> baseRevision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingMutationsCompanion(
                id: id,
                workspaceId: workspaceId,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                patchJson: patchJson,
                localUpdatedAt: localUpdatedAt,
                createdAt: createdAt,
                attempts: attempts,
                lastError: lastError,
                baseRevision: baseRevision,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String entityType,
                required String entityId,
                required String operation,
                Value<String?> patchJson = const Value.absent(),
                required DateTime localUpdatedAt,
                required DateTime createdAt,
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int?> baseRevision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingMutationsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                patchJson: patchJson,
                localUpdatedAt: localUpdatedAt,
                createdAt: createdAt,
                attempts: attempts,
                lastError: lastError,
                baseRevision: baseRevision,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingMutationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AwDatabase,
      $PendingMutationsTable,
      PendingMutation,
      $$PendingMutationsTableFilterComposer,
      $$PendingMutationsTableOrderingComposer,
      $$PendingMutationsTableAnnotationComposer,
      $$PendingMutationsTableCreateCompanionBuilder,
      $$PendingMutationsTableUpdateCompanionBuilder,
      (
        PendingMutation,
        BaseReferences<_$AwDatabase, $PendingMutationsTable, PendingMutation>,
      ),
      PendingMutation,
      PrefetchHooks Function()
    >;
typedef $$RejectedMutationsTableCreateCompanionBuilder =
    RejectedMutationsCompanion Function({
      required String id,
      required String workspaceId,
      required String entityType,
      required String entityId,
      required String operation,
      Value<String?> patchJson,
      Value<String?> errorCode,
      required DateTime rejectedAt,
      Value<int> rowid,
    });
typedef $$RejectedMutationsTableUpdateCompanionBuilder =
    RejectedMutationsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> operation,
      Value<String?> patchJson,
      Value<String?> errorCode,
      Value<DateTime> rejectedAt,
      Value<int> rowid,
    });

class $$RejectedMutationsTableFilterComposer
    extends Composer<_$AwDatabase, $RejectedMutationsTable> {
  $$RejectedMutationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get patchJson => $composableBuilder(
    column: $table.patchJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get rejectedAt => $composableBuilder(
    column: $table.rejectedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RejectedMutationsTableOrderingComposer
    extends Composer<_$AwDatabase, $RejectedMutationsTable> {
  $$RejectedMutationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get patchJson => $composableBuilder(
    column: $table.patchJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get rejectedAt => $composableBuilder(
    column: $table.rejectedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RejectedMutationsTableAnnotationComposer
    extends Composer<_$AwDatabase, $RejectedMutationsTable> {
  $$RejectedMutationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get patchJson =>
      $composableBuilder(column: $table.patchJson, builder: (column) => column);

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);

  GeneratedColumn<DateTime> get rejectedAt => $composableBuilder(
    column: $table.rejectedAt,
    builder: (column) => column,
  );
}

class $$RejectedMutationsTableTableManager
    extends
        RootTableManager<
          _$AwDatabase,
          $RejectedMutationsTable,
          RejectedMutation,
          $$RejectedMutationsTableFilterComposer,
          $$RejectedMutationsTableOrderingComposer,
          $$RejectedMutationsTableAnnotationComposer,
          $$RejectedMutationsTableCreateCompanionBuilder,
          $$RejectedMutationsTableUpdateCompanionBuilder,
          (
            RejectedMutation,
            BaseReferences<
              _$AwDatabase,
              $RejectedMutationsTable,
              RejectedMutation
            >,
          ),
          RejectedMutation,
          PrefetchHooks Function()
        > {
  $$RejectedMutationsTableTableManager(
    _$AwDatabase db,
    $RejectedMutationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RejectedMutationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RejectedMutationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RejectedMutationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String?> patchJson = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<DateTime> rejectedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RejectedMutationsCompanion(
                id: id,
                workspaceId: workspaceId,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                patchJson: patchJson,
                errorCode: errorCode,
                rejectedAt: rejectedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String entityType,
                required String entityId,
                required String operation,
                Value<String?> patchJson = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                required DateTime rejectedAt,
                Value<int> rowid = const Value.absent(),
              }) => RejectedMutationsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                patchJson: patchJson,
                errorCode: errorCode,
                rejectedAt: rejectedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RejectedMutationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AwDatabase,
      $RejectedMutationsTable,
      RejectedMutation,
      $$RejectedMutationsTableFilterComposer,
      $$RejectedMutationsTableOrderingComposer,
      $$RejectedMutationsTableAnnotationComposer,
      $$RejectedMutationsTableCreateCompanionBuilder,
      $$RejectedMutationsTableUpdateCompanionBuilder,
      (
        RejectedMutation,
        BaseReferences<_$AwDatabase, $RejectedMutationsTable, RejectedMutation>,
      ),
      RejectedMutation,
      PrefetchHooks Function()
    >;
typedef $$SyncStatesTableCreateCompanionBuilder =
    SyncStatesCompanion Function({
      required String workspaceId,
      required String clientId,
      Value<int> lastRevision,
      Value<DateTime?> lastPulledAt,
      Value<int> rowid,
    });
typedef $$SyncStatesTableUpdateCompanionBuilder =
    SyncStatesCompanion Function({
      Value<String> workspaceId,
      Value<String> clientId,
      Value<int> lastRevision,
      Value<DateTime?> lastPulledAt,
      Value<int> rowid,
    });

class $$SyncStatesTableFilterComposer
    extends Composer<_$AwDatabase, $SyncStatesTable> {
  $$SyncStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastRevision => $composableBuilder(
    column: $table.lastRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastPulledAt => $composableBuilder(
    column: $table.lastPulledAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStatesTableOrderingComposer
    extends Composer<_$AwDatabase, $SyncStatesTable> {
  $$SyncStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastRevision => $composableBuilder(
    column: $table.lastRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastPulledAt => $composableBuilder(
    column: $table.lastPulledAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStatesTableAnnotationComposer
    extends Composer<_$AwDatabase, $SyncStatesTable> {
  $$SyncStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<int> get lastRevision => $composableBuilder(
    column: $table.lastRevision,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastPulledAt => $composableBuilder(
    column: $table.lastPulledAt,
    builder: (column) => column,
  );
}

class $$SyncStatesTableTableManager
    extends
        RootTableManager<
          _$AwDatabase,
          $SyncStatesTable,
          SyncState,
          $$SyncStatesTableFilterComposer,
          $$SyncStatesTableOrderingComposer,
          $$SyncStatesTableAnnotationComposer,
          $$SyncStatesTableCreateCompanionBuilder,
          $$SyncStatesTableUpdateCompanionBuilder,
          (
            SyncState,
            BaseReferences<_$AwDatabase, $SyncStatesTable, SyncState>,
          ),
          SyncState,
          PrefetchHooks Function()
        > {
  $$SyncStatesTableTableManager(_$AwDatabase db, $SyncStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> workspaceId = const Value.absent(),
                Value<String> clientId = const Value.absent(),
                Value<int> lastRevision = const Value.absent(),
                Value<DateTime?> lastPulledAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStatesCompanion(
                workspaceId: workspaceId,
                clientId: clientId,
                lastRevision: lastRevision,
                lastPulledAt: lastPulledAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String workspaceId,
                required String clientId,
                Value<int> lastRevision = const Value.absent(),
                Value<DateTime?> lastPulledAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStatesCompanion.insert(
                workspaceId: workspaceId,
                clientId: clientId,
                lastRevision: lastRevision,
                lastPulledAt: lastPulledAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AwDatabase,
      $SyncStatesTable,
      SyncState,
      $$SyncStatesTableFilterComposer,
      $$SyncStatesTableOrderingComposer,
      $$SyncStatesTableAnnotationComposer,
      $$SyncStatesTableCreateCompanionBuilder,
      $$SyncStatesTableUpdateCompanionBuilder,
      (SyncState, BaseReferences<_$AwDatabase, $SyncStatesTable, SyncState>),
      SyncState,
      PrefetchHooks Function()
    >;

class $AwDatabaseManager {
  final _$AwDatabase _db;
  $AwDatabaseManager(this._db);
  $$ProjectsTableTableManager get projects =>
      $$ProjectsTableTableManager(_db, _db.projects);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
  $$TaskTagRowsTableTableManager get taskTagRows =>
      $$TaskTagRowsTableTableManager(_db, _db.taskTagRows);
  $$ChecklistItemsTableTableManager get checklistItems =>
      $$ChecklistItemsTableTableManager(_db, _db.checklistItems);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db, _db.notes);
  $$NoteLinkRowsTableTableManager get noteLinkRows =>
      $$NoteLinkRowsTableTableManager(_db, _db.noteLinkRows);
  $$RemindersTableTableManager get reminders =>
      $$RemindersTableTableManager(_db, _db.reminders);
  $$ExternalEventsTableTableManager get externalEvents =>
      $$ExternalEventsTableTableManager(_db, _db.externalEvents);
  $$AppleEventLinksTableTableManager get appleEventLinks =>
      $$AppleEventLinksTableTableManager(_db, _db.appleEventLinks);
  $$FileRowsTableTableManager get fileRows =>
      $$FileRowsTableTableManager(_db, _db.fileRows);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db, _db.folders);
  $$QuickLinksTableTableManager get quickLinks =>
      $$QuickLinksTableTableManager(_db, _db.quickLinks);
  $$TaskSeriesTableTableManager get taskSeries =>
      $$TaskSeriesTableTableManager(_db, _db.taskSeries);
  $$AlarmEventsTableTableManager get alarmEvents =>
      $$AlarmEventsTableTableManager(_db, _db.alarmEvents);
  $$AiMessagesTableTableManager get aiMessages =>
      $$AiMessagesTableTableManager(_db, _db.aiMessages);
  $$ShareEventsTableTableManager get shareEvents =>
      $$ShareEventsTableTableManager(_db, _db.shareEvents);
  $$PendingMutationsTableTableManager get pendingMutations =>
      $$PendingMutationsTableTableManager(_db, _db.pendingMutations);
  $$RejectedMutationsTableTableManager get rejectedMutations =>
      $$RejectedMutationsTableTableManager(_db, _db.rejectedMutations);
  $$SyncStatesTableTableManager get syncStates =>
      $$SyncStatesTableTableManager(_db, _db.syncStates);
}
