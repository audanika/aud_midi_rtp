// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpSendingPolicy', () {
    test('has the j_update tokens of RFC 6295 C.2.2', () {
      expect([
        for (final p in MidiRtpSendingPolicy.values) p.token,
      ], equals(['anchor', 'closed-loop', 'open-loop']));
    });

    group('fromToken(token)', () {
      test('finds the policy', () {
        for (final policy in MidiRtpSendingPolicy.values) {
          expect(MidiRtpSendingPolicy.fromToken(policy.token), policy);
        }
      });

      test('rejects unknown tokens', () {
        expect(
          () => MidiRtpSendingPolicy.fromToken('closedLoop'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'Unknown j_update value',
            ),
          ),
        );
      });
    });
  });
}
