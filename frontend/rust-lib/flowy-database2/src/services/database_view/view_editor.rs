use std::borrow::Cow;
use std::collections::HashMap;
use std::sync::Arc;

use super::{notify_did_update_calculation, DatabaseViewChanged};
use crate::entities::{
  CalculationChangesetNotificationPB, CalendarEventPB, CreateRowPayloadPB, DatabaseLayoutMetaPB,
  DatabaseLayoutSettingPB, DeleteSortPayloadPB, FieldSettingsChangesetPB, FieldType,
  GroupChangesPB, GroupPB, InsertedRowPB, LayoutSettingChangeset, LayoutSettingParams,
  RemoveCalculationChangesetPB, ReorderSortPayloadPB, RowMetaPB, RowsChangePB,
  SortChangesetNotificationPB, SortPB, UpdateCalculationChangesetPB, UpdateSortPayloadPB,
};
use crate::notification::{database_notification_builder, DatabaseNotification};
use crate::services::calculations::{Calculation, CalculationChangeset, CalculationsController};
use crate::services::cell::{CellBuilder, CellCache};
use crate::services::database::{database_view_setting_pb_from_view, DatabaseRowEvent, UpdatedRow};
use crate::services::database_view::view_calculations::make_calculations_controller;
use crate::services::database_view::view_filter::make_filter_controller;
use crate::services::database_view::view_group::{get_cell_for_row, new_group_controller};
use crate::services::database_view::view_operation::DatabaseViewOperation;
use crate::services::database_view::view_sort::make_sort_controller;
use crate::services::database_view::{
  notify_did_update_filter, notify_did_update_group_rows, notify_did_update_num_of_groups,
  notify_did_update_setting, notify_did_update_sort, DatabaseLayoutDepsResolver,
  DatabaseViewChangedNotifier, DatabaseViewChangedReceiverRunner,
};
use crate::services::field_settings::FieldSettings;
use crate::services::filter::{Filter, FilterChangeset, FilterController};
use crate::services::group::{
  DidMoveGroupRowResult, GroupChangeset, GroupController, MoveGroupRowContext, UpdatedCells,
};
use crate::services::setting::CalendarLayoutSetting;
use crate::services::sort::{Sort, SortChangeset, SortController};
use collab_database::database::{gen_database_calculation_id, gen_database_sort_id, gen_row_id};
use collab_database::entity::DatabaseView;
use collab_database::fields::Field;
use collab_database::rows::{Cell, Cells, CreateRowParams, Row, RowCell, RowDetail, RowId};
use collab_database::views::{DatabaseLayout, RowOrder};
use dashmap::DashMap;
use flowy_error::{FlowyError, FlowyResult};

use lib_infra::util::timestamp;
use tokio::sync::{broadcast, RwLock};
use tracing::{error, instrument, trace, warn};

pub struct DatabaseViewEditor {
  database_id: String,
  pub view_id: String,
  delegate: Arc<dyn DatabaseViewOperation>,
  group_controller: Arc<RwLock<Option<Box<dyn GroupController>>>>,
  filter_controller: Arc<FilterController>,
  sort_controller: Arc<RwLock<SortController>>,
  calculations_controller: Arc<CalculationsController>,
  /// Use lazy_rows as cache that represents the row's order for given view
  /// It can't get the row id when deleting a row. it only returns the deleted index.
  /// So using this cache to get the row id by index
  ///
  /// Check out this link (https://github.com/y-crdt/y-crdt/issues/341) for more information.
  pub(crate) row_orders: RwLock<Vec<RowOrder>>,
  pub(crate) row_by_row_id: DashMap<String, Arc<Row>>,
  pub notifier: DatabaseViewChangedNotifier,
}

impl Drop for DatabaseViewEditor {
  fn drop(&mut self) {
    tracing::trace!("Drop {}", std::any::type_name::<Self>());
  }
}

impl DatabaseViewEditor {
  /// Create a new Database View Editor.
  ///
  /// After creating the editor, you must call [DatabaseViewEditor::initialize] to properly initialize it.
  /// This initialization step will load essential data, such as group information.
  ///
  /// Avoid calling any methods of [DatabaseViewOperation] before the editor is fully initialized,
  /// as some actions may rely on the current editor state. Failing to follow this order could result
  /// in unexpected behavior, including potential deadlocks.
  pub async fn new(
    database_id: String,
    view_id: String,
    delegate: Arc<dyn DatabaseViewOperation>,
    cell_cache: CellCache,
  ) -> FlowyResult<Self> {
    let (notifier, _) = broadcast::channel(100);
    tokio::spawn(DatabaseViewChangedReceiverRunner(Some(notifier.subscribe())).run());

    // Filter
    let filter_controller = make_filter_controller(
      &view_id,
      delegate.clone(),
      notifier.clone(),
      cell_cache.clone(),
    )
    .await;

    // Sort
    let sort_controller = make_sort_controller(
      &view_id,
      delegate.clone(),
      notifier.clone(),
      filter_controller.clone(),
      cell_cache,
    )
    .await;

    // Group
    let group_controller = Arc::new(RwLock::new(
      new_group_controller(
        view_id.clone(),
        delegate.clone(),
        filter_controller.clone(),
        None,
      )
      .await?,
    ));

    // Calculations
    let calculations_controller =
      make_calculations_controller(&view_id, delegate.clone(), notifier.clone()).await;

    Ok(Self {
      database_id,
      view_id,
      delegate,
      group_controller,
      filter_controller,
      sort_controller,
      calculations_controller,
      row_orders: Default::default(),
      row_by_row_id: Default::default(),
      notifier,
    })
  }

