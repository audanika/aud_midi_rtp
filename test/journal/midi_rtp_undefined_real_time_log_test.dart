// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpUndefinedRealTimeLog', () {
    final log = MidiRtpUndefinedRealTimeLog(s: false, count: 9, legal: [0xAA]);
    // RFC 6295 Figure B.1.5: |S|C|L|LENGTH|, COUNT, LEGAL.
    const bytes = [0x63, 0x09, 0xAA];

    test('codes header, COUNT and LEGAL', () {
      expect(log.toBytes(), equals(bytes));
      expect(log.length, 3);
      expect(MidiRtpUndefinedRealTimeLog().toBytes(), equals([0x81]));
    });

    test('decodes the log', () {
      expect(MidiRtpUndefinedRealTimeLog.read(MidiRtpByteReader(bytes)), log);
      expect(
        MidiRtpUndefinedRealTimeLog.read(MidiRtpByteReader([0xC2, 0x04])),
        MidiRtpUndefinedRealTimeLog(count: 4),
      );
    });

    test('rejects a LENGTH of 0', () {
      expect(
        () => MidiRtpUndefinedRealTimeLog.read(MidiRtpByteReader([0x80])),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Command log LENGTH 0 is too small',
          ),
        ),
      );
    });

    test('copyWith replaces the given fields', () {
      expect(log.copyWith(), log);
      expect(
        log.copyWith(s: true, count: 1, legal: [1, 2]),
        MidiRtpUndefinedRealTimeLog(count: 1, legal: [1, 2]),
      );
    });

    test('compares by value', () {
      final same = MidiRtpUndefinedRealTimeLog.read(MidiRtpByteReader(bytes));
      expect(log, same);
      expect(log.hashCode, same.hashCode);
      expect(log == log.copyWith(s: true), isFalse);
      expect(log == log.copyWith(count: 1), isFalse);
      expect(log == log.copyWith(legal: [1]), isFalse);
      expect(
        log.toString(),
        'MidiRtpUndefinedRealTimeLog(s: false, count: 9, legal: [aa])',
      );
    });
  });
}
