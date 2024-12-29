use crate::local_ai::local_llm_chat::LLMModelInfo;
use appflowy_plugin::core::plugin::RunningState;
use std::collections::HashMap;

use crate::local_ai::local_llm_resource::PendingResource;
use flowy_ai_pub::cloud::{
  ChatMessage, ChatSettings, LLMModel, RelatedQuestion, RepeatedChatMessage,
  RepeatedRelatedQuestion,
};
use flowy_derive::{ProtoBuf, ProtoBuf_Enum};
use lib_infra::validator_fn::required_not_empty_str;
use validator::Validate;

#[derive(Default, ProtoBuf, Validate, Clone, Debug)]
pub struct ChatId {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub value: String,
}

#[derive(Default, ProtoBuf, Clone, Debug)]
pub struct ChatInfoPB {
  #[pb(index = 1)]
  pub chat_id: String,

  #[pb(index = 2)]
  pub files: Vec<FilePB>,
}

#[derive(Default, ProtoBuf, Clone, Debug)]
pub struct FilePB {
  #[pb(index = 1)]
  pub id: String,
  #[pb(index = 2)]
  pub name: String,
}

#[derive(Default, ProtoBuf, Validate, Clone, Debug)]
pub struct SendChatPayloadPB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub chat_id: String,

  #[pb(index = 2)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub message: String,

  #[pb(index = 3)]
  pub message_type: ChatMessageTypePB,
}

#[derive(Default, ProtoBuf, Validate, Clone, Debug)]
pub struct StreamChatPayloadPB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub chat_id: String,

  #[pb(index = 2)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub message: String,

  #[pb(index = 3)]
  pub message_type: ChatMessageTypePB,

  #[pb(index = 4)]
  pub answer_stream_port: i64,

  #[pb(index = 5)]
  pub question_stream_port: i64,

  #[pb(index = 6)]
  pub metadata: Vec<ChatMessageMetaPB>,
}

#[derive(Default, ProtoBuf, Validate, Clone, Debug)]
pub struct RegenerateResponsePB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub chat_id: String,

  #[pb(index = 2)]
  pub answer_message_id: i64,

  #[pb(index = 3)]
  pub answer_stream_port: i64,
}

#[derive(Default, ProtoBuf, Validate, Clone, Debug)]
pub struct ChatMessageMetaPB {
  #[pb(index = 1)]
  pub id: String,

  #[pb(index = 2)]
  pub name: String,

  #[pb(index = 3)]
  pub data: String,

  #[pb(index = 4)]
  pub loader_type: ContextLoaderTypePB,

  #[pb(index = 5)]
  pub source: String,
}

#[derive(Debug, Default, Clone, ProtoBuf_Enum, PartialEq, Eq, Copy)]
pub enum ContextLoaderTypePB {
  #[default]
  UnknownLoaderType = 0,
  Txt = 1,
  Markdown = 2,
  PDF = 3,
}

#[derive(Default, ProtoBuf, Validate, Clone, Debug)]
pub struct StopStreamPB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub chat_id: String,
}

#[derive(Debug, Default, Clone, ProtoBuf_Enum, PartialEq, Eq, Copy)]
pub enum ChatMessageTypePB {
  #[default]
  System = 0,
  User = 1,
}

#[derive(Default, ProtoBuf, Validate, Clone, Debug)]
pub struct LoadPrevChatMessagePB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub chat_id: String,

  #[pb(index = 2)]
  pub limit: i64,

  #[pb(index = 4, one_of)]
  pub before_message_id: Option<i64>,
}

#[derive(Default, ProtoBuf, Validate, Clone, Debug)]
pub struct LoadNextChatMessagePB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub chat_id: String,

  #[pb(index = 2)]
  pub limit: i64,

  #[pb(index = 4, one_of)]
  pub after_message_id: Option<i64>,
}

#[derive(Default, ProtoBuf, Validate, Clone, Debug)]
pub struct ChatMessageListPB {
  #[pb(index = 1)]
  pub has_more: bool,

