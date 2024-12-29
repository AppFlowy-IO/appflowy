use std::fs;
use std::path::PathBuf;

use crate::ai_manager::AIManager;
use crate::completion::AICompletion;
use crate::entities::*;
use crate::local_ai::local_llm_chat::LLMModelInfo;
use crate::notification::{
  chat_notification_builder, ChatNotification, APPFLOWY_AI_NOTIFICATION_KEY,
};
use allo_isolate::Isolate;
use flowy_ai_pub::cloud::{ChatMessageMetadata, ChatMessageType, ChatRAGData, ContextLoader};
use flowy_error::{ErrorCode, FlowyError, FlowyResult};
use lib_dispatch::prelude::{data_result_ok, AFPluginData, AFPluginState, DataResult};
use lib_infra::isolate_stream::IsolateSink;
use std::sync::{Arc, Weak};
use tracing::trace;
use validator::Validate;

fn upgrade_ai_manager(ai_manager: AFPluginState<Weak<AIManager>>) -> FlowyResult<Arc<AIManager>> {
  let ai_manager = ai_manager
    .upgrade()
    .ok_or(FlowyError::internal().with_context("The chat manager is already dropped"))?;
  Ok(ai_manager)
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn stream_chat_message_handler(
  data: AFPluginData<StreamChatPayloadPB>,
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> DataResult<ChatMessagePB, FlowyError> {
  let data = data.into_inner();
  data.validate()?;

  let message_type = match data.message_type {
    ChatMessageTypePB::System => ChatMessageType::System,
    ChatMessageTypePB::User => ChatMessageType::User,
  };

  let metadata = data
    .metadata
    .into_iter()
    .map(|metadata| {
      let (content_type, content_len) = match metadata.loader_type {
        ContextLoaderTypePB::Txt => (ContextLoader::Text, metadata.data.len()),
        ContextLoaderTypePB::Markdown => (ContextLoader::Markdown, metadata.data.len()),
        ContextLoaderTypePB::PDF => (ContextLoader::PDF, 0),
        ContextLoaderTypePB::UnknownLoaderType => (ContextLoader::Unknown, 0),
      };

      ChatMessageMetadata {
        data: ChatRAGData {
          content: metadata.data,
          content_type,
          size: content_len as i64,
        },
        id: metadata.id,
        name: metadata.name.clone(),
        source: metadata.source,
        extra: None,
      }
    })
    .collect::<Vec<_>>();

  trace!("Stream chat message with metadata: {:?}", metadata);
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  let result = ai_manager
    .stream_chat_message(
      &data.chat_id,
      &data.message,
      message_type,
      data.answer_stream_port,
      data.question_stream_port,
      metadata,
    )
    .await?;
  data_result_ok(result)
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn regenerate_response_handler(
  data: AFPluginData<RegenerateResponsePB>,
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> FlowyResult<()> {
  let data = data.try_into_inner()?;

  let ai_manager = upgrade_ai_manager(ai_manager)?;
  ai_manager
    .stream_regenerate_response(
      &data.chat_id,
      data.answer_message_id,
      data.answer_stream_port,
    )
    .await?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn load_prev_message_handler(
  data: AFPluginData<LoadPrevChatMessagePB>,
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> DataResult<ChatMessageListPB, FlowyError> {
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  let data = data.into_inner();
  data.validate()?;

  let messages = ai_manager
    .load_prev_chat_messages(&data.chat_id, data.limit, data.before_message_id)
    .await?;
  data_result_ok(messages)
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn load_next_message_handler(
  data: AFPluginData<LoadNextChatMessagePB>,
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> DataResult<ChatMessageListPB, FlowyError> {
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  let data = data.into_inner();
  data.validate()?;

  let messages = ai_manager
    .load_latest_chat_messages(&data.chat_id, data.limit, data.after_message_id)
    .await?;
  data_result_ok(messages)
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn get_related_question_handler(
  data: AFPluginData<ChatMessageIdPB>,
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> DataResult<RepeatedRelatedQuestionPB, FlowyError> {
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  let data = data.into_inner();
  let messages = ai_manager
    .get_related_questions(&data.chat_id, data.message_id)
    .await?;
  data_result_ok(messages)
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn get_answer_handler(
  data: AFPluginData<ChatMessageIdPB>,
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> DataResult<ChatMessagePB, FlowyError> {
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  let data = data.into_inner();
  let message = ai_manager
    .generate_answer(&data.chat_id, data.message_id)
    .await?;
  data_result_ok(message)
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn stop_stream_handler(
  data: AFPluginData<StopStreamPB>,
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> Result<(), FlowyError> {
  let data = data.into_inner();
  data.validate()?;

  let ai_manager = upgrade_ai_manager(ai_manager)?;
  ai_manager.stop_stream(&data.chat_id).await?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn refresh_local_ai_info_handler(
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> DataResult<LLMModelInfoPB, FlowyError> {
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  let model_info = ai_manager.local_ai_controller.refresh_model_info().await;
  if model_info.is_err() {
    if let Some(llm_model) = ai_manager.local_ai_controller.get_current_model() {
      let model_info = LLMModelInfo {
        selected_model: llm_model.clone(),
        models: vec![llm_model],
      };
      return data_result_ok(model_info.into());
    }
  }
  data_result_ok(model_info?.into())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn update_local_llm_model_handler(
  data: AFPluginData<LLMModelPB>,
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> DataResult<LocalModelResourcePB, FlowyError> {
  let data = data.into_inner();
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  let state = ai_manager
    .local_ai_controller
    .select_local_llm(data.llm_id)
    .await?;
  data_result_ok(state)
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn get_local_llm_state_handler(
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> DataResult<LocalModelResourcePB, FlowyError> {
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  let state = ai_manager.local_ai_controller.get_local_llm_state().await?;
  data_result_ok(state)
}

pub(crate) async fn start_complete_text_handler(
  data: AFPluginData<CompleteTextPB>,
  tools: AFPluginState<Arc<AICompletion>>,
) -> DataResult<CompleteTextTaskPB, FlowyError> {
  let task = tools.create_complete_task(data.into_inner()).await?;
  data_result_ok(task)
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn stop_complete_text_handler(
  data: AFPluginData<CompleteTextTaskPB>,
  tools: AFPluginState<Arc<AICompletion>>,
) -> Result<(), FlowyError> {
  let data = data.into_inner();
  tools.cancel_complete_task(&data.task_id).await;
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn chat_file_handler(
  data: AFPluginData<ChatFilePB>,
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> Result<(), FlowyError> {
  let data = data.try_into_inner()?;
  let file_path = PathBuf::from(&data.file_path);

  let allowed_extensions = ["pdf", "md", "txt"];
  let extension = file_path
    .extension()
    .and_then(|ext| ext.to_str())
    .ok_or_else(|| {
      FlowyError::new(
        ErrorCode::UnsupportedFileFormat,
        "Can't find file extension",
      )
    })?;

  if !allowed_extensions.contains(&extension) {
    return Err(FlowyError::new(
      ErrorCode::UnsupportedFileFormat,
      "Only support pdf,md and txt",
    ));
  }
  let file_size = fs::metadata(&file_path)
    .map_err(|_| {
      FlowyError::new(
        ErrorCode::UnsupportedFileFormat,
        "Failed to get file metadata",
      )
    })?
    .len();

  const MAX_FILE_SIZE: u64 = 10 * 1024 * 1024;
  if file_size > MAX_FILE_SIZE {
    return Err(FlowyError::new(
      ErrorCode::PayloadTooLarge,
      "File size is too large. Max file size is 10MB",
    ));
  }

  tracing::debug!("File size: {} bytes", file_size);
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  ai_manager.chat_with_file(&data.chat_id, file_path).await?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn download_llm_resource_handler(
  data: AFPluginData<DownloadLLMPB>,
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> DataResult<DownloadTaskPB, FlowyError> {
  let data = data.into_inner();
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  let text_sink = IsolateSink::new(Isolate::new(data.progress_stream));
  let task_id = ai_manager
    .local_ai_controller
    .start_downloading(text_sink)
    .await?;
  data_result_ok(DownloadTaskPB { task_id })
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn cancel_download_llm_resource_handler(
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> Result<(), FlowyError> {
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  ai_manager.local_ai_controller.cancel_download()?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn get_plugin_state_handler(
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> DataResult<LocalAIPluginStatePB, FlowyError> {
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  let state = ai_manager.local_ai_controller.get_chat_plugin_state();
  data_result_ok(state)
}
#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn toggle_local_ai_chat_handler(
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> DataResult<LocalAIChatPB, FlowyError> {
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  let enabled = ai_manager
    .local_ai_controller
    .toggle_local_ai_chat()
    .await?;
  let file_enabled = ai_manager.local_ai_controller.is_rag_enabled();
  let plugin_state = ai_manager.local_ai_controller.get_chat_plugin_state();
  let pb = LocalAIChatPB {
    enabled,
    file_enabled,
    plugin_state,
  };
  chat_notification_builder(
    APPFLOWY_AI_NOTIFICATION_KEY,
    ChatNotification::UpdateLocalChatAI,
  )
  .payload(pb.clone())
  .send();
  data_result_ok(pb)
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn toggle_local_ai_chat_file_handler(
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> DataResult<LocalAIChatPB, FlowyError> {
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  let enabled = ai_manager.local_ai_controller.is_chat_enabled();
  let file_enabled = ai_manager
    .local_ai_controller
    .toggle_local_ai_chat_rag()
    .await?;
  let plugin_state = ai_manager.local_ai_controller.get_chat_plugin_state();
  let pb = LocalAIChatPB {
    enabled,
    file_enabled,
    plugin_state,
  };
  chat_notification_builder(
    APPFLOWY_AI_NOTIFICATION_KEY,
    ChatNotification::UpdateLocalChatAI,
  )
  .payload(pb.clone())
  .send();

  data_result_ok(pb)
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn get_local_ai_chat_state_handler(
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> DataResult<LocalAIChatPB, FlowyError> {
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  let enabled = ai_manager.local_ai_controller.is_chat_enabled();
  let file_enabled = ai_manager.local_ai_controller.is_rag_enabled();
  let plugin_state = ai_manager.local_ai_controller.get_chat_plugin_state();
  data_result_ok(LocalAIChatPB {
    enabled,
    file_enabled,
    plugin_state,
  })
}
#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn restart_local_ai_chat_handler(
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> Result<(), FlowyError> {
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  ai_manager.local_ai_controller.restart_chat_plugin();
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn toggle_local_ai_handler(
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> DataResult<LocalAIPB, FlowyError> {
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  let enabled = ai_manager.local_ai_controller.toggle_local_ai().await?;
  data_result_ok(LocalAIPB { enabled })
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn get_local_ai_state_handler(
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> DataResult<LocalAIPB, FlowyError> {
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  let enabled = ai_manager.local_ai_controller.is_enabled();
  data_result_ok(LocalAIPB { enabled })
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn get_model_storage_directory_handler(
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> DataResult<LocalModelStoragePB, FlowyError> {
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  let file_path = ai_manager
    .local_ai_controller
    .get_model_storage_directory()?;
  data_result_ok(LocalModelStoragePB { file_path })
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn get_offline_app_handler(
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> DataResult<OfflineAIPB, FlowyError> {
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  let link = ai_manager
    .local_ai_controller
    .get_offline_ai_app_download_link()
    .await?;
  data_result_ok(OfflineAIPB { link })
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn create_chat_context_handler(
  data: AFPluginData<CreateChatContextPB>,
  _ai_manager: AFPluginState<Weak<AIManager>>,
) -> Result<(), FlowyError> {
  let _data = data.try_into_inner()?;

  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn get_chat_info_handler(
  data: AFPluginData<ChatId>,
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> DataResult<ChatInfoPB, FlowyError> {
  let chat_id = data.try_into_inner()?.value;
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  let pb = ai_manager.get_chat_info(&chat_id).await?;
  data_result_ok(pb)
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn get_chat_settings_handler(
  data: AFPluginData<ChatId>,
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> DataResult<ChatSettingsPB, FlowyError> {
  let chat_id = data.try_into_inner()?.value;
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  let pb = ai_manager.get_chat_settings(&chat_id).await?;
  data_result_ok(pb)
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub(crate) async fn update_chat_settings_handler(
  data: AFPluginData<UpdateChatSettingsPB>,
  ai_manager: AFPluginState<Weak<AIManager>>,
) -> FlowyResult<()> {
  let params = data.try_into_inner()?;
  let ai_manager = upgrade_ai_manager(ai_manager)?;
  ai_manager
    .update_settings(
      &params.chat_id.value,
      params.rag_ids.map(|v| v.rag_ids),
      params.rag_only,
    )
    .await?;

  Ok(())
}
