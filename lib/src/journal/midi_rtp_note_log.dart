// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';

// #############################################################################
/// A note log of Chapter N: the most recent N-active NoteOn of a note
/// number (RFC 6295 A.6.2, Figure A.6.3).
final class MidiRtpNoteLog {
  /// Creates a log.
  ///
  /// - [s] the S bit: false when the NoteOn is in the previous packet.
  /// - [note] the note number.
  /// - [y] the Y bit: the sender recommends to play (true) or to skip
  ///   (false) the NoteOn when it is recovered (RFC 4696 4.2).
  /// - [velocity] the NoteOn velocity, 1 to 127.
  const MidiRtpNoteLog({
    this.s = true,
    required this.note,
    this.y = true,
    required this.velocity,
  }) : assert(note >= 0 && note <= 0x7F),
       assert(velocity >= 0 && velocity <= 0x7F);

  // ...........................................................................
  /// Reads a log at the position of [reader].
  factory MidiRtpNoteLog.read(MidiRtpByteReader reader) {
    final first = reader.readUint8();
    final second = reader.readUint8();
    return MidiRtpNoteLog(
      s: first >= 0x80,
      note: first & 0x7F,
      y: second >= 0x80,
      velocity: second & 0x7F,
    );
  }

  // ...........................................................................
  /// Returns the encoded log.
  Uint8List toBytes() =>
      Uint8List.fromList([(s ? 0x80 : 0) | note, (y ? 0x80 : 0) | velocity]);

  /// Returns a copy with the given fields replaced.
  MidiRtpNoteLog copyWith({bool? s, int? note, bool? y, int? velocity}) =>
      MidiRtpNoteLog(
        s: s ?? this.s,
        note: note ?? this.note,
        y: y ?? this.y,
        velocity: velocity ?? this.velocity,
      );

  // ...........................................................................
  /// The S bit.
  final bool s;

  /// The note number.
  final int note;

  /// The Y bit: the recommendation to play the recovered NoteOn.
  final bool y;

  /// The NoteOn velocity.
  final int velocity;

  // ...........................................................................
  /// The number of encoded bytes.
  static const int length = 2;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpNoteLog &&
      other.s == s &&
      other.note == note &&
      other.y == y &&
      other.velocity == velocity;

  @override
  int get hashCode => Object.hash(MidiRtpNoteLog, s, note, y, velocity);

  @override
  String toString() =>
      'MidiRtpNoteLog(s: $s, note: $note, y: $y, velocity: $velocity)';
}
