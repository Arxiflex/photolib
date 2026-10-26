import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The address a browser served the app from, where photolibd serves it
/// (M2-25), which *Add a server* offers first; null elsewhere.
final ownOriginProvider = Provider<Uri?>(
  (ref) => kIsWeb ? ownAddress(Uri.base) : null,
);

/// [page] without its query and fragment, if it is a web address.
Uri? ownAddress(Uri page) => {'http', 'https'}.contains(page.scheme)
    ? Uri.parse(page.toString().split(RegExp('[?#]')).first)
    : null;
