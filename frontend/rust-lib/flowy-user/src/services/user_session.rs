use crate::entities::{UserProfilePB, UserSettingPB};
use crate::event_map::UserStatusCallback;
use crate::uid::UserIDGenerator;
use crate::{
  errors::{ErrorCode, FlowyError},
  event_map::UserCloudService,
  notification::*,
  services::database::{UserDB, UserTable, UserTableChangeset},
};
use collab_persistence::CollabKV;
use flowy_sqlite::ConnectionPool;
use flowy_sqlite::{
  kv::KV,
  query_dsl::*,
  schema::{user_table, user_table::dsl},
  DBConnection, ExpressionMethods, UserDatabaseConnection,
};
use lazy_static::lazy_static;
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use user_model::{
  SignInParams, SignInResponse, SignUpParams, SignUpResponse, UpdateUserProfileParams, UserProfile,
};

lazy_static! {
  static ref ID_GEN: Mutex<UserIDGenerator> = Mutex::new(UserIDGenerator::new(1));
}
pub struct UserSessionConfig {
  root_dir: String,

  /// Used as the key of `Session` when saving session information to KV.
  session_cache_key: String,
}

impl UserSessionConfig {
  /// The `root_dir` represents as the root of the user folders. It must be unique for each
  /// users.
  pub fn new(name: &str, root_dir: &str) -> Self {
    let session_cache_key = format!("{}_session_cache", name);
    Self {
      root_dir: root_dir.to_owned(),
      session_cache_key,
    }
  }
}

pub struct UserSession {
  database: UserDB,
  config: UserSessionConfig,
  cloud_service: Arc<dyn UserCloudService>,
  user_status_callback: RwLock<Option<Arc<dyn UserStatusCallback>>>,
}

impl UserSession {
  pub fn new(config: UserSessionConfig, cloud_service: Arc<dyn UserCloudService>) -> Self {
    let db = UserDB::new(&config.root_dir);
    let user_status_callback = RwLock::new(None);
    Self {
      database: db,
      config,
      cloud_service,
      user_status_callback,
    }
  }

  pub async fn init<C: UserStatusCallback + 'static>(&self, user_status_callback: C) {
    // if let Some(old_session) = self.get_old_session() {
    //   let uid = ID_GEN.lock().next_id();
    //   let _ = user_status_callback
    //     .will_migrated(&old_session.token, &old_session.user_id, uid)
    //     .await;
    //
    //   let new_session = Session {
    //     user_id: uid,
    //     token: old_session.token.clone(),
    //     email: old_session.email.clone(),
    //     name: old_session.name.clone(),
    //   };
    //   self.set_session(Some(new_session)).unwrap();
    //
    //   if let Ok(db) = self.db_connection() {
    //     // Update db
    //     let _ = db.immediate_transaction(|| {
    //       // get the user data
    //       let mut user = dsl::user_table
    //         .filter(user_table::id.eq(&old_session.user_id))
    //         .first::<UserTable>(&*db)?;
    //
    //       // delete the existing row
    //       let _ = diesel::delete(dsl::user_table.filter(dsl::id.eq(&old_session.user_id)))
    //         .execute(&*db)?;
    //
    //       // insert new row
    //       user.id = uid.to_string();
    //       let _ = diesel::insert_into(user_table::table)
    //         .values(user)
    //         .execute(&*db)?;
    //       Ok::<(), FlowyError>(())
    //     });
    //   }
    // }

