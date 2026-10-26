// Starts offline_sw.js (WEB-07) once the app has loaded, and tells it what that took, so that the next visit works
// without a network. A browser without Service Workers, or a page that is not a secure context, runs as before.
if ('serviceWorker' in navigator) {
  addEventListener('load', async () => {
    try {
      const registration = await navigator.serviceWorker.register(new URL('offline_sw.js', document.baseURI), {
        scope: new URL('./', document.baseURI).pathname,
      });
      const worker = registration.installing ?? registration.waiting ?? registration.active;
      while (worker.state !== 'activated') await new Promise((done) => worker.addEventListener('statechange', done, { once: true }));
      // The app loads its engine and fonts after this event: send what there is once it has settled.
      setTimeout(() => {
        const shell = [document.baseURI, ...performance.getEntriesByType('resource').map((entry) => entry.name)];
        worker.postMessage({ shell });
      }, 5000);
    } catch (error) {
      console.warn('offline shell unavailable', error);
    }
  });
}
