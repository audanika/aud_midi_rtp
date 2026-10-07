// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpControllerTool', () {
    test('orders the tools as their logs follow each other', () {
      expect(
        MidiRtpControllerTool.values,
        equals([
          MidiRtpControllerTool.count,
          MidiRtpControllerTool.value,
          MidiRtpControllerTool.toggle,
        ]),
      );
    });

    test('max is 127 for values and 63 for counts', () {
      expect([
        for (final tool in MidiRtpControllerTool.values) tool.max,
      ], equals([63, 127, 63]));
    });
  });
}
