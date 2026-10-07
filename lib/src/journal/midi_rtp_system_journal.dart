// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';
import 'midi_rtp_chapter_d.dart';
import 'midi_rtp_chapter_f.dart';
import 'midi_rtp_chapter_q.dart';
import 'midi_rtp_chapter_v.dart';
import 'midi_rtp_chapter_x.dart';

// #############################################################################
/// The system journal: the recovery data of the system commands, a 2-octet
/// header with the chapter table of contents followed by the chapters D,
/// V, Q, F and X (RFC 6295 5, Figure 10).
final class MidiRtpSystemJournal {
  /// Creates a system journal.
  ///
  /// - [s] the S bit: false when a chapter codes a command of the previous
  ///   packet.
  /// - [chapterD] to [chapterX] the chapters; null ones are left out.
  const MidiRtpSystemJournal({
    this.s = true,
    this.chapterD,
    this.chapterV,
    this.chapterQ,
    this.chapterF,
    this.chapterX,
  });

  // ...........................................................................
  /// Reads a system journal at the position of [reader]; the LENGTH field
  /// bounds the chapters, and Chapter X takes the octets after the others.
  factory MidiRtpSystemJournal.read(MidiRtpByteReader reader) {
    final header = reader.readUint16();
    final length = header & 0x03FF;
    if (length < 2) {
      throw FormatException('System journal LENGTH $length is too small');
    }
    final body = reader.take(length - 2);
    T? chapter<T>(int mask, T Function(MidiRtpByteReader) read) =>
        (header & mask) != 0 ? read(body) : null;
    return MidiRtpSystemJournal(
      s: (header & 0x8000) != 0,
      chapterD: chapter(0x4000, MidiRtpChapterD.read),
      chapterV: chapter(0x2000, MidiRtpChapterV.read),
      chapterQ: chapter(0x1000, MidiRtpChapterQ.read),
      chapterF: chapter(0x0800, MidiRtpChapterF.read),
      chapterX: chapter(0x0400, MidiRtpChapterX.read),
    );
  }

  // ...........................................................................
  /// Returns the encoded system journal.
  ///
  /// Throws an [ArgumentError] when it exceeds the 1023 octets the LENGTH
  /// field can code.
  Uint8List toBytes() {
    final body = <int>[
      ...?chapterD?.toBytes(),
      ...?chapterV?.toBytes(),
      ...?chapterQ?.toBytes(),
      ...?chapterF?.toBytes(),
      ...?chapterX?.toBytes(),
    ];
    final length = body.length + 2;
    if (length > 0x03FF) {
      throw ArgumentError.value(length, 'length', 'System journal too long');
    }
    final header =
        (s ? 0x8000 : 0) |
        (chapterD != null ? 0x4000 : 0) |
        (chapterV != null ? 0x2000 : 0) |
        (chapterQ != null ? 0x1000 : 0) |
        (chapterF != null ? 0x0800 : 0) |
        (chapterX != null ? 0x0400 : 0) |
        length;
    return Uint8List.fromList([header >> 8, header & 0xFF, ...body]);
  }

  /// Returns a copy with the given fields replaced.
  MidiRtpSystemJournal copyWith({
    bool? s,
    MidiRtpChapterD? chapterD,
    MidiRtpChapterV? chapterV,
    MidiRtpChapterQ? chapterQ,
    MidiRtpChapterF? chapterF,
    MidiRtpChapterX? chapterX,
  }) => MidiRtpSystemJournal(
    s: s ?? this.s,
    chapterD: chapterD ?? this.chapterD,
    chapterV: chapterV ?? this.chapterV,
    chapterQ: chapterQ ?? this.chapterQ,
    chapterF: chapterF ?? this.chapterF,
    chapterX: chapterX ?? this.chapterX,
  );

  // ...........................................................................
  /// The S bit.
  final bool s;

  /// Chapter D, the simple system commands.
  final MidiRtpChapterD? chapterD;

  /// Chapter V, Active Sense.
  final MidiRtpChapterV? chapterV;

  /// Chapter Q, the sequencer state.
  final MidiRtpChapterQ? chapterQ;

  /// Chapter F, the MIDI Time Code.
  final MidiRtpChapterF? chapterF;

  /// Chapter X, System Exclusive.
  final MidiRtpChapterX? chapterX;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpSystemJournal &&
      other.s == s &&
      other.chapterD == chapterD &&
      other.chapterV == chapterV &&
      other.chapterQ == chapterQ &&
      other.chapterF == chapterF &&
      other.chapterX == chapterX;

  @override
  int get hashCode =>
      Object.hash(s, chapterD, chapterV, chapterQ, chapterF, chapterX);

  @override
  String toString() =>
      'MidiRtpSystemJournal(s: $s, chapterD: $chapterD, '
      'chapterV: $chapterV, chapterQ: $chapterQ, chapterF: $chapterF, '
      'chapterX: $chapterX)';
}