  /// Initialize the editor after creating it
  /// You should call [DatabaseViewEditor::initialize] after creating the editor
  pub async fn initialize(&self) -> FlowyResult<()> {
    if let Some(group) = self.group_controller.write().await.as_mut() {
      group.load_group_data().await?;
    }

    Ok(())
  }

  pub async fn insert_row(&self, row: Option<Arc<Row>>, index: u32, row_order: &RowOrder) {
    let mut row_orders = self.row_orders.write().await;
    if row_orders.len() >= index as usize {
      row_orders.insert(index as usize, row_order.clone());
    } else {
      warn!(
        "[RowOrder]: insert row at index:{} out of range:{}",
        index,
        row_orders.len()
      );
    }
    if let Some(row) = row {
      self.row_by_row_id.insert(row.id.to_string(), row);
    }
  }

  pub async fn set_row_orders(&self, row_orders: Vec<RowOrder>) {
    *self.row_orders.write().await = row_orders;
  }

  pub async fn get_all_row_orders(&self) -> FlowyResult<Vec<RowOrder>> {
    let row_orders = self.delegate.get_all_row_orders(&self.view_id).await;
    Ok(row_orders)
  }

  pub async fn close(&self) {
    self.sort_controller.write().await.close().await;
    self.filter_controller.close().await;
    self.calculations_controller.close().await;
  }

  pub async fn has_filters(&self) -> bool {
    self.filter_controller.has_filters().await
  }

  pub async fn has_sorts(&self) -> bool {
    self.sort_controller.read().await.has_sorts().await
  }

  pub async fn v_get_view(&self) -> Option<DatabaseView> {
    self.delegate.get_view(&self.view_id).await
  }

  pub async fn v_will_create_row(
    &self,
    params: CreateRowPayloadPB,
  ) -> FlowyResult<CreateRowParams> {
    let timestamp = timestamp();
    trace!("[Database]: will create row at: {:?}", params.row_position);
    let mut result = CreateRowParams {
      id: gen_row_id(),
      database_id: self.database_id.clone(),
      cells: Cells::new(),
      height: 60,
      visibility: true,
      row_position: params.row_position.try_into()?,
      created_at: timestamp,
      modified_at: timestamp,
    };

    // fill in cells from the frontend
    let fields = self.delegate.get_fields(&params.view_id, None).await;
    let mut cells = CellBuilder::with_cells(params.data, &fields).build();

    // fill in cells according to group_id if supplied
    if let Some(group_id) = params.group_id {
      if let Some(controller) = self.group_controller.read().await.as_ref() {
        let field = self
          .delegate
          .get_field(controller.get_grouping_field_id())
          .await
          .ok_or_else(|| FlowyError::internal().with_context("Failed to get grouping field"))?;
        controller.will_create_row(&mut cells, &field, &group_id);
      }
    }

    // fill in cells according to active filters
    let filter_controller = self.filter_controller.clone();
    filter_controller.fill_cells(&mut cells).await;

    result.cells = cells;
    Ok(result)
  }

  pub async fn v_did_update_row_meta(&self, row_id: &RowId, row_detail: &RowDetail) {
    let rows = vec![Arc::new(row_detail.row.clone())];
    let mut rows = self.v_filter_rows(rows).await;
    if rows.pop().is_some() {
      let update_row = UpdatedRow::new(row_id.as_str()).with_row_meta(row_detail.clone());
      let changeset = RowsChangePB::from_update(update_row.into());
      database_notification_builder(&self.view_id, DatabaseNotification::DidUpdateRow)
        .payload(changeset)
        .send();
    }
  }

  pub async fn v_did_create_row(
    &self,
    row_detail: &RowDetail,
    index: u32,
    is_move_row: bool,
    is_local_change: bool,
    row_changes: &DashMap<String, RowsChangePB>,
  ) {
    // Send the group notification if the current view has groups
    if let Some(controller) = self.group_controller.write().await.as_mut() {
      let rows = vec![Arc::new(row_detail.row.clone())];
      let mut rows = self.v_filter_rows(rows).await;
      if let Some(row) = rows.pop() {
        let changesets = controller.did_create_row(&row, index as usize);
        for changeset in changesets {
          notify_did_update_group_rows(changeset).await;
        }
      }
    }

    let index = self
      .sort_controller
      .write()
      .await
      .did_create_row(&row_detail.row)
      .await;

    row_changes
      .entry(self.view_id.clone())
      .or_insert_with(|| {
        let mut change = RowsChangePB::new();
        change.is_move_row = is_move_row;
        change
      })
      .inserted_rows
      .push(InsertedRowPB {
        row_meta: RowMetaPB::from(row_detail),
        index: index.map(|index| index as i32),
        is_new: true,
        is_hidden_in_view: is_local_change && index.is_none(),
      });

    self
      .gen_did_create_row_view_tasks(row_detail.row.clone())
      .await;
  }

