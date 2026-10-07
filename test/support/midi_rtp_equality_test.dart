// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/src/support/midi_rtp_equality.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpEquality', () {
    group('lists(a, b)', () {
      test('compares element by element', () {
        final list = [1, 2];
        expect(MidiRtpEquality.lists(list, list), isTrue);
        expect(MidiRtpEquality.lists(null, null), isTrue);
        expect(MidiRtpEquality.lists([1, 2], [1, 2]), isTrue);
        expect(MidiRtpEquality.lists([1, 2], [1, 3]), isFalse);
        expect(MidiRtpEquality.lists([1, 2], [1]), isFalse);
        expect(MidiRtpEquality.lists([1], null), isFalse);
        expect(MidiRtpEquality.lists(null, [1]), isFalse);
      });
    });

    group('hash(list)', () {
      test('hashes the elements', () {
        expect(MidiRtpEquality.hash([1, 2]), MidiRtpEquality.hash([1, 2]));
        expect(MidiRtpEquality.hash(null), null.hashCode);
      });
    });

    group('hex(bytes)', () {
      test('prints hex pairs', () {
        expect(MidiRtpEquality.hex([0x0F, 0xA0]), '[0f a0]');
        expect(MidiRtpEquality.hex(null), 'null');
      });
    });
  });
}
