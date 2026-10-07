// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpArrival', () {
    test('accepts first, next and after-loss packets', () {
      expect([
        for (final a in MidiRtpArrival.values) a.isAccepted,
      ], equals([true, true, true, false, false]));
    });
  });
}
