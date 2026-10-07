// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';
import 'midi_rtp_chapter_a.dart';
import 'midi_rtp_chapter_c.dart';
import 'midi_rtp_chapter_e.dart';
import 'midi_rtp_chapter_m.dart';
import 'midi_rtp_chapter_n.dart';
import 'midi_rtp_chapter_p.dart';
import 'midi_rtp_chapter_t.dart';
import 'midi_rtp_chapter_w.dart';

// #############################################################################
/// A channel journal: the recovery data of one MIDI voice channel, a
/// 3-octet header with the chapter table of contents followed by the
/// chapters P, C, M, W, N, E, T and A (RFC 6295 5, Figure 9).
final class MidiRtpChannelJournal {
  /// Creates a channel journal for [channel], 0 to 15.
  ///
  /// - [s] the S bit: false when a chapter codes a command of the previous
  ///   packet.
  /// - [h] the H bit: controllers of the channel use the enhanced Chapter C
  ///   encoding.
  /// - [chapterP] to [chapterA] the chapters; null ones are left out.
  const MidiRtpChannelJournal({
    this.s = true,
    required this.channel,
    this.h = false,
    this.chapterP,
    this.chapterC,
    this.chapterM,
    this.chapterW,
    this.chapterN,
    this.chapterE,
    this.chapterT,
    this.chapterA,
  }) : assert(channel >= 0 && channel <= 15);

  // ...........................................................................
  /// Reads a channel journal at the position of [reader]; the LENGTH field
  /// bounds the chapters and octets after them are skipped.
  factory MidiRtpChannelJournal.read(MidiRtpByteReader reader) {
    final first = reader.readUint8();
    final length = (first & 0x03) << 8 | reader.readUint8();
    final toc = reader.readUint8();
    if (length < 3) {
      throw FormatException('Channel journal LENGTH $length is too small');
    }
    final body = reader.take(length - 3);
    T? chapter<T>(int mask, T Function(MidiRtpByteReader) read) =>
        (toc & mask) != 0 ? read(body) : null;
    return MidiRtpChannelJournal(
      s: first >= 0x80,
      channel: (first >> 3) & 0x0F,
      h: (first & 0x04) != 0,
      chapterP: chapter(0x80, MidiRtpChapterP.read),
      chapterC: chapter(0x40, MidiRtpChapterC.read),
      chapterM: chapter(0x20, MidiRtpChapterM.read),
      chapterW: chapter(0x10, MidiRtpChapterW.read),
      chapterN: chapter(0x08, MidiRtpChapterN.read),
      chapterE: chapter(0x04, MidiRtpChapterE.read),
      chapterT: chapter(0x02, MidiRtpChapterT.read),
      chapterA: chapter(0x01, MidiRtpChapterA.read),
    );
  }

  // ...........................................................................
  /// Returns the encoded channel journal.
  ///
  /// Throws an [ArgumentError] when it exceeds the 1023 octets the LENGTH
  /// field can code.
  Uint8List toBytes() {
    final body = <int>[
      ...?chapterP?.toBytes(),
      ...?chapterC?.toBytes(),
      ...?chapterM?.toBytes(),
      ...?chapterW?.toBytes(),
      ...?chapterN?.toBytes(),
      ...?chapterE?.toBytes(),
      ...?chapterT?.toBytes(),
      ...?chapterA?.toBytes(),
    ];
    final length = body.length + 3;
    if (length > 0x03FF) {
      throw ArgumentError.value(
        length,
        'length',
        'Channel journal $channel is too long',
      );
    }
    return Uint8List.fromList([
      (s ? 0x80 : 0) | channel << 3 | (h ? 0x04 : 0) | length >> 8,
      length & 0xFF,
      (chapterP != null ? 0x80 : 0) |
          (chapterC != null ? 0x40 : 0) |
          (chapterM != null ? 0x20 : 0) |
          (chapterW != null ? 0x10 : 0) |
          (chapterN != null ? 0x08 : 0) |
          (chapterE != null ? 0x04 : 0) |
          (chapterT != null ? 0x02 : 0) |
          (chapterA != null ? 0x01 : 0),
      ...body,
    ]);
  }

  /// Returns a copy with the given fields replaced.
  MidiRtpChannelJournal copyWith({
    bool? s,
    int? channel,
    bool? h,
    MidiRtpChapterP? chapterP,
    MidiRtpChapterC? chapterC,
    MidiRtpChapterM? chapterM,
    MidiRtpChapterW? chapterW,
    MidiRtpChapterN? chapterN,
    MidiRtpChapterE? chapterE,
    MidiRtpChapterT? chapterT,
    MidiRtpChapterA? chapterA,
  }) => MidiRtpChannelJournal(
    s: s ?? this.s,
    channel: channel ?? this.channel,
    h: h ?? this.h,
    chapterP: chapterP ?? this.chapterP,
    chapterC: chapterC ?? this.chapterC,
    chapterM: chapterM ?? this.chapterM,
    chapterW: chapterW ?? this.chapterW,
    chapterN: chapterN ?? this.chapterN,
    chapterE: chapterE ?? this.chapterE,
    chapterT: chapterT ?? this.chapterT,
    chapterA: chapterA ?? this.chapterA,
  );

  // ...........................................................................
  /// The S bit.
  final bool s;

  /// The MIDI channel, 0 to 15.
  final int channel;

  /// The H bit: the channel uses the enhanced Chapter C encoding.
  final bool h;

  /// Chapter P, the program change.
  final MidiRtpChapterP? chapterP;

  /// Chapter C, the control changes.
  final MidiRtpChapterC? chapterC;

  /// Chapter M, the parameter system.
  final MidiRtpChapterM? chapterM;

  /// Chapter W, the pitch wheel.
  final MidiRtpChapterW? chapterW;

  /// Chapter N, the notes.
  final MidiRtpChapterN? chapterN;

  /// Chapter E, the note command extras.
  final MidiRtpChapterE? chapterE;

  /// Chapter T, the channel aftertouch.
  final MidiRtpChapterT? chapterT;

  /// Chapter A, the poly aftertouch.
  final MidiRtpChapterA? chapterA;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpChannelJournal &&
      other.s == s &&
      other.channel == channel &&
      other.h == h &&
      other.chapterP == chapterP &&
      other.chapterC == chapterC &&
      other.chapterM == chapterM &&
      other.chapterW == chapterW &&
      other.chapterN == chapterN &&
      other.chapterE == chapterE &&
      other.chapterT == chapterT &&
      other.chapterA == chapterA;

  @override
  int get hashCode => Object.hash(
    s,
    channel,
    h,
    chapterP,
    chapterC,
    chapterM,
    chapterW,
    chapterN,
    chapterE,
    chapterT,
    chapterA,
  );

  @override
  String toString() =>
      'MidiRtpChannelJournal(s: $s, channel: $channel, h: $h, '
      'chapterP: $chapterP, chapterC: $chapterC, chapterM: $chapterM, '
      'chapterW: $chapterW, chapterN: $chapterN, chapterE: $chapterE, '
      'chapterT: $chapterT, chapterA: $chapterA)';
}
