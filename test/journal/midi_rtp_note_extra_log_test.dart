// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpNoteExtraLog', () {
    const log = MidiRtpNoteExtraLog(note: 60, v: true, value: 90);
    // RFC 6295 Figure A.7.2: |S|NOTENUM|V|COUNT/VEL|.

    test('codes and decodes release velocities and reference counts', () {
      expect(log.toBytes(), equals([0xBC, 0xDA]));
      expect(MidiRtpNoteExtraLog.read(MidiRtpByteReader([0xBC, 0xDA])), log);
      const count = MidiRtpNoteExtraLog(s: false, note: 2, v: false, value: 3);
      expect(count.toBytes(), equals([0x02, 0x03]));
      expect(MidiRtpNoteExtraLog.read(MidiRtpByteReader([0x02, 0x03])), count);
      expect(MidiRtpNoteExtraLog.length, 2);
    });

    test('copyWith replaces the given fields', () {
      expect(log.copyWith(), log);
      expect(
        log.copyWith(s: false, note: 2, v: false, value: 3),
        const MidiRtpNoteExtraLog(s: false, note: 2, v: false, value: 3),
      );
    });

    test('compares by value', () {
      expect(log, const MidiRtpNoteExtraLog(note: 60, v: true, value: 90));
      expect(
        log.hashCode,
        const MidiRtpNoteExtraLog(note: 60, v: true, value: 90).hashCode,
      );
      for (final other in [
        log.copyWith(s: false),
        log.copyWith(note: 1),
        log.copyWith(v: false),
        log.copyWith(value: 1),
      ]) {
        expect(log == other, isFalse);
      }
      expect(
        log.toString(),
        'MidiRtpNoteExtraLog(s: true, note: 60, v: true, value: 90)',
      );
    });
  });
}
