use crate::database::database_editor::{DatabaseEditorTest, FilterRowChanged};
use bytes::Bytes;
use flowy_database2::entities::{
  CheckboxFilterConditionPB, CheckboxFilterPB, DateFilterConditionPB, DateFilterPB, FieldType,
  FilterDataPB, FilterPB, FilterType, NumberFilterConditionPB, NumberFilterPB,
};
use lib_infra::box_any::BoxAny;
use protobuf::ProtobufError;
use std::convert::TryInto;

/// Create a single advanced filter:
///
/// 1. Add an OR filter
/// 2. Add a Checkbox and an AND filter to its children
/// 3. Add a DateTime and a Number filter to the AND filter's children
///
#[tokio::test]
async fn create_advanced_filter_test() {
  let mut test = DatabaseEditorTest::new_grid().await;

  let create_checkbox_filter = || -> CheckboxFilterPB {
    CheckboxFilterPB {
      condition: CheckboxFilterConditionPB::IsChecked,
    }
  };

  let create_date_filter = || -> DateFilterPB {
    DateFilterPB {
      condition: DateFilterConditionPB::DateStartsAfter,
      timestamp: Some(1651366800),
      ..Default::default()
    }
  };

  let create_number_filter = || -> NumberFilterPB {
    NumberFilterPB {
      condition: NumberFilterConditionPB::NumberIsNotEmpty,
      content: "".to_string(),
    }
  };

  // Create OR Filter
  test.create_or_filter(None, None).await;
  test.wait(100).await;

  test
    .assert_filters(vec![FilterPB {
      id: "".to_string(),
      filter_type: FilterType::Or,
      children: vec![],
      data: None,
    }])
    .await;

  let or_filter = test.get_filter(FilterType::Or, None).await.unwrap();

  let checkbox_filter_bytes: Result<Bytes, ProtobufError> = create_checkbox_filter().try_into();
  let checkbox_filter_bytes = checkbox_filter_bytes.unwrap().to_vec();

  // Create Checkbox Filter and AND Filter
  test
    .create_data_filter(
      Some(or_filter.id.clone()),
      FieldType::Checkbox,
      BoxAny::new(create_checkbox_filter()),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: 4,
      }),
    )
    .await;

  test
    .create_and_filter(Some(or_filter.id.clone()), None)
    .await;
  test.wait(100).await;

  test
    .assert_filters(vec![FilterPB {
      id: "".to_string(),
      filter_type: FilterType::Or,
      children: vec![
        FilterPB {
          id: "".to_string(),
          filter_type: FilterType::Data,
          children: vec![],
          data: Some(FilterDataPB {
            field_id: "".to_string(),
            field_type: FieldType::Checkbox,
            data: checkbox_filter_bytes.clone(),
          }),
        },
        FilterPB {
          id: "".to_string(),
          filter_type: FilterType::And,
          children: vec![],
          data: None,
        },
      ],
      data: None,
    }])
    .await;

  test.assert_number_of_visible_rows(3).await;

  let and_filter = test.get_filter(FilterType::And, None).await.unwrap();

  let date_filter_bytes: Result<Bytes, ProtobufError> = create_date_filter().try_into();
  let date_filter_bytes = date_filter_bytes.unwrap().to_vec();
  let number_filter_bytes: Result<Bytes, ProtobufError> = create_number_filter().try_into();
  let number_filter_bytes = number_filter_bytes.unwrap().to_vec();

  // Create Date Filter and Number Filter
  test
    .create_data_filter(
      Some(and_filter.id.clone()),
      FieldType::DateTime,
      BoxAny::new(create_date_filter()),
      None,
    )
    .await;

  test
    .create_data_filter(
      Some(and_filter.id),
      FieldType::Number,
      BoxAny::new(create_number_filter()),
      None,
    )
    .await;

  test.wait(100).await;

  test
    .assert_filters(vec![FilterPB {
      id: "".to_string(),
      filter_type: FilterType::Or,
      children: vec![
        FilterPB {
          id: "".to_string(),
          filter_type: FilterType::Data,
          children: vec![],
          data: Some(FilterDataPB {
            field_id: "".to_string(),
            field_type: FieldType::Checkbox,
            data: checkbox_filter_bytes,
          }),
        },
        FilterPB {
          id: "".to_string(),
          filter_type: FilterType::And,
          children: vec![
            FilterPB {
              id: "".to_string(),
              filter_type: FilterType::Data,
              children: vec![],
              data: Some(FilterDataPB {
                field_id: "".to_string(),
                field_type: FieldType::DateTime,
                data: date_filter_bytes,
              }),
            },
            FilterPB {
              id: "".to_string(),
              filter_type: FilterType::Data,
              children: vec![],
              data: Some(FilterDataPB {
                field_id: "".to_string(),
                field_type: FieldType::Number,
                data: number_filter_bytes,
              }),
            },
          ],
          data: None,
        },
      ],
      data: None,
    }])
    .await;

  test.assert_number_of_visible_rows(4).await;
}

