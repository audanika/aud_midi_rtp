// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';

// #############################################################################
/// System Chapter Q: the state of the sequencer, coded by Song Position
/// Pointer, Clock, Start, Continue and Stop (RFC 6295 B.3, Figures B.3.1
/// and B.3.2).
final class MidiRtpChapterQ {
  /// Creates a chapter.
  ///
  /// - [s] the S bit.
  /// - [n] the N bit: a Start or Continue is more recent than a Stop.
  /// - [d] the D bit: the song position has been played; the next Clock
  ///   advances it.
  /// - [position] the song position in MIDI clocks modulo 2^19 (C = 1,
  ///   TOP and CLOCK), or null for the start of the song (C = 0).
  /// - [time] the TIMETOOLS correction in milliseconds (T = 1) for
  ///   sequencers that do not count with Clock commands.
  const MidiRtpChapterQ({
    this.s = true,
    this.n = false,
    this.d = false,
    this.position,
    this.time,
  }) : assert(position == null || (position >= 0 && position <= 0x7FFFF)),
       assert(time == null || (time >= 0 && time <= 0xFFFFFF));

  // ...........................................................................
  /// Reads a chapter at the position of [reader].
  factory MidiRtpChapterQ.read(MidiRtpByteReader reader) {
    final header = reader.readUint8();
    final position = (header & 0x10) != 0
        ? (header & 0x07) << 16 | reader.readUint16()
        : null;
    return MidiRtpChapterQ(
      s: header >= 0x80,
      n: (header & 0x40) != 0,
      d: (header & 0x20) != 0,
      position: position,
      time: (header & 0x08) != 0 ? reader.readUint24() : null,
    );
  }

  // ...........................................................................
  /// Returns the encoded chapter.
  Uint8List toBytes() => Uint8List.fromList([
    (s ? 0x80 : 0) |
        (n ? 0x40 : 0) |
        (d ? 0x20 : 0) |
        (position != null ? 0x10 : 0) |
        (time != null ? 0x08 : 0) |
        (position ?? 0) >> 16,
    if (position != null) ...[(position! >> 8) & 0xFF, position! & 0xFF],
    if (time != null) ...[time! >> 16, (time! >> 8) & 0xFF, time! & 0xFF],
  ]);

  /// Returns a copy with the given fields replaced.
  MidiRtpChapterQ copyWith({
    bool? s,
    bool? n,
    bool? d,
    int? position,
    int? time,
  }) => MidiRtpChapterQ(
    s: s ?? this.s,
    n: n ?? this.n,
    d: d ?? this.d,
    position: position ?? this.position,
    time: time ?? this.time,
  );

  // ...........................................................................
  /// The S bit.
  final bool s;

  /// The N bit: the sequencer runs.
  final bool n;

  /// The D bit: the song position has been played.
  final bool d;

  /// The song position in MIDI clocks, or null for the start of the song.
  final int? position;

  /// The TIMETOOLS correction in milliseconds.
  final int? time;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpChapterQ &&
      other.s == s &&
      other.n == n &&
      other.d == d &&
      other.position == position &&
      other.time == time;

  @override
  int get hashCode => Object.hash(MidiRtpChapterQ, s, n, d, position, time);

  @override
  String toString() =>
      'MidiRtpChapterQ(s: $s, n: $n, d: $d, position: $position, '
      'time: $time)';
}