  #[tracing::instrument(level = "trace", skip_all)]
  pub async fn v_did_delete_row(&self, row: &Row, is_move_row: bool, is_local_change: bool) {
    let deleted_row = row.clone();

    // Only update group rows
    // 1. when the row is deleted locally. If the row is moved, we don't need to send the group
    // notification. Because it's handled by the move_group_row function
    // 2. when the row is deleted remotely
    if !is_move_row || !is_local_change {
      // Send the group notification if the current view has groups;
      let result = self
        .mut_group_controller(|group_controller, _| group_controller.did_delete_row(row))
        .await;
      handle_mut_group_result(&self.view_id, result).await;
    }

    // Updating calculations for each of the Rows cells is a tedious task
    // Therefore we spawn a separate task for this
    let weak_calculations_controller = Arc::downgrade(&self.calculations_controller);
    tokio::spawn(async move {
      if let Some(calculations_controller) = weak_calculations_controller.upgrade() {
        calculations_controller
          .did_receive_row_changed(deleted_row)
          .await;
      }
    });
  }

  /// Notify the view that the row has been updated. If the view has groups,
  /// send the group notification with [GroupRowsNotificationPB]. Otherwise,
  /// send the view notification with [RowsChangePB]
  #[instrument(level = "trace", skip_all)]
  pub async fn v_did_update_row(&self, old_row: &Option<Row>, row: &Row, field_id: Option<String>) {
    if let Some(controller) = self.group_controller.write().await.as_mut() {
      let field = self
        .delegate
        .get_field(controller.get_grouping_field_id())
        .await;

      if let Some(field) = field {
        let rows = vec![Arc::new(row.clone())];
        let mut rows = self.v_filter_rows(rows).await;

        let mut group_changes = GroupChangesPB {
          view_id: self.view_id.clone(),
          ..Default::default()
        };

        let (inserted_group, deleted_group, row_changesets) = if let Some(row) = rows.pop() {
          if let Ok(result) = controller.did_update_group_row(old_row, &row, &field) {
            (
              result.inserted_group,
              result.deleted_group,
              result.row_changesets,
            )
          } else {
            (None, None, vec![])
          }
        } else if let Ok(result) = controller.did_delete_row(row) {
          (None, result.deleted_group, result.row_changesets)
        } else {
          (None, None, vec![])
        };

        if let Some(inserted_group) = inserted_group {
          tracing::trace!("Create group after editing the row: {:?}", inserted_group);
          group_changes.inserted_groups.push(inserted_group);
        }
        if let Some(delete_group) = deleted_group {
          tracing::trace!("Delete group after editing the row: {:?}", delete_group);
          group_changes.deleted_groups.push(delete_group.group_id);
        }

        if !group_changes.is_empty() {
          notify_did_update_num_of_groups(&self.view_id, group_changes).await;
        }

        for changeset in row_changesets {
          if !changeset.is_empty() {
            tracing::trace!("Group change after editing the row: {:?}", changeset);
            notify_did_update_group_rows(changeset).await;
          }
        }
      }
    }

    // Each row update will trigger a calculations, filter and sort operation. We don't want
    // to block the main thread, so we spawn a new task to do the work.
    self
      .gen_did_update_row_view_tasks(row.id.clone(), field_id)
      .await;
  }

  pub async fn v_filter_rows(&self, rows: Vec<Arc<Row>>) -> Vec<Arc<Row>> {
    self.filter_controller.filter_rows(rows).await
  }

  pub async fn v_filter_rows_and_notify(&self, rows: &mut Vec<Arc<Row>>) {
    let _ = self.filter_controller.filter_rows_and_notify(rows).await;
  }

  pub async fn v_sort_rows(&self, rows: &mut Vec<Arc<Row>>) {
    self.sort_controller.write().await.sort_rows(rows).await
  }

  pub async fn v_sort_rows_and_notify(&self, rows: &mut Vec<Arc<Row>>) {
    self
      .sort_controller
      .write()
      .await
      .sort_rows_and_notify(rows)
      .await;
  }

  #[instrument(level = "info", skip(self))]
  pub async fn v_get_all_rows(&self) -> Vec<Arc<Row>> {
    let row_orders = self.delegate.get_all_row_orders(&self.view_id).await;
    let rows = self.delegate.get_all_rows(&self.view_id, row_orders).await;
    let mut rows = self.v_filter_rows(rows).await;
    self.v_sort_rows(&mut rows).await;
    rows
  }

  pub async fn v_get_cells_for_field(&self, field_id: &str) -> Vec<RowCell> {
    let row_orders = self.delegate.get_all_row_orders(&self.view_id).await;
    let rows = self.delegate.get_all_rows(&self.view_id, row_orders).await;
    let rows = self.v_filter_rows(rows).await;
    let rows = rows
      .into_iter()
      .filter_map(|row| {
        row
          .cells
          .get(field_id)
          .map(|cell| RowCell::new(row.id.clone(), Some(cell.clone())))
      })
      .collect::<Vec<_>>();
    trace!(
      "[Database]: get cells for field: {}, total rows:{}",
      field_id,
      rows.len()
    );
    rows
  }

  pub async fn v_get_row(&self, row_id: &RowId) -> Option<(usize, Arc<RowDetail>)> {
    self.delegate.get_row_detail(&self.view_id, row_id).await
  }

  pub async fn v_move_group_row(
    &self,
    row: &Row,
    to_group_id: &str,
    to_row_id: Option<RowId>,
  ) -> UpdatedCells {
    let mut updated_cells = UpdatedCells::new();
    let result = self
      .mut_group_controller(|group_controller, field| {
        let move_row_context = MoveGroupRowContext {
          row,
          updated_cells: &mut updated_cells,
          field: &field,
          to_group_id,
          to_row_id,
        };
        group_controller.move_group_row(move_row_context)
      })
      .await;

    handle_mut_group_result(&self.view_id, result).await;
    updated_cells
  }

