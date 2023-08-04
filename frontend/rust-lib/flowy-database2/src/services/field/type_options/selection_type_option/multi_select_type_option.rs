use std::cmp::Ordering;

use collab::core::any_map::AnyMapExtension;
use collab_database::fields::{TypeOptionData, TypeOptionDataBuilder};
use collab_database::rows::Cell;
use serde::{Deserialize, Serialize};

use flowy_error::FlowyResult;

use crate::entities::{FieldType, SelectOptionCellDataPB, SelectOptionFilterPB};
use crate::services::cell::CellDataChangeset;
use crate::services::field::{
  default_order, SelectOption, SelectOptionCellChangeset, SelectOptionIds,
  SelectTypeOptionSharedAction, TypeOption, TypeOptionCellData, TypeOptionCellDataCompare,
  TypeOptionCellDataFilter,
};
use crate::services::sort::SortCondition;

// Multiple select
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct MultiSelectTypeOption {
  pub options: Vec<SelectOption>,
  pub disable_color: bool,
}

impl TypeOption for MultiSelectTypeOption {
  type CellData = SelectOptionIds;
  type CellChangeset = SelectOptionCellChangeset;
  type CellProtobufType = SelectOptionCellDataPB;
  type CellFilter = SelectOptionFilterPB;
}

impl From<TypeOptionData> for MultiSelectTypeOption {
  fn from(data: TypeOptionData) -> Self {
    data
      .get_str_value("content")
      .map(|s| serde_json::from_str::<MultiSelectTypeOption>(&s).unwrap_or_default())
      .unwrap_or_default()
  }
}

impl From<MultiSelectTypeOption> for TypeOptionData {
  fn from(data: MultiSelectTypeOption) -> Self {
    let content = serde_json::to_string(&data).unwrap_or_default();
    TypeOptionDataBuilder::new()
      .insert_str_value("content", content)
      .build()
  }
}

impl TypeOptionCellData for MultiSelectTypeOption {
  fn protobuf_encode(
    &self,
    cell_data: <Self as TypeOption>::CellData,
  ) -> <Self as TypeOption>::CellProtobufType {
    self.get_selected_options(cell_data).into()
  }

  fn parse_cell(&self, cell: &Cell) -> FlowyResult<<Self as TypeOption>::CellData> {
    Ok(SelectOptionIds::from(cell))
  }
}

impl SelectTypeOptionSharedAction for MultiSelectTypeOption {
  fn number_of_max_options(&self) -> Option<usize> {
    None
  }

  fn to_type_option_data(&self) -> TypeOptionData {
    self.clone().into()
  }

  fn options(&self) -> &Vec<SelectOption> {
    &self.options
  }

  fn mut_options(&mut self) -> &mut Vec<SelectOption> {
    &mut self.options
  }
}

impl CellDataChangeset for MultiSelectTypeOption {
  fn apply_changeset(
    &self,
    changeset: <Self as TypeOption>::CellChangeset,
    cell: Option<Cell>,
  ) -> FlowyResult<(Cell, <Self as TypeOption>::CellData)> {
    let insert_option_ids = changeset
      .insert_option_ids
      .into_iter()
      .filter(|insert_option_id| {
        self
          .options
          .iter()
          .any(|option| &option.id == insert_option_id)
      })
      .collect::<Vec<String>>();

    let select_option_ids = match cell {
      None => SelectOptionIds::from(insert_option_ids),
      Some(cell) => {
        let mut select_ids = SelectOptionIds::from(&cell);
        for insert_option_id in insert_option_ids {
          if !select_ids.contains(&insert_option_id) {
            select_ids.push(insert_option_id);
          }
        }

        for delete_option_id in changeset.delete_option_ids {
          select_ids.retain(|id| id != &delete_option_id);
        }

        tracing::trace!("Multi-select cell data: {}", select_ids.to_string());
        select_ids
      },
    };
    Ok((
      select_option_ids.to_cell_data(FieldType::MultiSelect),
      select_option_ids,
    ))
  }
}

impl TypeOptionCellDataFilter for MultiSelectTypeOption {
  fn apply_filter(
    &self,
    filter: &<Self as TypeOption>::CellFilter,
    field_type: &FieldType,
    cell_data: &<Self as TypeOption>::CellData,
  ) -> bool {
    if !field_type.is_multi_select() {
      return true;
    }
    let selected_options = self.get_selected_options(cell_data.clone()).select_options;
    filter.is_visible(&selected_options, FieldType::MultiSelect)
  }
}

impl TypeOptionCellDataCompare for MultiSelectTypeOption {
  fn apply_cmp(
    &self,
    cell_data: &<Self as TypeOption>::CellData,
    other_cell_data: &<Self as TypeOption>::CellData,
    sort_condition: SortCondition,
  ) -> Ordering {
    match cell_data.len().cmp(&other_cell_data.len()) {
      Ordering::Equal => {
        for (left_id, right_id) in cell_data.iter().zip(other_cell_data.iter()) {
          let left = self.options.iter().find(|option| &option.id == left_id);
          let right = self.options.iter().find(|option| &option.id == right_id);

          let order = match (left, right) {
            (None, None) => Ordering::Equal,
            (None, Some(_)) => Ordering::Greater,
            (Some(_), None) => Ordering::Less,
            (Some(left_option), Some(right_option)) => {
              let name_order = left_option.name.cmp(&right_option.name);
              match sort_condition {
                SortCondition::Ascending => name_order,
                SortCondition::Descending => name_order.reverse(),
              }
            },
          };

          if order.is_ne() {
            return order;
          }
        }
        default_order()
      },
      order => match sort_condition {
        SortCondition::Ascending => order,
        SortCondition::Descending => order.reverse(),
      },
    }
  }

