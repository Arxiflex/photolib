import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:photolib_video/photolib_video.dart';

import 'fixtures.dart';

/// An edit decision list of [clips] (JSON), with more top-level fields in [extra].
String doc(List<String> clips, [String extra = '']) =>
    '{"tracks": [{"items": [${clips.join(',')}]}]$extra}';

String clip(String id, int startMs, int ms) =>
    '{"clip": {"assetId": "$id", "source": {"start": {"num": $startMs, "den": 1000}, '
    '"duration": {"num": $ms, "den": 1000}}}}';

Edl edl(List<String> clips, [String extra = '']) =>
    Edl.fromJson(jsonDecode(doc(clips, extra)));

SourceInfo source({
  int width = 1920,
  int height = 1080,
  int rotation = 0,
  String fps = '30/1',
  String? transfer,
  bool audio = true,
  Map<String, String> tags = const {},
}) => SourceInfo(
  width: width,
  height: height,
  rotation: rotation,
  fps: Rational.parse(fps),
  transfer: transfer,
  hasAudio: audio,
  durationUs: 4000000,
  keyframesUs: const [0, 1000000, 2000000, 3000000],
  tags: tags,
);

const keptTags = {
  'creation_time': '2021-12-24T17:30:00Z',
  'com.apple.quicktime.creationdate': '2021-12-24T18:30:00+0100',
  'location': '+48.8584+002.2945/',
};
const phoneTags = {
  ...keptTags,
  'com.apple.quicktime.content.identifier': 'ABC-123',
  'location-eng': '+48.8584+002.2945/',
  'encoder': 'Lavf62.12.103',
};

const h264 = Capability.h264, hevc10 = Capability.hevc10;
const x265 = Capability.x265,
    av1 = Capability.av1,
    playsAv1 = Capability.playAv1;

/// A device with an H.264 and a hardware 10-bit HEVC encoder.
const desktop = Devices({h264, hevc10});

Map<String, Object?> video(
  int width,
  int height,
  String fps,
  String transfer,
) => {
  'width': width,
  'height': height,
  'fps': fps,
  'transfer': transfer,
  'bitDepth': transfer == 'bt709' ? 8 : 10,
  'codec': transfer == 'bt709' ? 'h264' : 'hevc',
};

/// Each cut as (asset, start, duration, silence, tone map).
List<(String, int, int, bool, bool)> cuts(Plan plan) => [
  for (final c in plan.cuts)
    (c.assetId, c.startUs, c.durationUs, c.silence, c.toneMap),
];

