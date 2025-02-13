use collab_database::database::gen_database_view_id;
use collab_database::fields::checkbox_type_option::CheckboxTypeOption;
use collab_database::fields::checklist_type_option::ChecklistTypeOption;
use collab_database::fields::select_type_option::{
  MultiSelectTypeOption, SelectOption, SingleSelectTypeOption,
};
use collab_database::fields::Field;
use collab_database::rows::{Row, RowId};
use event_integration_test::folder_event::ViewTest;
use event_integration_test::EventIntegrationTest;
use flowy_database2::entities::{
  DatabasePB, DatabaseViewSettingPB, FieldType, FilterPB, FilterType, RowMetaPB,
  TextFilterConditionPB, TextFilterPB, UpdateCalculationChangesetPB,
};
use lib_infra::box_any::BoxAny;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use strum::EnumCount;
use tokio::sync::broadcast::Receiver;

use flowy_database2::services::database::DatabaseEditor;
use flowy_database2::services::database_view::DatabaseViewChanged;
use flowy_database2::services::field::checklist_filter::ChecklistCellChangeset;
use flowy_database2::services::field::SelectOptionCellChangeset;
use flowy_database2::services::filter::{FilterChangeset, FilterInner};
use flowy_database2::services::share::csv::{CSVFormat, ImportResult};
use flowy_error::FlowyResult;

use crate::database::mock_data::{
  make_no_date_test_grid, make_test_board, make_test_calendar, make_test_grid,
};

pub struct DatabaseEditorTest {
  pub sdk: EventIntegrationTest,
  pub view_id: String,
  pub editor: Arc<DatabaseEditor>,
  pub fields: Vec<Arc<Field>>,
  pub rows: Vec<Arc<Row>>,
  pub field_count: usize,
  pub row_by_row_id: HashMap<String, RowMetaPB>,
  view_change_recv: Option<Receiver<DatabaseViewChanged>>,
}

impl DatabaseEditorTest {
  pub async fn new_grid() -> Self {
    let sdk = EventIntegrationTest::new().await;
    let _ = sdk.init_anon_user().await;

    let params = make_test_grid();
    let view_test = ViewTest::new_grid_view(&sdk, params.to_json_bytes().unwrap()).await;
    Self::new(sdk, view_test).await
  }

  pub async fn new_no_date_grid() -> Self {
    let sdk = EventIntegrationTest::new().await;
    let _ = sdk.init_anon_user().await;

    let params = make_no_date_test_grid();
    let view_test = ViewTest::new_grid_view(&sdk, params.to_json_bytes().unwrap()).await;
    Self::new(sdk, view_test).await
  }

  pub async fn new_board() -> Self {
    let sdk = EventIntegrationTest::new().await;
    let _ = sdk.init_anon_user().await;

    let params = make_test_board();
    let view_test = ViewTest::new_board_view(&sdk, params.to_json_bytes().unwrap()).await;
    Self::new(sdk, view_test).await
  }

  pub async fn new_calendar() -> Self {
    let sdk = EventIntegrationTest::new().await;
    let _ = sdk.init_anon_user().await;

    let params = make_test_calendar();
    let view_test = ViewTest::new_grid_view(&sdk, params.to_json_bytes().unwrap()).await;
    Self::new(sdk, view_test).await
  }

  pub async fn new(sdk: EventIntegrationTest, test: ViewTest) -> Self {
    let editor = sdk
      .database_manager
      .get_database_editor_with_view_id(&test.child_view.id)
      .await
      .unwrap();
    let fields = editor
      .get_fields(&test.child_view.id, None)
      .await
      .into_iter()
      .map(Arc::new)
      .collect();
    let rows = editor
      .get_all_rows(&test.child_view.id)
      .await
      .unwrap()
      .into_iter()
      .collect();

    let view_id = test.child_view.id;
    let this = Self {
      sdk,
      view_id: view_id.clone(),
      editor,
      fields,
      rows,
      field_count: FieldType::COUNT,
      row_by_row_id: HashMap::default(),
      view_change_recv: None,
    };
    this.get_database_data(&view_id).await;
    this
  }

  pub async fn get_database_data(&self, view_id: &str) -> DatabasePB {
    self.editor.open_database_view(view_id, None).await.unwrap()
  }

  #[allow(dead_code)]
  pub async fn database_filters(&self) -> Vec<FilterPB> {
    self.editor.get_all_filters(&self.view_id).await.items
  }

  pub async fn get_rows(&self) -> Vec<Arc<Row>> {
    self.editor.get_all_rows(&self.view_id).await.unwrap()
  }