  /// Only call once after database view editor initialized
  #[tracing::instrument(level = "trace", skip(self))]
  pub async fn v_load_groups(&self) -> Option<Vec<GroupPB>> {
    let groups = self
      .group_controller
      .read()
      .await
      .as_ref()?
      .get_all_groups()
      .into_iter()
      .map(|group_data| GroupPB::from(group_data.clone()))
      .collect::<Vec<_>>();
    tracing::trace!("Number of groups: {}", groups.len());
    Some(groups)
  }

  #[tracing::instrument(level = "trace", skip(self))]
  pub async fn v_get_group(&self, group_id: &str) -> FlowyResult<GroupPB> {
    match self
      .group_controller
      .read()
      .await
      .as_ref()
      .and_then(|group| group.get_group(group_id))
    {
      None => Err(FlowyError::record_not_found().with_context("Can't find the group")),
      Some((_, group)) => Ok(GroupPB::from(group)),
    }
  }

  #[tracing::instrument(level = "trace", skip(self), err)]
  pub async fn v_move_group(&self, from_group: &str, to_group: &str) -> FlowyResult<()> {
    self
      .mut_group_controller(|group_controller, _| group_controller.move_group(from_group, to_group))
      .await;
    Ok(())
  }

  pub async fn is_grouping_field(&self, field_id: &str) -> bool {
    match self.group_controller.read().await.as_ref() {
      Some(group_controller) => group_controller.get_grouping_field_id() == field_id,
      None => false,
    }
  }

  /// Called when the user changes the grouping field
  pub async fn v_initialize_new_group(&self, field_id: &str) -> FlowyResult<()> {
    if let Some(view) = self.delegate.get_view(&self.view_id).await {
      let setting = database_view_setting_pb_from_view(view);
      notify_did_update_setting(&self.view_id, setting).await;
    }

    self.v_group_by_field(field_id).await?;
    Ok(())
  }

  pub async fn v_create_group(&self, name: &str) -> FlowyResult<()> {
    let mut old_field: Option<Field> = None;
    let result = if let Some(controller) = self.group_controller.write().await.as_mut() {
      let create_group_results = controller.create_group(name.to_string()).await?;
      old_field = self
        .delegate
        .get_field(controller.get_grouping_field_id())
        .await;
      create_group_results
    } else {
      (None, None)
    };

    if let Some(old_field) = old_field {
      if let (Some(type_option_data), Some(payload)) = result {
        self
          .delegate
          .update_field(type_option_data, old_field)
          .await?;

        let group_changes = GroupChangesPB {
          view_id: self.view_id.clone(),
          inserted_groups: vec![payload],
          ..Default::default()
        };

        notify_did_update_num_of_groups(&self.view_id, group_changes).await;
      }
    }

    Ok(())
  }

  pub async fn v_delete_group(&self, group_id: &str) -> FlowyResult<RowsChangePB> {
    let mut group_controller = self.group_controller.write().await;
    let controller = match group_controller.as_mut() {
      Some(controller) => controller,
      None => return Ok(RowsChangePB::default()),
    };

    let old_field = self
      .delegate
      .get_field(controller.get_grouping_field_id())
      .await;
    let (row_ids, type_option_data) = controller.delete_group(group_id).await?;

    drop(group_controller);

    let mut changes = RowsChangePB::default();
    if let Some(field) = old_field {
      for row_id in row_ids {
        if let Some(row) = self.delegate.remove_row(&row_id).await {
          changes.deleted_rows.push(row.id.into_inner());
        }
      }

      if let Some(type_option) = type_option_data {
        self.delegate.update_field(type_option, field).await?;
      }
      let notification = GroupChangesPB {
        view_id: self.view_id.clone(),
        deleted_groups: vec![group_id.to_string()],
        ..Default::default()
      };
      notify_did_update_num_of_groups(&self.view_id, notification).await;
    }

    Ok(changes)
  }

  pub async fn v_update_group(&self, changeset: Vec<GroupChangeset>) -> FlowyResult<()> {
    let mut type_option_data = None;
    let (old_field, updated_groups) = if let Some(controller) =
      self.group_controller.write().await.as_mut()
    {
      let old_field = self
        .delegate
        .get_field(controller.get_grouping_field_id())
        .await;
      let (updated_groups, new_type_option) = controller.apply_group_changeset(&changeset).await?;

      if new_type_option.is_some() {
        type_option_data = new_type_option;
      }

      (old_field, updated_groups)
    } else {
      (None, vec![])
    };

    if let Some(old_field) = old_field {
      if let Some(type_option_data) = type_option_data {
        self
          .delegate
          .update_field(type_option_data, old_field)
          .await?;
      }
      let notification = GroupChangesPB {
        view_id: self.view_id.clone(),
        update_groups: updated_groups,
        ..Default::default()
      };
      notify_did_update_num_of_groups(&self.view_id, notification).await;
    }

    Ok(())
  }

  pub async fn v_get_all_sorts(&self) -> Vec<Sort> {
    self.delegate.get_all_sorts(&self.view_id).await
  }

  #[tracing::instrument(level = "trace", skip(self), err)]
  pub async fn v_create_or_update_sort(&self, params: UpdateSortPayloadPB) -> FlowyResult<Sort> {
    let is_exist = params.sort_id.is_some();
    let sort_id = match params.sort_id {
      None => gen_database_sort_id(),
      Some(sort_id) => sort_id,
    };

    let sort = Sort {
      id: sort_id,
      field_id: params.field_id.clone(),
      condition: params.condition.into(),
    };

    self.delegate.insert_sort(&self.view_id, sort.clone()).await;
    let mut sort_controller = self.sort_controller.write().await;
    let notification = if is_exist {
      sort_controller
        .apply_changeset(SortChangeset::from_update(sort.clone()))
        .await
    } else {
      sort_controller
        .apply_changeset(SortChangeset::from_insert(sort.clone()))
        .await
    };
    drop(sort_controller);
    notify_did_update_sort(notification).await;
    Ok(sort)
  }

