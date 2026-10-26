//! Installed models: `<root>/<id>@<revision>/` holds a model's files and its `manifest.json`. A file gets there only
//! by a rename after its SHA-256 and size matched, so a model directory never holds a partial or unverified file.

use std::{
    collections::BTreeMap,
    fmt::Display,
    fs,
    io::{self, Write},
    path::{Component, Path, PathBuf},
    time::Duration,
};

use bytes::Bytes;
use http::{Uri, header::LOCATION};
use http_body_util::{BodyExt, Empty};
use hyper_util::{
    client::legacy::{Client, connect::HttpConnector},
    rt::TokioExecutor,
};
use sha2::{Digest, Sha256};
use tar::EntryType;

use crate::{Model, Target};

type Result<T> = std::result::Result<T, String>;

/// The SHA-256 and size of each file of each `<id>@<revision>` directory.
type Found = BTreeMap<String, BTreeMap<String, (String, u64)>>;

pub struct Store<'r> {
    root: PathBuf,
    registry: &'r [Model],
    /// How long a download may send nothing before the next URL is tried
    idle: Duration,
}

/// A model a bundle installed; bring-your-own models come with the warning to show.
#[derive(Debug, PartialEq, Eq)]
pub struct Imported {
    pub name: String,
    pub warning: Option<String>,
}

/// Writes to a file, hashing and counting what it writes.
struct Hashing<'f> {
    file: &'f fs::File,
    sha256: Sha256,
    size: u64,
}

impl Write for Hashing<'_> {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        let n = self.file.write(buf)?;
        self.sha256.update(&buf[..n]);
        self.size += n as u64;
        Ok(n)
    }

    fn flush(&mut self) -> io::Result<()> {
        self.file.flush()
    }
}

impl<'f> Hashing<'f> {
    fn new(file: &'f fs::File) -> Self {
        Hashing {
            file,
            sha256: Sha256::new(),
            size: 0,
        }
    }

    /// Syncs the file and returns its SHA-256 and size.
    fn finish(self) -> Result<(String, u64)> {
        self.file.sync_all().map_err(|e| e.to_string())?;
        Ok((format!("{:x}", self.sha256.finalize()), self.size))
    }
}

fn failed(what: impl Display) -> impl FnOnce(io::Error) -> String {
    move |e| format!("{what}: {e}")
}

type Http = Client<hyper_rustls::HttpsConnector<HttpConnector>, Empty<Bytes>>;

/// HTTPS on rustls with the system's roots, as the S3 driver; plain HTTP only reaches the tests' mirror, and the pin
/// is what makes a download trusted either way.
fn http() -> Result<Http> {
    let connector = hyper_rustls::HttpsConnectorBuilder::new()
        .with_provider_and_native_roots(std::sync::Arc::new(rustls::crypto::ring::default_provider()))
        .map_err(|e| format!("cannot load the system's TLS roots: {e}"))?
        .https_or_http()
        .enable_http1()
        .build();
    Ok(Client::builder(TokioExecutor::new()).build(connector))
}

/// Downloads `url` into `out`, following redirects, and stops once it is larger than `limit` or sent nothing for
/// `idle`.
async fn download(http: &Http, url: &str, out: &mut Hashing<'_>, limit: u64, idle: Duration) -> Result<()> {
    let stalled = |_| format!("no data for {idle:?}");
    let mut uri = url.parse::<Uri>().map_err(|e| e.to_string())?;
    for _ in 0..10 {
        let response = tokio::time::timeout(idle, http.get(uri.clone()))
            .await
            .map_err(stalled)?
            .map_err(|e| e.to_string())?;
        let status = response.status();
        if status.is_redirection() {
            let location = response.headers().get(LOCATION).and_then(|l| l.to_str().ok());
            let location = location.ok_or(format!("HTTP {status} without a location"))?;
            let mut parts = location.parse::<Uri>().map_err(|e| e.to_string())?.into_parts();
            if parts.scheme.is_none() {
                (parts.scheme, parts.authority) = (uri.scheme().cloned(), uri.authority().cloned());
            }
            uri = Uri::from_parts(parts).map_err(|e| e.to_string())?;
            continue;
        }
        if !status.is_success() {
            return Err(format!("HTTP {}", status.as_u16()));
        }
        let mut body = response.into_body();
        while let Some(frame) = tokio::time::timeout(idle, body.frame()).await.map_err(stalled)?
            && out.size <= limit
        {
            if let Ok(data) = frame.map_err(|e| e.to_string())?.into_data() {
                out.write_all(&data).map_err(|e| e.to_string())?;
            }
        }
        return Ok(());
    }
    Err("more than 10 redirects".into())
}

fn warning(model: &Model) -> String {
    let licence = &model.licence;
    format!(
        "WARNING: {} is bring-your-own, not in Photolib's registry, under {} ({:?}). Photolib has not reviewed that \
         licence, never downloads it or sends it to devices; using it within its terms is up to you.",
        model.name(),
        licence.spdx,
        licence.class()
    )
}

