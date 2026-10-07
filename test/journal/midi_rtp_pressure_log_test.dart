// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpPressureLog', () {
    const log = MidiRtpPressureLog(note: 60, x: true, pressure: 33);
    // RFC 6295 Figure A.9.2: |S|NOTENUM|X|PRESSURE|.

    test('codes and decodes the log', () {
      expect(log.toBytes(), equals([0xBC, 0xA1]));
      expect(MidiRtpPressureLog.read(MidiRtpByteReader([0xBC, 0xA1])), log);
      const plain = MidiRtpPressureLog(s: false, note: 1, pressure: 2);
      expect(plain.toBytes(), equals([0x01, 0x02]));
      expect(MidiRtpPressureLog.length, 2);
    });

    test('copyWith replaces the given fields', () {
      expect(log.copyWith(), log);
      expect(
        log.copyWith(s: false, note: 1, x: false, pressure: 2),
        const MidiRtpPressureLog(s: false, note: 1, pressure: 2),
      );
    });

    test('compares by value', () {
      expect(log, const MidiRtpPressureLog(note: 60, x: true, pressure: 33));
      expect(
        log.hashCode,
        const MidiRtpPressureLog(note: 60, x: true, pressure: 33).hashCode,
      );
      for (final other in [
        log.copyWith(s: false),
        log.copyWith(note: 1),
        log.copyWith(x: false),
        log.copyWith(pressure: 1),
      ]) {
        expect(log == other, isFalse);
      }
      expect(
        log.toString(),
        'MidiRtpPressureLog(s: true, note: 60, x: true, pressure: 33)',
      );
    });
  });
}