  pub async fn get_field(&self, field_id: &str, field_type: FieldType) -> Field {
    self
      .editor
      .get_fields(&self.view_id, None)
      .await
      .into_iter()
      .filter(|field| {
        let t_field_type = FieldType::from(field.field_type);
        field.id == field_id && t_field_type == field_type
      })
      .collect::<Vec<_>>()
      .pop()
      .unwrap()
  }

  /// returns the first `Field` in the build-in test grid.
  /// Not support duplicate `FieldType` in test grid yet.
  pub async fn get_first_field(&self, field_type: FieldType) -> Field {
    self
      .editor
      .get_fields(&self.view_id, None)
      .await
      .into_iter()
      .filter(|field| {
        let t_field_type = FieldType::from(field.field_type);
        t_field_type == field_type
      })
      .collect::<Vec<_>>()
      .pop()
      .unwrap()
  }

  pub async fn get_fields(&self) -> Vec<Field> {
    self.editor.get_fields(&self.view_id, None).await
  }

  pub async fn get_multi_select_type_option(&self, field_id: &str) -> Vec<SelectOption> {
    let field_type = FieldType::MultiSelect;
    let field = self.get_field(field_id, field_type).await;
    let type_option = field
      .get_type_option::<MultiSelectTypeOption>(field_type)
      .unwrap()
      .0;
    type_option.options
  }

  pub async fn get_single_select_type_option(&self, field_id: &str) -> Vec<SelectOption> {
    let field_type = FieldType::SingleSelect;
    let field = self.get_field(field_id, field_type).await;
    let type_option = field
      .get_type_option::<SingleSelectTypeOption>(field_type)
      .unwrap()
      .0;
    type_option.options
  }

  #[allow(dead_code)]
  pub async fn get_checklist_type_option(&self, field_id: &str) -> ChecklistTypeOption {
    let field_type = FieldType::Checklist;
    let field = self.get_field(field_id, field_type).await;
    field
      .get_type_option::<ChecklistTypeOption>(field_type)
      .unwrap()
  }

  #[allow(dead_code)]
  pub async fn get_checkbox_type_option(&self, field_id: &str) -> CheckboxTypeOption {
    let field_type = FieldType::Checkbox;
    let field = self.get_field(field_id, field_type).await;
    field
      .get_type_option::<CheckboxTypeOption>(field_type)
      .unwrap()
  }

  pub async fn update_cell(
    &self,
    field_id: &str,
    row_id: RowId,
    cell_changeset: BoxAny,
  ) -> FlowyResult<()> {
    let field = self
      .editor
      .get_fields(&self.view_id, None)
      .await
      .into_iter()
      .find(|field| field.id == field_id)
      .unwrap();

    self
      .editor
      .update_cell_with_changeset(&self.view_id, &row_id, &field.id, cell_changeset)
      .await
  }

  pub(crate) async fn update_text_cell(&mut self, row_id: RowId, content: &str) -> FlowyResult<()> {
    let field = self
      .editor
      .get_fields(&self.view_id, None)
      .await
      .iter()
      .find(|field| {
        let field_type = FieldType::from(field.field_type);
        field_type == FieldType::RichText
      })
      .unwrap()
      .clone();

    self
      .update_cell(&field.id, row_id, BoxAny::new(content.to_string()))
      .await
  }

  pub(crate) async fn set_checklist_cell(
    &mut self,
    row_id: RowId,
    selected_options: Vec<String>,
  ) -> FlowyResult<()> {
    let field = self
      .editor
      .get_fields(&self.view_id, None)
      .await
      .iter()
      .find(|field| {
        let field_type = FieldType::from(field.field_type);
        field_type == FieldType::Checklist
      })
      .unwrap()
      .clone();
    let cell_changeset = ChecklistCellChangeset {
      completed_task_ids: selected_options,
      ..Default::default()
    };
    self
      .editor
      .set_checklist_options(&self.view_id, row_id, &field.id, cell_changeset)
      .await
  }

  pub(crate) async fn update_single_select_cell(
    &mut self,
    row_id: RowId,
    option_id: &str,
  ) -> FlowyResult<()> {
    let field = self
      .editor
      .get_fields(&self.view_id, None)
      .await
      .iter()
      .find(|field| {
        let field_type = FieldType::from(field.field_type);
        field_type == FieldType::SingleSelect
      })
      .unwrap()
      .clone();

    let cell_changeset = SelectOptionCellChangeset::from_insert_option_id(option_id);
    self
      .update_cell(&field.id, row_id, BoxAny::new(cell_changeset))
      .await
  }

  pub async fn import(&self, s: String, format: CSVFormat) -> ImportResult {
    self
      .sdk
      .database_manager
      .import_csv(gen_database_view_id(), s, format)
      .await
      .unwrap()
  }

