// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpSysExLog', () {
    final log = MidiRtpSysExLog(
      tcount: 1,
      count: 2,
      first: 200,
      data: [1, 2, 3],
      l: true,
      status: MidiRtpSysExStatus.finished,
    );
    // RFC 6295 Figures B.5.1 and B.5.2: |S|T|C|F|D|L|STA|, TCOUNT, COUNT,
    // FIRST as a variable-length value, DATA with the top bit of its last
    // octet set.
    const bytes = [0xFF, 0x01, 0x02, 0x81, 0x48, 0x01, 0x02, 0x83];

    test('codes every field', () {
      expect(log.toBytes(), equals(bytes));
      expect(
        MidiRtpSysExLog(
          s: false,
          status: MidiRtpSysExStatus.unfinished,
        ).toBytes(),
        equals([0x00]),
      );
    });

    test('decodes the log', () {
      expect(MidiRtpSysExLog.read(MidiRtpByteReader(bytes)), log);
      expect(
        MidiRtpSysExLog.read(MidiRtpByteReader([0x29, 0x05, 0x81])),
        MidiRtpSysExLog(
          s: false,
          count: 5,
          data: [1],
          status: MidiRtpSysExStatus.cancelled,
        ),
      );
    });

    test('copyWith replaces the given fields', () {
      expect(log.copyWith(), log);
      expect(
        MidiRtpSysExLog(status: MidiRtpSysExStatus.cancelled).copyWith(
          s: true,
          tcount: 1,
          count: 2,
          first: 200,
          data: [1, 2, 3],
          l: true,
          status: MidiRtpSysExStatus.finished,
        ),
        log,
      );
    });

    test('compares by value', () {
      final same = MidiRtpSysExLog.read(MidiRtpByteReader(bytes));
      expect(log, same);
      expect(log.hashCode, same.hashCode);
      for (final other in [
        log.copyWith(s: false),
        log.copyWith(tcount: 9),
        log.copyWith(count: 9),
        log.copyWith(first: 9),
        log.copyWith(data: [9]),
        log.copyWith(l: false),
        log.copyWith(status: MidiRtpSysExStatus.droppedF7),
      ]) {
        expect(log == other, isFalse);
      }
      expect(
        log.toString(),
        'MidiRtpSysExLog(s: true, tcount: 1, count: 2, first: 200, '
        'data: [01 02 03], l: true, status: finished)',
      );
    });
  });
}
