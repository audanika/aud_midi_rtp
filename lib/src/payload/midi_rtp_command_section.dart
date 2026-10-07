// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import 'package:aud_midi_standard/aud_midi_standard.dart';

import '../support/midi_rtp_byte_reader.dart';
import 'midi_rtp_command.dart';
import 'midi_rtp_delta_time.dart';
import 'midi_rtp_sys_ex_kind.dart';

// #############################################################################
/// Codes the MIDI command section of an RTP MIDI payload (RFC 6295 3,
/// Figures 2 and 3): the B, J, Z and P flags, the 4- or 12-bit LEN field
/// and the MIDI list of delta times and commands.
///
/// Encoding uses running status for every channel command that may use it
/// and the short header when the list fits in 15 octets. Decoding accepts
/// every legal form: long headers for short lists, any delta time form,
/// running status, System Exclusive segments, undefined system commands and
/// a final delta time without a command (RFC 6295 3.1, 3.2).
abstract final class MidiRtpCommandSection {
  // ...........................................................................
  /// Encodes [commands] into a command section.
  ///
  /// - [phantom] sets the P bit: the status octet of the first channel
  ///   command was not in the source stream (RFC 6295 3.2).
  /// - [journal] sets the J bit: a journal section follows.
  ///
  /// Throws an [ArgumentError] when an empty command is not the last one or
  /// the MIDI list exceeds [maxLength] octets.
  static Uint8List encode(
    List<MidiRtpCommand> commands, {
    bool phantom = false,
    bool journal = false,
  }) {
    final z =
        commands.isNotEmpty &&
        (commands.first.deltaTime != 0 ||
            commands.first is MidiRtpEmptyCommand);
    final list = _encodeList(commands, z: z);
    if (list.length > maxLength) {
      throw ArgumentError.value(
        list.length,
        'commands',
        'The MIDI list exceeds $maxLength octets',
      );
    }
    final flags = (journal ? 0x40 : 0) | (z ? 0x20 : 0) | (phantom ? 0x10 : 0);
    return Uint8List.fromList([
      if (list.length > 0x0F) ...[
        0x80 | flags | list.length >> 8,
        list.length & 0xFF,
      ] else
        flags | list.length,
      ...list,
    ]);
  }

  // ...........................................................................
  /// Reads a command section at the position of [reader].
  ///
  /// Returns the commands, the P bit and the J bit. Throws a
  /// [FormatException] when the section is malformed.
  static ({List<MidiRtpCommand> commands, bool phantom, bool journal}) read(
    MidiRtpByteReader reader,
  ) {
    final first = reader.readUint8();
    var length = first & 0x0F;
    if ((first & 0x80) != 0) length = (length << 8) | reader.readUint8();
    return (
      commands: _readList(reader.take(length), z: (first & 0x20) != 0),
      phantom: (first & 0x10) != 0,
      journal: (first & 0x40) != 0,
    );
  }

  // ...........................................................................
  /// The largest MIDI list the 12-bit LEN field can code, in octets.
  static const int maxLength = 0x0FFF;

  // ...........................................................................
  static List<int> _encodeList(
    List<MidiRtpCommand> commands, {
    required bool z,
  }) {
    final list = <int>[];
    int? running;
    for (var i = 0; i < commands.length; i++) {
      final command = commands[i];
      if (command is MidiRtpEmptyCommand && i != commands.length - 1) {
        throw ArgumentError.value(
          commands,
          'commands',
          'Only the last command may be empty',
        );
      }
      if (i > 0 || z) list.addAll(MidiRtpDeltaTime.encode(command.deltaTime));
      final octets = command.octets;
      if (octets.isEmpty) continue;
      final status = octets.first;
      if (status < 0xF0) {
        list.addAll(status == running ? octets.skip(1) : octets);
        running = status;
      } else {
        list.addAll(octets);
        if (status < 0xF8) running = null;
      }
    }
    return list;
  }

  // ...........................................................................
  static List<MidiRtpCommand> _readList(
    MidiRtpByteReader list, {
    required bool z,
  }) {
    final commands = <MidiRtpCommand>[];
    final parser = MidiByteParser();
    int? running;
    var first = true;
    while (!list.isAtEnd) {
      final deltaTime = first && !z ? 0 : MidiRtpDeltaTime.read(list);
      first = false;
      if (list.isAtEnd) {
        commands.add(MidiRtpEmptyCommand(deltaTime: deltaTime));
        break;
      }
      int status;
      if (list.peek() < 0x80) {
        if (running == null) {
          throw const FormatException('Data octet without running status');
        }
        status = running;
      } else {
        status = list.readUint8();
      }
      if (status < 0xF0) running = status;
      if (status >= 0xF0 && status < 0xF8) running = null;
      commands.add(_readCommand(list, status, deltaTime, parser));
    }
    return commands;
  }

  // ...........................................................................
  static MidiRtpCommand _readCommand(
    MidiRtpByteReader list,
    int status,
    int deltaTime,
    MidiByteParser parser,
  ) {
    switch (status) {
      case 0xF0:
      case 0xF7:
        return _readSysEx(list, status, deltaTime);
      case 0xF4:
      case 0xF5:
        final data = _readData(list);
        if (list.readUint8() != 0xF7) {
          throw const FormatException('Undefined command not closed by 0xF7');
        }
        return MidiRtpUndefinedCommand(
          deltaTime: deltaTime,
          status: status,
          data: data,
        );
      case 0xF9:
      case 0xFD:
        return MidiRtpUndefinedCommand(deltaTime: deltaTime, status: status);
    }
    final octets = [status];
    for (var i = 0; i < _dataLength(status); i++) {
      final data = list.readUint8();
      if (data > 0x7F) {
        throw FormatException('Status octet inside a command', data);
      }
      octets.add(data);
    }
    return MidiRtpMessageCommand(
      deltaTime: deltaTime,
      message: parser.add(octets).single.message,
    );
  }

  // ...........................................................................
  static MidiRtpSysExCommand _readSysEx(
    MidiRtpByteReader list,
    int head,
    int deltaTime,
  ) {
    final data = _readData(list);
    final tail = list.readUint8();
    final kind = switch ((head, tail)) {
      (0xF0, 0xF7) || (0xF0, 0xF5) => MidiRtpSysExKind.complete,
      (0xF0, 0xF0) => MidiRtpSysExKind.first,
      (0xF7, 0xF0) => MidiRtpSysExKind.middle,
      (0xF7, 0xF7) || (0xF7, 0xF5) => MidiRtpSysExKind.last,
      (0xF7, 0xF4) when data.isEmpty => MidiRtpSysExKind.cancel,
      _ => throw FormatException('Illegal System Exclusive segment', tail),
    };
    return MidiRtpSysExCommand(
      deltaTime: deltaTime,
      kind: kind,
      data: data,
      droppedF7: tail == MidiRtpSysExKind.droppedF7Tail,
    );
  }

  // ...........................................................................
  static List<int> _readData(MidiRtpByteReader list) {
    final data = <int>[];
    while (list.peek() < 0x80) {
      data.add(list.readUint8());
    }
    return data;
  }

  // ...........................................................................
  static int _dataLength(int status) => switch (status) {
    < 0xC0 => 2,
    < 0xE0 => 1,
    < 0xF0 => 2,
    0xF1 || 0xF3 => 1,
    0xF2 => 2,
    _ => 0,
  };
}
