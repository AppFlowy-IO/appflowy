use crate::chat::Chat;
use crate::entities::{
  ChatInfoPB, ChatMessageListPB, ChatMessagePB, ChatSettingsPB, FilePB, RepeatedRelatedQuestionPB,
};
use crate::local_ai::local_llm_chat::LocalAIController;
use crate::middleware::chat_service_mw::AICloudServiceMiddleware;
use crate::persistence::{insert_chat, read_chat_metadata, ChatTable};

use appflowy_plugin::manager::PluginManager;
use dashmap::DashMap;
use flowy_ai_pub::cloud::{
  ChatCloudService, ChatMessageMetadata, ChatMessageType, ChatSettings, UpdateChatParams,
};
use flowy_error::{FlowyError, FlowyResult};
use flowy_sqlite::kv::KVStorePreferences;
use flowy_sqlite::DBConnection;

use crate::notification::{chat_notification_builder, ChatNotification};
use flowy_storage_pub::storage::StorageService;
use lib_infra::async_trait::async_trait;
use lib_infra::util::timestamp;
use serde_json::json;
use std::path::PathBuf;
use std::sync::{Arc, Weak};
use tracing::{error, info, trace};

pub trait AIUserService: Send + Sync + 'static {
  fn user_id(&self) -> Result<i64, FlowyError>;
  fn device_id(&self) -> Result<String, FlowyError>;
  fn workspace_id(&self) -> Result<String, FlowyError>;
  fn sqlite_connection(&self, uid: i64) -> Result<DBConnection, FlowyError>;
  fn application_root_dir(&self) -> Result<PathBuf, FlowyError>;
}


/// AIExternalService is an interface for external services that AI plugin can interact with.
#[async_trait]
pub trait AIExternalService: Send + Sync + 'static {
  async fn query_chat_rag_ids(
    &self,
    parent_view_id: &str,
    chat_id: &str,
  ) -> Result<Vec<String>, FlowyError>;

  async fn sync_rag_documents(
    &self,
    workspace_id: &str,
    rag_ids: Vec<String>,
  ) -> Result<(), FlowyError>;

  async fn notify_did_send_message(&self, chat_id: &str, message: &str) -> Result<(), FlowyError>;
}

pub struct AIManager {
  pub cloud_service_wm: Arc<AICloudServiceMiddleware>,
  pub user_service: Arc<dyn AIUserService>,
  pub external_service: Arc<dyn AIExternalService>,
  chats: Arc<DashMap<String, Arc<Chat>>>,
  pub local_ai_controller: Arc<LocalAIController>,
  store_preferences: Arc<KVStorePreferences>,
}

impl AIManager {
  pub fn new(
    chat_cloud_service: Arc<dyn ChatCloudService>,
    user_service: impl AIUserService,
    store_preferences: Arc<KVStorePreferences>,
    storage_service: Weak<dyn StorageService>,
    query_service: impl AIExternalService,
  ) -> AIManager {
    let user_service = Arc::new(user_service);
    let plugin_manager = Arc::new(PluginManager::new());
    let local_ai_controller = Arc::new(LocalAIController::new(
      plugin_manager.clone(),
      store_preferences.clone(),
      user_service.clone(),
      chat_cloud_service.clone(),
    ));
    let external_service = Arc::new(query_service);

    // setup local chat service
    let cloud_service_wm = Arc::new(AICloudServiceMiddleware::new(
      user_service.clone(),
      chat_cloud_service,
      local_ai_controller.clone(),
      storage_service,
    ));

    Self {
      cloud_service_wm,
      user_service,
      chats: Arc::new(DashMap::new()),
      local_ai_controller,
      external_service,
      store_preferences,
    }
  }

  pub async fn initialize(&self, _workspace_id: &str) -> Result<(), FlowyError> {
    // Ignore following error
    let _ = self.local_ai_controller.refresh().await;
    Ok(())
  }

  pub async fn open_chat(&self, chat_id: &str) -> Result<(), FlowyError> {
    self.chats.entry(chat_id.to_string()).or_insert_with(|| {
      Arc::new(Chat::new(
        self.user_service.user_id().unwrap(),
        chat_id.to_string(),
        self.user_service.clone(),
        self.cloud_service_wm.clone(),
      ))
    });
    trace!("[AI Plugin] notify open chat: {}", chat_id);
    if self.local_ai_controller.is_running() {
      self.local_ai_controller.open_chat(chat_id);
    }

    let user_service = self.user_service.clone();
    let cloud_service_wm = self.cloud_service_wm.clone();
    let store_preferences = self.store_preferences.clone();
    let external_service = self.external_service.clone();
    let chat_id = chat_id.to_string();
    tokio::spawn(async move {
      match refresh_chat_setting(
        &user_service,
        &cloud_service_wm,
        &store_preferences,
        &chat_id,
      )
      .await
      {
        Ok(settings) => {
          if settings.rag_ids.is_empty() {
            return;
          }
          if let Ok(workspace_id) = user_service.workspace_id() {
            let _ = external_service
              .sync_rag_documents(&workspace_id, settings.rag_ids)
              .await;
          }
        },
        Err(err) => {
          error!("failed to refresh chat settings: {}", err);
        },
      }
    });

    Ok(())
  }

