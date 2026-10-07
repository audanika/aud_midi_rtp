// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpSysExKind', () {
    test('holds the status octets of RFC 6295 Figure 5', () {
      expect(
        [for (final kind in MidiRtpSysExKind.values) (kind.head, kind.tail)],
        equals([
          (0xF0, 0xF7),
          (0xF0, 0xF0),
          (0xF7, 0xF0),
          (0xF7, 0xF7),
          (0xF7, 0xF4),
        ]),
      );
      expect(MidiRtpSysExKind.droppedF7Tail, 0xF5);
    });

    test('tells which kinds start and end a command', () {
      expect(
        [
          for (final kind in MidiRtpSysExKind.values)
            (kind.startsCommand, kind.endsCommand),
        ],
        equals([
          (true, true),
          (true, false),
          (false, false),
          (false, true),
          (false, true),
        ]),
      );
    });
  });
}
