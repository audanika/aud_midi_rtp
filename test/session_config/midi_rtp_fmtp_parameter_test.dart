// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpFmtpParameter', () {
    group('MidiRtpFmtpParameter.parse(assignment)', () {
      test('splits name and value at the first =', () {
        expect(
          MidiRtpFmtpParameter.parse(' j_update = open-loop '),
          const MidiRtpFmtpParameter('j_update', 'open-loop'),
        );
        expect(
          MidiRtpFmtpParameter.parse('cm_used=__7E_00-7F_09_01.02.03__'),
          const MidiRtpFmtpParameter('cm_used', '__7E_00-7F_09_01.02.03__'),
        );
      });

      test('strips double quotes and remembers them', () {
        final url = MidiRtpFmtpParameter.parse(
          'url="http://example.com/a.asc"',
        );
        expect(url.value, 'http://example.com/a.asc');
        expect(url.quoted, isTrue);
        expect(MidiRtpFmtpParameter.parse('config=""').value, '');
        expect(MidiRtpFmtpParameter.parse('x="').quoted, isFalse);
      });

      for (final bad in ['novalue', '=x', '']) {
        test('rejects "$bad"', () {
          expect(
            () => MidiRtpFmtpParameter.parse(bad),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                'Not a name=value assignment',
              ),
            ),
          );
        });
      }
    });

    group('toString()', () {
      test('writes the assignment', () {
        expect(
          const MidiRtpFmtpParameter('cid', 'a;b', quoted: true).toString(),
          'cid="a;b"',
        );
        expect(const MidiRtpFmtpParameter('a', 'b').toString(), 'a=b');
      });
    });

    group('==, hashCode', () {
      test('compare by value', () {
        const p = MidiRtpFmtpParameter('a', 'b');
        expect(p, const MidiRtpFmtpParameter('a', 'b'));
        expect(p.hashCode, const MidiRtpFmtpParameter('a', 'b').hashCode);
        expect(p == const MidiRtpFmtpParameter('x', 'b'), isFalse);
        expect(p == const MidiRtpFmtpParameter('a', 'x'), isFalse);
        expect(
          p == const MidiRtpFmtpParameter('a', 'b', quoted: true),
          isFalse,
        );
      });
    });
  });
}
