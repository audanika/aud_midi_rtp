// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import '../support/midi_rtp_byte_reader.dart';

// #############################################################################
/// Codes the variable-length unsigned integers of RTP MIDI: the delta times
/// of the MIDI list (RFC 6295 3.1, Figure 4) and the FIRST field of System
/// Chapter X (RFC 6295 B.5.1, Figure B.5.2).
///
/// A value takes one to four octets of seven bits each, most significant
/// first; every octet but the last has its top bit set. Decoding accepts
/// every legal form, e.g. the four forms of zero (0x00, 0x8000, 0x808000,
/// 0x80808000); encoding always uses the shortest form.
abstract final class MidiRtpDeltaTime {
  // ...........................................................................
  /// Returns the shortest encoding of [value], 0 to [max].
  static List<int> encode(int value) {
    if (value < 0 || value > max) {
      throw RangeError.range(value, 0, max, 'value');
    }
    final count = encodedLength(value);
    return [
      for (var i = count - 1; i >= 0; i--)
        ((value >> (7 * i)) & 0x7F) | (i > 0 ? 0x80 : 0),
    ];
  }

  // ...........................................................................
  /// Reads a value at the position of [reader].
  ///
  /// Throws a [FormatException] when the value has more than four octets or
  /// the data ends early.
  static int read(MidiRtpByteReader reader) {
    var value = 0;
    for (var i = 0; i < 4; i++) {
      final octet = reader.readUint8();
      value = (value << 7) | (octet & 0x7F);
      if (octet < 0x80) return value;
    }
    throw const FormatException('Variable-length value longer than 4 octets');
  }

  // ...........................................................................
  /// Returns the number of octets of the shortest encoding of [value].
  static int encodedLength(int value) => value < 0x80
      ? 1
      : value < 0x4000
      ? 2
      : value < 0x200000
      ? 3
      : 4;

  // ...........................................................................
  /// The largest value four octets can code.
  static const int max = 0x0FFFFFFF;
}
