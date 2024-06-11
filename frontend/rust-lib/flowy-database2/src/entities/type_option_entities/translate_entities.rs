use crate::services::field::translate_type_option::translate::TranslateTypeOption;
use flowy_derive::ProtoBuf;

#[derive(Debug, Clone, Default, ProtoBuf)]
pub struct TranslateTypeOptionPB {
  #[pb(index = 1)]
  pub auto_fill: bool,

  #[pb(index = 2)]
  pub language: String,
}

impl From<TranslateTypeOption> for TranslateTypeOptionPB {
  fn from(value: TranslateTypeOption) -> Self {
    TranslateTypeOptionPB {
      auto_fill: value.auto_fill,
      language: value.language,
    }
  }
}

impl From<TranslateTypeOptionPB> for TranslateTypeOption {
  fn from(value: TranslateTypeOptionPB) -> Self {
    TranslateTypeOption {
      auto_fill: value.auto_fill,
      language: value.language,
    }
  }
}