    if let Ok(session) = self.get_session() {
      let _ = user_status_callback
        .did_sign_in(&session.token, session.user_id)
        .await;
    }
    *self.user_status_callback.write().await = Some(Arc::new(user_status_callback));
  }

  pub fn db_connection(&self) -> Result<DBConnection, FlowyError> {
    let user_id = self.get_session()?.user_id;
    self.database.get_connection(user_id)
  }

  // The caller will be not 'Sync' before of the return value,
  // PooledConnection<ConnectionManager> is not sync. You can use
  // db_connection_pool function to require the ConnectionPool that is 'Sync'.
  //
  // let pool = self.db_connection_pool()?;
  // let conn: PooledConnection<ConnectionManager> = pool.get()?;
  pub fn db_pool(&self) -> Result<Arc<ConnectionPool>, FlowyError> {
    let user_id = self.get_session()?.user_id;
    self.database.get_pool(user_id)
  }

  pub fn get_kv_db(&self) -> Result<Arc<CollabKV>, FlowyError> {
    let user_id = self.get_session()?.user_id;
    self.database.get_kv_db(user_id)
  }

  #[tracing::instrument(level = "debug", skip(self))]
  pub async fn sign_in(&self, params: SignInParams) -> Result<UserProfile, FlowyError> {
    if self.is_user_login(&params.email) {
      match self.get_user_profile().await {
        Ok(profile) => {
          send_sign_in_notification()
            .payload::<UserProfilePB>(profile.clone().into())
            .send();
          Ok(profile)
        },
        Err(err) => Err(err),
      }
    } else {
      let resp = self.cloud_service.sign_in(params).await?;
      let session: Session = resp.clone().into();
      self.set_session(Some(session))?;
      let user_profile: UserProfile = self.save_user(resp.into()).await?.into();
      let _ = self
        .user_status_callback
        .read()
        .await
        .as_ref()
        .unwrap()
        .did_sign_in(&user_profile.token, user_profile.id)
        .await;
      send_sign_in_notification()
        .payload::<UserProfilePB>(user_profile.clone().into())
        .send();
      Ok(user_profile)
    }
  }

  #[tracing::instrument(level = "debug", skip(self))]
  pub async fn sign_up(&self, params: SignUpParams) -> Result<UserProfile, FlowyError> {
    if self.is_user_login(&params.email) {
      self.get_user_profile().await
    } else {
      let resp = self.cloud_service.sign_up(params).await?;
      let session: Session = resp.clone().into();
      self.set_session(Some(session))?;
      let user_table = self.save_user(resp.into()).await?;
      let user_profile: UserProfile = user_table.into();
      let _ = self
        .user_status_callback
        .read()
        .await
        .as_ref()
        .unwrap()
        .did_sign_up(&user_profile)
        .await;
      Ok(user_profile)
    }
  }

  #[tracing::instrument(level = "debug", skip(self))]
  pub async fn sign_out(&self) -> Result<(), FlowyError> {
    let session = self.get_session()?;
    let uid = session.user_id.to_string();
    let _ = diesel::delete(dsl::user_table.filter(dsl::id.eq(&uid)))
      .execute(&*(self.db_connection()?))?;
    self.database.close_user_db(session.user_id)?;
    self.set_session(None)?;
    let _ = self
      .user_status_callback
      .read()
      .await
      .as_ref()
      .unwrap()
      .did_expired(&session.token, session.user_id)
      .await;
    self.sign_out_on_server(&session.token).await?;

    Ok(())
  }

  #[tracing::instrument(level = "debug", skip(self))]
  pub async fn update_user_profile(
    &self,
    params: UpdateUserProfileParams,
  ) -> Result<(), FlowyError> {
    let session = self.get_session()?;
    let changeset = UserTableChangeset::new(params.clone());
    diesel_update_table!(user_table, changeset, &*self.db_connection()?);

    let user_profile = self.get_user_profile().await?;
    let profile_pb: UserProfilePB = user_profile.into();
    send_notification(&session.token, UserNotification::DidUpdateUserProfile)
      .payload(profile_pb)
      .send();
    self.update_user_on_server(&session.token, params).await?;
    Ok(())
  }

  pub async fn init_user(&self) -> Result<(), FlowyError> {
    Ok(())
  }

  pub async fn check_user(&self) -> Result<UserProfile, FlowyError> {
    let (user_id, token) = self.get_session()?.into_part();
    let user_id = user_id.to_string();
    let user = dsl::user_table
      .filter(user_table::id.eq(&user_id))
      .first::<UserTable>(&*(self.db_connection()?))?;

    self.read_user_profile_on_server(&token)?;
    Ok(user.into())
  }

  pub async fn get_user_profile(&self) -> Result<UserProfile, FlowyError> {
    let (user_id, token) = self.get_session()?.into_part();
    let user_id = user_id.to_string();
    let user = dsl::user_table
      .filter(user_table::id.eq(&user_id))
      .first::<UserTable>(&*(self.db_connection()?))?;

    self.read_user_profile_on_server(&token)?;
    Ok(user.into())
  }

  pub fn user_dir(&self) -> Result<String, FlowyError> {
    let session = self.get_session()?;
    Ok(format!("{}/{}", self.config.root_dir, session.user_id))
  }

  pub fn user_setting(&self) -> Result<UserSettingPB, FlowyError> {
    let user_setting = UserSettingPB {
      user_folder: self.user_dir()?,
    };
    Ok(user_setting)
  }

  pub fn user_id(&self) -> Result<i64, FlowyError> {
    Ok(self.get_session()?.user_id)
  }

  pub fn user_name(&self) -> Result<String, FlowyError> {
    Ok(self.get_session()?.name)
  }

  pub fn token(&self) -> Result<String, FlowyError> {
    Ok(self.get_session()?.token)
  }
}