/// Create the same advanced filter single advanced filter:
///
/// 1. Add an OR filter
/// 2. Add a Checkbox and a DateTime filter to its children
/// 3. Add a Number filter to the DateTime filter's children
///
#[tokio::test]
async fn create_advanced_filter_with_conversion_test() {
  let mut test = DatabaseEditorTest::new_grid().await;

  let create_checkbox_filter = || -> CheckboxFilterPB {
    CheckboxFilterPB {
      condition: CheckboxFilterConditionPB::IsChecked,
    }
  };

  let create_date_filter = || -> DateFilterPB {
    DateFilterPB {
      condition: DateFilterConditionPB::DateStartsAfter,
      timestamp: Some(1651366800),
      ..Default::default()
    }
  };

  let create_number_filter = || -> NumberFilterPB {
    NumberFilterPB {
      condition: NumberFilterConditionPB::NumberIsNotEmpty,
      content: "".to_string(),
    }
  };

  // Create OR Filter
  test.create_or_filter(None, None).await;

  let or_filter = test.get_filter(FilterType::Or, None).await.unwrap();

  // Create Checkbox Filter and Date Filter
  test
    .create_data_filter(
      Some(or_filter.id.clone()),
      FieldType::Checkbox,
      BoxAny::new(create_checkbox_filter()),
      Some(FilterRowChanged {
        showing_num_of_rows: 0,
        hiding_num_of_rows: 4,
      }),
    )
    .await;

  test
    .create_data_filter(
      Some(or_filter.id.clone()),
      FieldType::DateTime,
      BoxAny::new(create_date_filter()),
      None,
    )
    .await;

  let date_filter = test
    .get_filter(FilterType::Data, Some(FieldType::DateTime))
    .await
    .unwrap();

  let checkbox_filter_bytes: Result<Bytes, ProtobufError> = create_checkbox_filter().try_into();
  let checkbox_filter_bytes = checkbox_filter_bytes.unwrap().to_vec();
  let date_filter_bytes: Result<Bytes, ProtobufError> = create_date_filter().try_into();
  let date_filter_bytes = date_filter_bytes.unwrap().to_vec();
  let number_filter_bytes: Result<Bytes, ProtobufError> = create_number_filter().try_into();
  let number_filter_bytes = number_filter_bytes.unwrap().to_vec();

  // Create Number Filter
  test
    .create_data_filter(
      Some(date_filter.id),
      FieldType::Number,
      BoxAny::new(create_number_filter()),
      None,
    )
    .await;

  test.wait(100).await;

  test
    .assert_filters(vec![FilterPB {
      id: "".to_string(),
      filter_type: FilterType::Or,
      children: vec![
        FilterPB {
          id: "".to_string(),
          filter_type: FilterType::Data,
          children: vec![],
          data: Some(FilterDataPB {
            field_id: "".to_string(),
            field_type: FieldType::Checkbox,
            data: checkbox_filter_bytes,
          }),
        },
        FilterPB {
          id: "".to_string(),
          filter_type: FilterType::And,
          children: vec![
            FilterPB {
              id: "".to_string(),
              filter_type: FilterType::Data,
              children: vec![],
              data: Some(FilterDataPB {
                field_id: "".to_string(),
                field_type: FieldType::DateTime,
                data: date_filter_bytes,
              }),
            },
            FilterPB {
              id: "".to_string(),
              filter_type: FilterType::Data,
              children: vec![],
              data: Some(FilterDataPB {
                field_id: "".to_string(),
                field_type: FieldType::Number,
                data: number_filter_bytes,
              }),
            },
          ],
          data: None,
        },
      ],
      data: None,
    }])
    .await;

  test.assert_number_of_visible_rows(4).await;
}
