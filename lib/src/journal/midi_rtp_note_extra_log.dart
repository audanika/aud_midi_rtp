// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';

// #############################################################################
/// A note log of Chapter E: the release velocity or the reference count of
/// a note number (RFC 6295 A.7.1, Figure A.7.2).
final class MidiRtpNoteExtraLog {
  /// Creates a log.
  ///
  /// - [s] the S bit: false when the coded command is in the previous
  ///   packet.
  /// - [note] the note number.
  /// - [v] the V bit: true when [value] is the release velocity of the most
  ///   recent N-active NoteOff, false when it is the reference count of
  ///   NoteOn and NoteOff commands (127 for 127 or more).
  /// - [value] the release velocity or reference count.
  const MidiRtpNoteExtraLog({
    this.s = true,
    required this.note,
    required this.v,
    required this.value,
  }) : assert(note >= 0 && note <= 0x7F),
       assert(value >= 0 && value <= 0x7F);

  // ...........................................................................
  /// Reads a log at the position of [reader].
  factory MidiRtpNoteExtraLog.read(MidiRtpByteReader reader) {
    final first = reader.readUint8();
    final second = reader.readUint8();
    return MidiRtpNoteExtraLog(
      s: first >= 0x80,
      note: first & 0x7F,
      v: second >= 0x80,
      value: second & 0x7F,
    );
  }

  // ...........................................................................
  /// Returns the encoded log.
  Uint8List toBytes() =>
      Uint8List.fromList([(s ? 0x80 : 0) | note, (v ? 0x80 : 0) | value]);

  /// Returns a copy with the given fields replaced.
  MidiRtpNoteExtraLog copyWith({bool? s, int? note, bool? v, int? value}) =>
      MidiRtpNoteExtraLog(
        s: s ?? this.s,
        note: note ?? this.note,
        v: v ?? this.v,
        value: value ?? this.value,
      );

  // ...........................................................................
  /// The S bit.
  final bool s;

  /// The note number.
  final int note;

  /// The V bit: [value] is a release velocity, not a reference count.
  final bool v;

  /// The release velocity or reference count.
  final int value;

  // ...........................................................................
  /// The number of encoded bytes.
  static const int length = 2;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpNoteExtraLog &&
      other.s == s &&
      other.note == note &&
      other.v == v &&
      other.value == value;

  @override
  int get hashCode => Object.hash(MidiRtpNoteExtraLog, s, note, v, value);

  @override
  String toString() =>
      'MidiRtpNoteExtraLog(s: $s, note: $note, v: $v, value: $value)';
}