impl UserSession {
  fn read_user_profile_on_server(&self, _token: &str) -> Result<(), FlowyError> {
    Ok(())
  }

  async fn update_user_on_server(
    &self,
    token: &str,
    params: UpdateUserProfileParams,
  ) -> Result<(), FlowyError> {
    let server = self.cloud_service.clone();
    let token = token.to_owned();
    let _ = tokio::spawn(async move {
      match server.update_user(&token, params).await {
        Ok(_) => {},
        Err(e) => {
          // TODO: retry?
          tracing::error!("update user profile failed: {:?}", e);
        },
      }
    })
    .await;
    Ok(())
  }

  async fn sign_out_on_server(&self, token: &str) -> Result<(), FlowyError> {
    let server = self.cloud_service.clone();
    let token = token.to_owned();
    let _ = tokio::spawn(async move {
      match server.sign_out(&token).await {
        Ok(_) => {},
        Err(e) => tracing::error!("Sign out failed: {:?}", e),
      }
    })
    .await;
    Ok(())
  }

  async fn save_user(&self, user: UserTable) -> Result<UserTable, FlowyError> {
    let conn = self.db_connection()?;
    let _ = diesel::insert_into(user_table::table)
      .values(user.clone())
      .execute(&*conn)?;
    Ok(user)
  }

  fn set_session(&self, session: Option<Session>) -> Result<(), FlowyError> {
    tracing::debug!("Set user session: {:?}", session);
    match &session {
      None => KV::remove(&self.config.session_cache_key)
        .map_err(|e| FlowyError::new(ErrorCode::Internal, &e))?,
      Some(session) => KV::set_str(&self.config.session_cache_key, session.clone().into()),
    }
    Ok(())
  }

  fn get_session(&self) -> Result<Session, FlowyError> {
    match KV::get_str(&self.config.session_cache_key) {
      None => Err(FlowyError::unauthorized()),
      Some(s) => Ok(Session::from(s)),
    }
  }

  // fn get_old_session(&self) -> Option<OldSession> {
  //   let s = KV::get_str(&self.config.session_cache_key)?;
  //   serde_json::from_str::<OldSession>(&s).ok()
  // }

  fn is_user_login(&self, email: &str) -> bool {
    match self.get_session() {
      Ok(session) => session.email == email,
      Err(_) => false,
    }
  }
}

pub async fn update_user(
  _cloud_service: Arc<dyn UserCloudService>,
  pool: Arc<ConnectionPool>,
  params: UpdateUserProfileParams,
) -> Result<(), FlowyError> {
  let changeset = UserTableChangeset::new(params);
  let conn = pool.get()?;
  diesel_update_table!(user_table, changeset, &*conn);
  Ok(())
}

impl UserDatabaseConnection for UserSession {
  fn get_connection(&self) -> Result<DBConnection, String> {
    self.db_connection().map_err(|e| format!("{:?}", e))
  }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct Session {
  user_id: i64,
  token: String,
  email: String,
  #[serde(default)]
  name: String,
}

impl std::convert::From<SignInResponse> for Session {
  fn from(resp: SignInResponse) -> Self {
    Session {
      user_id: resp.user_id,
      token: resp.token,
      email: resp.email,
      name: resp.name,
    }
  }
}

impl std::convert::From<SignUpResponse> for Session {
  fn from(resp: SignUpResponse) -> Self {
    Session {
      user_id: resp.user_id,
      token: resp.token,
      email: resp.email,
      name: resp.name,
    }
  }
}

impl Session {
  pub fn into_part(self) -> (i64, String) {
    (self.user_id, self.token)
  }
}

impl std::convert::From<String> for Session {
  fn from(s: String) -> Self {
    match serde_json::from_str(&s) {
      Ok(s) => s,
      Err(e) => {
        tracing::error!("Deserialize string to Session failed: {:?}", e);
        Session::default()
      },
    }
  }
}
impl std::convert::From<Session> for String {
  fn from(session: Session) -> Self {
    match serde_json::to_string(&session) {
      Ok(s) => s,
      Err(e) => {
        tracing::error!("Serialize session to string failed: {:?}", e);
        "".to_string()
      },
    }
  }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct OldSession {
  user_id: String,
  token: String,
  email: String,
  #[serde(default)]
  name: String,
}
