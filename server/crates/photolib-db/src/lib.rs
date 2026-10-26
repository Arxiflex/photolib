//! PostgreSQL schema and data migrations for photolibd.

pub mod cluster;
pub mod data;
pub mod doctor;
#[cfg(test)]
mod domain_model;
pub mod dump;
pub mod lint;
pub mod migrate;
pub mod ocr;
pub mod sync;
#[cfg(any(test, feature = "testing"))]
pub mod testpg;
#[cfg(test)]
mod versions;
