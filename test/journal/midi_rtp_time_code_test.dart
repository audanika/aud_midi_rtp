// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpTimeCode', () {
    const code = MidiRtpTimeCode(
      hours: 17,
      minutes: 42,
      seconds: 59,
      frames: 24,
      rate: 3,
    );

    group('nibbles', () {
      test('code the Quarter Frame data of message types 0 to 7', () {
        expect(
          code.toNibbles(),
          equals([0x8, 0x1, 0xB, 0x3, 0xA, 0x2, 0x1, 0x7]),
        );
        expect(MidiRtpTimeCode.fromNibbles(code.toNibbles()), code);
      });

      test('ignore reserved bits', () {
        expect(
          MidiRtpTimeCode.fromNibbles([0x8, 0xF, 0xB, 0xF, 0xA, 0xE, 0x1, 0xF]),
          code,
        );
      });
    });

    group('full frame', () {
      test('codes the hr mn sc fr octets', () {
        expect(code.toFullFrame(), equals([0x71, 42, 59, 24]));
        expect(MidiRtpTimeCode.fromFullFrame([0x71, 42, 59, 24]), code);
      });
    });

    group('fields', () {
      test('code the COMPLETE formats of Figures B.4.2 and B.4.3', () {
        expect(code.toField(nibbles: true), 0x81B3A217);
        expect(code.toField(nibbles: false), 0x712A3B18);
        expect(MidiRtpTimeCode.fromField(0x81B3A217, nibbles: true), code);
        expect(MidiRtpTimeCode.fromField(0x712A3B18, nibbles: false), code);
      });
    });

    group('advance(count)', () {
      test('carries frames into seconds, minutes and hours', () {
        expect(
          const MidiRtpTimeCode(
            hours: 23,
            minutes: 59,
            seconds: 59,
            frames: 23,
          ).advance(2),
          const MidiRtpTimeCode(frames: 1),
        );
        expect(
          const MidiRtpTimeCode(frames: 23, rate: 1).advance(2),
          const MidiRtpTimeCode(frames: 0, seconds: 1, rate: 1),
        );
      });

      test('skips the dropped frames of 29.97 drop frame', () {
        expect(
          const MidiRtpTimeCode(seconds: 59, frames: 29, rate: 2).advance(1),
          const MidiRtpTimeCode(minutes: 1, frames: 2, rate: 2),
        );
        expect(
          const MidiRtpTimeCode(
            minutes: 9,
            seconds: 59,
            frames: 29,
            rate: 2,
          ).advance(1),
          const MidiRtpTimeCode(minutes: 10, rate: 2),
        );
      });

      test('counts 30 frames per second without drop frame', () {
        expect(
          const MidiRtpTimeCode(seconds: 59, frames: 29, rate: 3).advance(1),
          const MidiRtpTimeCode(minutes: 1, rate: 3),
        );
        expect(
          [
            for (var rate = 0; rate < 4; rate++) MidiRtpTimeCode(rate: rate),
          ].map((c) => c.framesPerSecond),
          equals([24, 25, 30, 30]),
        );
      });
    });

    group('==, hashCode, toString', () {
      test('compare by value', () {
        expect(code, MidiRtpTimeCode.fromFullFrame(code.toFullFrame()));
        expect(
          code.hashCode,
          MidiRtpTimeCode.fromFullFrame(code.toFullFrame()).hashCode,
        );
        for (final other in [
          const MidiRtpTimeCode(minutes: 42, seconds: 59, frames: 24, rate: 3),
          const MidiRtpTimeCode(hours: 17, seconds: 59, frames: 24, rate: 3),
          const MidiRtpTimeCode(hours: 17, minutes: 42, frames: 24, rate: 3),
          const MidiRtpTimeCode(hours: 17, minutes: 42, seconds: 59, rate: 3),
          const MidiRtpTimeCode(
            hours: 17,
            minutes: 42,
            seconds: 59,
            frames: 24,
          ),
        ]) {
          expect(code == other, isFalse);
        }
        expect(code.toString(), 'MidiRtpTimeCode(17:42:59:24, rate: 3)');
      });
    });
  });
}
