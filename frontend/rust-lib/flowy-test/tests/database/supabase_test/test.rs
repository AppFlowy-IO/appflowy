use flowy_database2::entities::{DatabaseSnapshotStatePB, DatabaseSyncStatePB};
use std::time::Duration;

use crate::database::supabase_test::helper::FlowySupabaseDatabaseTest;

#[tokio::test]
async fn initial_collab_update_test() {
  if let Some(test) = FlowySupabaseDatabaseTest::new().await {
    let (view, database) = test.create_database().await;
    let mut rx = test
      .notification_sender
      .subscribe::<DatabaseSnapshotStatePB>(&database.id);

    // Continue to receive updates until we get the initial snapshot
    loop {
      if let Some(state) = rx.recv().await {
        if let Some(snapshot_id) = state.new_snapshot_id {
          break;
        }
      }
    }

    let snapshots = test.get_database_snapshots(&view.id).await;
    assert_eq!(snapshots.items.len(), 1);
  }
}
