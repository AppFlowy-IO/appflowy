#[cfg(feature = "proto_gen")]
pub mod protobuf_file;

#[cfg(feature = "dart_event")]
pub mod dart_event;

#[cfg(feature = "ts_event")]
pub mod ts_event;

#[cfg(any(feature = "proto_gen", feature = "dart_event", feature = "ts_event"))]
mod flowy_toml;

pub(crate) mod ast;
#[cfg(any(feature = "proto_gen", feature = "dart_event", feature = "ts_event"))]
pub mod util;

#[derive(serde::Serialize, serde::Deserialize)]
pub struct ProtoCache {
  pub structs: Vec<String>,
  pub enums: Vec<String>,
}

pub enum Project {
  Tauri,
  Web,
  Native,
}

impl Project {
  pub fn dst(&self) -> String {
    match self {
      Project::Tauri => "appflowy_tauri/src/services/backend".to_string(),
      Project::Web => "src/services/backend".to_string(),
      Project::Native => panic!("Native project is not supported yet."),
    }
  }

  pub fn event_root(&self) -> String {
    match self {
      Project::Tauri => "../../".to_string(),
      Project::Web => "../../".to_string(),
      Project::Native => panic!("Native project is not supported yet."),
    }
  }

  pub fn model_root(&self) -> String {
    match self {
      Project::Tauri => "../../".to_string(),
      Project::Web => "../../".to_string(),
      Project::Native => panic!("Native project is not supported yet."),
    }
  }

  pub fn event_imports(&self) -> String {
    match self {
      Project::Tauri => r#"
/// Auto generate. Do not edit
import { Ok, Err, Result } from "ts-results";
import { invoke } from "@tauri-apps/api/tauri";
import * as pb from "../..";
"#
      .to_string(),
      Project::Web => r#"
/// Auto generate. Do not edit
import { Ok, Err, Result } from "ts-results";
import { invoke } from "@/application/app.ts";
import * as pb from "../..";
"#
      .to_string(),
      Project::Native => panic!("Native project is not supported yet."),
    }
  }
}
