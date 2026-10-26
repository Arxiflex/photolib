//! The messages (buffa) and Connect services (connect-rust) that `tools/codegen.sh` generates from `proto/`.

#[rustfmt::skip]
#[path = "gen/buffa/mod.rs"]
pub mod proto;
#[rustfmt::skip]
#[path = "gen/connect/mod.rs"]
pub mod connect;
