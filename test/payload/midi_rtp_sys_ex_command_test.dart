// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpSysExCommand', () {
    group('octets', () {
      // RFC 6295 3.2, Figures 5 and 6.
      test('codes the segments of Figure 6', () {
        expect(
          MidiRtpSysExCommand(
            kind: MidiRtpSysExKind.first,
            data: [1, 2, 3, 4],
          ).octets,
          equals([0xF0, 1, 2, 3, 4, 0xF0]),
        );
        expect(
          MidiRtpSysExCommand(
            kind: MidiRtpSysExKind.middle,
            data: [3, 4],
          ).octets,
          equals([0xF7, 3, 4, 0xF0]),
        );
        expect(
          MidiRtpSysExCommand(
            kind: MidiRtpSysExKind.last,
            data: [5, 6, 7, 8],
          ).octets,
          equals([0xF7, 5, 6, 7, 8, 0xF7]),
        );
        expect(
          MidiRtpSysExCommand(kind: MidiRtpSysExKind.last).octets,
          equals([0xF7, 0xF7]),
        );
        expect(
          MidiRtpSysExCommand(kind: MidiRtpSysExKind.cancel).octets,
          equals([0xF7, 0xF4]),
        );
        expect(
          MidiRtpSysExCommand(
            kind: MidiRtpSysExKind.complete,
            data: [9],
          ).octets,
          equals([0xF0, 9, 0xF7]),
        );
      });

      test('codes a dropped 0xF7 with 0xF5', () {
        expect(
          MidiRtpSysExCommand(
            kind: MidiRtpSysExKind.complete,
            data: [9],
            droppedF7: true,
          ).octets,
          equals([0xF0, 9, 0xF5]),
        );
        expect(
          MidiRtpSysExCommand(
            kind: MidiRtpSysExKind.last,
            data: [9],
            droppedF7: true,
          ).octets,
          equals([0xF7, 9, 0xF5]),
        );
      });
    });

    group('MidiRtpSysExCommand(kind, data, droppedF7)', () {
      test('rejects illegal combinations', () {
        for (final create in [
          () => MidiRtpSysExCommand(kind: MidiRtpSysExKind.first, data: [128]),
          () => MidiRtpSysExCommand(kind: MidiRtpSysExKind.cancel, data: [1]),
          () => MidiRtpSysExCommand(
            kind: MidiRtpSysExKind.first,
            droppedF7: true,
          ),
        ]) {
          expect(create, throwsA(isA<AssertionError>()));
        }
      });

      test('copies the data into an unmodifiable list', () {
        final data = [1, 2];
        final command = MidiRtpSysExCommand(
          kind: MidiRtpSysExKind.complete,
          data: data,
        );
        data[0] = 5;
        expect(command.data, equals([1, 2]));
        expect(() => command.data[0] = 3, throwsUnsupportedError);
      });
    });

    group('withDeltaTime(deltaTime)', () {
      test('keeps kind, data and dropped 0xF7', () {
        final command = MidiRtpSysExCommand(
          kind: MidiRtpSysExKind.last,
          data: [1],
          droppedF7: true,
        );
        final moved = command.withDeltaTime(5);
        expect(moved.deltaTime, 5);
        expect(moved.withDeltaTime(0), command);
      });
    });

    group('==, hashCode, toString', () {
      test('compare by value', () {
        final command = MidiRtpSysExCommand(
          deltaTime: 1,
          kind: MidiRtpSysExKind.first,
          data: [1, 0x7F],
        );
        final same = MidiRtpSysExCommand(
          deltaTime: 1,
          kind: MidiRtpSysExKind.first,
          data: [1, 0x7F],
        );
        expect(command, same);
        expect(command.hashCode, same.hashCode);
        for (final other in [
          command.withDeltaTime(2),
          MidiRtpSysExCommand(
            deltaTime: 1,
            kind: MidiRtpSysExKind.complete,
            data: [1, 0x7F],
          ),
          MidiRtpSysExCommand(
            deltaTime: 1,
            kind: MidiRtpSysExKind.first,
            data: [1],
          ),
        ]) {
          expect(command == other, isFalse);
        }
        expect(
          MidiRtpSysExCommand(
            deltaTime: 1,
            kind: MidiRtpSysExKind.complete,
            data: [1],
            droppedF7: true,
          ),
          isNot(
            MidiRtpSysExCommand(
              deltaTime: 1,
              kind: MidiRtpSysExKind.complete,
              data: [1],
            ),
          ),
        );
        expect(
          command.toString(),
          'MidiRtpSysExCommand(deltaTime: 1, kind: first, data: [01 7f], '
          'droppedF7: false)',
        );
      });
    });
  });
}
