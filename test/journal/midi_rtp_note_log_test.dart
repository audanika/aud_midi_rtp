// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpNoteLog', () {
    const log = MidiRtpNoteLog(note: 60, velocity: 100);
    // RFC 6295 Figure A.6.3: |S|NOTENUM|Y|VELOCITY|.

    test('codes and decodes the log', () {
      expect(log.toBytes(), equals([0xBC, 0xE4]));
      expect(MidiRtpNoteLog.read(MidiRtpByteReader([0xBC, 0xE4])), log);
      const skip = MidiRtpNoteLog(s: false, note: 1, y: false, velocity: 2);
      expect(skip.toBytes(), equals([0x01, 0x02]));
      expect(MidiRtpNoteLog.read(MidiRtpByteReader([0x01, 0x02])), skip);
      expect(MidiRtpNoteLog.length, 2);
    });

    test('copyWith replaces the given fields', () {
      expect(log.copyWith(), log);
      expect(
        log.copyWith(s: false, note: 1, y: false, velocity: 2),
        const MidiRtpNoteLog(s: false, note: 1, y: false, velocity: 2),
      );
    });

    test('compares by value', () {
      expect(log, const MidiRtpNoteLog(note: 60, velocity: 100));
      expect(
        log.hashCode,
        const MidiRtpNoteLog(note: 60, velocity: 100).hashCode,
      );
      for (final other in [
        log.copyWith(s: false),
        log.copyWith(note: 1),
        log.copyWith(y: false),
        log.copyWith(velocity: 1),
      ]) {
        expect(log == other, isFalse);
      }
      expect(
        log.toString(),
        'MidiRtpNoteLog(s: true, note: 60, y: true, velocity: 100)',
      );
    });
  });
}
