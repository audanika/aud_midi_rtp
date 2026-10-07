// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpDeltaTime', () {
    // RFC 6295 3.1, Figure 4: one to four octets of seven bits.
    const cases = <int, List<int>>{
      0: [0x00],
      0x7F: [0x7F],
      0x80: [0x81, 0x00],
      0x2000: [0xC0, 0x00],
      0x3FFF: [0xFF, 0x7F],
      0x4000: [0x81, 0x80, 0x00],
      0x1FFFFF: [0xFF, 0xFF, 0x7F],
      0x200000: [0x81, 0x80, 0x80, 0x00],
      0x0FFFFFFF: [0xFF, 0xFF, 0xFF, 0x7F],
    };

    group('encode(value)', () {
      for (final c in cases.entries) {
        test('codes ${c.key} in ${c.value.length} octets', () {
          expect(MidiRtpDeltaTime.encode(c.key), equals(c.value));
          expect(MidiRtpDeltaTime.encodedLength(c.key), c.value.length);
        });
      }

      for (final value in [-1, MidiRtpDeltaTime.max + 1]) {
        test('rejects $value', () {
          expect(
            () => MidiRtpDeltaTime.encode(value),
            throwsA(isA<RangeError>()),
          );
        });
      }
    });

    group('read(reader)', () {
      for (final c in cases.entries) {
        test('decodes ${c.key}', () {
          final reader = MidiRtpByteReader([...c.value, 0x55]);
          expect(MidiRtpDeltaTime.read(reader), c.key);
          expect(reader.readUint8(), 0x55);
        });
      }

      test('decodes the four forms of zero', () {
        for (final form in [
          [0x00],
          [0x80, 0x00],
          [0x80, 0x80, 0x00],
          [0x80, 0x80, 0x80, 0x00],
        ]) {
          expect(MidiRtpDeltaTime.read(MidiRtpByteReader(form)), 0);
        }
      });

      test('rejects five octets', () {
        expect(
          () => MidiRtpDeltaTime.read(
            MidiRtpByteReader([0x80, 0x80, 0x80, 0x80, 0x00]),
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'Variable-length value longer than 4 octets',
            ),
          ),
        );
      });

      test('fails on a missing last octet', () {
        expect(
          () => MidiRtpDeltaTime.read(MidiRtpByteReader([0x81])),
          throwsA(isA<FormatException>()),
        );
      });
    });
  });
}