  pub async fn close_chat(&self, chat_id: &str) -> Result<(), FlowyError> {
    trace!("close chat: {}", chat_id);
    self.local_ai_controller.close_chat(chat_id);
    Ok(())
  }

  pub async fn delete_chat(&self, chat_id: &str) -> Result<(), FlowyError> {
    if let Some((_, chat)) = self.chats.remove(chat_id) {
      chat.close();

      if self.local_ai_controller.is_running() {
        info!("[AI Plugin] notify close chat: {}", chat_id);
        self.local_ai_controller.close_chat(chat_id);
      }
    }
    Ok(())
  }

  pub async fn get_chat_info(&self, chat_id: &str) -> FlowyResult<ChatInfoPB> {
    let mut conn = self.user_service.sqlite_connection(0)?;
    let metadata = read_chat_metadata(&mut conn, chat_id)?;
    let files = metadata
      .files
      .into_iter()
      .map(|file| FilePB {
        id: file.id,
        name: file.name,
      })
      .collect();

    Ok(ChatInfoPB {
      chat_id: chat_id.to_string(),
      files,
    })
  }

  pub async fn create_chat(
    &self,
    uid: &i64,
    parent_view_id: &str,
    chat_id: &str,
  ) -> Result<Arc<Chat>, FlowyError> {
    let workspace_id = self.user_service.workspace_id()?;
    let rag_ids = self
      .external_service
      .query_chat_rag_ids(parent_view_id, chat_id)
      .await
      .unwrap_or_default();
    info!("[Chat] create chat with rag_ids: {:?}", rag_ids);

    self
      .cloud_service_wm
      .create_chat(uid, &workspace_id, chat_id, rag_ids)
      .await?;
    save_chat(self.user_service.sqlite_connection(*uid)?, chat_id)?;

    let chat = Arc::new(Chat::new(
      self.user_service.user_id().unwrap(),
      chat_id.to_string(),
      self.user_service.clone(),
      self.cloud_service_wm.clone(),
    ));
    self.chats.insert(chat_id.to_string(), chat.clone());
    Ok(chat)
  }

  pub async fn stream_chat_message(
    &self,
    chat_id: &str,
    message: &str,
    message_type: ChatMessageType,
    answer_stream_port: i64,
    question_stream_port: i64,
    metadata: Vec<ChatMessageMetadata>,
  ) -> Result<ChatMessagePB, FlowyError> {
    let chat = self.get_or_create_chat_instance(chat_id).await?;
    let question = chat
      .stream_chat_message(
        message,
        message_type,
        answer_stream_port,
        question_stream_port,
        metadata,
      )
      .await?;
    let _ = self
      .external_service
      .notify_did_send_message(chat_id, message)
      .await;
    Ok(question)
  }

  pub async fn stream_regenerate_response(
    &self,
    chat_id: &str,
    answer_message_id: i64,
    answer_stream_port: i64,
  ) -> FlowyResult<()> {
    let chat = self.get_or_create_chat_instance(chat_id).await?;
    let question_message_id = chat
      .get_question_id_from_answer_id(answer_message_id)
      .await?;
    chat
      .stream_regenerate_response(question_message_id, answer_stream_port)
      .await?;
    Ok(())
  }

  pub async fn get_or_create_chat_instance(&self, chat_id: &str) -> Result<Arc<Chat>, FlowyError> {
    let chat = self.chats.get(chat_id).as_deref().cloned();
    match chat {
      None => {
        let chat = Arc::new(Chat::new(
          self.user_service.user_id().unwrap(),
          chat_id.to_string(),
          self.user_service.clone(),
          self.cloud_service_wm.clone(),
        ));
        self.chats.insert(chat_id.to_string(), chat.clone());
        Ok(chat)
      },
      Some(chat) => Ok(chat),
    }
  }

  /// Load chat messages for a given `chat_id`.
  ///
  /// 1. When opening a chat:
  ///    - Loads local chat messages.
  ///    - `after_message_id` and `before_message_id` are `None`.
  ///    - Spawns a task to load messages from the remote server, notifying the user when the remote messages are loaded.
  ///
  /// 2. Loading more messages in an existing chat with `after_message_id`:
  ///    - `after_message_id` is the last message ID in the current chat messages.
  ///
  /// 3. Loading more messages in an existing chat with `before_message_id`:
  ///    - `before_message_id` is the first message ID in the current chat messages.
  ///
  /// 4. `after_message_id` and `before_message_id` cannot be specified at the same time.

  pub async fn load_prev_chat_messages(
    &self,
    chat_id: &str,
    limit: i64,
    before_message_id: Option<i64>,
  ) -> Result<ChatMessageListPB, FlowyError> {
    let chat = self.get_or_create_chat_instance(chat_id).await?;
    let list = chat
      .load_prev_chat_messages(limit, before_message_id)
      .await?;
    Ok(list)
  }