  #[pb(index = 2)]
  pub messages: Vec<ChatMessagePB>,

  /// If the total number of messages is 0, then the total number of messages is unknown.
  #[pb(index = 3)]
  pub total: i64,
}

impl From<RepeatedChatMessage> for ChatMessageListPB {
  fn from(repeated_chat_message: RepeatedChatMessage) -> Self {
    let messages = repeated_chat_message
      .messages
      .into_iter()
      .map(ChatMessagePB::from)
      .collect();
    ChatMessageListPB {
      has_more: repeated_chat_message.has_more,
      messages,
      total: repeated_chat_message.total,
    }
  }
}

#[derive(Debug, Clone, Default, ProtoBuf)]
pub struct ChatMessagePB {
  #[pb(index = 1)]
  pub message_id: i64,

  #[pb(index = 2)]
  pub content: String,

  #[pb(index = 3)]
  pub created_at: i64,

  #[pb(index = 4)]
  pub author_type: i64,

  #[pb(index = 5)]
  pub author_id: String,

  #[pb(index = 6, one_of)]
  pub reply_message_id: Option<i64>,

  #[pb(index = 7, one_of)]
  pub metadata: Option<String>,
}

#[derive(Debug, Clone, Default, ProtoBuf)]
pub struct ChatMessageErrorPB {
  #[pb(index = 1)]
  pub chat_id: String,

  #[pb(index = 2)]
  pub error_message: String,
}

impl From<ChatMessage> for ChatMessagePB {
  fn from(chat_message: ChatMessage) -> Self {
    ChatMessagePB {
      message_id: chat_message.message_id,
      content: chat_message.content,
      created_at: chat_message.created_at.timestamp(),
      author_type: chat_message.author.author_type as i64,
      author_id: chat_message.author.author_id.to_string(),
      reply_message_id: None,
      metadata: Some(serde_json::to_string(&chat_message.meta_data).unwrap_or_default()),
    }
  }
}

#[derive(Debug, Clone, Default, ProtoBuf)]
pub struct RepeatedChatMessagePB {
  #[pb(index = 1)]
  items: Vec<ChatMessagePB>,
}

impl From<Vec<ChatMessage>> for RepeatedChatMessagePB {
  fn from(messages: Vec<ChatMessage>) -> Self {
    RepeatedChatMessagePB {
      items: messages.into_iter().map(ChatMessagePB::from).collect(),
    }
  }
}

#[derive(Debug, Clone, Default, ProtoBuf)]
pub struct ChatMessageIdPB {
  #[pb(index = 1)]
  pub chat_id: String,

  #[pb(index = 2)]
  pub message_id: i64,
}

#[derive(Debug, Clone, Default, ProtoBuf)]
pub struct RelatedQuestionPB {
  #[pb(index = 1)]
  pub content: String,
}

impl From<RelatedQuestion> for RelatedQuestionPB {
  fn from(value: RelatedQuestion) -> Self {
    RelatedQuestionPB {
      content: value.content,
    }
  }
}

#[derive(Debug, Clone, Default, ProtoBuf)]
pub struct RepeatedRelatedQuestionPB {
  #[pb(index = 1)]
  pub message_id: i64,

  #[pb(index = 2)]
  pub items: Vec<RelatedQuestionPB>,
}

impl From<RepeatedRelatedQuestion> for RepeatedRelatedQuestionPB {
  fn from(value: RepeatedRelatedQuestion) -> Self {
    RepeatedRelatedQuestionPB {
      message_id: value.message_id,
      items: value
        .items
        .into_iter()
        .map(RelatedQuestionPB::from)
        .collect(),
    }
  }
}

#[derive(Debug, Clone, Default, ProtoBuf)]
pub struct LLMModelInfoPB {
  #[pb(index = 1)]
  pub selected_model: LLMModelPB,

  #[pb(index = 2)]
  pub models: Vec<LLMModelPB>,
}

