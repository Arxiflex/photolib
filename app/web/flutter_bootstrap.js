{{flutter_js}}
{{flutter_build_config}}
// CanvasKit and fallback fonts come from the app's own origin, never from a
// third-party CDN (docs/dev/flutter.md, "Web fonts"). The engine's inline
// styles carry the nonce that index.html gives this script.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
    fontFallbackBaseUrl: "fonts/",
    nonce: document.currentScript.nonce,
  },
});
