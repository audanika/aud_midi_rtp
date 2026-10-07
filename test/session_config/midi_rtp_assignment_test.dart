// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpAssignment', () {
    MidiRtpAssignment parse(String value) =>
        MidiRtpAssignment.parse(value, parameter: 'ch_never');

    group('MidiRtpAssignment.parse(value, parameter)', () {
      test('parses channel list, letters and field list', () {
        final a = parse('4.11-13N60-72.127');
        expect(a.parameter, 'ch_never');
        expect(a.channels, equals([(4, 4), (11, 13)]));
        expect(a.letters, 'N');
        expect(a.fields, equals([(60, 72), (127, 127)]));
        expect(a.sysEx, isNull);
      });

      test('parses letters alone', () {
        final a = parse('ABCDEFGHJKMNPQTVWXYZ');
        expect(a.channels, isNull);
        expect(a.fields, isNull);
      });

      test('parses System Exclusive classes', () {
        final a = parse('__7E_00-7F_09_01.02.03__');
        expect(
          a.sysEx,
          equals([
            [(0x7E, 0x7E)],
            [(0x00, 0x7F)],
            [(0x09, 0x09)],
            [(0x01, 0x01), (0x02, 0x02), (0x03, 0x03)],
          ]),
        );
        expect(a.letters, '');
      });

      for (final bad in <String, String>{
        '__7E': 'Illegal SysEx class',
        '__7E_': 'Illegal SysEx class',
        '__': 'Illegal SysEx class',
        'n': 'Illegal assignment',
        '1N2N': 'Illegal assignment',
        '5-1N': 'Illegal list element "5-1"',
        '1-2-3N': 'Illegal list element "1-2-3"',
        '1..2N': 'Illegal list element ""',
        '__7G__': 'Illegal list element "7G"',
      }.entries) {
        test('rejects "${bad.key}"', () {
          expect(
            () => parse(bad.key),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                bad.value,
              ),
            ),
          );
        });
      }
    });

    group('matches(letter, channel, field)', () {
      test('checks letter, channel list and field list', () {
        final a = parse('0-3C7.64');
        expect(a.matches('C', channel: 2, field: 64), isTrue);
        expect(a.matches('C'), isTrue);
        expect(a.matches('C', channel: 4), isFalse);
        expect(a.matches('C', field: 8), isFalse);
        expect(a.matches('N'), isFalse);
        expect(parse('NP').matches('P', channel: 9, field: 1), isTrue);
      });
    });

    group('matchesSysEx(data)', () {
      test('checks the leading data octets', () {
        final a = parse('__7E_00-7F_09_01.02__');
        expect(a.matchesSysEx([0x7E, 0x10, 0x09, 0x02, 0x55]), isTrue);
        expect(a.matchesSysEx([0x7E, 0x10, 0x09, 0x03]), isFalse);
        expect(a.matchesSysEx([0x7E, 0x10, 0x09]), isFalse);
        expect(parse('X').matchesSysEx([1]), isFalse);
      });
    });

    group('hasChannel(number)', () {
      test('checks the channel list', () {
        expect(parse('0.2X').hasChannel(2), isTrue);
        expect(parse('0.2X').hasChannel(1), isFalse);
        expect(parse('X').hasChannel(0), isFalse);
      });
    });

    group('toString()', () {
      test('writes the value back', () {
        for (final value in [
          '4.11-13N60-72.127',
          'ABCF',
          'C135.138.192',
          '__7E_00-7F_09_01.02.03__',
        ]) {
          expect(parse(value).toString(), value);
        }
      });
    });

    group('==, hashCode', () {
      test('compare parameter and value', () {
        expect(parse('1C7'), parse('1C7'));
        expect(parse('1C7').hashCode, parse('1C7').hashCode);
        expect(parse('1C7') == parse('1C8'), isFalse);
        expect(
          parse('1C7') == MidiRtpAssignment.parse('1C7', parameter: 'cm_used'),
          isFalse,
        );
      });

      test('constructs from ranges', () {
        expect(
          MidiRtpAssignment(
            parameter: 'ch_never',
            channels: [(1, 1)],
            letters: 'C',
            fields: [(7, 7)],
          ),
          parse('1C7'),
        );
        expect(
          MidiRtpAssignment(
            parameter: 'ch_never',
            sysEx: [
              [(0x7E, 0x7E)],
            ],
          ),
          parse('__7E__'),
        );
      });
    });
  });
}
