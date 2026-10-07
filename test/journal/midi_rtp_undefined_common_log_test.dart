// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpUndefinedCommonLog', () {
    final log = MidiRtpUndefinedCommonLog(dsz: 2, count: 5, value: [1, 2]);
    // RFC 6295 Figure B.1.4: |S|C|V|L|DSZ|LENGTH|, COUNT, VALUE with the
    // top bit of its last octet set, LEGAL.
    const bytes = [0xE8, 0x05, 0x05, 0x01, 0x82];

    group('toBytes()', () {
      test('codes header, COUNT and VALUE', () {
        expect(log.toBytes(), equals(bytes));
      });

      test('codes the LEGAL field as raw octets', () {
        final legal = MidiRtpUndefinedCommonLog(
          s: false,
          dsz: 0,
          legal: [0xAA, 0xBB],
        );
        expect(legal.toBytes(), equals([0x10, 0x04, 0xAA, 0xBB]));
      });
    });

    group('MidiRtpUndefinedCommonLog.read(reader)', () {
      test('decodes the log', () {
        expect(MidiRtpUndefinedCommonLog.read(MidiRtpByteReader(bytes)), log);
      });

      test('decodes LEGAL up to LENGTH', () {
        final reader = MidiRtpByteReader([
          0xF0, 0x06, 0x07, 0x81, 0xAA, 0xBB, 0x99, //
        ]);
        expect(
          MidiRtpUndefinedCommonLog.read(reader),
          MidiRtpUndefinedCommonLog(
            dsz: 0,
            count: 7,
            value: [1],
            legal: [0xAA, 0xBB],
          ),
        );
        expect(reader.readUint8(), 0x99);
      });

      test('rejects a LENGTH below the header', () {
        expect(
          () => MidiRtpUndefinedCommonLog.read(MidiRtpByteReader([0x80, 0x01])),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'Command log LENGTH 1 is too small',
            ),
          ),
        );
      });
    });

    group('dszOf(dataLength)', () {
      test('classes data sizes', () {
        expect([
          for (var n = 0; n < 6; n++) MidiRtpUndefinedCommonLog.dszOf(n),
        ], equals([0, 1, 2, 3, 3, 3]));
      });
    });

    group('copyWith()', () {
      test('replaces the given fields', () {
        expect(log.copyWith(), log);
        expect(
          log.copyWith(
            s: false,
            dsz: 3,
            count: 1,
            value: [1, 2, 3],
            legal: [9],
          ),
          MidiRtpUndefinedCommonLog(
            s: false,
            dsz: 3,
            count: 1,
            value: [1, 2, 3],
            legal: [9],
          ),
        );
      });
    });

    group('==, hashCode, toString', () {
      test('compare by value', () {
        final same = MidiRtpUndefinedCommonLog.read(MidiRtpByteReader(bytes));
        expect(log, same);
        expect(log.hashCode, same.hashCode);
        for (final other in [
          log.copyWith(s: false),
          log.copyWith(dsz: 1),
          log.copyWith(count: 1),
          log.copyWith(value: [1]),
          log.copyWith(legal: [1]),
        ]) {
          expect(log == other, isFalse);
        }
        expect(
          log.toString(),
          'MidiRtpUndefinedCommonLog(s: true, dsz: 2, count: 5, '
          'value: [01 02], legal: null)',
        );
      });
    });
  });
}
