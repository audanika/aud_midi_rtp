// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

// #############################################################################
/// Reads the big-endian fields of an RTP MIDI packet (RFC 6295 1.2: all
/// fields are coded in network byte order).
///
/// The reader walks forward through [bytes] from an offset up to [end] and
/// throws a [FormatException] instead of reading past [end], so decoders of
/// network data never fail with a range error.
final class MidiRtpByteReader {
  /// Creates a reader over [bytes] that starts at [offset] and stops at
  /// [end], the end of the list by default.
  MidiRtpByteReader(List<int> bytes, {int offset = 0, int? end})
    : bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      end = end ?? bytes.length,
      _position = offset {
    RangeError.checkValueInInterval(this.end, 0, bytes.length, 'end');
    RangeError.checkValueInInterval(offset, 0, this.end, 'offset');
  }

  // ...........................................................................
  /// Returns the next byte without moving forward.
  int peek() {
    _require(1);
    return bytes[_position];
  }

  /// Reads one byte.
  int readUint8() {
    _require(1);
    return bytes[_position++];
  }

  /// Reads a 16-bit unsigned integer.
  int readUint16() => (readUint8() << 8) | readUint8();

  /// Reads a 24-bit unsigned integer.
  int readUint24() => (readUint16() << 8) | readUint8();

  /// Reads a 32-bit unsigned integer.
  int readUint32() => (readUint16() << 16) | readUint16();

  /// Reads the next [count] bytes into a new list.
  Uint8List readBytes(int count) {
    _require(count);
    final result = Uint8List.fromList(
      bytes.sublist(_position, _position + count),
    );
    _position += count;
    return result;
  }

  /// Returns a reader over the next [count] bytes and moves past them.
  ///
  /// Structures with a LENGTH field use it to stay inside their own octets
  /// (RFC 6295 A.1).
  MidiRtpByteReader take(int count) {
    _require(count);
    final result = MidiRtpByteReader(
      bytes,
      offset: _position,
      end: _position + count,
    );
    _position += count;
    return result;
  }

  /// Moves forward by [count] bytes.
  void skip(int count) {
    _require(count);
    _position += count;
  }

  // ...........................................................................
  /// The bytes the reader walks through.
  final Uint8List bytes;

  /// The index the reader stops at.
  final int end;

  /// The index of the next byte.
  int get position => _position;

  /// The number of bytes left before [end].
  int get remaining => end - _position;

  /// Whether no byte is left before [end].
  bool get isAtEnd => _position >= end;

  // ...........................................................................
  int _position;

  void _require(int count) {
    if (count < 0 || _position + count > end) {
      throw FormatException(
        'Unexpected end of data: $count bytes needed, $remaining left',
        bytes,
        _position,
      );
    }
  }
}