  pub async fn get_database(&self, database_id: &str) -> Option<Arc<DatabaseEditor>> {
    self
      .sdk
      .database_manager
      .get_or_init_database_editor(database_id)
      .await
      .ok()
  }

  pub async fn insert_calculation(&mut self, payload: UpdateCalculationChangesetPB) {
    self.view_change_recv = Some(
      self
        .editor
        .subscribe_view_changed(&self.view_id())
        .await
        .unwrap(),
    );
    self.editor.update_calculation(payload).await.unwrap();
  }

  pub async fn assert_calculation_float_value(&mut self, expected: f64) {
    let calculations = self.editor.get_all_calculations(&self.view_id()).await;
    let calculation = calculations.items.first().unwrap();
    assert_eq!(calculation.value, format!("{:.2}", expected));
  }

  pub async fn assert_calculation_value(&mut self, expected: &str) {
    let calculations = self.editor.get_all_calculations(&self.view_id()).await;
    let calculation = calculations.items.first().unwrap();
    assert_eq!(calculation.value, expected);
  }

  pub async fn duplicate_row(&self, row_id: &RowId) {
    self
      .editor
      .duplicate_row(&self.view_id, row_id)
      .await
      .unwrap();
  }

  pub fn view_id(&self) -> String {
    self.view_id.clone()
  }

  pub async fn get_all_filters(&self) -> Vec<FilterPB> {
    self.editor.get_all_filters(&self.view_id).await.items
  }

  pub async fn get_filter(
    &self,
    filter_type: FilterType,
    field_type: Option<FieldType>,
  ) -> Option<FilterPB> {
    let filters = self.editor.get_all_filters(&self.view_id).await;

    for filter in filters.items.iter() {
      let result = Self::find_filter(filter, filter_type, field_type);
      if result.is_some() {
        return result;
      }
    }

    None
  }

  fn find_filter(
    filter: &FilterPB,
    filter_type: FilterType,
    field_type: Option<FieldType>,
  ) -> Option<FilterPB> {
    match &filter.filter_type {
      FilterType::And | FilterType::Or if filter.filter_type == filter_type => Some(filter.clone()),
      FilterType::And | FilterType::Or => {
        for child_filter in filter.children.iter() {
          if let Some(result) = Self::find_filter(child_filter, filter_type, field_type) {
            return Some(result);
          }
        }
        None
      },
      FilterType::Data
        if filter.filter_type == filter_type
          && field_type.map_or(false, |field_type| {
            field_type == filter.data.clone().unwrap().field_type
          }) =>
      {
        Some(filter.clone())
      },
      _ => None,
    }
  }

  pub async fn update_text_cell_with_change(
    &mut self,
    row_id: RowId,
    text: String,
    changed: Option<FilterRowChanged>,
  ) {
    self.subscribe_view_changed().await;
    self.assert_future_changed(changed).await;
    self.update_text_cell(row_id, &text).await.unwrap();
  }

  pub async fn update_checklist_cell(&mut self, row_id: RowId, selected_option_ids: Vec<String>) {
    self
      .set_checklist_cell(row_id, selected_option_ids)
      .await
      .unwrap();
  }

  pub async fn update_single_select_cell_with_change(
    &mut self,
    row_id: RowId,
    option_id: String,
    changed: Option<FilterRowChanged>,
  ) {
    self.subscribe_view_changed().await;
    self.assert_future_changed(changed).await;
    self
      .update_single_select_cell(row_id, &option_id)
      .await
      .unwrap();
  }

  pub async fn create_data_filter(
    &mut self,
    parent_filter_id: Option<String>,
    field_type: FieldType,
    data: BoxAny,
    changed: Option<FilterRowChanged>,
  ) {
    self.subscribe_view_changed().await;
    self.assert_future_changed(changed).await;
    let field = self.get_first_field(field_type).await;
    let params = FilterChangeset::Insert {
      parent_filter_id,
      data: FilterInner::Data {
        field_id: field.id,
        field_type,
        condition_and_content: data,
      },
    };
    self
      .editor
      .modify_view_filters(&self.view_id, params)
      .await
      .unwrap();
  }

  pub async fn update_text_filter(
    &mut self,
    filter: FilterPB,
    condition: TextFilterConditionPB,
    content: String,
    changed: Option<FilterRowChanged>,
  ) {
    self.subscribe_view_changed().await;
    self.assert_future_changed(changed).await;
    let current_filter = filter.data.unwrap();
    let params = FilterChangeset::UpdateData {
      filter_id: filter.id,
      data: FilterInner::Data {
        field_id: current_filter.field_id,
        field_type: current_filter.field_type,
        condition_and_content: BoxAny::new(TextFilterPB { condition, content }),
      },
    };
    self
      .editor
      .modify_view_filters(&self.view_id, params)
      .await
      .unwrap();
  }