impl From<LLMModelInfo> for LLMModelInfoPB {
  fn from(value: LLMModelInfo) -> Self {
    LLMModelInfoPB {
      selected_model: LLMModelPB::from(value.selected_model),
      models: value.models.into_iter().map(LLMModelPB::from).collect(),
    }
  }
}

#[derive(Debug, Clone, Default, ProtoBuf)]
pub struct LLMModelPB {
  #[pb(index = 1)]
  pub llm_id: i64,

  #[pb(index = 2)]
  pub embedding_model: String,

  #[pb(index = 3)]
  pub chat_model: String,

  #[pb(index = 4)]
  pub requirement: String,

  #[pb(index = 5)]
  pub file_size: i64,
}

impl From<LLMModel> for LLMModelPB {
  fn from(value: LLMModel) -> Self {
    LLMModelPB {
      llm_id: value.llm_id,
      embedding_model: value.embedding_model.name,
      chat_model: value.chat_model.name,
      requirement: value.chat_model.requirements,
      file_size: value.chat_model.file_size,
    }
  }
}

#[derive(Default, ProtoBuf, Clone, Debug)]
pub struct CompleteTextPB {
  #[pb(index = 1)]
  pub text: String,

  #[pb(index = 2)]
  pub completion_type: CompletionTypePB,

  #[pb(index = 3)]
  pub stream_port: i64,
}

#[derive(Default, ProtoBuf, Clone, Debug)]
pub struct CompleteTextTaskPB {
  #[pb(index = 1)]
  pub task_id: String,
}

#[derive(Clone, Debug, ProtoBuf_Enum, Default)]
pub enum CompletionTypePB {
  UnknownCompletionType = 0,
  #[default]
  ImproveWriting = 1,
  SpellingAndGrammar = 2,
  MakeShorter = 3,
  MakeLonger = 4,
  ContinueWriting = 5,
}

#[derive(Default, ProtoBuf, Clone, Debug)]
pub struct ChatStatePB {
  #[pb(index = 1)]
  pub model_type: ModelTypePB,

  #[pb(index = 2)]
  pub available: bool,
}

#[derive(Clone, Debug, ProtoBuf_Enum, Default)]
pub enum ModelTypePB {
  LocalAI = 0,
  #[default]
  RemoteAI = 1,
}

#[derive(Default, ProtoBuf, Validate, Clone, Debug)]
pub struct ChatFilePB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub file_path: String,

  #[pb(index = 2)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub chat_id: String,
}

#[derive(Default, ProtoBuf, Clone, Debug)]
pub struct DownloadLLMPB {
  #[pb(index = 1)]
  pub progress_stream: i64,
}

#[derive(Default, ProtoBuf, Clone, Debug)]
pub struct DownloadTaskPB {
  #[pb(index = 1)]
  pub task_id: String,
}
#[derive(Default, ProtoBuf, Clone, Debug)]
pub struct LocalModelStatePB {
  #[pb(index = 1)]
  pub model_name: String,

  #[pb(index = 2)]
  pub model_size: String,

  #[pb(index = 3)]
  pub need_download: bool,

  #[pb(index = 4)]
  pub requirements: String,

  #[pb(index = 5)]
  pub is_downloading: bool,
}

#[derive(Default, ProtoBuf, Clone, Debug)]
pub struct LocalModelResourcePB {
  #[pb(index = 1)]
  pub is_ready: bool,

  #[pb(index = 2)]
  pub pending_resources: Vec<PendingResourcePB>,

  #[pb(index = 3)]
  pub is_downloading: bool,
}

#[derive(Default, ProtoBuf, Clone, Debug)]
pub struct PendingResourcePB {
  #[pb(index = 1)]
  pub name: String,

  #[pb(index = 2)]
  pub file_size: String,

  #[pb(index = 3)]
  pub requirements: String,

  #[pb(index = 4)]
  pub res_type: PendingResourceTypePB,
}