  fn apply_cmp_with_uninitialized(
    &self,
    cell_data: Option<&<Self as TypeOption>::CellData>,
    other_cell_data: Option<&<Self as TypeOption>::CellData>,
    _sort_conditon: SortCondition,
  ) -> Ordering {
    match (cell_data, other_cell_data) {
      (None, Some(cell_data)) if !cell_data.is_empty() => Ordering::Greater,
      (Some(cell_data), None) if !cell_data.is_empty() => Ordering::Less,
      _ => Ordering::Equal,
    }
  }
}

#[cfg(test)]
mod tests {
  use crate::entities::FieldType;
  use crate::services::cell::CellDataChangeset;
  use crate::services::field::type_options::selection_type_option::*;
  use crate::services::field::MultiSelectTypeOption;
  use crate::services::field::{CheckboxTypeOption, TypeOptionTransform};

  #[test]
  fn multi_select_transform_with_checkbox_type_option_test() {
    let checkbox_type_option = CheckboxTypeOption { is_selected: false };
    let mut multi_select = MultiSelectTypeOption::default();
    multi_select.transform_type_option(FieldType::Checkbox, checkbox_type_option.clone().into());
    debug_assert_eq!(multi_select.options.len(), 2);

    // Already contain the yes/no option. It doesn't need to insert new options
    multi_select.transform_type_option(FieldType::Checkbox, checkbox_type_option.into());
    debug_assert_eq!(multi_select.options.len(), 2);
  }

  #[test]
  fn multi_select_transform_with_single_select_type_option_test() {
    let google = SelectOption::new("Google");
    let facebook = SelectOption::new("Facebook");
    let single_select = SingleSelectTypeOption {
      options: vec![google, facebook],
      disable_color: false,
    };
    let mut multi_select = MultiSelectTypeOption {
      options: vec![],
      disable_color: false,
    };
    multi_select.transform_type_option(FieldType::MultiSelect, single_select.into());
    debug_assert_eq!(multi_select.options.len(), 2);
  }

  // #[test]

  #[test]
  fn multi_select_insert_multi_option_test() {
    let google = SelectOption::new("Google");
    let facebook = SelectOption::new("Facebook");
    let multi_select = MultiSelectTypeOption {
      options: vec![google.clone(), facebook.clone()],
      disable_color: false,
    };

    let option_ids = vec![google.id, facebook.id];
    let changeset = SelectOptionCellChangeset::from_insert_options(option_ids.clone());
    let select_option_ids: SelectOptionIds =
      multi_select.apply_changeset(changeset, None).unwrap().1;

    assert_eq!(&*select_option_ids, &option_ids);
  }

  #[test]
  fn multi_select_unselect_multi_option_test() {
    let google = SelectOption::new("Google");
    let facebook = SelectOption::new("Facebook");
    let multi_select = MultiSelectTypeOption {
      options: vec![google.clone(), facebook.clone()],
      disable_color: false,
    };
    let option_ids = vec![google.id, facebook.id];

    // insert
    let changeset = SelectOptionCellChangeset::from_insert_options(option_ids.clone());
    let select_option_ids = multi_select.apply_changeset(changeset, None).unwrap().1;
    assert_eq!(&*select_option_ids, &option_ids);

    // delete
    let changeset = SelectOptionCellChangeset::from_delete_options(option_ids);
    let select_option_ids = multi_select.apply_changeset(changeset, None).unwrap().1;
    assert!(select_option_ids.is_empty());
  }

  #[test]
  fn multi_select_insert_single_option_test() {
    let google = SelectOption::new("Google");
    let multi_select = MultiSelectTypeOption {
      options: vec![google.clone()],
      disable_color: false,
    };

    let changeset = SelectOptionCellChangeset::from_insert_option_id(&google.id);
    let select_option_ids = multi_select.apply_changeset(changeset, None).unwrap().1;
    assert_eq!(select_option_ids.to_string(), google.id);
  }

  #[test]
  fn multi_select_insert_non_exist_option_test() {
    let google = SelectOption::new("Google");
    let multi_select = MultiSelectTypeOption {
      options: vec![],
      disable_color: false,
    };

    let changeset = SelectOptionCellChangeset::from_insert_option_id(&google.id);
    let (_, select_option_ids) = multi_select.apply_changeset(changeset, None).unwrap();
    assert!(select_option_ids.is_empty());
  }

  #[test]
  fn multi_select_insert_invalid_option_id_test() {
    let google = SelectOption::new("Google");
    let multi_select = MultiSelectTypeOption {
      options: vec![google],
      disable_color: false,
    };

    // empty option id string
    let changeset = SelectOptionCellChangeset::from_insert_option_id("");
    let (cell, _) = multi_select.apply_changeset(changeset, None).unwrap();
    let option_ids = SelectOptionIds::from(&cell);
    assert!(option_ids.is_empty());

    let changeset = SelectOptionCellChangeset::from_insert_option_id("123,456");
    let select_option_ids = multi_select.apply_changeset(changeset, None).unwrap().1;
    assert!(select_option_ids.is_empty());
  }
}
