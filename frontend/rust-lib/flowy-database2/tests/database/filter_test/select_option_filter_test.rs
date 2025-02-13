use crate::database::database_editor::{DatabaseEditorTest, FilterRowChanged};
use flowy_database2::entities::{FieldType, SelectOptionFilterConditionPB, SelectOptionFilterPB};
use lib_infra::box_any::BoxAny;

#[tokio::test]
async fn grid_filter_multi_select_is_empty_test() {
  let mut test = DatabaseEditorTest::new_grid().await;

  // Create Multi-Select "Is Empty" filter
  test
    .create_data_filter(
      None,
      FieldType::MultiSelect,
      BoxAny::new(SelectOptionFilterPB {
        condition: SelectOptionFilterConditionPB::OptionIsEmpty,
        option_ids: vec![],
      }),
      None,
    )
    .await;

  // Assert the number of visible rows
  test.assert_number_of_visible_rows(2).await;
}

#[tokio::test]
async fn grid_filter_multi_select_is_not_empty_test() {
  let mut test = DatabaseEditorTest::new_grid().await;

  // Create Multi-Select "Is Not Empty" filter
  test
    .create_data_filter(
      None,
      FieldType::MultiSelect,
      BoxAny::new(SelectOptionFilterPB {
        condition: SelectOptionFilterConditionPB::OptionIsNotEmpty,
        option_ids: vec![],
      }),
      None,
    )
    .await;

  // Assert the number of visible rows
  test.assert_number_of_visible_rows(5).await;
}

#[tokio::test]
async fn grid_filter_single_select_is_empty_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let expected = 3;
  let row_count = test.rows.len();

  // Create Single-Select "Is Empty" filter
  test
    .create_data_filter(
      None,
      FieldType::SingleSelect,
      BoxAny::new(SelectOptionFilterPB {
        condition: SelectOptionFilterConditionPB::OptionIsEmpty,
        option_ids: vec![],
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
async fn grid_filter_single_select_is_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let field = test.get_first_field(FieldType::SingleSelect).await;
  let mut options = test.get_single_select_type_option(&field.id).await;
  let expected = 2;
  let row_count = test.rows.len();

  // Create Single-Select "Is" filter with a specific option ID
  test
    .create_data_filter(
      None,
      FieldType::SingleSelect,
      BoxAny::new(SelectOptionFilterPB {
        condition: SelectOptionFilterConditionPB::OptionIs,
        option_ids: vec![options.remove(0).id],
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
async fn grid_filter_single_select_is_test2() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let field = test.get_first_field(FieldType::SingleSelect).await;
  let row_details = test.get_rows().await;
  let mut options = test.get_single_select_type_option(&field.id).await;
  let option = options.remove(0);
  let row_count = test.rows.len();

  // Create Single-Select "Is" filter
  test
    .create_data_filter(
      None,
      FieldType::SingleSelect,
      BoxAny::new(SelectOptionFilterPB {
        condition: SelectOptionFilterConditionPB::OptionIs,
        option_ids: vec![option.id.clone()],
      }),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: row_count - 2,
      }),
    )
    .await;

  test.assert_number_of_visible_rows(2).await;

  // Update single-select cell to match the filter
  test
    .update_single_select_cell_with_change(row_details[1].id.clone(), option.id.clone(), None)
    .await;
  test.assert_number_of_visible_rows(3).await;

  // Update single-select cell to remove the option
  test
    .update_single_select_cell_with_change(
      row_details[1].id.clone(),
      "".to_string(),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: 1,
      }),
    )
    .await;
  test.assert_number_of_visible_rows(2).await;
}

#[tokio::test]
async fn grid_filter_multi_select_contains_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let field = test.get_first_field(FieldType::MultiSelect).await;
  let mut options = test.get_multi_select_type_option(&field.id).await;

  // Create Multi-Select "Contains" filter
  test
    .create_data_filter(
      None,
      FieldType::MultiSelect,
      BoxAny::new(SelectOptionFilterPB {
        condition: SelectOptionFilterConditionPB::OptionContains,
        option_ids: vec![options.remove(0).id, options.remove(0).id],
      }),
      None,
    )
    .await;

  // Assert the number of visible rows
  test.assert_number_of_visible_rows(5).await;
}

#[tokio::test]
async fn grid_filter_multi_select_contains_test2() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let field = test.get_first_field(FieldType::MultiSelect).await;
  let mut options = test.get_multi_select_type_option(&field.id).await;

  // Create Multi-Select "Contains" filter with a specific option ID
  test
    .create_data_filter(
      None,
      FieldType::MultiSelect,
      BoxAny::new(SelectOptionFilterPB {
        condition: SelectOptionFilterConditionPB::OptionContains,
        option_ids: vec![options.remove(1).id],
      }),
      None,
    )
    .await;

  // Assert the number of visible rows
  test.assert_number_of_visible_rows(4).await;
}
