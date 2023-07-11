use std::collections::HashMap;
use std::sync::Arc;

use appflowy_integrate::collab_builder::AppFlowyCollabBuilder;
use appflowy_integrate::{CollabPersistenceConfig, RocksCollabDB};
use collab::core::collab::{CollabRawData, MutexCollab};
use collab_database::blocks::BlockEvent;
use collab_database::database::{DatabaseData, YrsDocAction};
use collab_database::error::DatabaseError;
use collab_database::user::{
  make_workspace_database_id, CollabFuture, CollabObjectUpdate, CollabObjectUpdateByOid,
  DatabaseCollabService, WorkspaceDatabase,
};
use collab_database::views::{CreateDatabaseParams, CreateViewParams, DatabaseLayout};
use tokio::sync::RwLock;

use flowy_error::{internal_error, FlowyError, FlowyResult};
use flowy_task::TaskDispatcher;

use crate::deps::{DatabaseCloudService, DatabaseUser2};
use crate::entities::{
  DatabaseDescriptionPB, DatabaseLayoutPB, DatabaseSnapshotPB, DidFetchRowPB,
  RepeatedDatabaseDescriptionPB,
};
use crate::notification::{send_notification, DatabaseNotification};
use crate::services::database::DatabaseEditor;
use crate::services::database_view::DatabaseLayoutDepsResolver;
use crate::services::share::csv::{CSVFormat, CSVImporter, ImportResult};

pub struct DatabaseManager2 {
  user: Arc<dyn DatabaseUser2>,
  workspace_database: Arc<RwLock<Option<Arc<WorkspaceDatabase>>>>,
  task_scheduler: Arc<RwLock<TaskDispatcher>>,
  editors: RwLock<HashMap<String, Arc<DatabaseEditor>>>,
  collab_builder: Arc<AppFlowyCollabBuilder>,
  cloud_service: Arc<dyn DatabaseCloudService>,
}

impl DatabaseManager2 {
  pub fn new(
    database_user: Arc<dyn DatabaseUser2>,
    task_scheduler: Arc<RwLock<TaskDispatcher>>,
    collab_builder: Arc<AppFlowyCollabBuilder>,
    cloud_service: Arc<dyn DatabaseCloudService>,
  ) -> Self {
    Self {
      user: database_user,
      workspace_database: Default::default(),
      task_scheduler,
      editors: Default::default(),
      collab_builder,
      cloud_service,
    }
  }

  fn is_collab_exist(&self, uid: i64, collab_db: &Arc<RocksCollabDB>, object_id: &str) -> bool {
    let read_txn = collab_db.read_txn();
    read_txn.is_exist(uid, object_id)
  }

  pub async fn initialize(&self, uid: i64) -> FlowyResult<()> {
    let collab_db = self.user.collab_db()?;
    let workspace_database_id = make_workspace_database_id(uid);
    let collab_builder = UserDatabaseCollabServiceImpl {
      collab_builder: self.collab_builder.clone(),
      cloud_service: self.cloud_service.clone(),
    };
    let config = CollabPersistenceConfig::new().snapshot_per_update(10);
    let mut collab_raw_data = CollabRawData::default();

    // If the workspace database not exist in disk, try to fetch from remote.
    if !self.is_collab_exist(uid, &collab_db, &workspace_database_id) {
      tracing::trace!("workspace database not exist, try to fetch from remote");
      match self
        .cloud_service
        .get_collab_update(&workspace_database_id)
        .await
      {
        Ok(updates) => collab_raw_data = updates,
        Err(err) => {
          return Err(FlowyError::record_not_found().context(format!(
            "get workspace database :{} failed: {}",
            workspace_database_id, err,
          )));
        },
      }
    }

    // Construct the workspace database.
    tracing::trace!("open workspace database: {}", &workspace_database_id);
    let collab = collab_builder.build_collab_with_config(
      uid,
      &workspace_database_id,
      "databases",
      collab_db.clone(),
      collab_raw_data,
      &config,
    );
    let workspace_database =
      WorkspaceDatabase::open(uid, collab, collab_db, config, collab_builder);
    subscribe_block_event(&workspace_database);
    *self.workspace_database.write().await = Some(Arc::new(workspace_database));
    Ok(())
  }

  pub async fn initialize_with_new_user(&self, user_id: i64, _token: &str) -> FlowyResult<()> {
    self.initialize(user_id).await?;
    Ok(())
  }

  pub async fn get_all_databases_description(&self) -> RepeatedDatabaseDescriptionPB {
    let mut items = vec![];
    if let Ok(wdb) = self.get_workspace_database().await {
      items = wdb
        .get_all_databases()
        .into_iter()
        .map(DatabaseDescriptionPB::from)
        .collect();
    }
    RepeatedDatabaseDescriptionPB { items }
  }

