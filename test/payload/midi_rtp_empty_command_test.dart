// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpEmptyCommand', () {
    test('has no octets', () {
      expect(const MidiRtpEmptyCommand(deltaTime: 5).octets, isEmpty);
    });

    test('withDeltaTime replaces the delta time', () {
      expect(
        const MidiRtpEmptyCommand().withDeltaTime(4),
        const MidiRtpEmptyCommand(deltaTime: 4),
      );
    });

    test('compares by value', () {
      const command = MidiRtpEmptyCommand(deltaTime: 2);
      expect(command, const MidiRtpEmptyCommand(deltaTime: 2));
      expect(
        command.hashCode,
        const MidiRtpEmptyCommand(deltaTime: 2).hashCode,
      );
      expect(command == const MidiRtpEmptyCommand(), isFalse);
      expect(command.toString(), 'MidiRtpEmptyCommand(deltaTime: 2)');
    });
  });
}
