use crate::database::database_editor::{DatabaseEditorTest, FilterRowChanged};
use flowy_database2::entities::{FieldType, NumberFilterConditionPB, NumberFilterPB};
use lib_infra::box_any::BoxAny;

#[tokio::test]
async fn grid_filter_number_is_equal_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let row_count = test.rows.len();
  let expected = 1;

  // Create Number "Equal" filter
  test
    .create_data_filter(
      None,
      FieldType::Number,
      BoxAny::new(NumberFilterPB {
        condition: NumberFilterConditionPB::Equal,
        content: "1".to_string(),
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
async fn grid_filter_number_is_less_than_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let row_count = test.rows.len();
  let expected = 2;

  // Create Number "Less Than" filter
  test
    .create_data_filter(
      None,
      FieldType::Number,
      BoxAny::new(NumberFilterPB {
        condition: NumberFilterConditionPB::LessThan,
        content: "3".to_string(),
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
#[should_panic]
async fn grid_filter_number_is_less_than_test2() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let row_count = test.rows.len();
  let expected = 2;

  // Create Number "Less Than" filter with invalid content (should panic)
  test
    .create_data_filter(
      None,
      FieldType::Number,
      BoxAny::new(NumberFilterPB {
        condition: NumberFilterConditionPB::LessThan,
        content: "$3".to_string(),
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
async fn grid_filter_number_is_less_than_or_equal_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let row_count = test.rows.len();
  let expected = 3;

  // Create Number "Less Than Or Equal" filter
  test
    .create_data_filter(
      None,
      FieldType::Number,
      BoxAny::new(NumberFilterPB {
        condition: NumberFilterConditionPB::LessThanOrEqualTo,
        content: "3".to_string(),
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
async fn grid_filter_number_is_empty_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let row_count = test.rows.len();
  let expected = 2;

  // Create Number "Is Empty" filter
  test
    .create_data_filter(
      None,
      FieldType::Number,
      BoxAny::new(NumberFilterPB {
        condition: NumberFilterConditionPB::NumberIsEmpty,
        content: "".to_string(),
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
async fn grid_filter_number_is_not_empty_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let row_count = test.rows.len();
  let expected = 5;

  // Create Number "Is Not Empty" filter
  test
    .create_data_filter(
      None,
      FieldType::Number,
      BoxAny::new(NumberFilterPB {
        condition: NumberFilterConditionPB::NumberIsNotEmpty,
        content: "".to_string(),
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
