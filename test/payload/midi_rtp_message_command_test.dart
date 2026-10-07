// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpMessageCommand', () {
    const command = MidiRtpMessageCommand(
      deltaTime: 3,
      message: MidiControlChange(channel: 2, controller: 7, value: 100),
    );

    group('octets', () {
      test('codes the message with its status octet', () {
        expect(command.octets, equals([0xB2, 7, 100]));
        expect(
          const MidiRtpMessageCommand(message: MidiTimingClock()).octets,
          equals([0xF8]),
        );
        expect(
          const MidiRtpMessageCommand(
            message: MidiSongPositionPointer(position: 0x81),
          ).octets,
          equals([0xF2, 0x01, 0x01]),
        );
      });
    });

    group('MidiRtpMessageCommand(message)', () {
      test('rejects messages without a MIDI 1.0 command form', () {
        expect(
          () => MidiRtpMessageCommand(message: MidiSysEx([1])),
          throwsA(isA<AssertionError>()),
        );
      });
    });

    group('withDeltaTime(deltaTime)', () {
      test('replaces the delta time', () {
        expect(command.withDeltaTime(0).deltaTime, 0);
        expect(command.withDeltaTime(0).message, command.message);
      });
    });

    group('==, hashCode, toString', () {
      test('compare by value', () {
        const same = MidiRtpMessageCommand(
          deltaTime: 3,
          message: MidiControlChange(channel: 2, controller: 7, value: 100),
        );
        expect(command, same);
        expect(command.hashCode, same.hashCode);
        expect(command == command.withDeltaTime(4), isFalse);
        expect(
          command ==
              const MidiRtpMessageCommand(
                deltaTime: 3,
                message: MidiTimingClock(),
              ),
          isFalse,
        );
        expect(command.toString(), startsWith('MidiRtpMessageCommand('));
        expect(command.toString(), contains('deltaTime: 3'));
      });
    });
  });
}
