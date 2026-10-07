// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpParameterLog', () {
    const log = MidiRtpParameterLog(
      number: 3 << 7 | 5,
      t: true,
      entryMsb: (value: 10, x: false),
      entryLsb: (value: 20, x: true),
      aButton: (count: -3, x: true),
      cButton: 7,
      count: (value: 9, x: false),
    );
    // RFC 6295 Figures A.4.2 to A.4.7: |S|PNUM-LSB|Q|PNUM-MSB|J|K|L|M|N|T|V|R|
    // then ENTRY-MSB, ENTRY-LSB, |G|X|A-BUTTON|, |G|R|C-BUTTON|, COUNT.
    const bytes = [
      0x85, 0x03, 0xFE, 0x0A, 0x94, 0xC0, 0x03, 0x00, 0x07, 0x09, //
    ];

    group('toBytes(shortHeader)', () {
      test('codes header and every field', () {
        expect(log.toBytes(), equals(bytes));
        expect(log.msb, 3);
        expect(log.lsb, 5);
      });

      test('codes a log without fields', () {
        const empty = MidiRtpParameterLog(
          s: false,
          nrpn: true,
          number: 0x3FFE,
          v: false,
        );
        expect(empty.toBytes(), equals([0x7E, 0xFF, 0x00]));
      });

      test('leaves out Q and PNUM-MSB in the short header', () {
        const short = MidiRtpParameterLog(
          number: 6,
          entryMsb: (value: 2, x: false),
        );
        expect(short.toBytes(shortHeader: true), equals([0x86, 0x82, 0x02]));
      });

      test('limits the button magnitudes to 14 bits', () {
        const big = MidiRtpParameterLog(
          number: 1,
          aButton: (count: 20000, x: false),
          cButton: -20000,
        );
        expect(big.toBytes().sublist(3), equals([0x3F, 0xFF, 0xBF, 0xFF]));
      });
    });

    group('MidiRtpParameterLog.read(reader, shortHeader, nrpn)', () {
      test('decodes the log', () {
        expect(MidiRtpParameterLog.read(MidiRtpByteReader(bytes)), log);
      });

      test('infers Q and PNUM-MSB of a short header', () {
        expect(
          MidiRtpParameterLog.read(
            MidiRtpByteReader([0x86, 0x82, 0x02]),
            shortHeader: true,
            nrpn: true,
          ),
          const MidiRtpParameterLog(
            nrpn: true,
            number: 6,
            entryMsb: (value: 2, x: false),
          ),
        );
      });

      test('ignores the R bits', () {
        expect(
          MidiRtpParameterLog.read(
            MidiRtpByteReader([0x81, 0x00, 0x13, 0x40, 0x05]),
          ),
          const MidiRtpParameterLog(number: 1, v: true, cButton: 5),
        );
      });
    });

    group('copyWith()', () {
      test('replaces the given fields', () {
        expect(log.copyWith(), log);
        final changed = log.copyWith(
          s: false,
          nrpn: true,
          number: 1,
          t: false,
          v: false,
          entryMsb: (value: 1, x: true),
          entryLsb: (value: 2, x: false),
          aButton: (count: 4, x: false),
          cButton: 5,
          count: (value: 6, x: true),
        );
        expect(
          changed,
          const MidiRtpParameterLog(
            s: false,
            nrpn: true,
            number: 1,
            v: false,
            entryMsb: (value: 1, x: true),
            entryLsb: (value: 2, x: false),
            aButton: (count: 4, x: false),
            cButton: 5,
            count: (value: 6, x: true),
          ),
        );
      });
    });

    group('==, hashCode, toString', () {
      test('compare by value', () {
        final same = MidiRtpParameterLog.read(MidiRtpByteReader(bytes));
        expect(log, same);
        expect(log.hashCode, same.hashCode);
        for (final other in [
          log.copyWith(s: false),
          log.copyWith(nrpn: true),
          log.copyWith(number: 1),
          log.copyWith(t: false),
          log.copyWith(v: false),
          log.copyWith(entryMsb: (value: 1, x: false)),
          log.copyWith(entryLsb: (value: 1, x: false)),
          log.copyWith(aButton: (count: 1, x: false)),
          log.copyWith(cButton: 1),
          log.copyWith(count: (value: 1, x: false)),
        ]) {
          expect(log == other, isFalse);
        }
        expect(log.toString(), startsWith('MidiRtpParameterLog(s: true, '));
      });
    });
  });
}
