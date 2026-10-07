// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpCommandSection', () {
    MidiRtpMessageCommand message(MidiMessage m, [int deltaTime = 0]) =>
        MidiRtpMessageCommand(deltaTime: deltaTime, message: m);
    const noteOn = MidiNoteOn(channel: 0, note: 0x3C, velocity: 0x64);
    const noteOn2 = MidiNoteOn(channel: 0, note: 0x3E, velocity: 0x5A);

    ({List<MidiRtpCommand> commands, bool phantom, bool journal}) read(
      List<int> bytes,
    ) => MidiRtpCommandSection.read(MidiRtpByteReader(bytes));

    void roundTrip(List<MidiRtpCommand> commands, List<int> bytes) {
      expect(MidiRtpCommandSection.encode(commands), equals(bytes));
      expect(read(bytes).commands, equals(commands));
    }

    group('encode(commands, phantom, journal)', () {
      test('codes an empty list with a 1-octet header', () {
        expect(MidiRtpCommandSection.encode([]), equals([0x00]));
        expect(
          MidiRtpCommandSection.encode([], journal: true, phantom: true),
          equals([0x50]),
        );
      });

      test('codes a single command without delta time (Z = 0)', () {
        roundTrip([message(noteOn)], [0x03, 0x90, 0x3C, 0x64]);
      });

      test('uses running status for the following channel commands', () {
        roundTrip(
          [message(noteOn), message(noteOn2, 10)],
          [0x06, 0x90, 0x3C, 0x64, 0x0A, 0x3E, 0x5A],
        );
      });

      test('keeps running status across System Real-Time commands', () {
        roundTrip(
          [message(noteOn), message(const MidiTimingClock()), message(noteOn2)],
          [0x08, 0x90, 0x3C, 0x64, 0x00, 0xF8, 0x00, 0x3E, 0x5A],
        );
      });

      test('cancels running status with System Common commands', () {
        roundTrip(
          [
            message(noteOn),
            message(const MidiSongSelect(song: 5)),
            message(noteOn2),
          ],
          [0x0A, 0x90, 0x3C, 0x64, 0x00, 0xF3, 0x05, 0x00, 0x90, 0x3E, 0x5A],
        );
      });

      test('cancels running status with System Exclusive', () {
        roundTrip(
          [
            message(noteOn),
            MidiRtpSysExCommand(kind: MidiRtpSysExKind.complete, data: [1]),
            message(noteOn2),
          ],
          [
            0x0B,
            0x90,
            0x3C,
            0x64,
            0x00,
            0xF0,
            0x01,
            0xF7,
            0x00,
            0x90,
            0x3E,
            0x5A,
          ],
        );
      });

      test('codes a first delta time when it is not 0 (Z = 1)', () {
        roundTrip([message(noteOn, 5)], [0x24, 0x05, 0x90, 0x3C, 0x64]);
      });

      test('codes a final delta time without command', () {
        roundTrip(
          [message(noteOn), const MidiRtpEmptyCommand(deltaTime: 0x80)],
          [0x05, 0x90, 0x3C, 0x64, 0x81, 0x00],
        );
      });

      test('codes a list of a single delta time (Z = 1)', () {
        roundTrip([const MidiRtpEmptyCommand(deltaTime: 3)], [0x21, 0x03]);
        roundTrip([const MidiRtpEmptyCommand()], [0x21, 0x00]);
      });

      test('uses the 2-octet header for lists over 15 octets', () {
        final commands = [
          for (var channel = 0; channel < 6; channel++)
            message(MidiNoteOn(channel: channel, note: 1, velocity: 2)),
        ];
        final bytes = MidiRtpCommandSection.encode(commands, journal: true);
        // 6 commands of 3 octets and 5 delta times.
        expect(bytes.sublist(0, 2), equals([0xC0, 23]));
        expect(read(bytes).commands, equals(commands));
        expect(read(bytes).journal, isTrue);
      });

      test('codes a 12-bit LEN', () {
        final commands = [
          MidiRtpSysExCommand(
            kind: MidiRtpSysExKind.complete,
            data: List.filled(0x0FFF - 2, 1),
          ),
        ];
        final bytes = MidiRtpCommandSection.encode(commands);
        expect(bytes.sublist(0, 2), equals([0x8F, 0xFF]));
        expect(read(bytes).commands, equals(commands));
      });

      test('rejects an empty command before the end', () {
        expect(
          () => MidiRtpCommandSection.encode([
            const MidiRtpEmptyCommand(),
            message(noteOn),
          ]),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              'Only the last command may be empty',
            ),
          ),
        );
      });

      test('rejects lists over 4095 octets', () {
        expect(
          () => MidiRtpCommandSection.encode([
            MidiRtpSysExCommand(
              kind: MidiRtpSysExKind.complete,
              data: List.filled(0x0FFF, 1),
            ),
          ]),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              'The MIDI list exceeds 4095 octets',
            ),
          ),
        );
      });
    });

    group('read(reader)', () {
      test('reads the B, J, Z and P flags', () {
        final section = read([0x70, 0x00, 0x99]);
        expect(section.journal, isTrue);
        expect(section.phantom, isTrue);
        expect(section.commands, isEmpty);
      });

      test('stops at LEN', () {
        final reader = MidiRtpByteReader([0x03, 0x90, 0x3C, 0x64, 0xAA]);
        MidiRtpCommandSection.read(reader);
        expect(reader.readUint8(), 0xAA);
      });

      test('accepts a long header for a short list', () {
        expect(
          read([0x80, 0x03, 0x90, 0x3C, 0x64]).commands,
          equals([message(noteOn)]),
        );
      });

      test('accepts every form of a delta time', () {
        expect(
          read([
            0x09,
            0x90,
            0x3C,
            0x64,
            0x80,
            0x80,
            0x80,
            0x00,
            0x3E,
            0x5A,
          ]).commands,
          equals([message(noteOn), message(noteOn2)]),
        );
      });

      test('decodes every MIDI 1.0 command type', () {
        final messages = <MidiMessage>[
          const MidiNoteOff(channel: 1, note: 2, velocity: 3),
          const MidiNoteOn(channel: 1, note: 2, velocity: 0),
          const MidiPolyPressure(channel: 2, note: 3, pressure: 4),
          const MidiControlChange(channel: 3, controller: 4, value: 5),
          const MidiProgramChange(channel: 4, program: 5),
          const MidiChannelPressure(channel: 5, pressure: 6),
          const MidiPitchBend(channel: 6, value: 0x1234),
          const MidiTimeCodeQuarterFrame(piece: 3, value: 9),
          const MidiSongPositionPointer(position: 300),
          const MidiSongSelect(song: 7),
          const MidiTuneRequest(),
          const MidiTimingClock(),
          const MidiStart(),
          const MidiContinue(),
          const MidiStop(),
          const MidiActiveSensing(),
          const MidiSystemReset(),
        ];
        final commands = [for (final m in messages) message(m, 1)];
        final bytes = MidiRtpCommandSection.encode(commands);
        expect(read(bytes).commands, equals(commands));
      });

      test('decodes System Exclusive segments', () {
        // RFC 6295 Figure 6: a three-segment segmentation and a cancel.
        expect(
          read([
            0x80, 0x18, 0xF0, 0x01, 0x02, 0xF0, 0x00, 0xF7, 0x03, 0x04, //
            0xF0, //
            0x00, 0xF7, 0x05, 0x06, 0x07, 0x08, 0xF7, 0x00, 0xF7, 0xF4, //
            0x00, 0xF0, 0x09, 0xF5, 0x00, //
          ]).commands,
          equals([
            MidiRtpSysExCommand(kind: MidiRtpSysExKind.first, data: [1, 2]),
            MidiRtpSysExCommand(kind: MidiRtpSysExKind.middle, data: [3, 4]),
            MidiRtpSysExCommand(
              kind: MidiRtpSysExKind.last,
              data: [5, 6, 7, 8],
            ),
            MidiRtpSysExCommand(kind: MidiRtpSysExKind.cancel),
            MidiRtpSysExCommand(
              kind: MidiRtpSysExKind.complete,
              data: [9],
              droppedF7: true,
            ),
            const MidiRtpEmptyCommand(),
          ]),
        );
        expect(
          read([0x03, 0xF7, 0x01, 0xF5]).commands,
          equals([
            MidiRtpSysExCommand(
              kind: MidiRtpSysExKind.last,
              data: [1],
              droppedF7: true,
            ),
          ]),
        );
      });

      test('decodes undefined system commands', () {
        final commands = [
          MidiRtpUndefinedCommand(status: 0xF4, data: [1, 2]),
          MidiRtpUndefinedCommand(deltaTime: 1, status: 0xF5),
          MidiRtpUndefinedCommand(deltaTime: 2, status: 0xF9),
          MidiRtpUndefinedCommand(deltaTime: 3, status: 0xFD),
        ];
        roundTrip(commands, [
          0x0B, 0xF4, 0x01, 0x02, 0xF7, 0x01, 0xF5, 0xF7, 0x02, 0xF9, //
          0x03, 0xFD, //
        ]);
      });

      test('keeps running status across undefined real-time commands', () {
        expect(
          read([
            0x08,
            0x90,
            0x3C,
            0x64,
            0x00,
            0xF9,
            0x00,
            0x3E,
            0x5A,
          ]).commands.last,
          message(noteOn2),
        );
      });

      for (final bad in <String, List<int>>{
        'Data octet without running status': [0x02, 0x3C, 0x64],
        'Status octet inside a command': [0x03, 0x90, 0x3C, 0x90],
        'Illegal System Exclusive segment': [0x03, 0xF0, 0x01, 0xF4],
        'Undefined command not closed by 0xF7': [0x03, 0xF4, 0x01, 0xF8],
        'Unexpected end of data': [0x05, 0x90, 0x3C],
      }.entries) {
        test('rejects: ${bad.key}', () {
          expect(
            () => read(bad.value),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                startsWith(bad.key),
              ),
            ),
          );
        });
      }

      test('rejects a cancel sublist with data', () {
        expect(
          () => read([0x04, 0xF7, 0x01, 0xF4]),
          throwsA(isA<FormatException>()),
        );
      });

      test('rejects a running status after System Common', () {
        expect(
          () => read([0x07, 0x90, 0x3C, 0x64, 0x00, 0xF6, 0x00, 0x3E]),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('maxLength', () {
      test('is the largest 12-bit LEN', () {
        expect(MidiRtpCommandSection.maxLength, 4095);
      });
    });
  });
}
