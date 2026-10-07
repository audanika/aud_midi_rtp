// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

part of 'midi_rtp_command.dart';

// #############################################################################
/// A delta time without a command at the end of the MIDI list (RFC 6295
/// 3.1).
///
/// It pads a packet with time that is void of commands, or codes on its own
/// that a span of time holds no command.
final class MidiRtpEmptyCommand extends MidiRtpCommand {
  /// Creates an empty command that ends the void time [deltaTime] units
  /// after the previous command.
  const MidiRtpEmptyCommand({super.deltaTime});

  // ...........................................................................
  @override
  MidiRtpEmptyCommand withDeltaTime(int deltaTime) =>
      MidiRtpEmptyCommand(deltaTime: deltaTime);

  // ...........................................................................
  @override
  List<int> get octets => const [];

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpEmptyCommand && other.deltaTime == deltaTime;

  @override
  int get hashCode => Object.hash(MidiRtpEmptyCommand, deltaTime);

  @override
  String toString() => 'MidiRtpEmptyCommand(deltaTime: $deltaTime)';
}
