use tokio_postgres::{Client, NoTls};

use flowy_server_config::supabase_config::PostgresConfiguration;

/// Drop all tables and dependencies defined in the v1_initial_up.sql.
/// Be careful when using this function. It will drop all tables and dependencies.
/// Mostly used for testing.
#[allow(dead_code)]
#[cfg(debug_assertions)]
pub(crate) async fn run_initial_drop(client: &Client) {
  // let sql = include_str!("migrations/initial/initial_down.sql");
  let sql = r#"
DROP TABLE IF EXISTS af_user CASCADE;
DROP TABLE IF EXISTS af_workspace CASCADE;
DROP TABLE IF EXISTS af_user_workspace CASCADE;
DROP TABLE IF EXISTS af_collab CASCADE;
DROP TABLE IF EXISTS af_collab_update CASCADE;
DROP VIEW IF EXISTS af_collab_state CASCADE;
DROP TABLE IF EXISTS af_collab_snapshot CASCADE;
DROP TABLE IF EXISTS af_collab_statistics CASCADE;
DROP TABLE IF EXISTS af_roles CASCADE;
DROP TABLE IF EXISTS af_permissions CASCADE;
DROP TABLE IF EXISTS af_role_permissions CASCADE;
DROP TABLE IF EXISTS af_collab_member CASCADE;
DROP TABLE IF EXISTS af_workspace_member CASCADE;
DROP VIEW IF EXISTS af_user_profile_view CASCADE;
DROP TABLE IF EXISTS af_database_row_update CASCADE;

DROP TRIGGER IF EXISTS create_af_workspace_trigger ON af_workspace CASCADE;
DROP FUNCTION IF EXISTS create_af_workspace_func;

DROP TRIGGER IF EXISTS create_af_user_workspace_trigger ON af_workspace CASCADE;
DROP FUNCTION IF EXISTS create_af_user_workspace_trigger_func;

DROP TRIGGER IF EXISTS af_collab_update_insert_trigger ON af_collab_update CASCADE;
DROP FUNCTION IF EXISTS increment_af_collab_update_count;

DROP TRIGGER IF EXISTS af_collab_snapshot_update_edit_count_trigger ON af_collab_snapshot;
DROP FUNCTION IF EXISTS af_collab_snapshot_update_edit_count;

DROP TRIGGER IF EXISTS check_and_delete_snapshots_trigger ON af_collab_snapshot CASCADE;
DROP FUNCTION IF EXISTS check_and_delete_snapshots;

DROP TRIGGER IF EXISTS new_af_collab_update_row_trigger ON af_collab_update CASCADE;
DROP FUNCTION IF EXISTS notify_on_insert_af_collab_update;

DROP TRIGGER IF EXISTS insert_into_af_collab_trigger ON af_collab_update CASCADE;
DROP FUNCTION IF EXISTS insert_into_af_collab_if_not_exists;

DROP TRIGGER IF EXISTS insert_into_af_collab_member_trigger ON af_collab CASCADE;
DROP FUNCTION IF EXISTS insert_into_af_collab_member;

DROP TRIGGER IF EXISTS af_collab_update_edit_count_trigger ON af_collab_update CASCADE;
DROP FUNCTION IF EXISTS increment_af_collab_edit_count;

DROP TRIGGER IF EXISTS manage_af_workspace_member_role_trigger ON af_workspace CASCADE;
DROP FUNCTION IF EXISTS manage_af_workspace_member_role_func;

DROP TRIGGER IF EXISTS update_af_workspace_member_updated_at_trigger ON af_collab_update CASCADE;
DROP FUNCTION IF EXISTS update_af_workspace_member_updated_at_func;

DROP TRIGGER IF EXISTS update_af_user_modtime ON af_user CASCADE;
DROP FUNCTION IF EXISTS update_updated_at_column_func;

DROP FUNCTION IF EXISTS insert_af_workspace_member_if_owner;
DROP FUNCTION IF EXISTS af_shared_collab_for_uid;

DROP FUNCTION IF EXISTS flush_collab_updates;
"#;
  client.batch_execute(sql).await.unwrap();
  client
    .batch_execute("DROP TABLE IF EXISTS af_migration_history")
    .await
    .unwrap();
}

// ‼️‼️‼️ Warning: this test will create a table in the database
#[tokio::test]
async fn run_initial_drop_test() -> Result<(), anyhow::Error> {
  // rename the `.evn.test.danger` to the actual env file name.
  if dotenv::from_filename(".env.test").is_err() {
    return Ok(());
  }

  let configuration = PostgresConfiguration::from_env().unwrap();
  let mut config = tokio_postgres::Config::new();
  config
    .host(&configuration.url)
    .user(&configuration.user_name)
    .password(&configuration.password)
    .port(configuration.port);

  // Using the https://docs.rs/postgres-openssl/latest/postgres_openssl/ to enable tls connection.
  let (client, connection) = config.connect(NoTls).await?;
  tokio::spawn(async move {
    if let Err(e) = connection.await {
      tracing::error!("postgres db connection error: {}", e);
    }
  });

  #[cfg(debug_assertions)]
  {
    run_initial_drop(&client).await;
  }
  Ok(())
}
