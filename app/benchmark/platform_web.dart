import 'dart:js_interop';

@JS()
external JSPromise<JSAny?> fetch(JSString url, JSAny init);

/// Posts the results to the page's own origin, where the runner listens.
Future<void> report(String json) async {
  await fetch('/result'.toJS, {'method': 'POST', 'body': json}.jsify()!).toDart;
}
