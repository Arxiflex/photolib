import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Reports the page's uncaught errors, unhandled rejections and
/// `console.error` calls until the returned function undoes it.
void Function() installBrowser(void Function(String problem) report) {
  final page = globalContext as web.EventTarget;
  final JSObject console = web.console;
  final original = console['error'] as JSObject?;
  void uncaught(web.Event event) {
    final error = event as web.ErrorEvent;
    report(
      'Uncaught error in the page: ${_text(error.error ?? error.message.toJS)} '
      '(${error.filename.split('#').first}:${error.lineno}:${error.colno})',
    );
  }

  void rejected(web.Event event) => report(
    'Unhandled rejection in the page: '
    '${_text((event as web.PromiseRejectionEvent).reason)}',
  );

  // A Proxy hears every argument; a Dart function only as many as it declares.
  JSAny? consoleError(
    JSFunction error,
    JSAny? self,
    JSArray<JSAny?> arguments,
  ) {
    report('console.error: ${arguments.toDart.map(_text).join(' ')}');
    return _reflect.callMethod('apply'.toJS, error, self, arguments);
  }

  final onUncaught = uncaught.toJS;
  final onRejected = rejected.toJS;
  page
    ..addEventListener('error', onUncaught)
    ..addEventListener('unhandledrejection', onRejected);
  if (original != null) {
    console['error'] = globalContext
        .getProperty<JSFunction>('Proxy'.toJS)
        .callAsConstructor(original, JSObject()..['apply'] = consoleError.toJS);
  }
  return () {
    console['error'] = original;
    page
      ..removeEventListener('error', onUncaught)
      ..removeEventListener('unhandledrejection', onRejected);
  };
}

final JSObject _reflect = globalContext.getProperty<JSObject>('Reflect'.toJS);

String _text(JSAny? value) =>
    globalContext.callMethod<JSString>('String'.toJS, value).toDart;
