// photolibd's Content-Security-Policy enforces Trusted Types. Flutter's loader brings its own policy; this default one
// lets other code start workers (drift's, the worker pool's) from script URLs on this origin, and nothing else.
if (window.trustedTypes) {
  trustedTypes.createPolicy("default", {
    createScriptURL(url) {
      const resolved = new URL(url, document.baseURI);
      if (resolved.origin !== location.origin) throw new TypeError(`script from another origin: ${url}`);
      return resolved.href;
    },
  });
}
