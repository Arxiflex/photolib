import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/pages.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib/features/viewer/info_panel.dart';
import 'package:photolib/features/viewer/regions.dart';
import 'package:photolib/features/viewer/slideshow.dart';
import 'package:photolib/features/viewer/viewer_page.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/theme.dart';
import 'package:photolib_data/photolib_data.dart' show LocalAssetData, uuidOf;

import 'pump_app.dart';

/// Grey images of [width] × [height], the URIs of their items in [asked].
class Grey extends ThumbnailPipeline {
  new({this.width = 40, this.height = 30});

  final int width;
  final int height;
  final asked = <Uri>[];
  final _loads = <(String, int)>[];

  /// The last path segments of the items loaded at [tier].
  List<String> at(int tier) => [
    for (final (file, t) in _loads)
      if (t == tier) file,
  ];

  @override
  Future<ui.Image> load(ThumbnailItem item, int tier, Tile tile) async {
    asked.add(item.uri);
    _loads.add((item.uri.pathSegments.last, tier));
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xff808080), BlendMode.src);
    return recorder.endRecording().toImageSync(width, height);
  }
}

/// The viewer alone at [at] of [count] files `<n>.jpg`, or `<n>.mp4` for the
/// [video]s, or MediaStore items if [content], its images from [pipeline] and
/// its filmstrip's tiles from
/// [thumbnails]; with [rows], each item's row, a photo of May 3, 2024, or
/// [rowOf] the item, answers that long after it is asked for; with [ids] each
/// item has one, and with [assets] a server asset; with [server] the items are
/// photos only the server has (ADR-0267); with [settings] as the
/// user's; [overrides] replace other providers.
Future<ValueNotifier<int>> pumpViewer(
  WidgetTester tester, {
  required Size size,
  ThumbnailPipeline? pipeline,
  int count = 4,
  int at = 0,
  Thumbnails? thumbnails,
  bool Function(int p)? video,
  bool content = false,
  Duration? rows,
  LocalAssetData Function(ThumbnailItem)? rowOf,
  bool ids = false,
  bool assets = false,
  bool server = false,
  Settings settings = const Settings(),
  Locale? locale,
  Brightness brightness = Brightness.light,
  List<Override> overrides = const [],
}) async {
  final images = pipeline ?? Grey();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final position = ValueNotifier(at);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        thumbnailPipelineProvider.overrideWith((ref) async => images),
        regionsProvider.overrideWithValue((_) async => null),
        settingsStoreProvider.overrideWithValue(
          MemoryStore(jsonEncode(settings.toJson())),
        ),
        keepAwakeProvider.overrideWithValue(({required enable}) async {}),
        if (rows != null || rowOf != null)
          assetRowProvider.overrideWith(
            (ref, item) => Stream.fromFuture(
              Future.delayed(rows ?? Duration.zero, () => (rowOf ?? row)(item)),
            ),
          ),
        ...overrides,
      ],
      child: MaterialApp(
        theme: appTheme(brightness),
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ViewerPage(
          pages: TimelinePages(
            (first, n) async => [
              for (var p = first; p < min(count, first + n); p++)
                if (video?.call(p) ?? false)
                  ThumbnailItem(
                    '$p',
                    Uri.file('/p/$p.mp4'),
                    video: true,
                    id: ids ? idOf(p) : null,
                    asset: assets ? idOf(p) : null,
                  )
                else if (server)
                  ThumbnailItem(
                    '$p',
                    Uri(path: 'media/${uuidOf(idOf(p))}'),
                    asset: idOf(p),
                  )
                else if (content)
                  ThumbnailItem(
                    '$p',
                    Uri.parse('content://media/external/images/media/$p'),
                    id: ids ? idOf(p) : null,
                    asset: assets ? idOf(p) : null,
                  )
                else
                  ThumbnailItem(
                    '$p',
                    Uri.file('/p/$p.jpg'),
                    id: ids ? idOf(p) : null,
                    asset: assets ? idOf(p) : null,
                  ),
            ],
          ),
          count: count,
          position: position,
          thumbnails:
              thumbnails ??
              Thumbnails(
                (item, tier, cancelled) =>
                    images.load(item as ThumbnailItem, tier, cancelled),
              ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return position;
}

/// The id of the item at [p] when [pumpViewer] gives items ids.
Uint8List idOf(int p) => Uint8List(16)..[15] = p + 1;

/// How opaque what [finder] finds is, as the fades and opacities over it
/// make it.
double opacity(WidgetTester tester, Finder finder) => [
  for (final w in tester.widgetList(
    find.ancestor(
      of: finder,
      matching: find.byWidgetPredicate(
        (w) => w is FadeTransition || w is Opacity,
      ),
    ),
  ))
    if (w is FadeTransition) w.opacity.value else if (w is Opacity) w.opacity,
].fold<double>(1, (a, b) => a * b);

/// [item]'s row: a photo of May 3, 2024, of 4000 × 3000 if [orientation]
/// says how it turns.
LocalAssetData row(ThumbnailItem item, {int? orientation}) => LocalAssetData(
  id: Uint8List(16),
  source: 'folder',
  volume: '/p',
  sourceId: item.key,
  path: item.uri.pathSegments.last,
  size: 1,
  mtime: 0,
  state: 'present',
  favorite: 0,
  trashed: 0,
  edited: 0,
  folder: 0,
  hidden: 0,
  archived: 0,
  tile: 0,
  takenLocal: '2024-05-03T12:00:00',
  width: orientation == null ? null : 4000,
  height: orientation == null ? null : 3000,
  orientation: orientation,
);
