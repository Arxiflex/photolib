import 'dart:convert';
import 'dart:io';

import 'package:photolib_video/photolib_video.dart';

/// One of the edit decision lists in testdata/edl that every executor runs.
Edl fixture(String name) => Edl.fromJson(
  jsonDecode(File('../../../testdata/edl/$name.json').readAsStringSync()),
);
