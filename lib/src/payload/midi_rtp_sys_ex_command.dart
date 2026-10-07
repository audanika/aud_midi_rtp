// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

part of 'midi_rtp_command.dart';

// #############################################################################
/// A MIDI list command that codes a System Exclusive command verbatim or
/// one of its segments (RFC 6295 3.2, Figures 5 and 6).
final class MidiRtpSysExCommand extends MidiRtpCommand {
  /// Creates a command of [kind] with a copy of the 7-bit [data] octets
  /// between the head and the tail status octet.
  ///
  /// [droppedF7] marks a complete command or last segment whose source
  /// dropped the closing 0xF7; it is coded with the tail 0xF5. A cancel
  /// sublist carries no data.
  MidiRtpSysExCommand({
    super.deltaTime,
    required this.kind,
    Iterable<int> data = const [],
    this.droppedF7 = false,
  }) : data = Uint8List.fromList(data.toList()).asUnmodifiableView() {
    assert(this.data.every((b) => b <= 0x7F));
    assert(kind != MidiRtpSysExKind.cancel || this.data.isEmpty);
    assert(
      !droppedF7 ||
          kind == MidiRtpSysExKind.complete ||
          kind == MidiRtpSysExKind.last,
    );
  }

  // ...........................................................................
  @override
  MidiRtpSysExCommand withDeltaTime(int deltaTime) => MidiRtpSysExCommand(
    deltaTime: deltaTime,
    kind: kind,
    data: data,
    droppedF7: droppedF7,
  );

  // ...........................................................................
  /// The position of the segment in its command.
  final MidiRtpSysExKind kind;

  /// The data octets between the status octets; cannot be modified.
  final Uint8List data;

  /// Whether the source dropped the closing 0xF7 of the command.
  final bool droppedF7;

  @override
  List<int> get octets => [
    kind.head,
    ...data,
    if (droppedF7) MidiRtpSysExKind.droppedF7Tail else kind.tail,
  ];

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpSysExCommand &&
      other.deltaTime == deltaTime &&
      other.kind == kind &&
      other.droppedF7 == droppedF7 &&
      MidiRtpEquality.lists(other.data, data);

  @override
  int get hashCode =>
      Object.hash(deltaTime, kind, droppedF7, MidiRtpEquality.hash(data));

  @override
  String toString() =>
      'MidiRtpSysExCommand(deltaTime: $deltaTime, kind: ${kind.name}, '
      'data: ${MidiRtpEquality.hex(data)}, droppedF7: $droppedF7)';
}
