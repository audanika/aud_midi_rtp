// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import 'package:aud_midi_standard/aud_midi_standard.dart';

import '../support/midi_rtp_equality.dart';
import 'midi_rtp_sys_ex_kind.dart';

part 'midi_rtp_empty_command.dart';
part 'midi_rtp_message_command.dart';
part 'midi_rtp_sys_ex_command.dart';
part 'midi_rtp_undefined_command.dart';

// #############################################################################
/// One entry of the MIDI list of an RTP MIDI packet: a delta time and the
/// MIDI command field that follows it (RFC 6295 3, Figure 3).
///
/// A command field codes one complete MIDI command, one segment of a System
/// Exclusive command, an undefined system command, or nothing at all at the
/// end of the list (RFC 6295 3.1, 3.2).
sealed class MidiRtpCommand {
  /// Creates a command [deltaTime] RTP timestamp units after the previous
  /// command, or after the RTP timestamp for the first command.
  const MidiRtpCommand({this.deltaTime = 0})
    : assert(deltaTime >= 0 && deltaTime <= 0x0FFFFFFF);

  // ...........................................................................
  /// Returns a copy of this command with [deltaTime].
  MidiRtpCommand withDeltaTime(int deltaTime);

  // ...........................................................................
  /// The decoded delta time in RTP timestamp units.
  final int deltaTime;

  /// The octets of the command field with the status octet, as they appear
  /// in the MIDI list without running status.
  List<int> get octets;
}
