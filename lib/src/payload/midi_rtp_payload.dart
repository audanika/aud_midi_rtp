// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../journal/midi_rtp_journal.dart';
import '../support/midi_rtp_byte_reader.dart';
import '../support/midi_rtp_equality.dart';
import 'midi_rtp_command.dart';
import 'midi_rtp_command_section.dart';

// #############################################################################
/// The MIDI payload of an RTP MIDI packet: the MIDI command section,
/// optionally followed by the recovery journal (RFC 6295 2.2, Figure 1).
final class MidiRtpPayload {
  /// Creates a payload.
  ///
  /// - [commands] the MIDI list.
  /// - [phantom] the P bit: the status octet of the first channel command
  ///   was not in the source stream.
  /// - [journal] the recovery journal; its presence sets the J bit.
  MidiRtpPayload({
    Iterable<MidiRtpCommand> commands = const [],
    this.phantom = false,
    this.journal,
  }) : commands = List.unmodifiable(commands);

  // ...........................................................................
  /// Reads a payload at the position of [reader].
  ///
  /// Throws a [FormatException] when the payload is malformed.
  factory MidiRtpPayload.read(MidiRtpByteReader reader) {
    final section = MidiRtpCommandSection.read(reader);
    return MidiRtpPayload(
      commands: section.commands,
      phantom: section.phantom,
      journal: section.journal ? MidiRtpJournal.read(reader) : null,
    );
  }

  /// Decodes a payload from [bytes]; octets after it are ignored.
  factory MidiRtpPayload.decode(List<int> bytes) =>
      MidiRtpPayload.read(MidiRtpByteReader(bytes));

  // ...........................................................................
  /// Returns the encoded payload.
  ///
  /// Throws an [ArgumentError] when the MIDI list is malformed or too long.
  Uint8List toBytes() => Uint8List.fromList([
    ...MidiRtpCommandSection.encode(
      commands,
      phantom: phantom,
      journal: journal != null,
    ),
    ...?journal?.toBytes(),
  ]);

  /// Returns a copy with the given fields replaced.
  MidiRtpPayload copyWith({
    Iterable<MidiRtpCommand>? commands,
    bool? phantom,
    MidiRtpJournal? journal,
  }) => MidiRtpPayload(
    commands: commands ?? this.commands,
    phantom: phantom ?? this.phantom,
    journal: journal ?? this.journal,
  );

  // ...........................................................................
  /// The MIDI list; cannot be modified.
  final List<MidiRtpCommand> commands;

  /// The P bit.
  final bool phantom;

  /// The recovery journal.
  final MidiRtpJournal? journal;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpPayload &&
      other.phantom == phantom &&
      other.journal == journal &&
      MidiRtpEquality.lists(other.commands, commands);

  @override
  int get hashCode =>
      Object.hash(phantom, journal, MidiRtpEquality.hash(commands));

  @override
  String toString() =>
      'MidiRtpPayload(commands: $commands, phantom: $phantom, '
      'journal: $journal)';
}
