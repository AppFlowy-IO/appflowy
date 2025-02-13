use std::sync::Arc;

use crate::database::database_editor::{DatabaseEditorTest, FilterRowChanged};
use collab_database::fields::Field;
use flowy_database2::entities::{
  CalculationType, FieldType, NumberFilterConditionPB, NumberFilterPB, UpdateCalculationChangesetPB,
};
use lib_infra::box_any::BoxAny;

#[tokio::test]
async fn calculate_with_filter_test() {
  let mut test = DatabaseEditorTest::new_grid().await;
  let row_count = test.rows.len();
  let expected = 1;
  // let sub = test.sdk.notification_sender.subscribe().await.unwrap();

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
}

#[tokio::test]
async fn insert_delete_calculate_test() {
  let mut test = DatabaseEditorTest::new_grid().await;

  let expected_sum = 25.00;
  let expected_min = 1.00;
  let expected_average = 5.00;
  let expected_max = 14.00;
  let expected_median = 3.00;

  let view_id = &test.view_id();
  let number_fields = test
    .fields
    .clone()
    .into_iter()
    .filter(|field| field.field_type == FieldType::Number as i64)
    .collect::<Vec<Arc<Field>>>();
  let field_id = &number_fields.first().unwrap().id;

  let calculation_id = "calc_id".to_owned();

  // Insert Sum calculation and assert its value
  test
    .insert_calculation(UpdateCalculationChangesetPB {
      view_id: view_id.to_owned(),
      field_id: field_id.to_owned(),
      calculation_id: Some(calculation_id.clone()),
      calculation_type: CalculationType::Sum,
    })
    .await;

  test.assert_calculation_float_value(expected_sum).await;

  // Insert Min calculation and assert its value
  test
    .insert_calculation(UpdateCalculationChangesetPB {
      view_id: view_id.to_owned(),
      field_id: field_id.to_owned(),
      calculation_id: Some(calculation_id.clone()),
      calculation_type: CalculationType::Min,
    })
    .await;

  test.assert_calculation_float_value(expected_min).await;

  // Insert Average calculation and assert its value
  test
    .insert_calculation(UpdateCalculationChangesetPB {
      view_id: view_id.to_owned(),
      field_id: field_id.to_owned(),
      calculation_id: Some(calculation_id.clone()),
      calculation_type: CalculationType::Average,
    })
    .await;

  test.assert_calculation_float_value(expected_average).await;

  // Insert Max calculation and assert its value
  test
    .insert_calculation(UpdateCalculationChangesetPB {
      view_id: view_id.to_owned(),
      field_id: field_id.to_owned(),
      calculation_id: Some(calculation_id.clone()),
      calculation_type: CalculationType::Max,
    })
    .await;

  test.assert_calculation_float_value(expected_max).await;

  // Insert Median calculation and assert its value
  test
    .insert_calculation(UpdateCalculationChangesetPB {
      view_id: view_id.to_owned(),
      field_id: field_id.to_owned(),
      calculation_id: Some(calculation_id.clone()),
      calculation_type: CalculationType::Median,
    })
    .await;

  test.assert_calculation_float_value(expected_median).await;
}

#[tokio::test]
async fn calculations_empty_test() {
  let mut test = DatabaseEditorTest::new_grid().await;

  let view_id = &test.view_id();
  let text_fields = test
    .fields
    .clone()
    .into_iter()
    .filter(|field| field.field_type == FieldType::RichText as i64)
    .collect::<Vec<Arc<Field>>>();
  let field_id = &text_fields.first().unwrap().id.clone();
  let calculation_id = "calc_id".to_owned();

  test
    .insert_calculation(UpdateCalculationChangesetPB {
      view_id: view_id.clone(),
      field_id: field_id.clone(),
      calculation_id: Some(calculation_id.clone()),
      calculation_type: CalculationType::CountEmpty,
    })
    .await;
  test.assert_calculation_value("1").await;

  // Update the cell with a non-empty value
  test
    .update_cell(
      field_id,
      test.rows[1].id.clone(),
      BoxAny::new("change".to_string()),
    )
    .await
    .unwrap();

  // sleep for 3 seconds to wait for the calculation to update
  tokio::time::sleep(tokio::time::Duration::from_secs(3)).await;
  test.assert_calculation_value("0").await;
}

#[tokio::test]
async fn calculations_non_empty_test() {
  let mut test = DatabaseEditorTest::new_grid().await;

  let view_id = &test.view_id();
  let text_fields = test
    .fields
    .clone()
    .into_iter()
    .filter(|field| field.field_type == FieldType::RichText as i64)
    .collect::<Vec<Arc<Field>>>();
  let field_id = &text_fields.first().unwrap().id.clone();
  let calculation_id = "calc_id".to_owned();

  test
    .insert_calculation(UpdateCalculationChangesetPB {
      view_id: view_id.clone(),
      field_id: field_id.clone(),
      calculation_id: Some(calculation_id.clone()),
      calculation_type: CalculationType::CountNonEmpty,
    })
    .await;
  test.assert_calculation_value("6").await;

  // Update the cell with a non-empty value
  test
    .update_cell(
      field_id,
      test.rows[1].id.clone(),
      BoxAny::new("change".to_string()),
    )
    .await
    .unwrap();

  // sleep for 3 seconds to wait for the calculation to update
  tokio::time::sleep(tokio::time::Duration::from_secs(3)).await;
  test.assert_calculation_value("7").await;
}

#[tokio::test]
async fn calculations_count_test() {
  let mut test = DatabaseEditorTest::new_grid().await;

  let view_id = &test.view_id();
  let text_fields = test
    .fields
    .clone()
    .into_iter()
    .filter(|field| field.field_type == FieldType::RichText as i64)
    .collect::<Vec<Arc<Field>>>();
  let field_id = &text_fields.first().unwrap().id.clone();
  let calculation_id = "calc_id".to_owned();

  test
    .insert_calculation(UpdateCalculationChangesetPB {
      view_id: view_id.clone(),
      field_id: field_id.clone(),
      calculation_id: Some(calculation_id.clone()),
      calculation_type: CalculationType::Count,
    })
    .await;
  test.assert_calculation_value("7").await;
  test.duplicate_row(&test.rows[1].id).await;

  tokio::time::sleep(tokio::time::Duration::from_secs(3)).await;
  test.assert_calculation_value("8").await;
}