  pub async fn v_reorder_sort(&self, params: ReorderSortPayloadPB) -> FlowyResult<()> {
    self
      .delegate
      .move_sort(&self.view_id, &params.from_sort_id, &params.to_sort_id)
      .await;

    let notification = self
      .sort_controller
      .write()
      .await
      .apply_changeset(SortChangeset::from_reorder(
        params.from_sort_id,
        params.to_sort_id,
      ))
      .await;

    notify_did_update_sort(notification).await;
    Ok(())
  }

  pub async fn v_delete_sort(&self, params: DeleteSortPayloadPB) -> FlowyResult<()> {
    let notification = self
      .sort_controller
      .write()
      .await
      .apply_changeset(SortChangeset::from_delete(params.sort_id.clone()))
      .await;

    self
      .delegate
      .remove_sort(&self.view_id, &params.sort_id)
      .await;
    notify_did_update_sort(notification).await;

    Ok(())
  }

  #[instrument(level = "trace", skip_all)]
  pub async fn v_calculate_rows(&self, fields: Vec<Field>, rows: Vec<Arc<Row>>) -> FlowyResult<()> {
    let mut updates = vec![];
    // Filter fields to only those with calculations
    let fields_with_calculations: Vec<(&Field, Calculation)> =
      futures::future::join_all(fields.iter().map(|field| async move {
        self
          .delegate
          .get_calculation(&self.view_id, &field.id)
          .await
          .map(|cal| (field, cal))
      }))
      .await
      .into_iter()
      .flatten()
      .collect();

    // Pre-compute cells by field ID only for fields that have calculations
    let mut cells_by_field_id: HashMap<String, Vec<Arc<Cell>>> = fields_with_calculations
      .iter()
      .map(|(field, _)| {
        let cells = rows
          .iter()
          .filter_map(|row| row.cells.get(&field.id).cloned().map(Arc::new))
          .collect::<Vec<Arc<Cell>>>();
        (field.id.clone(), cells)
      })
      .collect();

    // Perform calculations for the filtered fields
    for (field, calculation) in fields_with_calculations {
      if let Some(cells) = cells_by_field_id.remove(&field.id) {
        let changes = self
          .calculations_controller
          .handle_cells_changed(field, &calculation, cells)
          .await;
        updates.extend(changes);
      }
    }

    // Send notification if updates were made
    trace!("Calculations updates: {:?}", updates);
    if !updates.is_empty() {
      let notification = CalculationChangesetNotificationPB::from_update(&self.view_id, updates);
      if let Err(_err) = self
        .notifier
        .send(DatabaseViewChanged::CalculationValueNotification(
          notification,
        ))
      {
        error!("Failed to send CalculationValueNotification");
      }
    }

    Ok(())
  }

  pub async fn v_delete_all_sorts(&self) -> FlowyResult<()> {
    let all_sorts = self.v_get_all_sorts().await;
    self.sort_controller.write().await.delete_all_sorts().await;

    self.delegate.remove_all_sorts(&self.view_id).await;
    let mut notification = SortChangesetNotificationPB::new(self.view_id.clone());
    notification.delete_sorts = all_sorts.into_iter().map(SortPB::from).collect();
    notify_did_update_sort(notification).await;
    Ok(())
  }

  pub async fn v_get_all_calculations(&self) -> Vec<Arc<Calculation>> {
    self.delegate.get_all_calculations(&self.view_id).await
  }

  pub async fn v_update_calculate(&self, field_id: &str) -> Option<()> {
    let field = self.delegate.get_field(field_id).await?;
    let cal = self
      .delegate
      .get_calculation(&self.view_id, &field.id)
      .await?;

    let cells = self
      .delegate
      .get_cells_for_field(&self.view_id, field_id)
      .await
      .into_iter()
      .flat_map(|row_cell| row_cell.cell.map(Arc::new))
      .collect::<Vec<_>>();

    let changes = self
      .calculations_controller
      .handle_cells_changed(&field, &cal, cells)
      .await;

    if !changes.is_empty() {
      let notification = CalculationChangesetNotificationPB::from_update(&self.view_id, changes);
      if let Err(_err) = self
        .notifier
        .send(DatabaseViewChanged::CalculationValueNotification(
          notification,
        ))
      {
        error!("Failed to send CalculationValueNotification");
      }
    }

    None
  }

  pub async fn v_edit_calculations(&self, params: UpdateCalculationChangesetPB) -> FlowyResult<()> {
    let calculation_id = params
      .calculation_id
      .unwrap_or_else(gen_database_calculation_id);
    let calculation = Calculation::none(
      calculation_id,
      params.field_id,
      Some(params.calculation_type.value()),
    );

    let changeset = self
      .calculations_controller
      .did_receive_changes(CalculationChangeset::from_insert(calculation.clone()))
      .await;

    if let Some(changeset) = changeset {
      if !changeset.insert_calculations.is_empty() {
        for insert in changeset.insert_calculations.clone() {
          let calculation: Calculation = Calculation::from(&insert);
          self
            .delegate
            .update_calculation(&params.view_id, calculation)
            .await;
        }
      }

      notify_did_update_calculation(changeset).await;
    }

    Ok(())
  }

