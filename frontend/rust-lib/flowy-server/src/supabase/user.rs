use std::collections::HashMap;
use std::sync::Arc;

use postgrest::Postgrest;

use flowy_error::{ErrorCode, FlowyError};
use flowy_user::entities::{SignInResponse, SignUpResponse, UpdateUserProfileParams, UserProfile};
use flowy_user::event_map::UserAuthService;
use lib_infra::box_any::BoxAny;
use lib_infra::future::FutureResult;

pub(crate) struct PostgrestUserAuthServiceImpl {
  postgrest: Arc<Postgrest>,
}

impl PostgrestUserAuthServiceImpl {
  pub(crate) fn new(postgrest: Arc<Postgrest>) -> Self {
    Self { postgrest }
  }
}

async fn create_user_with_uuid(postgrest: Arc<Postgrest>, uuid: String) -> Result<i64, FlowyError> {
  let insert = format!("{{\"uuid\": \"{}\"}}", uuid);
  let _resp = postgrest
    .from("user")
    .insert(insert)
    .execute()
    .await
    .map_err(|e| FlowyError::new(ErrorCode::HttpError, e))?;

  todo!()
}

fn uuid_from_box_any(any: BoxAny) -> Result<String, FlowyError> {
  let map: HashMap<String, String> = any.unbox_or_error()?;
  let uuid = map.get("uuid").ok_or(FlowyError::new(
    ErrorCode::MissingAuthField,
    "Missing uuid field",
  ))?;
  Ok(uuid.to_string())
}

impl UserAuthService for PostgrestUserAuthServiceImpl {
  fn sign_up(&self, params: BoxAny) -> FutureResult<SignUpResponse, FlowyError> {
    let postgrest = self.postgrest.clone();
    FutureResult::new(async move {
      let uuid = uuid_from_box_any(params)?;
      let uid = create_user_with_uuid(postgrest, uuid).await?;
      Ok(SignUpResponse {
        user_id: uid,
        ..Default::default()
      })
    })
  }

  fn sign_in(&self, params: BoxAny) -> FutureResult<SignInResponse, FlowyError> {
    let postgrest = self.postgrest.clone();
    FutureResult::new(async move {
      let uuid = uuid_from_box_any(params)?;
      let uid = create_user_with_uuid(postgrest, uuid).await?;
      Ok(SignInResponse {
        user_id: uid,
        ..Default::default()
      })
    })
  }

  fn sign_out(&self, _token: Option<String>) -> FutureResult<(), FlowyError> {
    FutureResult::new(async { Ok(()) })
  }

  fn update_user(
    &self,
    _uid: i64,
    _token: &Option<String>,
    _params: UpdateUserProfileParams,
  ) -> FutureResult<(), FlowyError> {
    FutureResult::new(async { Ok(()) })
  }

  fn get_user(&self, _token: &str) -> FutureResult<UserProfile, FlowyError> {
    todo!()
  }
}

#[cfg(test)]
mod tests {
  use std::sync::Arc;

  use dotenv::dotenv;
  use postgrest::Postgrest;
  use uuid::Uuid;

  use crate::supabase::{SupabaseServer, SupabaseServerConfiguration};

  #[tokio::test]
  async fn read_user_table_test() {
    dotenv().ok();
    if let Ok(config) = SupabaseServerConfiguration::from_env() {
      let server = Arc::new(SupabaseServer::new(config));
      let resp = server
        .postgres
        .from("user")
        .eq("id", "0")
        .select("*")
        .execute()
        .await
        .unwrap();
      let body = resp.text().await.unwrap();
      println!("{}", body);
    }
  }

  #[tokio::test]
  async fn insert_user_table_test() {
    dotenv().ok();
    if let Ok(config) = SupabaseServerConfiguration::from_env() {
      let server = Arc::new(SupabaseServer::new(config));
      // let uuid = Uuid::new_v4();
      let uuid = "e5d692b5-28bd-4995-9a4f-1c57a493fef7";
      let insert = format!("{{\"uuid\": \"{}\"}}", uuid.to_string());
      let resp = server
        .postgres
        .from("user")
        .insert(insert)
        .execute()
        .await
        .unwrap();
      println!("{:?}", resp.status());
      println!("{:?}", resp.headers());
      println!("{}", resp.text().await.unwrap());
    }
  }
}
