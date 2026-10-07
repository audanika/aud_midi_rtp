// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpTimestampMode', () {
    group('fromToken(token)', () {
      test('finds the mode', () {
        for (final mode in MidiRtpTimestampMode.values) {
          expect(MidiRtpTimestampMode.fromToken(mode.name), mode);
        }
      });

      test('rejects unknown tokens', () {
        expect(
          () => MidiRtpTimestampMode.fromToken('exact'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'Unknown tsmode value',
            ),
          ),
        );
      });
    });
  });
}