void main() {
  group('the edit decision list', () {
    test(
      'reads the shared fixtures: one track of clips in rational source time, defaults for the rest',
      () {
        final trim = fixture('trim');
        expect(
          [for (final c in trim.clips) (c.assetId, c.startUs, c.durationUs)],
          [('portrait', 1500000, 2000000)],
        );
        expect(
          (
            trim.keepHdr,
            trim.maxShortSide,
            trim.preferLossless,
            trim.keepLocation,
          ),
          (true, null, true, true),
        );
        expect(fixture('merge').clips.map((c) => c.assetId), [
          'landscape',
          'portrait',
          'silent',
          'hlg',
        ]);
        expect(fixture('merge-hdr').clips.map((c) => c.durationUs), [
          1500000,
          1000000,
        ]);
      },
    );

    test('reads the output, planner and metadata policies', () {
      final e = edl(
        [clip('a', 0, 1000)],
        ', "output": {"maxShortSide": 720, "hdr": "TONE_MAP"}, "planner": {"preferLossless": false}, '
        '"metadata": {"stripGps": true}',
      );
      expect(
        (e.keepHdr, e.maxShortSide, e.preferLossless, e.keepLocation),
        (false, 720, false, false),
      );
    });

    for (final (why, json) in [
      ('no clips', '{"tracks": []}'),
      ('a gap', doc(['{"gap": {}}'])),
      ('an empty clip', doc([clip('a', 0, 0)])),
      ('a negative start', doc([clip('a', -1, 1000)])),
      (
        'a zero denominator',
        doc([clip('a', 0, 1000).replaceFirst('1000', '0')]),
      ),
      (
        'an unknown HDR policy',
        doc([clip('a', 0, 1000)], ', "output": {"hdr": "HLG_CONTAINER"}'),
      ),
    ]) {
      test(
        'rejects $why',
        () =>
            expect(() => Edl.fromJson(jsonDecode(json)), throwsFormatException),
      );
    }
  });

  group('a single clip that may stay lossless', () {
    test(
      'is remuxed from the keyframe at or before its start to its requested end, with metadata but no pairing id',
      () {
        final plan = Plan.of(fixture('trim'), {
          'portrait': source(rotation: 90, tags: phoneTags),
        });
        expect(plan.toJson(), {
          'mode': 'remux',
          'cuts': [
            {'assetId': 'portrait', 'startUs': 1000000, 'durationUs': 2500000},
          ],
          'audio': true,
          'tags': keptTags,
        });
        expect(plan.durationUs, 2500000);
      },
    );

    test('keeps a start on a keyframe and ends at the end of the source', () {
      expect(cuts(Plan.of(edl([clip('a', 2000, 5000)]), {'a': source()})), [
        ('a', 2000000, 2000000, false, false),
      ]);
    });

    test(
      'is transcoded frame-accurately in its own format when lossless is not preferred',
      () {
        final plan = Plan.of(
          edl([
            clip('a', 1500, 1000),
          ], ', "planner": {"preferLossless": false}'),
          {
            'a': source(
              width: 1080,
              height: 1920,
              fps: '60/1',
              transfer: 'arib-std-b67',
            ),
          },
          devices: desktop,
        );
        expect(plan.toJson()['mode'], 'transcode');
        expect(cuts(plan), [('a', 1500000, 1000000, false, false)]);
        expect(plan.video!.toJson(), video(1080, 1920, '60/1', 'arib-std-b67'));
      },
    );

    test('must start inside a known source', () {
      expect(
        () => Plan.of(edl([clip('a', 4000, 1000)]), {'a': source()}),
        throwsArgumentError,
      );
      expect(
        () => Plan.of(edl([clip('b', 0, 1000)]), {'a': source()}),
        throwsArgumentError,
      );
    });
  });

  group('heterogeneous clips are normalised (11 §6.3)', () {
    test(
      'into the first clip\'s orientation, the largest short side, the commonest rate and SDR',
      () {
        final plan = Plan.of(fixture('merge'), {
          'landscape': source(width: 1280, height: 720, tags: phoneTags),
          'portrait': source(rotation: 90),
          'silent': source(width: 640, height: 360, fps: '25/1', audio: false),
          'hlg': source(
            transfer: 'arib-std-b67',
            tags: {'creation_time': '2022-03-05T17:00:00Z'},
          ),
        }, devices: desktop);
        expect(cuts(plan), [
          ('landscape', 1000000, 2000000, false, false),
          ('portrait', 500000, 2000000, false, false),
          ('silent', 0, 1500000, true, false),
          ('hlg', 0, 2000000, false, true),
        ]);
        expect(plan.video!.toJson(), video(1920, 1080, '30/1', 'bt709'));
        expect(plan.audio, true);
        expect(plan.tags, keptTags);
      },
    );

    Map<String, Object?> videoOf(List<SourceInfo> infos, [String extra = '']) =>
        Plan.of(
          edl([
            for (var i = 0; i < infos.length; i++) clip('$i', 0, 1000),
          ], extra),
          {for (final (i, info) in infos.indexed) '$i': info},
          devices: desktop,
        ).video!.toJson();

    test('a portrait first clip makes a portrait output', () {
      expect(
        videoOf([source(rotation: 270), source(width: 1280, height: 720)]),
        video(1080, 1920, '30/1', 'bt709'),
      );
    });

    test(
      'the short side is capped at 1080, at 2160 when every clip is 4K, and at the requested maximum',
      () {
        expect(
          videoOf([source(width: 3840, height: 2160), source()])['height'],
          1080,
        );
        expect(
          videoOf([
            source(width: 3840, height: 2160),
            source(width: 4096, height: 2160),
          ])['height'],
          2160,
        );
        final small = videoOf([
          source(),
          source(width: 1280, height: 720),
        ], ', "output": {"maxShortSide": 480}');
        expect((small['width'], small['height']), (854, 480));
      },
    );

    test(
      'a tie between rates goes to the faster one, and no rate exceeds 60',
      () {
        expect(
          videoOf([source(fps: '25/1'), source(fps: '30000/1001')])['fps'],
          '30000/1001',
        );
        expect(
          videoOf([
            source(fps: '120/1'),
            source(fps: '120/1'),
            source(fps: '30/1'),
          ])['fps'],
          '60/1',
        );
      },
    );

    test(
      'HDR is kept in 10 bits only when every clip is HDR of one family and the policy allows it',
      () {
        final hlg = source(transfer: 'arib-std-b67');
        expect(videoOf([hlg, hlg]), video(1920, 1080, '30/1', 'arib-std-b67'));
        expect(
          videoOf([hlg, source(transfer: 'smpte2084')])['transfer'],
          'bt709',
        );
        expect(
          videoOf([hlg, hlg], ', "output": {"hdr": "TONE_MAP"}')['transfer'],
          'bt709',
        );
      },
    );

    test(
      'without audio in any clip the output has none, and stripGps drops the location',
      () {
        final plan = Plan.of(
          edl([
            clip('a', 0, 1000),
            clip('b', 0, 1000),
          ], ', "metadata": {"stripGps": true}'),
          {
            'a': source(audio: false, tags: phoneTags),
            'b': source(audio: false),
          },
          devices: desktop,
        );
        expect(plan.audio, false);
        expect(plan.tags, {...keptTags}..remove('location'));
      },
    );
  });

  group(
    'the devices\' capabilities choose the codec and where it runs (ADR-0043)',
    () {
      /// A merge of two HLG clips on [devices]: (codec, transfer, remote, user told, every cut tone-mapped).
      (String, String, bool, bool, bool) hlg(Devices devices) {
        final hlg = source(transfer: 'arib-std-b67');
        final plan = Plan.of(edl([clip('a', 0, 1000), clip('b', 0, 1000)]), {
          'a': hlg,
          'b': hlg,
        }, devices: devices);
        return (
          plan.video!.codec,
          plan.video!.transfer,
          plan.remote,
          plan.hdrNotice,
          plan.cuts.every((c) => c.toneMap),
        );
      }

      const kept = ('hevc', 'arib-std-b67', false, false, false);
      const toneMapped = ('h264', 'bt709', false, true, true);
      for (final (why, devices, expected) in [
        (
          'by a hardware 10-bit HEVC encoder first, even with a server',
          const Devices({h264, hevc10, x265, av1, playsAv1}, remote: true),
          kept,
        ),
        (
          'else by the server or the trusted node, in HEVC (x265)',
          const Devices({h264, x265, av1, playsAv1}, remote: true),
          ('hevc', 'arib-std-b67', true, false, false),
        ),
        (
          'else by libx265 in an FFmpeg the user installed',
          const Devices({h264, x265, av1, playsAv1}),
          kept,
        ),
        (
          'else in 10-bit AV1 when every device of the library plays it',
          const Devices(
            {h264, av1, playsAv1},
            others: [
              {playsAv1},
            ],
          ),
          ('av1', 'arib-std-b67', false, false, false),
        ),
        (
          'else tone-mapped to SDR, and the user is told: a device plays no AV1',
          const Devices(
            {h264, av1, playsAv1},
            others: [
              {playsAv1},
              {h264},
            ],
          ),
          toneMapped,
        ),
        (
          'else tone-mapped to SDR, and the user is told: this device plays no AV1',
          const Devices(
            {h264, av1},
            others: [
              {playsAv1},
            ],
          ),
          toneMapped,
        ),
        (
          'else tone-mapped to SDR, and the user is told: no AV1 encoder',
          const Devices({h264, playsAv1}),
          toneMapped,
        ),
      ]) {
        test('kept HDR is encoded $why', () => expect(hlg(devices), expected));
      }

      test(
        'SDR is H.264 on this device, else on the server or the trusted node, else nowhere',
        () {
          Plan sdr(Devices devices) => Plan.of(
            edl([clip('a', 0, 1000), clip('b', 0, 1000)]),
            {'a': source(), 'b': source()},
            devices: devices,
          );
          final remote = sdr(const Devices({hevc10, av1}, remote: true));
          expect(
            (
              sdr(const Devices({h264}, remote: true)).remote,
              remote.remote,
              remote.video!.codec,
              remote.hdrNotice,
            ),
            (false, true, 'h264', false),
          );
          expect(() => sdr(const Devices({hevc10, av1})), throwsStateError);
        },
      );
    },
  );
}
