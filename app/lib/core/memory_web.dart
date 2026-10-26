import 'dart:js_interop';

@JS('navigator.deviceMemory')
external JSNumber? get _gib;

/// The device's RAM as Chromium rounds it (at most 8 GiB), or null elsewhere.
int? physicalMemory() =>
    _gib == null ? null : (_gib!.toDartDouble * (1 << 30)).round();
