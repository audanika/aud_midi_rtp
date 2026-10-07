// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpCommand', () {
    final commands = <MidiRtpCommand>[
      const MidiRtpMessageCommand(
        message: MidiNoteOn(channel: 0, note: 60, velocity: 100),
      ),
      MidiRtpSysExCommand(kind: MidiRtpSysExKind.complete, data: [1]),
      MidiRtpUndefinedCommand(status: 0xF9),
      const MidiRtpEmptyCommand(),
    ];

    group('deltaTime', () {
      test('defaults to 0', () {
        expect([for (final c in commands) c.deltaTime], equals([0, 0, 0, 0]));
      });
    });

    group('withDeltaTime(deltaTime)', () {
      test('keeps the command and replaces the delta time', () {
        for (final command in commands) {
          final moved = command.withDeltaTime(9);
          expect(moved.deltaTime, 9);
          expect(moved.octets, equals(command.octets));
          expect(moved.runtimeType, command.runtimeType);
        }
      });
    });

    group('MidiRtpCommand(deltaTime)', () {
      test('rejects delta times beyond 28 bits', () {
        expect(
          () => MidiRtpEmptyCommand(deltaTime: MidiRtpDeltaTime.max + 1),
          throwsA(isA<AssertionError>()),
        );
      });
    });
  });
}