  pub async fn load_latest_chat_messages(
    &self,
    chat_id: &str,
    limit: i64,
    after_message_id: Option<i64>,
  ) -> Result<ChatMessageListPB, FlowyError> {
    let chat = self.get_or_create_chat_instance(chat_id).await?;
    let list = chat
      .load_latest_chat_messages(limit, after_message_id)
      .await?;
    Ok(list)
  }

  pub async fn get_related_questions(
    &self,
    chat_id: &str,
    message_id: i64,
  ) -> Result<RepeatedRelatedQuestionPB, FlowyError> {
    let chat = self.get_or_create_chat_instance(chat_id).await?;
    let resp = chat.get_related_question(message_id).await?;
    Ok(resp)
  }

  pub async fn generate_answer(
    &self,
    chat_id: &str,
    question_message_id: i64,
  ) -> Result<ChatMessagePB, FlowyError> {
    let chat = self.get_or_create_chat_instance(chat_id).await?;
    let resp = chat.generate_answer(question_message_id).await?;
    Ok(resp)
  }

  pub async fn stop_stream(&self, chat_id: &str) -> Result<(), FlowyError> {
    let chat = self.get_or_create_chat_instance(chat_id).await?;
    chat.stop_stream_message().await;
    Ok(())
  }

  pub async fn chat_with_file(&self, chat_id: &str, file_path: PathBuf) -> FlowyResult<()> {
    let chat = self.get_or_create_chat_instance(chat_id).await?;
    chat.index_file(file_path).await?;
    Ok(())
  }

  pub async fn get_chat_settings(&self, chat_id: &str) -> FlowyResult<ChatSettingsPB> {
    if let Some(settings) = self
      .store_preferences
      .get_object::<ChatSettings>(&setting_store_key(chat_id))
    {
      return Ok(settings.into());
    }

    let settings = refresh_chat_setting(
      &self.user_service,
      &self.cloud_service_wm,
      &self.store_preferences,
      chat_id,
    )
    .await?;
    Ok(settings.into())
  }

  pub async fn update_settings(
    &self,
    chat_id: &str,
    rag_ids: Option<Vec<String>>,
    rag_only: Option<bool>,
  ) -> FlowyResult<()> {
    info!("[Chat] update chat:{} rag ids: {:?}", chat_id, rag_ids);
    let workspace_id = self.user_service.workspace_id()?;
    let update_setting = UpdateChatParams {
      name: None,
      metadata: rag_only.map(|rag_only| json!({"rag_only": rag_only})),
      rag_ids: rag_ids.clone(),
    };

    self
      .cloud_service_wm
      .update_chat_settings(&workspace_id, chat_id, update_setting)
      .await?;

    let chat_setting_store_key = setting_store_key(chat_id);
    if let Some(mut settings) = self
      .store_preferences
      .get_object::<ChatSettings>(&chat_setting_store_key)
    {
      if let Some(rag_only) = rag_only {
        settings.metadata = json!({"rag_only": rag_only});
      }

      if let Some(rag_ids) = rag_ids {
        settings.rag_ids = rag_ids.clone();
        let user_service = self.user_service.clone();
        let external_service = self.external_service.clone();
        tokio::spawn(async move {
          if let Ok(workspace_id) = user_service.workspace_id() {
            let _ = external_service
              .sync_rag_documents(&workspace_id, rag_ids)
              .await;
          }
        });
      }

      if let Err(err) = self
        .store_preferences
        .set_object(&chat_setting_store_key, &settings)
      {
        error!("failed to set chat settings: {}", err);
      }
    }

    Ok(())
  }
}

fn save_chat(conn: DBConnection, chat_id: &str) -> FlowyResult<()> {
  let row = ChatTable {
    chat_id: chat_id.to_string(),
    created_at: timestamp(),
    name: "".to_string(),
    local_files: "".to_string(),
    metadata: "".to_string(),
    local_enabled: false,
    sync_to_cloud: false,
  };

  insert_chat(conn, &row)?;
  Ok(())
}

async fn refresh_chat_setting(
  user_service: &Arc<dyn AIUserService>,
  cloud_service: &Arc<AICloudServiceMiddleware>,
  store_preferences: &Arc<KVStorePreferences>,
  chat_id: &str,
) -> FlowyResult<ChatSettings> {
  info!("[Chat] refresh chat:{} setting", chat_id);
  let workspace_id = user_service.workspace_id()?;
  let settings = cloud_service
    .get_chat_settings(&workspace_id, chat_id)
    .await?;

  if let Err(err) = store_preferences.set_object(&setting_store_key(chat_id), &settings) {
    error!("failed to set chat settings: {}", err);
  }

  chat_notification_builder(chat_id, ChatNotification::DidUpdateChatSettings)
    .payload(ChatSettingsPB::from(settings.clone()))
    .send();

  Ok(settings)
}

fn setting_store_key(chat_id: &str) -> String {
  format!("chat_settings_{}", chat_id)
}