  pub async fn v_remove_calculation(
    &self,
    params: RemoveCalculationChangesetPB,
  ) -> FlowyResult<()> {
    self
      .delegate
      .remove_calculation(&params.view_id, &params.calculation_id)
      .await;

    let calculation = Calculation::none(params.calculation_id, params.field_id, None);

    let changeset = self
      .calculations_controller
      .did_receive_changes(CalculationChangeset::from_delete(calculation.clone()))
      .await;

    if let Some(changeset) = changeset {
      notify_did_update_calculation(changeset).await;
    }

    Ok(())
  }

  pub async fn v_get_all_filters(&self) -> Vec<Filter> {
    self.delegate.get_all_filters(&self.view_id).await
  }

  pub async fn v_get_filter(&self, filter_id: &str) -> Option<Filter> {
    self.delegate.get_filter(&self.view_id, filter_id).await
  }

  #[tracing::instrument(level = "trace", skip(self), err)]
  pub async fn v_modify_filters(&self, changeset: FilterChangeset) -> FlowyResult<()> {
    let notification = self.filter_controller.apply_changeset(changeset).await;
    notify_did_update_filter(notification).await;

    let group_controller_read_guard = self.group_controller.read().await;
    let grouping_field_id = group_controller_read_guard
      .as_ref()
      .map(|controller| controller.get_grouping_field_id().to_string());
    drop(group_controller_read_guard);

    if let Some(field_id) = grouping_field_id {
      self.v_group_by_field(&field_id).await?;
    }

    let row_orders = self.delegate.get_all_row_orders(&self.view_id).await;
    let rows = self.delegate.get_all_rows(&self.view_id, row_orders).await;
    let fields = self.delegate.get_fields(&self.view_id, None).await;
    self.v_calculate_rows(fields, rows).await?;
    Ok(())
  }

  /// Returns the current calendar settings
  #[tracing::instrument(level = "trace", skip(self))]
  pub async fn v_get_layout_settings(&self, layout_ty: &DatabaseLayout) -> LayoutSettingParams {
    let mut layout_setting = LayoutSettingParams::default();
    match layout_ty {
      DatabaseLayout::Grid => {},
      DatabaseLayout::Board => {
        if let Some(value) = self
          .delegate
          .get_layout_setting(&self.view_id, layout_ty)
          .await
        {
          layout_setting.board = Some(value.into());
        }
      },
      DatabaseLayout::Calendar => {
        if let Some(value) = self
          .delegate
          .get_layout_setting(&self.view_id, layout_ty)
          .await
        {
          let calendar_setting = CalendarLayoutSetting::from(value);
          // Check the field exist or not
          if let Some(field) = self.delegate.get_field(&calendar_setting.field_id).await {
            let field_type = FieldType::from(field.field_type);

            // Check the type of field is Datetime or not
            if field_type == FieldType::DateTime {
              layout_setting.calendar = Some(calendar_setting);
            } else {
              tracing::warn!("The field of calendar setting is not datetime type")
            }
          } else {
            tracing::warn!("The field of calendar setting is not exist");
          }
        }
      },
    }

    layout_setting
  }

  /// Update the layout settings and send the notification to refresh the UI
  pub async fn v_set_layout_settings(&self, params: LayoutSettingChangeset) -> FlowyResult<()> {
    if self.v_get_layout_type().await != params.layout_type || !params.is_valid() {
      return Err(FlowyError::invalid_data());
    }

    let layout_setting_pb = match params.layout_type {
      DatabaseLayout::Board => {
        let layout_setting = params.board.unwrap();

        self
          .delegate
          .insert_layout_setting(
            &self.view_id,
            &params.layout_type,
            layout_setting.clone().into(),
          )
          .await;

        Some(DatabaseLayoutSettingPB::from_board(layout_setting))
      },
      DatabaseLayout::Calendar => {
        let layout_setting = params.calendar.unwrap();

        if let Some(field) = self.delegate.get_field(&layout_setting.field_id).await {
          if FieldType::from(field.field_type) != FieldType::DateTime {
            return Err(FlowyError::unexpect_calendar_field_type());
          }

          self
            .delegate
            .insert_layout_setting(
              &self.view_id,
              &params.layout_type,
              layout_setting.clone().into(),
            )
            .await;

          Some(DatabaseLayoutSettingPB::from_calendar(layout_setting))
        } else {
          None
        }
      },
      _ => None,
    };

    if let Some(payload) = layout_setting_pb {
      database_notification_builder(&self.view_id, DatabaseNotification::DidUpdateLayoutSettings)
        .payload(payload)
        .send();
    }

    Ok(())
  }

  pub async fn v_did_delete_field(&self, deleted_field_id: &str) {
    let changeset = FilterChangeset::DeleteAllWithFieldId {
      field_id: deleted_field_id.to_string(),
    };
    let notification = self.filter_controller.apply_changeset(changeset).await;
    notify_did_update_filter(notification).await;

    let sorts = self.delegate.get_all_sorts(&self.view_id).await;

    if let Some(sort) = sorts.iter().find(|sort| sort.field_id == deleted_field_id) {
      self.delegate.remove_sort(&self.view_id, &sort.id).await;
      let notification = self
        .sort_controller
        .write()
        .await
        .apply_changeset(SortChangeset::from_delete(sort.id.clone()))
        .await;
      if !notification.is_empty() {
        notify_did_update_sort(notification).await;
      }
    }

    self
      .calculations_controller
      .did_receive_field_deleted(deleted_field_id.to_string())
      .await;
  }

