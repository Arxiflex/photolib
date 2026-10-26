# Release notes

Photolib has no release yet; each one adds its notes here, newest first.

## Known issues

### macOS

* Photolib can close unexpectedly when it comes back to the front: after it was hidden or minimised, or when it enters
  or leaves full screen. The cause is in Flutter, the toolkit Photolib is built with
  ([flutter/flutter#185394](https://github.com/flutter/flutter/issues/185394)), and goes away with the Flutter release
  that carries its fix. Until then, quit Photolib rather than hide it, and reopen it if it closed; nothing in your
  library is lost.
