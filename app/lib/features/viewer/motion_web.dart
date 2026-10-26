import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Whether the page may read the motion sensors: Safari on iOS asks the user
/// through `DeviceMotionEvent.requestPermission`, which only a tap may call,
/// before sensors_plus' streams hear anything; other browsers do not ask.
Future<bool> motionPermission() async {
  final event = globalContext['DeviceMotionEvent'];
  if (event == null || !event.isA<JSObject>()) return true;
  final motion = event as JSObject;
  if (!motion.has('requestPermission')) return true;
  final asked = motion.callMethod<JSPromise<JSString>>(
    'requestPermission'.toJS,
  );
  return (await asked.toDart).toDart == 'granted';
}
