import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib_video/photolib_video.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Media3 and AVFoundation share one channel: probe returns a source, execute takes a plan',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('org.photolib.video'), (
            call,
          ) async {
            calls.add(call);
            if (call.method != 'probe') return null;
            return {
              'width': 1920,
              'height': 1080,
              'rotation': 90,
              'fps': '30000/1001',
              'transfer': 'arib-std-b67',
              'hasAudio': true,
              'durationUs': 4000000,
              'keyframesUs': [0, 1000000],
              'tags': {'creation_time': '2021-12-24T17:30:00Z'},
            };
          });
      final executor = NativeExecutor();

      final source = await executor.probe('/clip.mov');
      expect(
        [
          source.displayWidth,
          source.displayHeight,
          '${source.fps}',
          source.hdr,
          source.keyframesUs,
          source.tags,
        ],
        [
          1080,
          1920,
          '30000/1001',
          true,
          [0, 1000000],
          {'creation_time': '2021-12-24T17:30:00Z'},
        ],
      );
      final plan = Plan.of(fixture('trim'), {'portrait': source});
      await executor.run(plan, {'portrait': '/clip.mov'}, '/out.mp4');
      expect(
        [
          for (final c in calls) [c.method, c.arguments],
        ],
        [
          ['probe', '/clip.mov'],
          [
            'execute',
            {
              'plan': plan.toJson(),
              'paths': {'portrait': '/clip.mov'},
              'out': '/out.mp4',
            },
          ],
        ],
      );
    },
  );
}
