import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

extension TileStarts on WidgetTester {
  /// Where the content of each [ListTile] under [of] starts, by its title: the
  /// left edge of its leading widget, else of its title.
  Map<String?, double> tileStarts(Finder of) => {
    for (final tile
        in find.descendant(of: of, matching: find.byType(ListTile)).evaluate())
      ((tile.widget as ListTile).title as Text?)?.data: [
        for (final part
            in find
                .descendant(
                  of: find.byElementPredicate((e) => e == tile),
                  matching: find.byWidgetPredicate(
                    (w) => w is Icon || w is RichText,
                  ),
                )
                .evaluate())
          (part.findRenderObject()! as RenderBox).localToGlobal(Offset.zero).dx,
      ].reduce(min),
  };
}
