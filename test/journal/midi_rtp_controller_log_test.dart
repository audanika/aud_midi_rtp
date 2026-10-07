// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpControllerLog', () {
    // RFC 6295 Figures A.3.2 and A.3.3: |S|NUMBER|A|VALUE/ALT| with
    // A = 0 value tool, A = 1 T = 0 toggle tool, A = 1 T = 1 count tool.
    final cases = <MidiRtpControllerLog, List<int>>{
      const MidiRtpControllerLog(
        number: 7,
        tool: MidiRtpControllerTool.value,
        value: 100,
      ): [
        0x87,
        0x64,
      ],
      const MidiRtpControllerLog(
        number: 64,
        tool: MidiRtpControllerTool.toggle,
        value: 5,
      ): [
        0xC0,
        0x85,
      ],
      const MidiRtpControllerLog(
        s: false,
        number: 123,
        tool: MidiRtpControllerTool.count,
        value: 63,
      ): [
        0x7B,
        0xFF,
      ],
    };

    for (final c in cases.entries) {
      test('codes and decodes the ${c.key.tool.name} tool', () {
        expect(c.key.toBytes(), equals(c.value));
        expect(MidiRtpControllerLog.read(MidiRtpByteReader(c.value)), c.key);
      });
    }

    test('has two octets', () {
      expect(MidiRtpControllerLog.length, 2);
    });

    test('copyWith replaces the given fields', () {
      final log = cases.keys.first;
      expect(log.copyWith(), log);
      expect(
        log.copyWith(
          s: false,
          number: 123,
          tool: MidiRtpControllerTool.count,
          value: 63,
        ),
        cases.keys.last,
      );
    });

    test('compares by value', () {
      final log = cases.keys.first;
      expect(log, MidiRtpControllerLog.read(MidiRtpByteReader([0x87, 0x64])));
      expect(
        log.hashCode,
        MidiRtpControllerLog.read(MidiRtpByteReader([0x87, 0x64])).hashCode,
      );
      for (final other in [
        log.copyWith(s: false),
        log.copyWith(number: 1),
        log.copyWith(tool: MidiRtpControllerTool.count, value: 1),
        log.copyWith(value: 1),
      ]) {
        expect(log == other, isFalse);
      }
      expect(
        log.toString(),
        'MidiRtpControllerLog(s: true, number: 7, tool: value, value: 100)',
      );
    });
  });
}
