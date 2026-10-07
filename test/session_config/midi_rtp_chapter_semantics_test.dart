// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpChapterSemantics', () {
    test('names the chapter inclusion parameters', () {
      expect([
        for (final s in MidiRtpChapterSemantics.values) s.parameter,
      ], equals(['ch_never', 'ch_default', 'ch_anchor']));
    });

    group('ofParameter(parameter)', () {
      test('finds the semantics of a parameter', () {
        for (final semantics in MidiRtpChapterSemantics.values) {
          expect(
            MidiRtpChapterSemantics.ofParameter(semantics.parameter),
            semantics,
          );
        }
        expect(MidiRtpChapterSemantics.ofParameter('cm_used'), isNull);
      });
    });
  });
}
