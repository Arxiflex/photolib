import 'dart:convert';
import 'dart:typed_data';

/// A `photolib.api.v1.SyncResponse` read from its bytes (photolib/sync/v1/sync.proto), its rows left there until read:
/// the messages of a batch of a thousand assets are some 60,000 values, and while they are alive every garbage
/// collection of the app's isolates, the UI's included, copies them.
final class SyncMessage {
  SyncMessage(Uint8List message) {
    final response = _Wire(message, 0, message.length);
    while (response.more) {
      final tag = response.varint();
      if (tag != 0x0a) {
        response.skip(tag);
        continue;
      }
      final batch = response.field();
      while (batch.more) {
        switch (batch.varint()) {
          case 0x0a:
            stream = batch.text();
          case 0x10:
            status = batch.varint();
          case 0x1a:
            changes.add(SyncRows._(batch.field()));
          case 0x22:
            cursor = Uint8List.fromList(batch.blob());
          case final tag:
            batch.skip(tag);
        }
      }
    }
  }

  String stream = '';

  /// A `StreamStatus`: 1 is OK, 2 RESET_REQUIRED.
  int status = 0;
  Uint8List cursor = Uint8List(0);
  final changes = <SyncRows>[];
}

/// A `Rows` group of a batch.
final class SyncRows {
  SyncRows._(_Wire group) {
    while (group.more) {
      switch (group.varint()) {
        case 0x0a:
          entity = group.text();
        case 0x12:
          columns.add(group.text());
        case 0x1a:
          _rows.add(group.field());
        case 0x20:
          deleted = group.varint() != 0;
        case final tag:
          group.skip(tag);
      }
    }
  }

  String entity = '';
  final columns = <String>[];
  bool deleted = false;
  final _rows = <_Wire>[];

  int get length => _rows.length;

  /// The values of row [i]: a String, int, double, bool, Uint8List or null each.
  List<Object?> values(int i) {
    final row = _rows[i].copy();
    final values = <Object?>[];
    while (row.more) {
      final tag = row.varint();
      if (tag != 0x0a) {
        row.skip(tag);
        continue;
      }
      final value = row.field();
      Object? v;
      while (value.more) {
        switch (value.varint()) {
          case 0x0a:
            v = value.text();
          case 0x10:
            v = _unzigzag(value.varint());
          case 0x19:
            v = value.real();
          case 0x20:
            v = value.varint() != 0;
          case 0x2a:
            v = value.blob();
          case final tag:
            value.skip(tag);
        }
      }
      values.add(v);
    }
    return values;
  }
}

/// 2^i for each shift of a varint, never a shift itself: dart2js's bit
/// operations are 32 bits wide, and a timestamp in milliseconds is not. The
/// sums stay exact up to 2^53, which a browser's integers are.
final List<int> _power = [for (var i = 0, p = 1; i < 64; i++, p *= 2) p];

/// The integer that zigzag encoding [n] stands for.
int _unzigzag(int n) =>
    _js ? (n.isEven ? n ~/ 2 : -((n + 1) ~/ 2)) : (n >>> 1) ^ -(n & 1);

/// Whether integers are JavaScript's numbers.
const bool _js = identical(0, 0.0);

/// Protobuf's wire format in [_bytes] from [_at] to [_end].
final class _Wire {
  _Wire(this._bytes, this._at, this._end);

  final Uint8List _bytes;
  int _at;
  final int _end;

  bool get more => _at < _end;

  _Wire copy() => _Wire(_bytes, _at, _end);

  int varint() {
    var value = 0;
    for (var shift = 0; shift < 64 && _at < _end; shift += 7) {
      final b = _bytes[_at++];
      value += (b & 0x7f) * _power[shift];
      if (b < 0x80) return value;
    }
    throw const FormatException('a broken varint');
  }

  /// The length-delimited field that follows.
  _Wire field() {
    final length = varint();
    if (length < 0 || length > _end - _at) {
      throw const FormatException('a field past its message');
    }
    return _Wire(_bytes, _at, _at += length);
  }

  String text() {
    final f = field();
    return utf8.decode(Uint8List.sublistView(_bytes, f._at, f._end));
  }

  Uint8List blob() {
    final f = field();
    return Uint8List.sublistView(_bytes, f._at, f._end);
  }

  double real() {
    if (_end - _at < 8) throw const FormatException('a broken double');
    return ByteData.sublistView(
      _bytes,
      _at,
      _at += 8,
    ).getFloat64(0, Endian.little);
  }

  /// Skips the value of a field of [tag].
  void skip(int tag) {
    switch (tag & 7) {
      case 0:
        varint();
      case 2:
        field();
      case final type when type == 1 || type == 5:
        _at += type == 1 ? 8 : 4;
        if (_at > _end) throw const FormatException('a field past its message');
      default:
        throw FormatException('wire type ${tag & 7}');
    }
  }
}
