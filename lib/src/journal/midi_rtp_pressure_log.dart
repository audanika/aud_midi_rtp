// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';

// #############################################################################
/// A note log of Chapter A: the most recent C-active Poly Aftertouch of a
/// note number (RFC 6295 A.9, Figure A.9.2).
final class MidiRtpPressureLog {
  /// Creates a log.
  ///
  /// - [s] the S bit: false when the command is in the previous packet.
  /// - [note] the note number.
  /// - [x] the X bit: the command came before an All Notes Off or All
  ///   Sound Off (controllers 120, 123 to 127).
  /// - [pressure] the pressure value.
  const MidiRtpPressureLog({
    this.s = true,
    required this.note,
    this.x = false,
    required this.pressure,
  }) : assert(note >= 0 && note <= 0x7F),
       assert(pressure >= 0 && pressure <= 0x7F);

  // ...........................................................................
  /// Reads a log at the position of [reader].
  factory MidiRtpPressureLog.read(MidiRtpByteReader reader) {
    final first = reader.readUint8();
    final second = reader.readUint8();
    return MidiRtpPressureLog(
      s: first >= 0x80,
      note: first & 0x7F,
      x: second >= 0x80,
      pressure: second & 0x7F,
    );
  }

  // ...........................................................................
  /// Returns the encoded log.
  Uint8List toBytes() =>
      Uint8List.fromList([(s ? 0x80 : 0) | note, (x ? 0x80 : 0) | pressure]);

  /// Returns a copy with the given fields replaced.
  MidiRtpPressureLog copyWith({bool? s, int? note, bool? x, int? pressure}) =>
      MidiRtpPressureLog(
        s: s ?? this.s,
        note: note ?? this.note,
        x: x ?? this.x,
        pressure: pressure ?? this.pressure,
      );

  // ...........................................................................
  /// The S bit.
  final bool s;

  /// The note number.
  final int note;

  /// The X bit: the command is no longer N-active.
  final bool x;

  /// The pressure value.
  final int pressure;

  // ...........................................................................
  /// The number of encoded bytes.
  static const int length = 2;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpPressureLog &&
      other.s == s &&
      other.note == note &&
      other.x == x &&
      other.pressure == pressure;

  @override
  int get hashCode => Object.hash(MidiRtpPressureLog, s, note, x, pressure);

  @override
  String toString() =>
      'MidiRtpPressureLog(s: $s, note: $note, x: $x, pressure: $pressure)';
}
