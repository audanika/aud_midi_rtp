// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';

// #############################################################################
/// System Chapter V: the reference count of Active Sense commands (RFC 6295
/// B.2, Figure B.2.1).
final class MidiRtpChapterV {
  /// Creates a chapter with the S bit [s] and the Active Sense [count]
  /// modulo 128.
  const MidiRtpChapterV({this.s = true, required this.count})
    : assert(count >= 0 && count <= 0x7F);

  // ...........................................................................
  /// Reads a chapter at the position of [reader].
  factory MidiRtpChapterV.read(MidiRtpByteReader reader) {
    final octet = reader.readUint8();
    return MidiRtpChapterV(s: octet >= 0x80, count: octet & 0x7F);
  }

  // ...........................................................................
  /// Returns the encoded chapter.
  Uint8List toBytes() => Uint8List.fromList([(s ? 0x80 : 0) | count]);

  /// Returns a copy with the given fields replaced.
  MidiRtpChapterV copyWith({bool? s, int? count}) =>
      MidiRtpChapterV(s: s ?? this.s, count: count ?? this.count);

  // ...........................................................................
  /// The S bit.
  final bool s;

  /// The number of Active Sense commands modulo 128.
  final int count;

  // ...........................................................................
  /// The number of encoded bytes.
  static const int length = 1;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpChapterV && other.s == s && other.count == count;

  @override
  int get hashCode => Object.hash(MidiRtpChapterV, s, count);

  @override
  String toString() => 'MidiRtpChapterV(s: $s, count: $count)';
}