  pub async fn get_database_with_view_id(&self, view_id: &str) -> FlowyResult<Arc<DatabaseEditor>> {
    let database_id = self.get_database_id_with_view_id(view_id).await?;
    self.get_database(&database_id).await
  }

  pub async fn get_database_id_with_view_id(&self, view_id: &str) -> FlowyResult<String> {
    let wdb = self.get_workspace_database().await?;
    wdb.get_database_id_with_view_id(view_id).ok_or_else(|| {
      FlowyError::record_not_found()
        .context(format!("The database for view id: {} not found", view_id))
    })
  }

  pub async fn get_database(&self, database_id: &str) -> FlowyResult<Arc<DatabaseEditor>> {
    if let Some(editor) = self.editors.read().await.get(database_id) {
      return Ok(editor.clone());
    }
    self.open_database(database_id).await
  }

  pub async fn open_database(&self, database_id: &str) -> FlowyResult<Arc<DatabaseEditor>> {
    tracing::trace!("create new editor for database {}", database_id);
    let mut editors = self.editors.write().await;

    let wdb = self.get_workspace_database().await?;
    let database = wdb
      .get_database(database_id)
      .await
      .ok_or_else(FlowyError::record_not_found)?;

    let editor = Arc::new(DatabaseEditor::new(database, self.task_scheduler.clone()).await?);
    editors.insert(database_id.to_string(), editor.clone());
    Ok(editor)
  }

  #[tracing::instrument(level = "debug", skip_all)]
  pub async fn close_database_view<T: AsRef<str>>(&self, view_id: T) -> FlowyResult<()> {
    // TODO(natan): defer closing the database if the sync is not finished
    let view_id = view_id.as_ref();
    let wdb = self.get_workspace_database().await?;
    let database_id = wdb.get_database_id_with_view_id(view_id);
    if database_id.is_some() {
      wdb.close_database(database_id.as_ref().unwrap());
    }

    if let Some(database_id) = database_id {
      let mut editors = self.editors.write().await;
      if let Some(editor) = editors.get(&database_id) {
        if editor.close_view_editor(view_id).await {
          editor.close().await;
          editors.remove(&database_id);
        }
      }
    }

    Ok(())
  }

  pub async fn delete_database_view(&self, view_id: &str) -> FlowyResult<()> {
    let database = self.get_database_with_view_id(view_id).await?;
    let _ = database.delete_database_view(view_id).await?;
    Ok(())
  }

  pub async fn duplicate_database(&self, view_id: &str) -> FlowyResult<Vec<u8>> {
    let wdb = self.get_workspace_database().await?;
    let data = wdb.get_database_duplicated_data(view_id).await?;
    let json_bytes = data.to_json_bytes()?;
    Ok(json_bytes)
  }

  /// Create a new database with the given data that can be deserialized to [DatabaseData].
  #[tracing::instrument(level = "trace", skip_all, err)]
  pub async fn create_database_with_database_data(
    &self,
    view_id: &str,
    data: Vec<u8>,
  ) -> FlowyResult<()> {
    let mut database_data = DatabaseData::from_json_bytes(data)?;
    database_data.view.id = view_id.to_string();

    let wdb = self.get_workspace_database().await?;
    let _ = wdb.create_database_with_data(database_data)?;
    Ok(())
  }

  pub async fn create_database_with_params(&self, params: CreateDatabaseParams) -> FlowyResult<()> {
    let wdb = self.get_workspace_database().await?;
    let _ = wdb.create_database(params)?;
    Ok(())
  }

  /// A linked view is a view that is linked to existing database.
  #[tracing::instrument(level = "trace", skip(self), err)]
  pub async fn create_linked_view(
    &self,
    name: String,
    layout: DatabaseLayout,
    database_id: String,
    database_view_id: String,
  ) -> FlowyResult<()> {
    let wdb = self.get_workspace_database().await?;
    let mut params = CreateViewParams::new(database_id.clone(), database_view_id, name, layout);
    if let Some(database) = wdb.get_database(&database_id).await {
      if let Some((field, layout_setting)) = DatabaseLayoutDepsResolver::new(database, layout)
        .resolve_deps_when_create_database_linked_view()
      {
        params = params
          .with_deps_fields(vec![field])
          .with_layout_setting(layout_setting);
      }
    };
    wdb.create_database_linked_view(params).await?;
    Ok(())
  }

  pub async fn import_csv(
    &self,
    view_id: String,
    content: String,
    format: CSVFormat,
  ) -> FlowyResult<ImportResult> {
    let params = tokio::task::spawn_blocking(move || {
      CSVImporter.import_csv_from_string(view_id, content, format)
    })
    .await
    .map_err(internal_error)??;
    let result = ImportResult {
      database_id: params.database_id.clone(),
      view_id: params.view_id.clone(),
    };
    self.create_database_with_params(params).await?;
    Ok(result)
  }

