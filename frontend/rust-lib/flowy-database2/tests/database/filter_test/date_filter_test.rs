use crate::database::database_editor::{DatabaseEditorTest, FilterRowChanged};
use flowy_database2::entities::{DateFilterConditionPB, DateFilterPB, FieldType};
use lib_infra::box_any::BoxAny;

#[tokio::test]
async fn grid_filter_date_is_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let row_count = test.rows.len();
  let expected = 3;

  // Create "Date Is" filter
  test
    .create_data_filter(
      None,
      FieldType::DateTime,
      BoxAny::new(DateFilterPB {
        condition: DateFilterConditionPB::DateStartsOn,
        start: None,
        end: None,
        timestamp: Some(1647251762),
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
async fn grid_filter_date_after_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let row_count = test.rows.len();
  let expected = 3;

  // Create "Date After" filter
  test
    .create_data_filter(
      None,
      FieldType::DateTime,
      BoxAny::new(DateFilterPB {
        condition: DateFilterConditionPB::DateStartsAfter,
        start: None,
        end: None,
        timestamp: Some(1647251762),
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
async fn grid_filter_date_on_or_after_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let row_count = test.rows.len();
  let expected = 3;

  // Create "Date On Or After" filter
  test
    .create_data_filter(
      None,
      FieldType::DateTime,
      BoxAny::new(DateFilterPB {
        condition: DateFilterConditionPB::DateStartsOnOrAfter,
        start: None,
        end: None,
        timestamp: Some(1668359085),
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
async fn grid_filter_date_on_or_before_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let row_count = test.rows.len();
  let expected = 4;

  // Create "Date On Or Before" filter
  test
    .create_data_filter(
      None,
      FieldType::DateTime,
      BoxAny::new(DateFilterPB {
        condition: DateFilterConditionPB::DateStartsOnOrBefore,
        start: None,
        end: None,
        timestamp: Some(1668359085),
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
async fn grid_filter_date_within_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let row_count = test.rows.len();
  let expected = 5;

  // Create "Date Within Range" filter
  test
    .create_data_filter(
      None,
      FieldType::DateTime,
      BoxAny::new(DateFilterPB {
        condition: DateFilterConditionPB::DateStartsBetween,
        start: Some(1647251762),
        end: Some(1668704685),
        timestamp: None,
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
