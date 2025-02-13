use crate::database::database_editor::{DatabaseEditorTest, FilterRowChanged};
use flowy_database2::entities::{FieldType, TextFilterConditionPB, TextFilterPB};
use lib_infra::box_any::BoxAny;

#[tokio::test]
async fn grid_filter_text_is_empty_test() {
  let mut test = DatabaseEditorTest::new_grid().await;

  // Create Text "Is Empty" filter
  test
    .create_data_filter(
      None,
      FieldType::RichText,
      BoxAny::new(TextFilterPB {
        condition: TextFilterConditionPB::TextIsEmpty,
        content: "".to_string(),
      }),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: 5,
      }),
    )
    .await;

  // Assert filter count
  test.assert_filter_count(1).await;
}

#[tokio::test]
async fn grid_filter_text_is_not_empty_test() {
  let mut test = DatabaseEditorTest::new_grid().await;

  // Create Text "Is Not Empty" filter
  test
    .create_data_filter(
      None,
      FieldType::RichText,
      BoxAny::new(TextFilterPB {
        condition: TextFilterConditionPB::TextIsNotEmpty,
        content: "".to_string(),
      }),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: 1,
      }),
    )
    .await;

  // Assert filter count
  test.assert_filter_count(1).await;

  // Delete the filter
  let filter = test.get_all_filters().await.pop().unwrap();
  test
    .delete_filter(
      filter.id,
      Some(FilterRowChanged {
        showing_num_of_rows: 1,
        hiding_num_of_rows: 0,
      }),
    )
    .await;

  // Assert filter count after deletion
  test.assert_filter_count(0).await;
}

#[tokio::test]
async fn grid_filter_is_text_test() {
  let mut test = DatabaseEditorTest::new_grid().await;

  // Create Text "Is" filter
  test
    .create_data_filter(
      None,
      FieldType::RichText,
      BoxAny::new(TextFilterPB {
        condition: TextFilterConditionPB::TextIs,
        content: "A".to_string(),
      }),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: 5,
      }),
    )
    .await;
}

#[tokio::test]
async fn grid_filter_contain_text_test() {
  let mut test = DatabaseEditorTest::new_grid().await;

  // Create Text "Contains" filter
  test
    .create_data_filter(
      None,
      FieldType::RichText,
      BoxAny::new(TextFilterPB {
        condition: TextFilterConditionPB::TextContains,
        content: "A".to_string(),
      }),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: 2,
      }),
    )
    .await;
}

#[tokio::test]
async fn grid_filter_contain_text_test2() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let row_detail = test.rows.clone();

  // Create Text "Contains" filter
  test
    .create_data_filter(
      None,
      FieldType::RichText,
      BoxAny::new(TextFilterPB {
        condition: TextFilterConditionPB::TextContains,
        content: "A".to_string(),
      }),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: 2,
      }),
    )
    .await;

  // Update the text of a row
  test
    .update_text_cell_with_change(
      row_detail[1].id.clone(),
      "ABC".to_string(),
      Some(FilterRowChanged {
        showing_num_of_rows: 1,
        hiding_num_of_rows: 0,
      }),
    )
    .await;
}

#[tokio::test]
async fn grid_filter_does_not_contain_text_test() {
  let mut test = DatabaseEditorTest::new_grid().await;

  // Create Text "Does Not Contain" filter
  test
    .create_data_filter(
      None,
      FieldType::RichText,
      BoxAny::new(TextFilterPB {
        condition: TextFilterConditionPB::TextDoesNotContain,
        content: "AB".to_string(),
      }),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: 0,
      }),
    )
    .await;
}

#[tokio::test]
async fn grid_filter_start_with_text_test() {
  let mut test = DatabaseEditorTest::new_grid().await;

  // Create Text "Starts With" filter
  test
    .create_data_filter(
      None,
      FieldType::RichText,
      BoxAny::new(TextFilterPB {
        condition: TextFilterConditionPB::TextStartsWith,
        content: "A".to_string(),
      }),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: 3,
      }),
    )
    .await;
}

#[tokio::test]
async fn grid_filter_ends_with_text_test() {
  let mut test = DatabaseEditorTest::new_grid().await;

  // Create Text "Ends With" filter
  test
    .create_data_filter(
      None,
      FieldType::RichText,
      BoxAny::new(TextFilterPB {
        condition: TextFilterConditionPB::TextEndsWith,
        content: "A".to_string(),
      }),
      None,
    )
    .await;

  // Assert number of visible rows
  test.assert_number_of_visible_rows(2).await;
}

#[tokio::test]
async fn grid_update_text_filter_test() {
  let mut test = DatabaseEditorTest::new_grid().await;

  // Create Text "Ends With" filter
  test
    .create_data_filter(
      None,
      FieldType::RichText,
      BoxAny::new(TextFilterPB {
        condition: TextFilterConditionPB::TextEndsWith,
        content: "A".to_string(),
      }),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: 4,
      }),
    )
    .await;

  // Assert number of visible rows and filter count
  test.assert_number_of_visible_rows(2).await;
  test.assert_filter_count(1).await;

  // Update the filter
  let filter = test.get_all_filters().await.pop().unwrap();
  test
    .update_text_filter(
      filter,
      TextFilterConditionPB::TextIs,
      "A".to_string(),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: 1,
      }),
    )
    .await;

  // Assert number of visible rows after update
  test.assert_number_of_visible_rows(1).await;
}

#[tokio::test]
async fn grid_filter_delete_test() {
  let mut test = DatabaseEditorTest::new_grid().await;

  // Create Text "Is Empty" filter
  test
    .create_data_filter(
      None,
      FieldType::RichText,
      BoxAny::new(TextFilterPB {
        condition: TextFilterConditionPB::TextIsEmpty,
        content: "".to_string(),
      }),
      None,
    )
    .await;

  // Assert filter count and number of visible rows
  test.assert_filter_count(1).await;
  test.assert_number_of_visible_rows(1).await;

  // Delete the filter
  let filter = test.get_all_filters().await.pop().unwrap();
  test.delete_filter(filter.id, None).await;

  // Assert filter count and number of visible rows after deletion
  test.assert_filter_count(0).await;
  test.assert_number_of_visible_rows(7).await;
}

#[tokio::test]
async fn grid_filter_update_empty_text_cell_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let row = test.rows.clone();

  // Create Text "Is Empty" filter
  test
    .create_data_filter(
      None,
      FieldType::RichText,
      BoxAny::new(TextFilterPB {
        condition: TextFilterConditionPB::TextIsEmpty,
        content: "".to_string(),
      }),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: 5,
      }),
    )
    .await;

  // Assert filter count
  test.assert_filter_count(1).await;

  // Update the text of a row
  test
    .update_text_cell_with_change(
      row[0].id.clone(),
      "".to_string(),
      Some(FilterRowChanged {
        showing_num_of_rows: 1,
        hiding_num_of_rows: 0,
      }),
    )
    .await;
}