/// Writes `<dir>/manifest.json` by a rename, once the files are in place.
fn write_manifest(dir: &Path, model: &Model) -> Result<()> {
    let mut part = tempfile::NamedTempFile::new_in(dir).map_err(failed(dir.display()))?;
    serde_json::to_writer_pretty(&mut part, model).map_err(|e| e.to_string())?;
    part.persist(dir.join("manifest.json")).map_err(|e| e.to_string())?;
    Ok(())
}

/// `<id>@<revision>/<file>` of a tar entry, or `None` for what a bundle may hold besides: directories and the
/// dot-files of a store, such as an import in progress.
fn entry_path(path: &Path, kind: EntryType) -> Result<Option<(String, String)>> {
    let parts: Vec<_> = path.components().filter(|c| *c != Component::CurDir).collect();
    let dotted = parts.iter().any(|c| c.as_os_str().as_encoded_bytes().starts_with(b"."));
    if parts.iter().all(|c| matches!(c, Component::Normal(_))) && (dotted || kind.is_dir() && parts.len() <= 1) {
        return Ok(None);
    }
    let shown = path.display();
    let [Component::Normal(dir), Component::Normal(file)] = parts[..] else {
        return Err(format!("{shown} is not <id>@<revision>/<file>"));
    };
    if !kind.is_file() {
        return Err(format!("{shown} is not a regular file"));
    }
    let utf8 = |s: &std::ffi::OsStr| s.to_str().map(str::to_owned).ok_or(format!("{shown} is not UTF-8"));
    Ok(Some((utf8(dir)?, utf8(file)?)))
}

/// Extracts the files of a bundle into `staging`.
fn unpack(bundle: &Path, staging: &Path) -> Result<Found> {
    let at = || failed(bundle.display());
    let mut found = Found::new();
    let mut archive = tar::Archive::new(fs::File::open(bundle).map_err(at())?);
    for entry in archive.entries().map_err(at())? {
        let mut entry = entry.map_err(at())?;
        let path = entry.path().map_err(at())?.into_owned();
        let Some((dir, file)) = entry_path(&path, entry.header().entry_type())? else {
            continue;
        };
        fs::create_dir_all(staging.join(&dir)).map_err(at())?;
        let out = fs::File::create_new(staging.join(&dir).join(&file)).map_err(failed(path.display()))?;
        let mut hashing = Hashing::new(&out);
        io::copy(&mut entry, &mut hashing).map_err(failed(path.display()))?;
        found.entry(dir).or_default().insert(file, hashing.finish()?);
    }
    Ok(found)
}

impl<'r> Store<'r> {
    pub fn new(root: impl Into<PathBuf>, registry: &'r [Model]) -> Self {
        Store {
            root: root.into(),
            registry,
            idle: Duration::from_secs(30),
        }
    }

    /// Installs the models of a bundle, a tar of `<id>@<revision>/` directories, each with its `manifest.json`.
    /// Models of the registry must match it, whatever their manifest says; any other model is bring-your-own and
    /// needs its SPDX id in `accepted`. Nothing is installed unless every file of the bundle checks out.
    pub fn import(&self, bundle: &Path, accepted: &[String]) -> Result<Vec<Imported>> {
        fs::create_dir_all(&self.root).map_err(failed(self.root.display()))?;
        let staging = tempfile::TempDir::new_in(&self.root).map_err(failed(self.root.display()))?;
        let verified = unpack(bundle, staging.path())?
            .into_iter()
            .map(|(dir, mut files)| {
                files
                    .remove("manifest.json")
                    .ok_or(format!("{dir}: no manifest.json"))?;
                let (model, warning) = self.check(&staging.path().join(&dir), &files, accepted)?;
                Ok((dir, files, model, warning))
            })
            .collect::<Result<Vec<_>>>()?;
        let mut imported = Vec::new();
        for (dir, files, model, warning) in verified {
            let name = model.name();
            let to = self.root.join(&name);
            fs::create_dir_all(&to).map_err(failed(to.display()))?;
            for file in files.keys() {
                let from = staging.path().join(&dir).join(file);
                fs::rename(from, to.join(file)).map_err(failed(to.join(file).display()))?;
            }
            write_manifest(&to, &model)?;
            imported.push(Imported { name, warning });
        }
        Ok(imported)
    }

