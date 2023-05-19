use std::collections::HashMap;
use std::sync::Arc;

use postgrest::Postgrest;
use serde_json::json;

use flowy_error::{ErrorCode, FlowyError};
use flowy_user::entities::UpdateUserProfileParams;
use lib_infra::box_any::BoxAny;

use crate::supabase::response::{
  InsertResponse, PostgresUserProfile, PostgrestError, PostgrestProfileList,
};
use crate::supabase::user::{USER_PROFILE_TABLE, USER_TABLE};

const USER_ID: &str = "uid";
const USER_UUID: &str = "uuid";

pub(crate) async fn create_user_with_uuid(
  postgrest: Arc<Postgrest>,
  uuid: String,
) -> Result<i64, FlowyError> {
  let insert = format!("{{\"{}\": \"{}\"}}", USER_UUID, &uuid);

  // Create a new user with uuid.
  let resp = postgrest
    .from(USER_TABLE)
    .insert(insert)
    .execute()
    .await
    .map_err(|e| FlowyError::new(ErrorCode::HttpError, e))?;

  // Check if the request is successful.
  // If the request is successful, get the user id from the response. Otherwise, try to get the
  // user id with uuid if the error is unique violation,
  let is_success = resp.status().is_success();
  let content = resp
    .text()
    .await
    .map_err(|e| FlowyError::new(ErrorCode::UnexpectedEmpty, e))?;

  if is_success {
    let record = serde_json::from_str::<InsertResponse>(&content)
      .map_err(|e| FlowyError::serde().context(e))?
      .first_or_error()?;
    Ok(record.id)
  } else {
    let err = serde_json::from_str::<PostgrestError>(&content)
      .map_err(|e| FlowyError::serde().context(e))?;

    // If there is a unique violation, try to get the user id with uuid. At this point, the user
    // should exist.
    if err.is_unique_violation() {
      match get_user_id_with_uuid(postgrest, uuid).await? {
        Some(uid) => Ok(uid),
        None => Err(FlowyError::internal().context("Failed to get user id with uuid")),
      }
    } else {
      Err(FlowyError::new(ErrorCode::Internal, err))
    }
  }
}

pub(crate) async fn get_user_id_with_uuid(
  postgrest: Arc<Postgrest>,
  uuid: String,
) -> Result<Option<i64>, FlowyError> {
  let resp = postgrest
    .from(USER_TABLE)
    .eq(USER_UUID, uuid)
    .select("*")
    .execute()
    .await
    .map_err(|e| FlowyError::new(ErrorCode::HttpError, e))?;

  let is_success = resp.status().is_success();
  if !is_success {
    return Err(FlowyError::new(
      ErrorCode::Internal,
      "Failed to get user id with uuid",
    ));
  }

  let content = resp
    .text()
    .await
    .map_err(|e| FlowyError::new(ErrorCode::UnexpectedEmpty, e))?;
  let resp = serde_json::from_str::<InsertResponse>(&content).unwrap();
  if resp.0.is_empty() {
    Ok(None)
  } else {
    Ok(Some(resp.0[0].id))
  }
}

pub(crate) fn uuid_from_box_any(any: BoxAny) -> Result<String, FlowyError> {
  let map: HashMap<String, String> = any.unbox_or_error()?;
  let uuid = map
    .get(USER_UUID)
    .ok_or_else(|| FlowyError::new(ErrorCode::MissingAuthField, "Missing uuid field"))?;
  Ok(uuid.to_string())
}

pub(crate) async fn get_user_profile(
  postgrest: Arc<Postgrest>,
  uid: i64,
) -> Result<Option<PostgresUserProfile>, FlowyError> {
  let resp = postgrest
    .from(USER_PROFILE_TABLE)
    .eq(USER_ID, uid.to_string())
    .select("*")
    .execute()
    .await
    .map_err(|e| FlowyError::new(ErrorCode::HttpError, e))?;

  let content = resp
    .text()
    .await
    .map_err(|e| FlowyError::new(ErrorCode::UnexpectedEmpty, e))?;
  let resp = serde_json::from_str::<PostgrestProfileList>(&content)
    .map_err(|_e| FlowyError::new(ErrorCode::Serde, "Deserialize PostgrestProfileList failed"))?;
  Ok(resp.0.first().cloned())
}

pub(crate) async fn update_user_profile(
  postgrest: Arc<Postgrest>,
  params: UpdateUserProfileParams,
) -> Result<Option<PostgresUserProfile>, FlowyError> {
  if params.is_empty() {
    return Err(FlowyError::new(
      ErrorCode::UnexpectedEmpty,
      "Empty update params",
    ));
  }

  let mut update = serde_json::Map::new();
  if let Some(name) = params.name {
    update.insert("name".to_string(), json!(name));
  }
  let update_str = serde_json::to_string(&update).unwrap();
  let resp = postgrest
    .from(USER_PROFILE_TABLE)
    .eq(USER_ID, params.id.to_string())
    .update(update_str)
    .execute()
    .await
    .map_err(|e| FlowyError::new(ErrorCode::HttpError, e))?;

  let content = resp
    .text()
    .await
    .map_err(|e| FlowyError::new(ErrorCode::UnexpectedEmpty, e))?;

  let resp = serde_json::from_str::<PostgrestProfileList>(&content)
    .map_err(|_e| FlowyError::new(ErrorCode::Serde, "Deserialize PostgrestProfileList failed"))?;
  Ok(resp.0.first().cloned())
}
