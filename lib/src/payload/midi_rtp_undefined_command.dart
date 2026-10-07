// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

part of 'midi_rtp_command.dart';

// #############################################################################
/// A MIDI list command that codes an undefined system command: System
/// Common 0xF4 or 0xF5, or System Real-Time 0xF9 or 0xFD (RFC 6295 3.2).
///
/// Streams carry these commands only when the session configuration allows
/// them (RFC 6295 C.1). An undefined System Common command is closed with
/// 0xF7 in the MIDI list; trailing 0xF7 octets of the source are removed
/// before.
final class MidiRtpUndefinedCommand extends MidiRtpCommand {
  /// Creates an undefined command with [status] and a copy of the 7-bit
  /// [data] octets; real-time commands carry no data.
  MidiRtpUndefinedCommand({
    super.deltaTime,
    required this.status,
    Iterable<int> data = const [],
  }) : data = Uint8List.fromList(data.toList()).asUnmodifiableView() {
    assert(statuses.contains(status));
    assert(this.data.every((b) => b <= 0x7F));
    assert(isCommon || this.data.isEmpty);
  }

  // ...........................................................................
  @override
  MidiRtpUndefinedCommand withDeltaTime(int deltaTime) =>
      MidiRtpUndefinedCommand(deltaTime: deltaTime, status: status, data: data);

  // ...........................................................................
  /// The status octet: 0xF4, 0xF5, 0xF9 or 0xFD.
  final int status;

  /// The data octets of a System Common command; cannot be modified.
  final Uint8List data;

  /// Whether the command is an undefined System Common command.
  bool get isCommon => status < 0xF8;

  @override
  List<int> get octets => [
    status,
    if (isCommon) ...[...data, 0xF7],
  ];

  // ...........................................................................
  /// The undefined system status octets.
  static const List<int> statuses = [0xF4, 0xF5, 0xF9, 0xFD];

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpUndefinedCommand &&
      other.deltaTime == deltaTime &&
      other.status == status &&
      MidiRtpEquality.lists(other.data, data);

  @override
  int get hashCode =>
      Object.hash(deltaTime, status, MidiRtpEquality.hash(data));

  @override
  String toString() =>
      'MidiRtpUndefinedCommand(deltaTime: $deltaTime, '
      'status: 0x${status.toRadixString(16)}, '
      'data: ${MidiRtpEquality.hex(data)})';
}