  pub async fn create_and_filter(
    &mut self,
    parent_filter_id: Option<String>,
    changed: Option<FilterRowChanged>,
  ) {
    self.subscribe_view_changed().await;
    self.assert_future_changed(changed).await;
    let params = FilterChangeset::Insert {
      parent_filter_id,
      data: FilterInner::And { children: vec![] },
    };
    self
      .editor
      .modify_view_filters(&self.view_id, params)
      .await
      .unwrap();
  }

  pub async fn create_or_filter(
    &mut self,
    parent_filter_id: Option<String>,
    changed: Option<FilterRowChanged>,
  ) {
    self.subscribe_view_changed().await;
    self.assert_future_changed(changed).await;
    let params = FilterChangeset::Insert {
      parent_filter_id,
      data: FilterInner::Or { children: vec![] },
    };
    self
      .editor
      .modify_view_filters(&self.view_id, params)
      .await
      .unwrap();
  }

  pub async fn delete_filter(&mut self, filter_id: String, changed: Option<FilterRowChanged>) {
    self.subscribe_view_changed().await;
    self.assert_future_changed(changed).await;
    let params = FilterChangeset::Delete { filter_id };
    self
      .editor
      .modify_view_filters(&self.view_id, params)
      .await
      .unwrap();
  }

  pub async fn assert_filter_count(&self, count: usize) {
    let filters = self.editor.get_all_filters(&self.view_id).await.items;
    assert_eq!(count, filters.len());
  }

  pub async fn assert_grid_setting(&self, expected_setting: DatabaseViewSettingPB) {
    let setting = self
      .editor
      .get_database_view_setting(&self.view_id)
      .await
      .unwrap();
    assert_eq!(expected_setting, setting);
  }

  pub async fn assert_filters(&self, expected: Vec<FilterPB>) {
    let actual = self.get_all_filters().await;
    for (actual_filter, expected_filter) in actual.iter().zip(expected.iter()) {
      Self::assert_filter(actual_filter, expected_filter);
    }
  }

  pub async fn assert_number_of_visible_rows(&self, expected: usize) {
    let (tx, rx) = tokio::sync::oneshot::channel();
    let _ = self
      .editor
      .open_database_view(&self.view_id, Some(tx))
      .await
      .unwrap();
    rx.await.unwrap();

    let rows = self.editor.get_all_rows(&self.view_id).await.unwrap();
    assert_eq!(rows.len(), expected);
  }

  pub async fn wait(&self, millisecond: u64) {
    tokio::time::sleep(Duration::from_millis(millisecond)).await;
  }

  async fn subscribe_view_changed(&mut self) {
    self.view_change_recv = Some(
      self
        .editor
        .subscribe_view_changed(&self.view_id)
        .await
        .unwrap(),
    );
  }

  async fn assert_future_changed(&mut self, change: Option<FilterRowChanged>) {
    if change.is_none() {
      return;
    }
    let change = change.unwrap();
    let mut receiver = self.view_change_recv.take().unwrap();
    tokio::spawn(async move {
      match tokio::time::timeout(Duration::from_secs(2), receiver.recv()).await {
        Ok(changed) => {
          if let DatabaseViewChanged::FilterNotification(notification) = changed.unwrap() {
            assert_eq!(
              notification.visible_rows.len(),
              change.showing_num_of_rows,
              "visible rows not match"
            );
            assert_eq!(
              notification.invisible_rows.len(),
              change.hiding_num_of_rows,
              "invisible rows not match"
            );
          }
        },
        Err(e) => {
          panic!("Process filter task timeout: {:?}", e);
        },
      }
    });
  }

  fn assert_filter(actual: &FilterPB, expected: &FilterPB) {
    assert_eq!(actual.filter_type, expected.filter_type);
    assert_eq!(actual.children.is_empty(), expected.children.is_empty());
    assert_eq!(actual.data.is_some(), expected.data.is_some());

    match actual.filter_type {
      FilterType::Data => {
        let actual_data = actual.data.clone().unwrap();
        let expected_data = expected.data.clone().unwrap();
        assert_eq!(actual_data.field_type, expected_data.field_type);
        assert_eq!(actual_data.data, expected_data.data);
      },
      FilterType::And | FilterType::Or => {
        for (actual_child, expected_child) in actual.children.iter().zip(expected.children.iter()) {
          Self::assert_filter(actual_child, expected_child);
        }
      },
    }
  }
}

pub struct FilterRowChanged {
  pub(crate) showing_num_of_rows: usize,
  pub(crate) hiding_num_of_rows: usize,
}
