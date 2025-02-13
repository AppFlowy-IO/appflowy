use crate::database::database_editor::{DatabaseEditorTest, FilterRowChanged};
use flowy_database2::entities::{CheckboxFilterConditionPB, CheckboxFilterPB, FieldType};
use lib_infra::box_any::BoxAny;

#[tokio::test]
async fn grid_filter_checkbox_is_check_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let expected = 3;
  let row_count = test.rows.len();

  // The initial number of checked is 3
  // The initial number of unchecked is 4
  test
    .create_data_filter(
      None,
      FieldType::Checkbox,
      BoxAny::new(CheckboxFilterPB {
        condition: CheckboxFilterConditionPB::IsChecked,
      }),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: row_count - expected,
      }),
    )
    .await;

  test.assert_number_of_visible_rows(expected).await;
}

#[tokio::test]
async fn grid_filter_checkbox_is_uncheck_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let expected = 4;
  let row_count = test.rows.len();

  test
    .create_data_filter(
      None,
      FieldType::Checkbox,
      BoxAny::new(CheckboxFilterPB {
        condition: CheckboxFilterConditionPB::IsUnChecked,
      }),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: row_count - expected,
      }),
    )
    .await;

  test.assert_number_of_visible_rows(expected).await;
}
