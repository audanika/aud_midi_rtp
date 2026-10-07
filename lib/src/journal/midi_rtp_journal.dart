// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';
import '../support/midi_rtp_equality.dart';
import 'midi_rtp_channel_journal.dart';
import 'midi_rtp_system_journal.dart';

// #############################################################################
/// The recovery journal of an RTP MIDI packet: a 3-octet header, the
/// optional system journal and the channel journals in ascending channel
/// order (RFC 6295 5, Figures 7 and 8).
///
/// The journal codes the history of the stream since the checkpoint packet,
/// so that a receiver repairs the loss of any packets in between.
final class MidiRtpJournal {
  /// Creates a recovery journal.
  ///
  /// - [s] the S bit: false when the journal codes a command of the
  ///   previous packet.
  /// - [h] the H bit: the stream uses the enhanced Chapter C encoding.
  /// - [checkpoint] the 16-bit sequence number of the checkpoint packet.
  /// - [systemJournal] the system journal (Y bit).
  /// - [channelJournals] up to 16 channel journals in ascending channel
  ///   order (A bit and TOTCHAN).
  MidiRtpJournal({
    this.s = true,
    this.h = false,
    required this.checkpoint,
    this.systemJournal,
    Iterable<MidiRtpChannelJournal> channelJournals = const [],
  }) : channelJournals = List.unmodifiable(channelJournals) {
    assert(checkpoint >= 0 && checkpoint <= 0xFFFF);
    assert(this.channelJournals.length <= 16);
    assert(() {
      for (var i = 1; i < this.channelJournals.length; i++) {
        if (this.channelJournals[i].channel <=
            this.channelJournals[i - 1].channel) {
          return false;
        }
      }
      return true;
    }());
  }

  // ...........................................................................
  /// Reads a journal at the position of [reader].
  factory MidiRtpJournal.read(MidiRtpByteReader reader) {
    final first = reader.readUint8();
    final checkpoint = reader.readUint16();
    final systemJournal = (first & 0x40) != 0
        ? MidiRtpSystemJournal.read(reader)
        : null;
    final channelJournals = [
      if ((first & 0x20) != 0)
        for (var i = 0; i <= (first & 0x0F); i++)
          MidiRtpChannelJournal.read(reader),
    ];
    return MidiRtpJournal(
      s: first >= 0x80,
      h: (first & 0x10) != 0,
      checkpoint: checkpoint,
      systemJournal: systemJournal,
      channelJournals: channelJournals,
    );
  }

  // ...........................................................................
  /// Returns the encoded journal.
  Uint8List toBytes() => Uint8List.fromList([
    (s ? 0x80 : 0) |
        (systemJournal != null ? 0x40 : 0) |
        (channelJournals.isNotEmpty ? 0x20 | (channelJournals.length - 1) : 0) |
        (h ? 0x10 : 0),
    checkpoint >> 8,
    checkpoint & 0xFF,
    ...?systemJournal?.toBytes(),
    for (final channelJournal in channelJournals) ...channelJournal.toBytes(),
  ]);

  /// Returns the channel journal of [channel], or null.
  MidiRtpChannelJournal? channelJournal(int channel) {
    for (final journal in channelJournals) {
      if (journal.channel == channel) return journal;
    }
    return null;
  }

  /// Returns a copy with the given fields replaced.
  MidiRtpJournal copyWith({
    bool? s,
    bool? h,
    int? checkpoint,
    MidiRtpSystemJournal? systemJournal,
    Iterable<MidiRtpChannelJournal>? channelJournals,
  }) => MidiRtpJournal(
    s: s ?? this.s,
    h: h ?? this.h,
    checkpoint: checkpoint ?? this.checkpoint,
    systemJournal: systemJournal ?? this.systemJournal,
    channelJournals: channelJournals ?? this.channelJournals,
  );

  // ...........................................................................
  /// The S bit.
  final bool s;

  /// The H bit: the stream uses the enhanced Chapter C encoding.
  final bool h;

  /// The sequence number of the checkpoint packet.
  final int checkpoint;

  /// The system journal.
  final MidiRtpSystemJournal? systemJournal;

  /// The channel journals in ascending channel order; cannot be modified.
  final List<MidiRtpChannelJournal> channelJournals;

  /// Whether the journal holds neither system nor channel journals.
  bool get isEmpty => systemJournal == null && channelJournals.isEmpty;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpJournal &&
      other.s == s &&
      other.h == h &&
      other.checkpoint == checkpoint &&
      other.systemJournal == systemJournal &&
      MidiRtpEquality.lists(other.channelJournals, channelJournals);

  @override
  int get hashCode => Object.hash(
    s,
    h,
    checkpoint,
    systemJournal,
    MidiRtpEquality.hash(channelJournals),
  );

  @override
  String toString() =>
      'MidiRtpJournal(s: $s, h: $h, checkpoint: $checkpoint, '
      'systemJournal: $systemJournal, channelJournals: $channelJournals)';
}
