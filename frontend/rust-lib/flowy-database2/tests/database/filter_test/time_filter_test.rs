use crate::database::database_editor::{DatabaseEditorTest, FilterRowChanged};
use flowy_database2::entities::{FieldType, NumberFilterConditionPB, TimeFilterPB};
use lib_infra::box_any::BoxAny;

#[tokio::test]
async fn grid_filter_time_is_equal_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let row_count = test.rows.len();
  let expected = 1;

  // Create Time "Equal" filter
  test
    .create_data_filter(
      None,
      FieldType::Time,
      BoxAny::new(TimeFilterPB {
        condition: NumberFilterConditionPB::Equal,
        content: "75".to_string(),
      }),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: row_count - expected,
      }),
    )
    .await;

  // Assert number of visible rows
  test.assert_number_of_visible_rows(expected).await;
}

#[tokio::test]
async fn grid_filter_time_is_less_than_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let row_count = test.rows.len();
  let expected = 1;

  // Create Time "Less Than" filter
  test
    .create_data_filter(
      None,
      FieldType::Time,
      BoxAny::new(TimeFilterPB {
        condition: NumberFilterConditionPB::LessThan,
        content: "80".to_string(),
      }),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: row_count - expected,
      }),
    )
    .await;

  // Assert number of visible rows
  test.assert_number_of_visible_rows(expected).await;
}

#[tokio::test]
async fn grid_filter_time_is_less_than_or_equal_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let row_count = test.rows.len();
  let expected = 1;

  // Create Time "Less Than or Equal" filter
  test
    .create_data_filter(
      None,
      FieldType::Time,
      BoxAny::new(TimeFilterPB {
        condition: NumberFilterConditionPB::LessThanOrEqualTo,
        content: "75".to_string(),
      }),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: row_count - expected,
      }),
    )
    .await;

  // Assert number of visible rows
  test.assert_number_of_visible_rows(expected).await;
}

#[tokio::test]
async fn grid_filter_time_is_empty_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let row_count = test.rows.len();
  let expected = 6;

  // Create Time "Is Empty" filter
  test
    .create_data_filter(
      None,
      FieldType::Time,
      BoxAny::new(TimeFilterPB {
        condition: NumberFilterConditionPB::NumberIsEmpty,
        content: "".to_string(),
      }),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: row_count - expected,
      }),
    )
    .await;

  // Assert number of visible rows
  test.assert_number_of_visible_rows(expected).await;
}

#[tokio::test]
async fn grid_filter_time_is_not_empty_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let row_count = test.rows.len();
  let expected = 1;

  // Create Time "Is Not Empty" filter
  test
    .create_data_filter(
      None,
      FieldType::Time,
      BoxAny::new(TimeFilterPB {
        condition: NumberFilterConditionPB::NumberIsNotEmpty,
        content: "".to_string(),
      }),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: row_count - expected,
      }),
    )
    .await;

  // Assert number of visible rows
  test.assert_number_of_visible_rows(expected).await;
}
