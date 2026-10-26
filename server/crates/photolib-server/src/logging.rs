use std::{
    collections::VecDeque,
    sync::{Arc, Mutex},
    time::Duration,
};

use async_trait::async_trait;
use opentelemetry::trace::TracerProvider as _;
use opentelemetry_http::{Bytes, HttpClient, HttpError, Request, Response, hyper::HyperClient};
use opentelemetry_otlp::{SpanExporter, WithExportConfig, WithHttpConfig};
use opentelemetry_sdk::{Resource, trace::SdkTracerProvider};
use tracing::{Level, Subscriber};
use tracing_subscriber::{
    Layer,
    filter::Targets,
    fmt::{self, MakeWriter, writer::MakeWriterExt},
    layer::SubscriberExt,
    registry,
};

use crate::config::{Log, LogFormat, Traces};

/// The subscriber for `log`: JSON lines or text, cut by the configured filter, and the same spans to `traces` if
/// set. `Config::load` has already validated the filter, so the fallback only matters to callers that build a `Log`
/// by hand.
pub fn subscriber<W>(log: &Log, writer: W, traces: Option<&SdkTracerProvider>) -> Box<dyn Subscriber + Send + Sync>
where
    W: for<'a> MakeWriter<'a> + Send + Sync + 'static,
{
    let filter = log
        .filter
        .parse::<Targets>()
        .unwrap_or_else(|_| Targets::new().with_default(Level::INFO));
    let layer = match log.format {
        LogFormat::Json => fmt::layer().json().with_writer(writer).boxed(),
        LogFormat::Text => fmt::layer().with_writer(writer).boxed(),
    };
    let spans = traces.map(|provider| {
        tracing_opentelemetry::layer()
            .with_tracer(provider.tracer("photolibd"))
            .with_filter(filter.clone())
    });
    Box::new(registry().with(layer.with_filter(filter)).with(spans))
}

/// Sends hyper's requests from the exporter's own thread through the Tokio runtime that hyper needs.
#[derive(Debug)]
struct OnRuntime(HyperClient, tokio::runtime::Handle);

#[async_trait]
impl HttpClient for OnRuntime {
    async fn send_bytes(&self, request: Request<Bytes>) -> Result<Response<Bytes>, HttpError> {
        let client = self.0.clone();
        self.1.spawn(async move { client.send_bytes(request).await }).await?
    }
}

/// The OTLP/HTTP exporter of `traces`, if one is configured; call from the runtime that is to send the spans.
pub fn tracer_provider(traces: &Traces) -> Result<Option<SdkTracerProvider>, String> {
    let Some(endpoint) = &traces.otlp_endpoint else {
        return Ok(None);
    };
    let timeout = Duration::from_secs(10);
    let client = HyperClient::with_default_connector(timeout, None);
    let exporter = SpanExporter::builder()
        .with_http()
        .with_endpoint(endpoint)
        .with_timeout(timeout)
        .with_http_client(OnRuntime(client, tokio::runtime::Handle::current()))
        .build()
        .map_err(|error| format!("traces.otlp_endpoint: {error}"))?;
    let resource = Resource::builder().with_service_name("photolibd").build();
    Ok(Some(
        SdkTracerProvider::builder()
            .with_batch_exporter(exporter)
            .with_resource(resource)
            .build(),
    ))
}

/// The newest lines of the log, for the admin console and the diagnostics bundle.
#[derive(Clone, Default)]
pub struct Tail(Arc<Mutex<VecDeque<String>>>);

impl Tail {
    pub const LINES: usize = 1000;

    /// The newest `count` lines, oldest first.
    pub fn lines(&self, count: usize) -> Vec<String> {
        let lines = self.0.lock().unwrap();
        lines.iter().skip(lines.len().saturating_sub(count)).cloned().collect()
    }
}