    /// The model an unpacked directory installs, once its manifest and files check out, with the warning of a
    /// bring-your-own model.
    fn check(
        &self,
        dir: &Path,
        files: &BTreeMap<String, (String, u64)>,
        accepted: &[String],
    ) -> Result<(Model, Option<String>)> {
        let shown = dir.file_name().unwrap_or_default().display();
        let text = fs::read(dir.join("manifest.json")).map_err(failed(&shown))?;
        let manifest: Model = serde_json::from_slice(&text).map_err(|e| format!("{shown}/manifest.json: {e}"))?;
        let name = manifest.name();
        if shown.to_string() != name {
            return Err(format!("{shown} holds the manifest of {name}"));
        }
        if let Some(problem) = manifest.problems().into_iter().next() {
            return Err(problem);
        }
        let known = self.registry.iter().find(|m| m.name() == name);
        let model = known.unwrap_or(&manifest).clone();
        let warning = known.is_none().then(|| warning(&model));
        if let Some(warning) = &warning
            && !accepted.contains(&model.licence.spdx)
        {
            return Err(format!(
                "{warning}\nTo import it anyway, pass --accept-licence {}",
                model.licence.spdx
            ));
        }
        for (file, (sha256, size)) in files {
            match model.files.iter().find(|f| &f.name == file) {
                Some(f) if &f.sha256 == sha256 && f.size == *size => {}
                Some(_) => {
                    return Err(format!("{name}: {file} does not match its SHA-256 and size"));
                }
                None => return Err(format!("{name}: {file} is not one of its files")),
            }
        }
        if let Ok(text) = fs::read(self.root.join(&name).join("manifest.json"))
            && serde_json::from_slice::<Model>(&text).ok().as_ref() != Some(&model)
        {
            return Err(format!("{name} is installed with another manifest"));
        }
        Ok((model, warning))
    }

    /// The installed models, by their manifests, in name order.
    pub fn installed(&self) -> Vec<Model> {
        let dirs = fs::read_dir(&self.root).into_iter().flatten().flatten();
        let manifests = dirs.filter_map(|dir| fs::read(dir.path().join("manifest.json")).ok());
        let mut models: Vec<Model> = manifests
            .filter_map(|text| serde_json::from_slice(&text).ok())
            .collect();
        models.sort_by_key(Model::name);
        models
    }

    /// Downloads the files of `model` that one of `targets` runs and that are not installed yet, keeping from each
    /// file's URLs the first download that matches its SHA-256 and size; then writes the manifest.
    pub async fn fetch(&self, model: &Model, targets: &[Target]) -> Result<()> {
        let to = self.root.join(model.name());
        fs::create_dir_all(&to).map_err(failed(to.display()))?;
        let http = http()?;
        for file in (model.files.iter()).filter(|f| f.targets.iter().any(|t| targets.contains(t))) {
            let path = to.join(&file.name);
            let mut errors = Vec::new();
            for url in &file.urls {
                if path.is_file() {
                    break;
                }
                let part = tempfile::NamedTempFile::new_in(&self.root).map_err(failed(self.root.display()))?;
                let mut out = Hashing::new(part.as_file());
                match download(&http, url, &mut out, file.size, self.idle)
                    .await
                    .and_then(|()| out.finish())
                {
                    Ok(got) if got == (file.sha256.clone(), file.size) => {
                        part.persist(&path).map_err(|e| e.to_string())?;
                    }
                    Ok(_) => errors.push(format!("{url}: does not match the SHA-256 and size of {}", file.name)),
                    Err(e) => errors.push(format!("{url}: {e}")),
                }
            }
            if !path.is_file() {
                fs::remove_dir(&to).ok();
                let errors = errors.join("\n  ");
                return Err(format!(
                    "{}: no download of {} succeeded:\n  {errors}",
                    model.name(),
                    file.name
                ));
            }
        }
        write_manifest(&to, model)
    }
}

#[cfg(test)]
mod tests {
    use tokio::{io::AsyncWriteExt, net::TcpListener};

    use super::*;

    #[tokio::test]
    async fn a_download_that_stops_sending_falls_back_then_gives_up() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        tokio::spawn(async move {
            let mut held = Vec::new();
            while let Ok((mut socket, _)) = listener.accept().await {
                if held.len() == 1 {
                    let head = "HTTP/1.1 200 OK\r\nContent-Length: 9\r\n\r\nweig";
                    socket.write_all(head.as_bytes()).await.unwrap();
                }
                held.push(socket);
            }
        });
        let urls = ["silent", "stalled"].map(|path| format!("{base}/{path}"));
        let model: Model = serde_json::from_value(serde_json::json!({
            "id": "m", "revision": "1", "task": "face_detection",
            "licence": {"spdx": "MIT", "source": "https://example.org/LICENSE"},
            "files": [{"name": "a.onnx", "sha256": format!("{:x}", Sha256::digest(b"weights a")), "size": 9,
                       "targets": ["server"], "urls": urls}]
        }))
        .unwrap();
        let dir = tempfile::tempdir().unwrap();
        let registry = [model.clone()];
        let store = Store {
            idle: Duration::from_millis(200),
            ..Store::new(dir.path(), &registry)
        };
        let error = photolib_spawn::within(Duration::from_secs(10), store.fetch(&model, &[Target::Server]))
            .await
            .expect("a download that stops sending gives up")
            .unwrap_err();
        for url in urls {
            let expected = format!("{url}: no data for 200ms");
            assert!(error.contains(&expected), "expected '{expected}' in '{error}'");
        }
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 0);
    }
}
