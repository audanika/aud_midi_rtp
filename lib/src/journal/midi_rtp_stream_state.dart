// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

import '../payload/midi_rtp_sys_ex_kind.dart';
import 'midi_rtp_channel_state.dart';
import 'midi_rtp_system_state.dart';

// #############################################################################
/// The MIDI state of one RTP MIDI stream, the 16 voice channels and the
/// system commands, as the recovery journal protects it (RFC 6295 A.1, B).
///
/// A sender keeps its session history in it, a receiver its model of the
/// stream; applied to the messages a receiver renders, it serves as a
/// renderer whose [snapshot] tests compare with the sender's. Reset State
/// commands (System Reset and the GM and DLS System Exclusive commands)
/// reset every channel and the active system state.
final class MidiRtpStreamState {
  /// Creates the state of a stream at power-up.
  ///
  /// - [isEnhanced] selects the controllers that use the enhanced Chapter C
  ///   encoding per channel.
  /// - [countsSysEx] excludes System Exclusive commands from the Chapter X
  ///   COUNT.
  MidiRtpStreamState({
    bool Function(int channel, int controller)? isEnhanced,
    bool Function(List<int> data)? countsSysEx,
  }) : channels = List.unmodifiable([
         for (var channel = 0; channel < 16; channel++)
           MidiRtpChannelState(
             channel: channel,
             enhancedControllers: {
               if (isEnhanced != null)
                 for (var c = 0; c < 128; c++)
                   if (isEnhanced(channel, c)) c,
             },
           ),
       ]),
       system = MidiRtpSystemState(countsSysEx: countsSysEx);

  // ...........................................................................
  /// Applies [message] of the packet [seq] at [time].
  ///
  /// Channel voice, system common and real-time messages and complete
  /// System Exclusive apply; other messages have no MIDI 1.0 byte form and
  /// are ignored.
  void apply(
    MidiMessage message, {
    int seq = 0,
    MidiTime time = MidiTime.zero,
  }) {
    final order = ++_order;
    switch (message) {
      case MidiChannelVoice1Message():
        channels[message.channel].apply(
          message,
          seq: seq,
          order: order,
          time: time,
        );
      case MidiSystemReset():
        reset();
        system.apply(message, seq: seq, order: order);
      case MidiSystemMessage():
        system.apply(message, seq: seq, order: order);
      case MidiSysEx(:final data):
        applySysEx(MidiRtpSysExKind.complete, data, seq: seq);
      default:
        break;
    }
  }

  /// Applies a System Exclusive command or segment and returns the data of
  /// the command it completes, or null (see
  /// [MidiRtpSystemState.applySysEx]).
  List<int>? applySysEx(
    MidiRtpSysExKind kind,
    List<int> data, {
    bool droppedF7 = false,
    int seq = 0,
    bool count = true,
  }) {
    final completed = system.applySysEx(
      kind,
      data,
      droppedF7: droppedF7,
      seq: seq,
      order: ++_order,
      count: count,
    );
    if (completed != null && MidiRtpSystemState.isResetState(completed)) {
      reset(keepLastSysEx: true);
    }
    return completed;
  }

  /// Applies an undefined system command (see
  /// [MidiRtpSystemState.applyUndefined]).
  void applyUndefined(int status, List<int> data, {int seq = 0}) {
    ++_order;
    system.applyUndefined(status, data, seq: seq);
  }

  /// Applies a Reset State command to every channel and the system state;
  /// [keepLastSysEx] keeps the System Exclusive command that caused it.
  void reset({bool keepLastSysEx = false}) {
    for (final channel in channels) {
      channel.reset();
    }
    system.reset(keepLastSysEx: keepLastSysEx);
  }

  /// Drops history the journal no longer needs before [checkpoint] (see
  /// [MidiRtpChannelState.trim] and [MidiRtpSystemState.trim]).
  void trim(
    int checkpoint, {
    bool Function(int channel, int controller)? keepController,
    bool Function(List<int> data)? keepSysEx,
  }) {
    for (final channel in channels) {
      channel.trim(
        checkpoint,
        keep: keepController == null
            ? null
            : (c) => keepController(channel.channel, c),
      );
    }
    system.trim(checkpoint, keep: keepSysEx);
  }

  // ...........................................................................
  /// The states of the voice channels 0 to 15.
  final List<MidiRtpChannelState> channels;

  /// The state of the system commands.
  final MidiRtpSystemState system;

  /// Whether a note sounds on any channel.
  bool get hasSoundingNotes => channels.any((c) => c.hasSoundingNotes);

  /// Returns the rendered state for comparisons: the snapshots of the
  /// channels that left power-up and of the system.
  Map<String, Object?> snapshot() => {
    for (final channel in channels)
      if (channel.snapshot().isNotEmpty)
        '${channel.channel}': channel.snapshot(),
    'system': system.snapshot(),
  };

  // ...........................................................................
  int _order = 0;
}
