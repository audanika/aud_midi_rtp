// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';

// #############################################################################
/// System Chapter F: the MIDI Time Code tape position (RFC 6295 B.4,
/// Figures B.4.1 to B.4.3).
///
/// COMPLETE holds the most recent complete frame, coded as Quarter Frame
/// nibbles (Q = 1, forward series offset by two frames) or as Full Frame
/// octets (Q = 0); PARTIAL holds the nibbles of the frame in progress, valid
/// from message type 0 up to POINT, or from 7 down to POINT in reverse (see
/// `MidiRtpTimeCode` for the field formats).
final class MidiRtpChapterF {
  /// Creates a chapter.
  ///
  /// - [s] the S bit.
  /// - [complete] the 32-bit COMPLETE field (C = 1).
  /// - [q] the Q bit: [complete] holds Quarter Frame nibbles.
  /// - [d] the D bit: the tape moves in reverse.
  /// - [point] the POINT field: the last valid message type of [partial];
  ///   7 (forward) or 0 (reverse) without a PARTIAL field.
  /// - [partial] the 32-bit PARTIAL field (P = 1).
  const MidiRtpChapterF({
    this.s = true,
    this.complete,
    this.q = false,
    this.d = false,
    this.point = 7,
    this.partial,
  }) : assert(point >= 0 && point <= 7),
       assert(complete == null || (complete >= 0 && complete <= 0xFFFFFFFF)),
       assert(partial == null || (partial >= 0 && partial <= 0xFFFFFFFF));

  // ...........................................................................
  /// Reads a chapter at the position of [reader].
  factory MidiRtpChapterF.read(MidiRtpByteReader reader) {
    final header = reader.readUint8();
    final complete = (header & 0x40) != 0 ? reader.readUint32() : null;
    return MidiRtpChapterF(
      s: header >= 0x80,
      complete: complete,
      q: (header & 0x10) != 0,
      d: (header & 0x08) != 0,
      point: header & 0x07,
      partial: (header & 0x20) != 0 ? reader.readUint32() : null,
    );
  }

  // ...........................................................................
  /// Returns the encoded chapter.
  Uint8List toBytes() => Uint8List.fromList([
    (s ? 0x80 : 0) |
        (complete != null ? 0x40 : 0) |
        (partial != null ? 0x20 : 0) |
        (q ? 0x10 : 0) |
        (d ? 0x08 : 0) |
        point,
    if (complete != null) ..._word(complete!),
    if (partial != null) ..._word(partial!),
  ]);

  /// Returns a copy with the given fields replaced.
  MidiRtpChapterF copyWith({
    bool? s,
    int? complete,
    bool? q,
    bool? d,
    int? point,
    int? partial,
  }) => MidiRtpChapterF(
    s: s ?? this.s,
    complete: complete ?? this.complete,
    q: q ?? this.q,
    d: d ?? this.d,
    point: point ?? this.point,
    partial: partial ?? this.partial,
  );

  // ...........................................................................
  /// The S bit.
  final bool s;

  /// The COMPLETE field.
  final int? complete;

  /// The Q bit: [complete] holds Quarter Frame nibbles.
  final bool q;

  /// The D bit: the tape moves in reverse.
  final bool d;

  /// The POINT field.
  final int point;

  /// The PARTIAL field.
  final int? partial;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpChapterF &&
      other.s == s &&
      other.complete == complete &&
      other.q == q &&
      other.d == d &&
      other.point == point &&
      other.partial == partial;

  @override
  int get hashCode => Object.hash(s, complete, q, d, point, partial);

  @override
  String toString() =>
      'MidiRtpChapterF(s: $s, complete: $complete, q: $q, d: $d, '
      'point: $point, partial: $partial)';

  // ...........................................................................
  static List<int> _word(int value) => [
    value >> 24,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ];
}
