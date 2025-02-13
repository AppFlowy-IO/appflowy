use crate::database::database_editor::{DatabaseEditorTest, FilterRowChanged};
use collab_database::template::check_list_parse::ChecklistCellData;
use flowy_database2::entities::{ChecklistFilterConditionPB, ChecklistFilterPB, FieldType};
use lib_infra::box_any::BoxAny;

#[tokio::test]
async fn grid_filter_checklist_is_incomplete_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let expected = 5;
  let row_count = test.rows.len();
  let option_ids = get_checklist_cell_options(&test).await;

  // Update checklist cell with selected option IDs
  test
    .update_checklist_cell(test.rows[0].id.clone(), option_ids)
    .await;

  // Create Checklist "Is Incomplete" filter
  test
    .create_data_filter(
      None,
      FieldType::Checklist,
      BoxAny::new(ChecklistFilterPB {
        condition: ChecklistFilterConditionPB::IsIncomplete,
      }),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: row_count - expected,
      }),
    )
    .await;

  // Assert the number of visible rows
  test.assert_number_of_visible_rows(expected).await;
}

#[tokio::test]
async fn grid_filter_checklist_is_complete_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let expected = 2;
  let row_count = test.rows.len();
  let option_ids = get_checklist_cell_options(&test).await;

  // Update checklist cell with selected option IDs
  test
    .update_checklist_cell(test.rows[0].id.clone(), option_ids)
    .await;

  // Create Checklist "Is Complete" filter
  test
    .create_data_filter(
      None,
      FieldType::Checklist,
      BoxAny::new(ChecklistFilterPB {
        condition: ChecklistFilterConditionPB::IsComplete,
      }),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: row_count - expected,
      }),
    )
    .await;

  // Assert the number of visible rows
  test.assert_number_of_visible_rows(expected).await;
}

async fn get_checklist_cell_options(test: &DatabaseEditorTest) -> Vec<String> {
  let field = test.get_first_field(FieldType::Checklist).await;
  let row_cell = test.editor.get_cell(&field.id, &test.rows[0].id).await;
  row_cell
    .map_or(ChecklistCellData::default(), |cell| {
      ChecklistCellData::from(&cell)
    })
    .options
    .into_iter()
    .map(|option| option.id)
    .collect()
}