  pub async fn v_did_update_field_type(&self, field_id: &str, new_field_type: FieldType) {
    self
      .sort_controller
      .read()
      .await
      .did_update_field_type()
      .await;
    self
      .calculations_controller
      .did_receive_field_type_changed(field_id.to_owned(), new_field_type)
      .await;
    if self.filter_controller.has_filters().await {
      let changeset = FilterChangeset::DeleteAllWithFieldId {
        field_id: field_id.to_string(),
      };
      let notification = self.filter_controller.apply_changeset(changeset).await;
      notify_did_update_filter(notification).await;
    }
    if self.is_grouping_field(field_id).await {
      let _ = self.v_group_by_field(field_id).await;
    }
  }

  /// Notifies the view's field type-option data is changed
  /// For the moment, only the groups will be generated after the type-option data changed. A
  /// [Field] has a property named type_options contains a list of type-option data.
  #[tracing::instrument(level = "trace", skip_all, err)]
  pub async fn v_did_update_field_type_option(&self, old_field: &Field) -> FlowyResult<()> {
    let field_id = &old_field.id;

    if let Some(field) = self.delegate.get_field(field_id).await {
      self
        .sort_controller
        .read()
        .await
        .did_update_field_type_option(&field)
        .await;

      // If the id of the grouping field is equal to the updated field's id
      // and something critical changed, then we need to update the group setting
      if self.is_grouping_field(field_id).await
        && matches!(
          FieldType::from(field.field_type),
          FieldType::SingleSelect | FieldType::MultiSelect
        )
      {
        self.v_group_by_field(field_id).await?;
      }
    }

    Ok(())
  }

  /// Called when a grouping field is updated.
  #[tracing::instrument(level = "debug", skip_all, err)]
  pub async fn v_group_by_field(&self, field_id: &str) -> FlowyResult<()> {
    if let Some(field) = self.delegate.get_field(field_id).await {
      tracing::trace!("create new group controller");

      let mut new_group_controller = new_group_controller(
        self.view_id.clone(),
        self.delegate.clone(),
        self.filter_controller.clone(),
        Some(field),
      )
      .await?;

      if let Some(controller) = &mut new_group_controller {
        (*controller).load_group_data().await?;

        let new_groups = controller
          .get_all_groups()
          .into_iter()
          .map(|group| GroupPB::from(group.clone()))
          .collect();

        let changeset = GroupChangesPB {
          view_id: self.view_id.clone(),
          initial_groups: new_groups,
          ..Default::default()
        };

        debug_assert!(!changeset.is_empty());
        if !changeset.is_empty() {
          database_notification_builder(&changeset.view_id, DatabaseNotification::DidGroupByField)
            .payload(changeset)
            .send();
        }
      }

      *self.group_controller.write().await = new_group_controller;

      tracing::trace!("did write group_controller to cache");
    }

    Ok(())
  }

  pub async fn v_get_calendar_event(&self, row_id: RowId) -> Option<CalendarEventPB> {
    let layout_ty = DatabaseLayout::Calendar;
    let calendar_setting = self.v_get_layout_settings(&layout_ty).await.calendar?;

    // Text
    let primary_field = self.delegate.get_primary_field().await?;
    let text_cell = get_cell_for_row(self.delegate.clone(), &primary_field.id, &row_id).await?;

    // Date
    let date_field = self.delegate.get_field(&calendar_setting.field_id).await?;

    let date_cell = get_cell_for_row(self.delegate.clone(), &date_field.id, &row_id).await?;
    let title = text_cell
      .into_text_field_cell_data()
      .unwrap_or_default()
      .into();

    let timestamp = date_cell
      .into_date_field_cell_data()
      .unwrap_or_default()
      .timestamp;

    let (_, row_detail) = self.delegate.get_row_detail(&self.view_id, &row_id).await?;

    Some(CalendarEventPB {
      row_meta: RowMetaPB::from(row_detail.as_ref().clone()),
      date_field_id: date_field.id.clone(),
      title,
      timestamp,
    })
  }

  pub async fn v_get_all_calendar_events(&self) -> Option<Vec<CalendarEventPB>> {
    let layout_ty = DatabaseLayout::Calendar;
    let calendar_setting = match self.v_get_layout_settings(&layout_ty).await.calendar {
      None => {
        // When create a new calendar view, the calendar setting should be created
        tracing::error!(
          "Calendar layout setting not found in database view:{}",
          self.view_id
        );
        return None;
      },
      Some(calendar_setting) => calendar_setting,
    };

    let primary_field = self.delegate.get_primary_field().await?;

    let mut events: Vec<CalendarEventPB> = vec![];

    let rows = self.v_get_all_rows().await;

    for row in rows {
      let primary_cell = get_cell_for_row(self.delegate.clone(), &primary_field.id, &row.id).await;
      let timestamp_cell =
        get_cell_for_row(self.delegate.clone(), &calendar_setting.field_id, &row.id).await;

      let timestamp = timestamp_cell
        .and_then(|cell| cell.into_date_field_cell_data())
        .and_then(|cell_data| cell_data.timestamp);

      let title = primary_cell
        .and_then(|cell| cell.into_text_field_cell_data())
        .map(|cell_data| cell_data.into())
        .unwrap_or_default();

      let (_, row_detail) = self.delegate.get_row_detail(&self.view_id, &row.id).await?;
      let event = CalendarEventPB {
        row_meta: RowMetaPB::from(row_detail.as_ref().clone()),
        date_field_id: calendar_setting.field_id.clone(),
        title,
        timestamp,
      };

      events.push(event);
    }

    Some(events)
  }