  // will implement soon
  pub async fn import_csv_from_file(
    &self,
    _file_path: String,
    _format: CSVFormat,
  ) -> FlowyResult<()> {
    Ok(())
  }

  pub async fn export_csv(&self, view_id: &str, style: CSVFormat) -> FlowyResult<String> {
    let database = self.get_database_with_view_id(view_id).await?;
    database.export_csv(style).await
  }

  pub async fn update_database_layout(
    &self,
    view_id: &str,
    layout: DatabaseLayoutPB,
  ) -> FlowyResult<()> {
    let database = self.get_database_with_view_id(view_id).await?;
    database.update_view_layout(view_id, layout.into()).await
  }

  pub async fn get_database_snapshots(
    &self,
    view_id: &str,
  ) -> FlowyResult<Vec<DatabaseSnapshotPB>> {
    let database_id = self.get_database_id_with_view_id(view_id).await?;
    let mut snapshots = vec![];
    if let Some(snapshot) = self
      .cloud_service
      .get_collab_latest_snapshot(&database_id)
      .await?
      .map(|snapshot| DatabaseSnapshotPB {
        snapshot_id: snapshot.snapshot_id,
        snapshot_desc: "".to_string(),
        created_at: snapshot.created_at,
        data: snapshot.data,
      })
    {
      snapshots.push(snapshot);
    }

    Ok(snapshots)
  }

  async fn get_workspace_database(&self) -> FlowyResult<Arc<WorkspaceDatabase>> {
    let database = self.workspace_database.read().await;
    match &*database {
      None => Err(FlowyError::internal().context("Workspace database not initialized")),
      Some(user_database) => Ok(user_database.clone()),
    }
  }

  /// Only expose this method for testing
  #[cfg(debug_assertions)]
  pub fn get_cloud_service(&self) -> &Arc<dyn DatabaseCloudService> {
    &self.cloud_service
  }
}

/// Send notification to all clients that are listening to the given object.
fn subscribe_block_event(workspace_database: &WorkspaceDatabase) {
  let mut block_event_rx = workspace_database.subscribe_block_event();
  tokio::spawn(async move {
    while let Ok(event) = block_event_rx.recv().await {
      match event {
        BlockEvent::DidFetchRow(row_details) => {
          for row_detail in row_details {
            tracing::trace!("Did fetch row: {:?}", row_detail.row.id);
            let row_id = row_detail.row.id.clone();
            let pb = DidFetchRowPB::from(row_detail);
            send_notification(&row_id, DatabaseNotification::DidFetchRow)
              .payload(pb)
              .send();
          }
        },
      }
    }
  });
}

struct UserDatabaseCollabServiceImpl {
  collab_builder: Arc<AppFlowyCollabBuilder>,
  cloud_service: Arc<dyn DatabaseCloudService>,
}

impl DatabaseCollabService for UserDatabaseCollabServiceImpl {
  fn get_collab_update(
    &self,
    object_id: &str,
  ) -> CollabFuture<Result<CollabObjectUpdate, DatabaseError>> {
    let object_id = object_id.to_string();
    let weak_cloud_service = Arc::downgrade(&self.cloud_service);
    Box::pin(async move {
      match weak_cloud_service.upgrade() {
        None => {
          tracing::warn!("Cloud service is dropped");
          Ok(vec![])
        },
        Some(cloud_service) => {
          let updates = cloud_service
            .get_collab_update(&object_id)
            .await
            .map_err(|e| DatabaseError::Internal(Box::new(e)))?;
          Ok(updates)
        },
      }
    })
  }

  fn batch_get_collab_update(
    &self,
    object_ids: Vec<String>,
  ) -> CollabFuture<Result<CollabObjectUpdateByOid, DatabaseError>> {
    let weak_cloud_service = Arc::downgrade(&self.cloud_service);
    Box::pin(async move {
      match weak_cloud_service.upgrade() {
        None => {
          tracing::warn!("Cloud service is dropped");
          Ok(CollabObjectUpdateByOid::default())
        },
        Some(cloud_service) => {
          let updates = cloud_service
            .batch_get_collab_updates(object_ids)
            .await
            .map_err(|e| DatabaseError::Internal(Box::new(e)))?;
          Ok(updates)
        },
      }
    })
  }

  fn build_collab_with_config(
    &self,
    uid: i64,
    object_id: &str,
    object_name: &str,
    collab_db: Arc<RocksCollabDB>,
    collab_raw_data: CollabRawData,
    config: &CollabPersistenceConfig,
  ) -> Arc<MutexCollab> {
    self
      .collab_builder
      .build_with_config(
        uid,
        object_id,
        object_name,
        collab_db,
        collab_raw_data,
        config,
      )
      .unwrap()
  }
}
