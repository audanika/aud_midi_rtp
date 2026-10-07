// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpChapterP', () {
    const chapter = MidiRtpChapterP(
      s: false,
      program: 0x12,
      b: true,
      bankMsb: 0x34,
      x: true,
      bankLsb: 0x56,
    );
    // RFC 6295 Figure A.2.1: |S|PROGRAM|B|BANK-MSB|X|BANK-LSB|.
    const bytes = [0x12, 0xB4, 0xD6];

    group('toBytes()', () {
      test('codes the 24-bit chapter', () {
        expect(chapter.toBytes(), equals(bytes));
        expect(
          const MidiRtpChapterP(program: 1).toBytes(),
          equals([0x81, 0, 0]),
        );
        expect(MidiRtpChapterP.length, 3);
      });
    });

    group('MidiRtpChapterP.read(reader)', () {
      test('decodes the chapter', () {
        expect(MidiRtpChapterP.read(MidiRtpByteReader(bytes)), chapter);
      });
    });

    group('copyWith()', () {
      test('replaces the given fields', () {
        expect(chapter.copyWith(), chapter);
        expect(
          chapter.copyWith(
            s: true,
            program: 1,
            b: false,
            bankMsb: 0,
            x: false,
            bankLsb: 0,
          ),
          const MidiRtpChapterP(program: 1),
        );
      });
    });

    group('==, hashCode, toString', () {
      test('compare by value', () {
        expect(chapter, MidiRtpChapterP.read(MidiRtpByteReader(bytes)));
        expect(
          chapter.hashCode,
          MidiRtpChapterP.read(MidiRtpByteReader(bytes)).hashCode,
        );
        for (final other in [
          chapter.copyWith(s: true),
          chapter.copyWith(program: 0),
          chapter.copyWith(b: false),
          chapter.copyWith(bankMsb: 0),
          chapter.copyWith(x: false),
          chapter.copyWith(bankLsb: 0),
        ]) {
          expect(chapter == other, isFalse);
        }
        expect(
          chapter.toString(),
          'MidiRtpChapterP(s: false, program: 18, b: true, bankMsb: 52, '
          'x: true, bankLsb: 86)',
        );
      });
    });
  });
}