  pub async fn v_get_layout_type(&self) -> DatabaseLayout {
    self.delegate.get_layout_for_view(&self.view_id).await
  }

  #[tracing::instrument(level = "trace", skip_all)]
  pub async fn v_update_layout_type(&self, new_layout_type: DatabaseLayout) -> FlowyResult<()> {
    self
      .delegate
      .update_layout_type(&self.view_id, &new_layout_type)
      .await;

    // using the {} brackets to denote the lifetime of the resolver. Because the DatabaseLayoutDepsResolver
    // is not sync and send, so we can't pass it to the async block.
    {
      let resolver = DatabaseLayoutDepsResolver::new(self.delegate.get_database(), new_layout_type);
      resolver
        .resolve_deps_when_update_layout_type(&self.view_id)
        .await;
    }

    // initialize the group controller if the current layout support grouping
    let new_group_controller = match new_group_controller(
      self.view_id.clone(),
      self.delegate.clone(),
      self.filter_controller.clone(),
      None,
    )
    .await?
    {
      Some(mut controller) => {
        controller.load_group_data().await?;
        Some(controller)
      },
      None => None,
    };

    *self.group_controller.write().await = new_group_controller;

    let payload = DatabaseLayoutMetaPB {
      view_id: self.view_id.clone(),
      layout: new_layout_type.into(),
    };
    database_notification_builder(&self.view_id, DatabaseNotification::DidUpdateDatabaseLayout)
      .payload(payload)
      .send();

    Ok(())
  }

  pub async fn handle_row_event(&self, event: Cow<'_, DatabaseRowEvent>) {
    let changeset = match event.into_owned() {
      DatabaseRowEvent::InsertRow(row) => RowsChangePB::from_insert(row.into()),
      DatabaseRowEvent::UpdateRow(row) => RowsChangePB::from_update(row.into()),
      DatabaseRowEvent::DeleteRow(row_id) => RowsChangePB::from_delete(row_id.into_inner()),
      DatabaseRowEvent::Move {
        deleted_row_id,
        inserted_row,
      } => RowsChangePB::from_move(vec![deleted_row_id.into_inner()], vec![inserted_row.into()]),
    };

    database_notification_builder(&self.view_id, DatabaseNotification::DidUpdateRow)
      .payload(changeset)
      .send();
  }

  pub async fn v_get_field_settings(&self, field_ids: &[String]) -> HashMap<String, FieldSettings> {
    self
      .delegate
      .get_field_settings(&self.view_id, field_ids)
      .await
  }

  pub async fn v_update_field_settings(&self, params: FieldSettingsChangesetPB) -> FlowyResult<()> {
    self.delegate.update_field_settings(params).await;
    Ok(())
  }

  async fn mut_group_controller<F, T>(&self, f: F) -> Option<T>
  where
    F: FnOnce(&mut Box<dyn GroupController>, Field) -> FlowyResult<T>,
  {
    let group_field_id = self
      .group_controller
      .read()
      .await
      .as_ref()
      .map(|controller| controller.get_grouping_field_id().to_owned())?;
    let field = self.delegate.get_field(&group_field_id).await?;
    let mut write_guard = self.group_controller.write().await;
    if let Some(group_controller) = &mut *write_guard {
      f(group_controller, field).ok()
    } else {
      None
    }
  }

  async fn gen_did_update_row_view_tasks(&self, row_id: RowId, field_id: Option<String>) {
    let weak_filter_controller = Arc::downgrade(&self.filter_controller);
    let weak_sort_controller = Arc::downgrade(&self.sort_controller);
    let weak_calculations_controller = Arc::downgrade(&self.calculations_controller);
    tokio::spawn(async move {
      if let Some(filter_controller) = weak_filter_controller.upgrade() {
        filter_controller
          .did_receive_row_changed(row_id.clone())
          .await;
      }
      if let Some(sort_controller) = weak_sort_controller.upgrade() {
        sort_controller
          .read()
          .await
          .did_receive_row_changed(row_id.clone())
          .await;
      }

      if let Some(calculations_controller) = weak_calculations_controller.upgrade() {
        if let Some(field_id) = field_id {
          calculations_controller
            .did_receive_cell_changed(field_id)
            .await;
        }
      }
    });
  }

  async fn gen_did_create_row_view_tasks(&self, row: Row) {
    let weak_calculations_controller = Arc::downgrade(&self.calculations_controller);
    tokio::spawn(async move {
      if let Some(calculations_controller) = weak_calculations_controller.upgrade() {
        calculations_controller
          .did_receive_row_changed(row.clone())
          .await;
      }
    });
  }
}

async fn handle_mut_group_result(view_id: &str, result: Option<DidMoveGroupRowResult>) {
  if let Some(result) = result {
    if let Some(deleted_group) = result.deleted_group {
      trace!("Delete group after moving the row: {:?}", deleted_group);
      let payload = GroupChangesPB {
        view_id: view_id.to_string(),
        deleted_groups: vec![deleted_group.group_id],
        ..Default::default()
      };
      notify_did_update_num_of_groups(view_id, payload).await;
    }
    for changeset in result.row_changesets {
      trace!("[RowOrder]: group row changeset: {:?}", changeset);
      notify_did_update_group_rows(changeset).await;
    }
  }
}
