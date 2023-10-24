use nanoid::nanoid;

use event_integration::{event_builder::EventBuilder, EventIntegrationTest};
use flowy_user::entities::{AuthTypePB, UpdateUserProfilePayloadPB, UserProfilePB};
use flowy_user::{errors::ErrorCode, event_map::UserEvent::*};

use crate::user::local_test::helper::*;

// use serial_test::*;

#[tokio::test]
async fn user_profile_get_failed() {
  let sdk = EventIntegrationTest::new();
  let result = EventBuilder::new(sdk)
    .event(GetUserProfile)
    .async_send()
    .await
    .error();
  assert!(result.is_some())
}

#[tokio::test]
async fn anon_user_profile_get() {
  let test = EventIntegrationTest::new();
  let user_profile = test.init_anon_user().await;
  let user = EventBuilder::new(test.clone())
    .event(GetUserProfile)
    .sync_send()
    .parse::<UserProfilePB>();
  assert_eq!(user_profile.id, user.id);
  assert_eq!(user_profile.openai_key, user.openai_key);
  assert_eq!(user_profile.stability_ai_key, user.stability_ai_key);
  assert_eq!(user_profile.workspace_id, user.workspace_id);
  assert_eq!(user_profile.auth_type, AuthTypePB::Local);
}

#[tokio::test]
async fn user_update_with_name() {
  let sdk = EventIntegrationTest::new();
  let user = sdk.init_anon_user().await;
  let new_name = "hello_world".to_owned();
  let request = UpdateUserProfilePayloadPB::new(user.id).name(&new_name);
  let _ = EventBuilder::new(sdk.clone())
    .event(UpdateUserProfile)
    .payload(request)
    .sync_send();

  let user_profile = EventBuilder::new(sdk.clone())
    .event(GetUserProfile)
    .sync_send()
    .parse::<UserProfilePB>();

  assert_eq!(user_profile.name, new_name,);
}

#[tokio::test]
async fn user_update_with_ai_key() {
  let sdk = EventIntegrationTest::new();
  let user = sdk.init_anon_user().await;
  let openai_key = "openai_key".to_owned();
  let stability_ai_key = "stability_ai_key".to_owned();
  let request = UpdateUserProfilePayloadPB::new(user.id)
    .openai_key(&openai_key)
    .stability_ai_key(&stability_ai_key);
  let _ = EventBuilder::new(sdk.clone())
    .event(UpdateUserProfile)
    .payload(request)
    .sync_send();

  let user_profile = EventBuilder::new(sdk.clone())
    .event(GetUserProfile)
    .sync_send()
    .parse::<UserProfilePB>();

  assert_eq!(user_profile.openai_key, openai_key,);
  assert_eq!(user_profile.stability_ai_key, stability_ai_key,);
}

#[tokio::test]
async fn anon_user_update_with_email() {
  let sdk = EventIntegrationTest::new();
  let user = sdk.init_anon_user().await;
  let new_email = format!("{}@gmail.com", nanoid!(6));
  let request = UpdateUserProfilePayloadPB::new(user.id).email(&new_email);
  let _ = EventBuilder::new(sdk.clone())
    .event(UpdateUserProfile)
    .payload(request)
    .sync_send();
  let user_profile = EventBuilder::new(sdk.clone())
    .event(GetUserProfile)
    .sync_send()
    .parse::<UserProfilePB>();

  // When the user is anonymous, the email is empty no matter what you set
  assert!(user_profile.email.is_empty());
}

#[tokio::test]
async fn user_update_with_invalid_email() {
  let test = EventIntegrationTest::new();
  let user = test.init_anon_user().await;
  for email in invalid_email_test_case() {
    let request = UpdateUserProfilePayloadPB::new(user.id).email(&email);
    assert_eq!(
      EventBuilder::new(test.clone())
        .event(UpdateUserProfile)
        .payload(request)
        .sync_send()
        .error()
        .unwrap()
        .code,
      ErrorCode::EmailFormatInvalid
    );
  }
}

#[tokio::test]
async fn user_update_with_invalid_password() {
  let test = EventIntegrationTest::new();
  let user = test.init_anon_user().await;
  for password in invalid_password_test_case() {
    let request = UpdateUserProfilePayloadPB::new(user.id).password(&password);

    assert!(EventBuilder::new(test.clone())
      .event(UpdateUserProfile)
      .payload(request)
      .async_send()
      .await
      .error()
      .is_some());
  }
}

#[tokio::test]
async fn user_update_with_invalid_name() {
  let test = EventIntegrationTest::new();
  let user = test.init_anon_user().await;
  let request = UpdateUserProfilePayloadPB::new(user.id).name("");
  assert!(EventBuilder::new(test.clone())
    .event(UpdateUserProfile)
    .payload(request)
    .sync_send()
    .error()
    .is_some())
}
