import 'package:appflowy/plugins/database_view/application/field/field_controller.dart';
import 'package:appflowy/plugins/database_view/application/view/view_cache.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database/group.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-database/group_changeset.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-database/row_entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:collection/collection.dart';
import 'dart:async';
import 'package:dartz/dartz.dart';
import '../../application/database_service.dart';
import '../../application/defines.dart';
import '../../application/row/row_cache.dart';
import '../../board/application/board_listener.dart';

typedef OnRowsChanged = void Function(
  List<RowInfo> rowInfos,
  RowsChangedReason,
);

typedef OnGroupByField = void Function(List<GroupPB>);
typedef OnUpdateGroup = void Function(List<GroupPB>);
typedef OnDeleteGroup = void Function(List<String>);
typedef OnInsertGroup = void Function(InsertedGroupPB);

class GroupCallbacks {
  final OnGroupByField? onGroupByField;
  final OnUpdateGroup? onUpdateGroup;
  final OnDeleteGroup? onDeleteGroup;
  final OnInsertGroup? onInsertGroup;

  GroupCallbacks({
    this.onGroupByField,
    this.onUpdateGroup,
    this.onDeleteGroup,
    this.onInsertGroup,
  });
}

class DatabaseCallbacks {
  OnDatabaseChanged? onDatabaseChanged;
  OnRowsChanged? onRowsChanged;
  OnFieldsChanged? onFieldsChanged;
  OnFiltersChanged? onFiltersChanged;
  DatabaseCallbacks({
    this.onDatabaseChanged,
    this.onRowsChanged,
    this.onFieldsChanged,
    this.onFiltersChanged,
  });
}

class DatabaseController {
  final String viewId;
  final DatabaseBackendService _databaseBackendSvc;
  final FieldController fieldController;
  late DatabaseViewCache _viewCache;

  // Callbacks
  DatabaseCallbacks? _databaseCallbacks;
  GroupCallbacks? _groupCallbacks;

  // Getters
  List<RowInfo> get rowInfos => _viewCache.rowInfos;
  RowCache get rowCache => _viewCache.rowCache;

// Listener
  final DatabaseGroupListener groupListener;

  DatabaseController({required ViewPB view})
      : viewId = view.id,
        _databaseBackendSvc = DatabaseBackendService(viewId: view.id),
        fieldController = FieldController(viewId: view.id),
        groupListener = DatabaseGroupListener(view.id) {
    _viewCache = DatabaseViewCache(
      viewId: viewId,
      fieldController: fieldController,
    );
    _listenOnRowsChanged();
    _listenOnFieldsChanged();
    _listenOnGroupChanged();
  }

  void addListener({
    DatabaseCallbacks? onDatabaseChanged,
    GroupCallbacks? onGroupChanged,
  }) {
    _databaseCallbacks = onDatabaseChanged;
    _groupCallbacks = onGroupChanged;
  }

  Future<Either<Unit, FlowyError>> openGrid() async {
    return _databaseBackendSvc.openGrid().then((result) {
      return result.fold(
        (database) async {
          _databaseCallbacks?.onDatabaseChanged?.call(database);
          _viewCache.rowCache.setInitialRows(database.rows);
          return await fieldController
              .loadFields(
            fieldIds: database.fields,
          )
              .then(
            (result) {
              return result.fold(
                (l) => Future(() async {
                  await _loadGroups();
                  return left(l);
                }),
                (err) => right(err),
              );
            },
          );
        },
        (err) => right(err),
      );
    });
  }

  Future<Either<RowPB, FlowyError>> createRow(
      {String? startRowId, String? groupId}) {
    if (groupId != null) {
      return _databaseBackendSvc.createGroupRow(groupId, startRowId);
    } else {
      return _databaseBackendSvc.createRow(startRowId: startRowId);
    }
  }

  Future<void> dispose() async {
    await _databaseBackendSvc.closeView();
    await fieldController.dispose();
    await groupListener.stop();
  }

  Future<void> _loadGroups() async {
    final result = await _databaseBackendSvc.loadGroups();
    return Future(
      () => result.fold(
        (groups) {
          _groupCallbacks?.onGroupByField?.call(groups.items);
        },
        (err) => Log.error(err),
      ),
    );
  }

  void _listenOnRowsChanged() {
    _viewCache.addListener(onRowsChanged: (reason) {
      _databaseCallbacks?.onRowsChanged?.call(rowInfos, reason);
    });
  }

  void _listenOnFieldsChanged() {
    fieldController.addListener(
      onReceiveFields: (fields) {
        _databaseCallbacks?.onFieldsChanged?.call(UnmodifiableListView(fields));
      },
      onFilters: (filters) {
        _databaseCallbacks?.onFiltersChanged?.call(filters);
      },
    );
  }

  void _listenOnGroupChanged() {
    groupListener.start(
      onNumOfGroupsChanged: (result) {
        result.fold((changeset) {
          if (changeset.updateGroups.isNotEmpty) {
            _groupCallbacks?.onUpdateGroup?.call(changeset.updateGroups);
          }

          if (changeset.deletedGroups.isNotEmpty) {
            _groupCallbacks?.onDeleteGroup?.call(changeset.deletedGroups);
          }

          for (final insertedGroup in changeset.insertedGroups) {
            _groupCallbacks?.onInsertGroup?.call(insertedGroup);
          }
        }, (r) => Log.error(r));
      },
      onGroupByNewField: (result) {
        result.fold((groups) {
          _groupCallbacks?.onGroupByField?.call(groups);
        }, (r) => Log.error(r));
      },
    );
  }
}
