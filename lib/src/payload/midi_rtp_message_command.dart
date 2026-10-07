// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

part of 'midi_rtp_command.dart';

// #############################################################################
/// A MIDI list command that codes one complete channel voice, system common
/// or system real-time message (RFC 6295 3.2).
///
/// System Exclusive travels as [MidiRtpSysExCommand], because the MIDI list
/// may segment it.
final class MidiRtpMessageCommand extends MidiRtpCommand {
  /// Creates a command for [message], a MIDI 1.0 channel voice or system
  /// common or real-time message.
  const MidiRtpMessageCommand({super.deltaTime, required this.message})
    : assert(
        message is MidiChannelVoice1Message || message is MidiSystemMessage,
      );

  // ...........................................................................
  @override
  MidiRtpMessageCommand withDeltaTime(int deltaTime) =>
      MidiRtpMessageCommand(deltaTime: deltaTime, message: message);

  // ...........................................................................
  /// The message the command codes.
  final MidiMessage message;

  @override
  List<int> get octets => MidiByteEncoder.encode(message)!.bytes;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpMessageCommand &&
      other.deltaTime == deltaTime &&
      other.message == message;

  @override
  int get hashCode => Object.hash(deltaTime, message);

  @override
  String toString() =>
      'MidiRtpMessageCommand(deltaTime: $deltaTime, message: $message)';
}
