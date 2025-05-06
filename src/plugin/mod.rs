use std::path::PathBuf;
use std::env;
use std::process::Command;
use libc::{self, c_int};
use anyhow::{Result, Context};
use tracing::{info, warn};

use crate::config::NetConf;
use crate::types::{CmdArgs, Result as CniResult, Interface};
use crate::integrations::aranya::AranyaClient;
use nix::sys::stat::Mode;
use nix::fcntl::{open, OFlag};
use nix::unistd::close;

use crate::types::{IPConfig, Route as CniRoute};

let fd = unsafe { libc::open(netns_path.as_ptr() as *const libc::c_char, libc::O_RDONLY) };

let cur_netns = unsafe { libc::open("/proc/self/ns/net".as_ptr() as *const libc::c_char, libc::O_RDONLY) }; 