//! `photolib`, the command-line client of photolibd.

mod client;
mod files;
mod journal;
mod upload;

use std::{path::PathBuf, process::ExitCode};

use clap::Parser;
use futures::StreamExt;
use serde_json::json;

use crate::upload::Outcome;

#[derive(Parser)]
#[command(version, about)]
enum Cli {
    /// Uploads photos and videos: the files given, and those in the folders given that the apps' folder sources
    /// would show. Signs in with the API key in PHOTOLIB_TOKEN. Interrupted runs resume, and files uploaded before
    /// are skipped, as the journal in the state directory records them.
    Upload(Upload),
}

#[derive(clap::Args)]
struct Upload {
    /// photolibd's URL
    #[arg(long, env = "PHOTOLIB_SERVER")]
    server: String,
    /// The library to upload into
    #[arg(long, env = "PHOTOLIB_LIBRARY")]
    library: uuid::Uuid,
    /// Where the journal lives [default: $XDG_STATE_HOME/photolib]
    #[arg(long, env = "PHOTOLIB_STATE")]
    state: Option<PathBuf>,
    /// How many files to upload at once
    #[arg(long, default_value_t = 8)]
    jobs: usize,
    /// List what a run would upload, reading and sending nothing
    #[arg(long)]
    dry_run: bool,
    /// Print JSON lines: a plan, each file, the progress of large ones and a summary
    #[arg(long)]
    json: bool,
    #[arg(required = true)]
    paths: Vec<PathBuf>,
}

#[tokio::main]
async fn main() -> ExitCode {
    let Cli::Upload(upload) = Cli::parse();
    match run(upload).await {
        Ok(0) => ExitCode::SUCCESS,
        Ok(_) => ExitCode::FAILURE,
        Err(error) => {
            eprintln!("photolib: {error}");
            ExitCode::FAILURE
        }
    }
}

/// Runs an upload; returns how many files failed.
async fn run(args: Upload) -> Result<u64, String> {
    let state = args
        .state
        .or_else(default_state)
        .ok_or("no --state, and no home directory to keep it in")?;
    let journal = journal::Journal::open(&state.join(format!("{}.jsonl", args.library)))
        .map_err(|e| format!("{}: {e}", state.display()))?;
    let mut files = Vec::new();
    for root in &args.paths {
        let found = std::fs::canonicalize(root).and_then(|root| files::walk(&root));
        files.extend(found.map_err(|e| format!("{}: {e}", root.display()))?);
    }
    let (skipped, files): (Vec<_>, Vec<_>) = files.into_iter().partition(|f| journal.done(f));
    let out = Output(args.json);
    let bytes = files.iter().map(|f| f.size).sum::<u64>();
    out.print(json!({"event": "plan", "files": files.len(), "bytes": bytes}));
    let summary = |uploaded, duplicates, failed| {
        json!({"event": "summary", "uploaded": uploaded, "duplicates": duplicates, "skipped": skipped.len(),
            "failed": failed})
    };
    if args.dry_run {
        for file in &files {
            out.print(json!({"event": "file", "path": file.path, "size": file.size, "status": "new"}));
        }
        let mut summary = summary(0, 0, 0);
        summary["new"] = files.len().into();
        out.print(summary);
        return Ok(0);
    }
    let token = std::env::var("PHOTOLIB_TOKEN").unwrap_or_default();
    if token.is_empty() {
        return Err("set PHOTOLIB_TOKEN to an API key of the library".into());
    }
    let client = client::Client::new(&args.server, args.library, token)?;
    let uploader = upload::Uploader::new(client, journal);
    let mut outcomes = futures::stream::iter(&files)
        .map(|file| {
            let (uploader, out) = (&uploader, &out);
            let progress = move |sent| {
                let event = json!({"event": "progress", "path": file.path, "sent": sent, "size": file.size});
                out.print(event);
            };
            async move { (file, uploader.upload(file, progress).await) }
        })
        .buffer_unordered(args.jobs.max(1));
    // Uploaded, duplicates, failed.
    let mut counts = [0; 3];
    let mut stop = None;
    while let Some((file, outcome)) = outcomes.next().await {
        let (index, status, key, value) = match outcome {
            Outcome::Uploaded(hash) => (0, "uploaded", "blake3", hash),
            Outcome::Duplicate(hash) => (1, "duplicate", "blake3", hash),
            Outcome::Failed(error) => {
                stop = stop.or(error.stops_run().then(|| error.to_string()));
                (2, "failed", "error", error.to_string())
            }
        };
        counts[index] += 1;
        out.print(json!({"event": "file", "path": file.path, "size": file.size, "status": status, key: value}));
        if stop.is_some() {
            break;
        }
    }
    drop(outcomes);
    uploader
        .journal
        .sync()
        .map_err(|e| format!("{}: {e}", state.display()))?;
    out.print(summary(counts[0], counts[1], counts[2]));
    match stop {
        Some(error) => Err(format!("{error}; stopped, the next run goes on from here")),
        None => Ok(counts[2]),
    }
}

/// Prints events as JSON lines, or as text for people: files that need attention, progress never.
struct Output(bool);

impl Output {
    fn print(&self, event: serde_json::Value) {
        if self.0 {
            println!("{event}");
            return;
        }
        let text = |key: &str| event[key].as_str().unwrap_or_default().to_owned();
        match text("event").as_str() {
            "file" => match text("error").as_str() {
                "" => println!("{} {}", text("status"), text("path")),
                error => println!("failed {}: {error}", text("path")),
            },
            "summary" => {
                let parts = ["new", "uploaded", "duplicates", "skipped", "failed"];
                let parts = parts.iter().filter_map(|p| Some(format!("{} {p}", event.get(p)?)));
                println!("{}", parts.collect::<Vec<_>>().join(", "));
            }
            _ => {}
        }
    }
}

/// `$XDG_STATE_HOME/photolib`, else `~/.local/state/photolib`; `%LOCALAPPDATA%\photolib` on Windows.
fn default_state() -> Option<PathBuf> {
    let var = |name| std::env::var_os(name).filter(|v| !v.is_empty()).map(PathBuf::from);
    let base = var("XDG_STATE_HOME")
        .or_else(|| var("LOCALAPPDATA"))
        .or_else(|| Some(var("HOME")?.join(".local/state")))?;
    Some(base.join("photolib"))
}
