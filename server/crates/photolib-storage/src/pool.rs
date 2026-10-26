//! Each store has its own threads, and every call there has a timeout: a hung NFS/SMB mount or S3 endpoint ties up
//! that store's threads and fails its calls, while the server and the other stores carry on.

use std::{future::Future, time::Duration};

use tokio::{
    runtime::{Builder, Runtime},
    task::JoinHandle,
};

use crate::{Error, Result};

pub(crate) struct Pool {
    runtime: Option<Runtime>,
    timeout: Duration,
}

impl Pool {
    pub fn new(name: &str, timeout: Duration) -> Result<Pool> {
        let runtime = Builder::new_multi_thread()
            .worker_threads(2)
            .max_blocking_threads(16)
            .thread_name(format!("store-{name}"))
            .enable_all()
            .build()
            .map_err(|error| Error::Other(format!("cannot start the threads of store {name}: {error}")))?;
        Ok(Pool {
            runtime: Some(runtime),
            timeout,
        })
    }

    fn runtime(&self) -> &Runtime {
        self.runtime.as_ref().expect("the runtime lives until drop")
    }

    pub async fn run<T: Send + 'static>(
        &self,
        what: &str,
        call: impl Future<Output = Result<T>> + Send + 'static,
    ) -> Result<T> {
        self.wait(what, self.runtime().spawn(call)).await
    }

    pub async fn blocking<T: Send + 'static>(
        &self,
        what: &str,
        call: impl FnOnce() -> Result<T> + Send + 'static,
    ) -> Result<T> {
        self.wait(what, self.runtime().spawn_blocking(call)).await
    }

    async fn wait<T>(&self, what: &str, task: JoinHandle<Result<T>>) -> Result<T> {
        let abort = task.abort_handle();
        match tokio::time::timeout(self.timeout, task).await {
            Ok(Ok(result)) => result,
            Ok(Err(error)) => Err(Error::Other(format!("{what} failed: {error}"))),
            Err(_) => {
                abort.abort();
                Err(Error::Timeout(format!("{what} took longer than {:?}", self.timeout)))
            }
        }
    }
}

impl Drop for Pool {
    fn drop(&mut self) {
        // Threads stuck in a hung call are abandoned, not joined.
        if let Some(runtime) = self.runtime.take() {
            runtime.shutdown_background();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hang() -> Result<()> {
        std::thread::sleep(Duration::from_secs(3600));
        Ok(())
    }

    #[tokio::test(flavor = "current_thread")]
    async fn hung_calls_time_out_without_stalling_the_caller_or_another_store() {
        let hung = Pool::new("hung", Duration::from_millis(300)).unwrap();
        let healthy = Pool::new("healthy", Duration::from_secs(5)).unwrap();
        let started = photolib_spawn::Running::start();
        let ticks = tokio::spawn(async {
            let mut ticks = 0;
            for _ in 0..5 {
                tokio::time::sleep(Duration::from_millis(50)).await;
                ticks += 1;
            }
            ticks
        });
        // More hung calls than the pool has threads: queued ones time out too.
        let calls = (0..20).map(|_| hung.blocking("stat", hang));
        let results = futures::future::join_all(calls).await;
        assert!(
            results.iter().all(|r| matches!(r, Err(Error::Timeout(_)))),
            "{results:?}"
        );
        assert!(started.elapsed() < Duration::from_secs(2), "{:?}", started.elapsed());
        assert_eq!(ticks.await.unwrap(), 5, "the caller's runtime kept running");
        assert_eq!(healthy.blocking("stat", || Ok(7)).await.unwrap(), 7);
        assert_eq!(healthy.run("head", async { Ok(8) }).await.unwrap(), 8);
        let message = hung
            .run("head", std::future::pending::<Result<()>>())
            .await
            .unwrap_err();
        assert_eq!(message.to_string(), "timed out: head took longer than 300ms");
        drop(hung);
    }
}