impl std::io::Write for Tail {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        let mut lines = self.0.lock().unwrap();
        for line in String::from_utf8_lossy(bytes).lines().filter(|line| !line.is_empty()) {
            if lines.len() == Self::LINES {
                lines.pop_front();
            }
            lines.push_back(line.to_string());
        }
        Ok(bytes.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

impl<'a> MakeWriter<'a> for Tail {
    type Writer = Tail;

    fn make_writer(&'a self) -> Tail {
        self.clone()
    }
}

/// Installs the process-wide subscriber; logs go to stderr so stdout stays free for the process's own output, and to
/// `tail`. Shut the returned exporter down before exiting, or the last spans are lost.
pub fn init(log: &Log, traces: &Traces, tail: &Tail) -> Result<Option<SdkTracerProvider>, String> {
    let provider = tracer_provider(traces)?;
    let _ =
        tracing::subscriber::set_global_default(subscriber(log, std::io::stderr.and(tail.clone()), provider.as_ref()));
    Ok(provider)
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use axum::{body::Body, http::Request};
    use tokio_util::sync::CancellationToken;
    use tower::ServiceExt;

    use super::*;
    use crate::{
        config::{Database, LogFormat, Traces},
        http::{Health, REQUEST_ID_HEADER, router},
        role::Role,
        secret::Secret,
        testing::Capture,
    };

    fn log(format: LogFormat, filter: &str) -> Log {
        Log {
            format,
            filter: filter.into(),
        }
    }

    #[test]
    fn the_tail_keeps_the_newest_thousand_lines() {
        let tail = Tail::default();
        tracing::subscriber::with_default(subscriber(&log(LogFormat::Text, "info"), tail.clone(), None), || {
            for n in 0..1005 {
                tracing::info!("line {n}");
            }
        });
        let lines = tail.lines(5000);
        assert_eq!(lines.len(), 1000);
        assert!(lines[0].ends_with("line 5") && lines[999].ends_with("line 1004"));
        assert_eq!(tail.lines(2), lines[998..]);
    }

    #[test]
    fn json_lines_carry_level_target_message_and_fields() {
        let capture = Capture::default();
        tracing::subscriber::with_default(subscriber(&log(LogFormat::Json, "info"), capture.clone(), None), || {
            tracing::info!(role = "api", "started");
        });
        let line: serde_json::Value = serde_json::from_str(capture.text().trim()).unwrap();
        assert_eq!(line["level"], "INFO");
        assert_eq!(line["fields"]["message"], "started");
        assert_eq!(line["fields"]["role"], "api");
        assert!(line["timestamp"].is_string() && line["target"].is_string());
    }

    #[test]
    fn the_filter_decides_what_is_logged() {
        let capture = Capture::default();
        tracing::subscriber::with_default(
            subscriber(&log(LogFormat::Json, "warn,noisy=debug"), capture.clone(), None),
            || {
                tracing::info!("dropped");
                tracing::warn!("kept");
                tracing::debug!(target: "noisy", "kept by module");
            },
        );
        let text = capture.text();
        assert!(
            !text.contains("dropped") && text.contains("kept\"") && text.contains("kept by module"),
            "{text}"
        );
    }

    #[test]
    fn the_text_format_is_human_readable() {
        let capture = Capture::default();
        tracing::subscriber::with_default(subscriber(&log(LogFormat::Text, "info"), capture.clone(), None), || {
            tracing::info!("hello");
        });
        let text = capture.text();
        assert!(
            text.contains("INFO")
                && text.contains("hello")
                && serde_json::from_str::<serde_json::Value>(text.trim()).is_err(),
            "{text}"
        );
    }

    #[test]
    fn a_logged_configuration_never_contains_the_database_password() {
        let capture = Capture::default();
        let database = Database {
            url: Some(Secret::new("postgres://photolib:hunter2@db/photolib".to_string())),
            ..Database::default()
        };
        tracing::subscriber::with_default(subscriber(&log(LogFormat::Json, "info"), capture.clone(), None), || {
            tracing::info!(?database, "configuration");
            tracing::info!(url = %database.url.as_ref().unwrap(), "database");
        });
        let text = capture.text();
        assert!(text.contains("[redacted]") && !text.contains("hunter2"), "{text}");
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn spans_go_to_the_configured_otlp_collector_and_nowhere_without_one() {
        let bodies = Arc::new(std::sync::Mutex::new(Vec::<u8>::new()));
        let received = bodies.clone();
        let collector = axum::Router::new().route(
            "/v1/traces",
            axum::routing::post(move |body: axum::body::Bytes| async move {
                received.lock().unwrap().extend_from_slice(&body);
            }),
        );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let endpoint = format!("http://{}/v1/traces", listener.local_addr().unwrap());
        tokio::spawn(async move { axum::serve(listener, collector).await });
        assert!(tracer_provider(&Traces::default()).unwrap().is_none());

        let provider = tracer_provider(&Traces {
            otlp_endpoint: Some(endpoint),
        })
        .unwrap()
        .unwrap();
        tracing::subscriber::with_default(
            subscriber(&log(LogFormat::Json, "info"), Capture::default(), Some(&provider)),
            || tracing::info_span!("request", path = "/readyz").in_scope(|| tracing::info!("done")),
        );
        tokio::task::spawn_blocking(move || provider.shutdown())
            .await
            .unwrap()
            .unwrap();
        let body = bodies.lock().unwrap().clone();
        for text in ["photolibd", "request", "/readyz"] {
            assert!(
                body.windows(text.len()).any(|window| window == text.as_bytes()),
                "{text} missing from the exported spans"
            );
        }
    }

    #[tokio::test]
    async fn request_logs_carry_the_request_id_that_is_returned_to_the_client() {
        let capture = Capture::default();
        let _guards = capture.set_default(&log(LogFormat::Json, "info"));
        let health = Arc::new(Health {
            roles: vec![Role::Ml],
            db: None,
            shutdown: CancellationToken::new(),
            maintenance: None,
        });
        let app = router(health, axum::Router::new(), Default::default());
        let request = || Request::get("/unknown").body(Body::empty()).unwrap();
        // Another test's thread, without this subscriber, may reach the request span first.
        let other = app.clone();
        std::thread::spawn(move || {
            let runtime = tokio::runtime::Builder::new_current_thread().build();
            runtime.unwrap().block_on(other.oneshot(request())).unwrap()
        })
        .join()
        .unwrap();
        let response = app.oneshot(request()).await.unwrap();
        let id = response.headers()[REQUEST_ID_HEADER].to_str().unwrap().to_string();
        let line: serde_json::Value = serde_json::from_str(capture.text().lines().next().unwrap()).unwrap();
        assert_eq!(line["span"]["request_id"], id, "{line}");
        assert_eq!(
            (line["fields"]["status"].as_u64(), line["span"]["path"].as_str()),
            (Some(404), Some("/unknown"))
        );
    }
}