#[derive(Debug, Default, Clone, ProtoBuf_Enum, PartialEq, Eq, Copy)]
pub enum PendingResourceTypePB {
  #[default]
  OfflineApp = 0,
  AIModel = 1,
}

impl From<PendingResource> for PendingResourceTypePB {
  fn from(value: PendingResource) -> Self {
    match value {
      PendingResource::OfflineApp { .. } => PendingResourceTypePB::OfflineApp,
      PendingResource::ModelInfoRes { .. } => PendingResourceTypePB::AIModel,
    }
  }
}

#[derive(Default, ProtoBuf, Clone, Debug)]
pub struct LocalAIPluginStatePB {
  #[pb(index = 1)]
  pub state: RunningStatePB,

  #[pb(index = 2)]
  pub offline_ai_ready: bool,
}

#[derive(Debug, Default, Clone, ProtoBuf_Enum, PartialEq, Eq, Copy)]
pub enum RunningStatePB {
  #[default]
  Connecting = 0,
  Connected = 1,
  Running = 2,
  Stopped = 3,
}

impl From<RunningState> for RunningStatePB {
  fn from(value: RunningState) -> Self {
    match value {
      RunningState::Connecting => RunningStatePB::Connecting,
      RunningState::Connected { .. } => RunningStatePB::Connected,
      RunningState::Running { .. } => RunningStatePB::Running,
      RunningState::Stopped { .. } => RunningStatePB::Stopped,
      RunningState::UnexpectedStop { .. } => RunningStatePB::Stopped,
    }
  }
}

#[derive(Default, ProtoBuf, Clone, Debug)]
pub struct LocalAIPB {
  #[pb(index = 1)]
  pub enabled: bool,
}

#[derive(Default, ProtoBuf, Clone, Debug)]
pub struct LocalAIChatPB {
  #[pb(index = 1)]
  pub enabled: bool,

  #[pb(index = 2)]
  pub file_enabled: bool,

  #[pb(index = 3)]
  pub plugin_state: LocalAIPluginStatePB,
}

#[derive(Default, ProtoBuf, Clone, Debug)]
pub struct LocalModelStoragePB {
  #[pb(index = 1)]
  pub file_path: String,
}

#[derive(Default, ProtoBuf, Clone, Debug)]
pub struct OfflineAIPB {
  #[pb(index = 1)]
  pub link: String,
}

#[derive(Default, ProtoBuf, Validate, Clone, Debug)]
pub struct CreateChatContextPB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub content_type: String,

  #[pb(index = 2)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub text: String,

  #[pb(index = 3)]
  pub metadata: HashMap<String, String>,

  #[pb(index = 4)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub chat_id: String,
}

#[derive(Default, ProtoBuf, Clone, Debug)]
pub struct ChatSettingsPB {
  #[pb(index = 1)]
  pub rag_ids: RepeatedRagId,

  #[pb(index = 2)]
  pub rag_only: bool,
}

impl From<ChatSettings> for ChatSettingsPB {
  fn from(value: ChatSettings) -> Self {
    let rag_ids = RepeatedRagId {
      rag_ids: value.rag_ids.clone(),
    };

    let rag_only = value
      .metadata
      .as_object()
      .and_then(|map| map.get("rag_only"))
      .and_then(|value| value.as_bool())
      .unwrap_or_default();

    Self { rag_ids, rag_only }
  }
}

#[derive(Default, ProtoBuf, Clone, Debug, Validate)]
pub struct UpdateChatSettingsPB {
  #[pb(index = 1)]
  #[validate(nested)]
  pub chat_id: ChatId,

  #[pb(index = 2, one_of)]
  pub rag_ids: Option<RepeatedRagId>,

  #[pb(index = 3, one_of)]
  pub rag_only: Option<bool>,
}

#[derive(Default, ProtoBuf, Clone, Debug)]
pub struct RepeatedRagId {
  #[pb(index = 1)]
  pub rag_ids: Vec<String>,
}
