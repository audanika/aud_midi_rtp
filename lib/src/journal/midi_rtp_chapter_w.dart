// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';

// #############################################################################
/// Chapter W of a channel journal: the most recent C-active Pitch Wheel
/// command (RFC 6295 A.5, Figure A.5.1).
final class MidiRtpChapterW {
  /// Creates a chapter.
  ///
  /// - [s] the S bit: false when the command is in the previous packet.
  /// - [value] the 14-bit wheel value; FIRST codes its low and SECOND its
  ///   high seven bits, like the data octets of the command.
  const MidiRtpChapterW({this.s = true, required this.value})
    : assert(value >= 0 && value <= 0x3FFF);

  // ...........................................................................
  /// Reads a chapter at the position of [reader]; the R bit is ignored.
  factory MidiRtpChapterW.read(MidiRtpByteReader reader) {
    final first = reader.readUint8();
    final second = reader.readUint8();
    return MidiRtpChapterW(
      s: first >= 0x80,
      value: (second & 0x7F) << 7 | (first & 0x7F),
    );
  }

  // ...........................................................................
  /// Returns the encoded chapter.
  Uint8List toBytes() =>
      Uint8List.fromList([(s ? 0x80 : 0) | (value & 0x7F), value >> 7]);

  /// Returns a copy with the given fields replaced.
  MidiRtpChapterW copyWith({bool? s, int? value}) =>
      MidiRtpChapterW(s: s ?? this.s, value: value ?? this.value);

  // ...........................................................................
  /// The S bit.
  final bool s;

  /// The 14-bit pitch wheel value.
  final int value;

  // ...........................................................................
  /// The number of encoded bytes.
  static const int length = 2;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpChapterW && other.s == s && other.value == value;

  @override
  int get hashCode => Object.hash(MidiRtpChapterW, s, value);

  @override
  String toString() => 'MidiRtpChapterW(s: $s, value: $value)';
}
