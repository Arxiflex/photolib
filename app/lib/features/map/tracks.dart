import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/features/map/map_logic.dart';

/// The largest GPX file read; a longer one is no track a person recorded.
const int maxTrackBytes = 32 << 20;

/// Lets the user choose a GPX file and reads its tracks (MAP-12): null when
/// none was chosen, none when the file holds none or is too large. A test
/// brings its own file.
final trackPickerProvider = Provider<Future<List<Track>?> Function()>(
  (ref) => () async {
    final file = await FileSelectorPlatform.instance.openFile(
      acceptedTypeGroups: const [
        XTypeGroup(extensions: ['gpx']),
      ],
    );
    if (file == null) return null;
    if (await file.length() > maxTrackBytes) return const [];
    return parseGpx(await file.readAsString());
  },
);
