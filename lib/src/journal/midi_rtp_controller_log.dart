// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';
import 'midi_rtp_controller_tool.dart';

// #############################################################################
/// A controller log of Chapter C: one tool's view of a Control Change
/// command (RFC 6295 A.3.2, Figures A.3.2 and A.3.3).
final class MidiRtpControllerLog {
  /// Creates a log.
  ///
  /// - [s] the S bit: false when the command is in the previous packet.
  /// - [number] the controller number.
  /// - [tool] the tool that codes [value].
  /// - [value] the controller value for the value tool, else the 6-bit
  ///   toggle or command count.
  const MidiRtpControllerLog({
    this.s = true,
    required this.number,
    required this.tool,
    required this.value,
  }) : assert(number >= 0 && number <= 0x7F),
       assert(
         value >= 0 &&
             value <= (tool == MidiRtpControllerTool.value ? 0x7F : 0x3F),
       );

  // ...........................................................................
  /// Reads a log at the position of [reader].
  factory MidiRtpControllerLog.read(MidiRtpByteReader reader) {
    final first = reader.readUint8();
    final second = reader.readUint8();
    final tool = second < 0x80
        ? MidiRtpControllerTool.value
        : (second & 0x40) != 0
        ? MidiRtpControllerTool.count
        : MidiRtpControllerTool.toggle;
    return MidiRtpControllerLog(
      s: first >= 0x80,
      number: first & 0x7F,
      tool: tool,
      value: second & tool.max,
    );
  }

  // ...........................................................................
  /// Returns the encoded log.
  Uint8List toBytes() => Uint8List.fromList([
    (s ? 0x80 : 0) | number,
    switch (tool) {
      MidiRtpControllerTool.value => value,
      MidiRtpControllerTool.toggle => 0x80 | value,
      MidiRtpControllerTool.count => 0xC0 | value,
    },
  ]);

  /// Returns a copy with the given fields replaced.
  MidiRtpControllerLog copyWith({
    bool? s,
    int? number,
    MidiRtpControllerTool? tool,
    int? value,
  }) => MidiRtpControllerLog(
    s: s ?? this.s,
    number: number ?? this.number,
    tool: tool ?? this.tool,
    value: value ?? this.value,
  );

  // ...........................................................................
  /// The S bit.
  final bool s;

  /// The controller number.
  final int number;

  /// The tool that codes [value].
  final MidiRtpControllerTool tool;

  /// The value, toggle count or command count.
  final int value;

  // ...........................................................................
  /// The number of encoded bytes.
  static const int length = 2;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpControllerLog &&
      other.s == s &&
      other.number == number &&
      other.tool == tool &&
      other.value == value;

  @override
  int get hashCode => Object.hash(s, number, tool, value);

  @override
  String toString() =>
      'MidiRtpControllerLog(s: $s, number: $number, tool: ${tool.name}, '
      'value: $value)';
}
