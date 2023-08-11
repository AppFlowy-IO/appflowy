use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_repr::*;
use uuid::Uuid;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct SignInResponse {
  pub user_id: i64,
  pub name: String,
  pub latest_workspace: UserWorkspace,
  pub user_workspaces: Vec<UserWorkspace>,
  pub email: Option<String>,
  pub token: Option<String>,
}

#[derive(Default, Serialize, Deserialize, Debug)]
pub struct SignInParams {
  pub email: String,
  pub password: String,
  pub name: String,
  pub auth_type: AuthType,
  // Currently, the uid only used in local sign in.
  pub uid: Option<i64>,
}

#[derive(Serialize, Deserialize, Default, Debug)]
pub struct SignUpParams {
  pub email: String,
  pub name: String,
  pub password: String,
  pub auth_type: AuthType,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct SignUpResponse {
  pub user_id: i64,
  pub name: String,
  pub latest_workspace: UserWorkspace,
  pub user_workspaces: Vec<UserWorkspace>,
  pub is_new: bool,
  pub email: Option<String>,
  pub token: Option<String>,
}

#[derive(Clone, Debug)]
pub struct UserCredentials {
  /// Currently, the token is only used when the [AuthType] is SelfHosted
  pub token: Option<String>,

  /// The user id
  pub uid: Option<i64>,

  /// The user id
  pub uuid: Option<String>,
}

impl UserCredentials {
  pub fn from_uid(uid: i64) -> Self {
    Self {
      token: None,
      uid: Some(uid),
      uuid: None,
    }
  }

  pub fn from_uuid(uuid: String) -> Self {
    Self {
      token: None,
      uid: None,
      uuid: Some(uuid),
    }
  }

  pub fn new(token: Option<String>, uid: Option<i64>, uuid: Option<String>) -> Self {
    Self { token, uid, uuid }
  }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct UserWorkspace {
  pub id: String,
  pub name: String,
  pub created_at: DateTime<Utc>,
  pub database_storage_id: String,
}

impl UserWorkspace {
  pub fn new(workspace_id: &str, _uid: i64) -> Self {
    Self {
      id: workspace_id.to_string(),
      name: "".to_string(),
      created_at: Utc::now(),
      database_storage_id: uuid::Uuid::new_v4().to_string(),
    }
  }
}

#[derive(Serialize, Deserialize, Default, Debug, Clone)]
pub struct UserProfile {
  pub id: i64,
  pub email: String,
  pub name: String,
  pub token: String,
  pub icon_url: String,
  pub openai_key: String,
  pub workspace_id: String,
  pub auth_type: AuthType,
}

#[derive(Serialize, Deserialize, Default, Clone, Debug)]
pub struct UpdateUserProfileParams {
  pub id: i64,
  pub auth_type: AuthType,
  pub name: Option<String>,
  pub email: Option<String>,
  pub password: Option<String>,
  pub icon_url: Option<String>,
  pub openai_key: Option<String>,
}

impl UpdateUserProfileParams {
  pub fn name(mut self, name: &str) -> Self {
    self.name = Some(name.to_owned());
    self
  }

  pub fn email(mut self, email: &str) -> Self {
    self.email = Some(email.to_owned());
    self
  }

  pub fn password(mut self, password: &str) -> Self {
    self.password = Some(password.to_owned());
    self
  }

  pub fn icon_url(mut self, icon_url: &str) -> Self {
    self.icon_url = Some(icon_url.to_owned());
    self
  }

  pub fn openai_key(mut self, openai_key: &str) -> Self {
    self.openai_key = Some(openai_key.to_owned());
    self
  }

  pub fn is_empty(&self) -> bool {
    self.name.is_none()
      && self.email.is_none()
      && self.password.is_none()
      && self.icon_url.is_none()
      && self.openai_key.is_none()
  }
}

#[derive(Debug, Clone, Hash, Serialize_repr, Deserialize_repr, Eq, PartialEq)]
#[repr(u8)]
pub enum AuthType {
  /// It's a local server, we do fake sign in default.
  Local = 0,
  /// Currently not supported. It will be supported in the future when the
  /// [AppFlowy-Server](https://github.com/AppFlowy-IO/AppFlowy-Server) ready.
  SelfHosted = 1,
  /// It uses Supabase as the backend.
  Supabase = 2,
}

impl Default for AuthType {
  fn default() -> Self {
    Self::Local
  }
}

impl AuthType {
  pub fn is_local(&self) -> bool {
    matches!(self, AuthType::Local)
  }
}

impl From<i32> for AuthType {
  fn from(value: i32) -> Self {
    match value {
      0 => AuthType::Local,
      1 => AuthType::SelfHosted,
      2 => AuthType::Supabase,
      _ => AuthType::Local,
    }
  }
}
pub struct ThirdPartyParams {
  pub uuid: Uuid,
  pub email: String,
}
