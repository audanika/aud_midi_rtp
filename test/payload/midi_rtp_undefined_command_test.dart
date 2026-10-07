// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpUndefinedCommand', () {
    group('octets', () {
      test('closes System Common commands with 0xF7', () {
        expect(
          MidiRtpUndefinedCommand(status: 0xF4, data: [1, 2]).octets,
          equals([0xF4, 1, 2, 0xF7]),
        );
        expect(
          MidiRtpUndefinedCommand(status: 0xF5).octets,
          equals([0xF5, 0xF7]),
        );
      });

      test('codes System Real-Time commands alone', () {
        expect(MidiRtpUndefinedCommand(status: 0xFD).octets, equals([0xFD]));
      });
    });

    group('isCommon', () {
      test('tells System Common from System Real-Time', () {
        expect([
          for (final status in MidiRtpUndefinedCommand.statuses)
            MidiRtpUndefinedCommand(status: status).isCommon,
        ], equals([true, true, false, false]));
      });
    });

    group('MidiRtpUndefinedCommand(status, data)', () {
      test('rejects defined statuses and real-time data', () {
        for (final create in [
          () => MidiRtpUndefinedCommand(status: 0xF8),
          () => MidiRtpUndefinedCommand(status: 0xF4, data: [0x80]),
          () => MidiRtpUndefinedCommand(status: 0xF9, data: [1]),
        ]) {
          expect(create, throwsA(isA<AssertionError>()));
        }
      });
    });

    group('withDeltaTime(deltaTime)', () {
      test('keeps status and data', () {
        final command = MidiRtpUndefinedCommand(status: 0xF4, data: [3]);
        expect(command.withDeltaTime(7).deltaTime, 7);
        expect(command.withDeltaTime(7).withDeltaTime(0), command);
      });
    });

    group('==, hashCode, toString', () {
      test('compare by value', () {
        final command = MidiRtpUndefinedCommand(status: 0xF4, data: [3]);
        final same = MidiRtpUndefinedCommand(status: 0xF4, data: [3]);
        expect(command, same);
        expect(command.hashCode, same.hashCode);
        expect(command == command.withDeltaTime(1), isFalse);
        expect(
          command == MidiRtpUndefinedCommand(status: 0xF5, data: [3]),
          isFalse,
        );
        expect(command == MidiRtpUndefinedCommand(status: 0xF4), isFalse);
        expect(
          command.toString(),
          'MidiRtpUndefinedCommand(deltaTime: 0, status: 0xf4, data: [03])',
        );
      });
    });
  });
}
