use anyhow::{Context, Result};
use std::process::Command;
use nix::sys::stat::Mode;
use nix::fcntl::{open, OFlag};
use nix::unistd::close;
use tracing::{info, warn};  // Remove unused error import

use crate::config::NetConf;
use crate::types::{CmdArgs, Result as CniResult, Interface, IPConfig, Route as CniRoute}; 