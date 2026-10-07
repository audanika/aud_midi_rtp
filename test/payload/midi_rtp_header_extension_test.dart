// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpHeaderExtension', () {
    final extension = MidiRtpHeaderExtension(
      profile: 0xBEDE,
      data: [1, 2, 3, 4],
    );
    // RFC 3550 5.3.1: profile, length in words, data.
    const bytes = [0xBE, 0xDE, 0x00, 0x01, 1, 2, 3, 4];

    group('toBytes()', () {
      test('codes profile, word count and data', () {
        expect(extension.toBytes(), equals(bytes));
        expect(extension.length, 8);
        expect(
          MidiRtpHeaderExtension(profile: 1).toBytes(),
          equals([0, 1, 0, 0]),
        );
      });
    });

    group('MidiRtpHeaderExtension.read(reader)', () {
      test('decodes the encoded extension', () {
        expect(
          MidiRtpHeaderExtension.read(MidiRtpByteReader(bytes)),
          extension,
        );
      });

      test('fails on missing data', () {
        expect(
          () => MidiRtpHeaderExtension.read(
            MidiRtpByteReader(bytes.sublist(0, 6)),
          ),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('copyWith()', () {
      test('replaces the given fields', () {
        expect(extension.copyWith(), extension);
        expect(extension.copyWith(profile: 7).profile, 7);
        expect(extension.copyWith(data: []).data, isEmpty);
      });
    });

    group('==, hashCode, toString', () {
      test('compare by value', () {
        final same = MidiRtpHeaderExtension(
          profile: 0xBEDE,
          data: [1, 2, 3, 4],
        );
        expect(extension, same);
        expect(extension.hashCode, same.hashCode);
        expect(extension == extension.copyWith(profile: 1), isFalse);
        expect(extension == extension.copyWith(data: [0, 0, 0, 0]), isFalse);
        expect(
          extension.toString(),
          'MidiRtpHeaderExtension(profile: 48862, data: [01 02 03 04])',
        );
      });
    });
  });
}
