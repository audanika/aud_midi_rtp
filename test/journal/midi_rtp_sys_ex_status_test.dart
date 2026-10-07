// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpSysExStatus', () {
    test('orders the STA values 0 to 3', () {
      expect([
        for (final s in MidiRtpSysExStatus.values) s.index,
      ], equals([0, 1, 2, 3]));
    });

    test('tells finished and complete commands', () {
      expect([
        for (final s in MidiRtpSysExStatus.values) (s.isFinished, s.isComplete),
      ], equals([(false, false), (true, false), (true, true), (true, true)]));
    });
  });
}
