use flowy_database::ConnectionPool;
use flowy_database::{schema::user_table, DBConnection, Database};
use flowy_error::{ErrorCode, FlowyError};
use flowy_user_data_model::entities::{SignInResponse, SignUpResponse, UpdateUserParams, UserProfile};
use lazy_static::lazy_static;
use parking_lot::RwLock;
use std::{collections::HashMap, sync::Arc, time::Duration};

lazy_static! {
    static ref DB: RwLock<Option<Database>> = RwLock::new(None);
}

pub struct UserDB {
    db_dir: String,
}

impl UserDB {
    pub fn new(db_dir: &str) -> Self {
        Self {
            db_dir: db_dir.to_owned(),
        }
    }

    fn open_user_db_if_need(&self, user_id: &str) -> Result<Arc<ConnectionPool>, FlowyError> {
        if user_id.is_empty() {
            return Err(ErrorCode::UserIdIsEmpty.into());
        }

        if let Some(database) = DB_MAP.read().get(user_id) {
            return Ok(database.get_pool());
        }

        let mut write_guard = DB_MAP.write();
        // The Write guard acquire exclusive access that will guarantee the user db only initialize once.
        match write_guard.get(user_id) {
            None => {}
            Some(database) => return Ok(database.get_pool()),
        }

        tracing::trace!("open user db {}", user_id);
        let dir = format!("{}/{}", self.db_dir, user_id);
        let db = flowy_database::init(&dir).map_err(|e| {
            log::error!("open user: {} db failed, {:?}", user_id, e);
            FlowyError::internal().context(e)
        })?;
        let pool = db.get_pool();
        write_guard.insert(user_id.to_owned(), db);
        drop(write_guard);
        Ok(pool)
    }

    pub(crate) fn close_user_db(&self, user_id: &str) -> Result<(), FlowyError> {
        match DB_MAP.try_write_for(Duration::from_millis(300)) {
            None => Err(FlowyError::internal().context("Acquire write lock to close user db failed")),
            Some(mut write_guard) => {
                write_guard.remove(user_id);
                Ok(())
            }
        }
    }

    pub(crate) fn get_connection(&self, user_id: &str) -> Result<DBConnection, FlowyError> {
        let conn = self.get_pool(user_id)?.get()?;
        Ok(conn)
    }

    pub(crate) fn get_pool(&self, user_id: &str) -> Result<Arc<ConnectionPool>, FlowyError> {
        let pool = self.open_user_db_if_need(user_id)?;
        Ok(pool)
    }
}

lazy_static! {
    static ref DB_MAP: RwLock<HashMap<String, Database>> = RwLock::new(HashMap::new());
}

#[derive(Clone, Default, Queryable, Identifiable, Insertable)]
#[table_name = "user_table"]
pub struct UserTable {
    pub(crate) id: String,
    pub(crate) name: String,
    pub(crate) token: String,
    pub(crate) email: String,
    pub(crate) workspace: String, // deprecated
}

impl UserTable {
    pub fn new(id: String, name: String, email: String, token: String) -> Self {
        Self {
            id,
            name,
            email,
            token,
            workspace: "".to_owned(),
        }
    }

    pub fn set_workspace(mut self, workspace: String) -> Self {
        self.workspace = workspace;
        self
    }
}

impl std::convert::From<SignUpResponse> for UserTable {
    fn from(resp: SignUpResponse) -> Self {
        UserTable::new(resp.user_id, resp.name, resp.email, resp.token)
    }
}

impl std::convert::From<SignInResponse> for UserTable {
    fn from(resp: SignInResponse) -> Self {
        UserTable::new(resp.user_id, resp.name, resp.email, resp.token)
    }
}

impl std::convert::From<UserTable> for UserProfile {
    fn from(table: UserTable) -> Self {
        UserProfile {
            id: table.id,
            email: table.email,
            name: table.name,
            token: table.token,
        }
    }
}

#[derive(AsChangeset, Identifiable, Default, Debug)]
#[table_name = "user_table"]
pub struct UserTableChangeset {
    pub id: String,
    pub workspace: Option<String>, // deprecated
    pub name: Option<String>,
    pub email: Option<String>,
}

impl UserTableChangeset {
    pub fn new(params: UpdateUserParams) -> Self {
        UserTableChangeset {
            id: params.id,
            workspace: None,
            name: params.name,
            email: params.email,
        }
    }
}
