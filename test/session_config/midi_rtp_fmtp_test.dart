// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpFmtp', () {
    group('MidiRtpFmtp.parse(line)', () {
      test('parses the RFC 6295 C.2.3 example', () {
        final fmtp = MidiRtpFmtp.parse(
          'a=fmtp:96 j_update=open-loop; cm_unused=ABCFGHJKMQTVWXYZ; '
          'cm_used=__7E_00-7F_09_01.02.03__; '
          'cm_used=__7F_00-7F_04_01.02__; cm_used=C7.64; '
          'ch_never=ABCDEFGHJKMQTVWXYZ; ch_never=4.11-13N; '
          'ch_anchor=P; ch_anchor=C7.64; '
          'ch_anchor=__7E_00-7F_09_01.02.03__; '
          'ch_anchor=__7F_00-7F_04_01.02__',
        );
        expect(fmtp.payloadType, 96);
        expect(fmtp.parameters, hasLength(11));
        expect(
          fmtp.all('ch_anchor').map((p) => p.value),
          equals([
            'P',
            'C7.64',
            '__7E_00-7F_09_01.02.03__',
            '__7F_00-7F_04_01.02__',
          ]),
        );
      });

      test('keeps semicolons inside quotes', () {
        final fmtp = MidiRtpFmtp.parse(
          'a=fmtp:97 cid="a;b";  url="http://x/a.asc"; ',
        );
        expect(
          fmtp.parameters,
          equals([
            const MidiRtpFmtpParameter('cid', 'a;b', quoted: true),
            const MidiRtpFmtpParameter('url', 'http://x/a.asc', quoted: true),
          ]),
        );
      });

      test('accepts a line without parameters', () {
        expect(MidiRtpFmtp.parse('a=fmtp:96').parameters, isEmpty);
      });

      for (final bad in <String, String>{
        'fmtp:96 a=b': 'Not an fmtp line',
        'a=fmtp:x a=b': 'Illegal payload type',
        'a=fmtp:128': 'Illegal payload type',
      }.entries) {
        test('rejects "${bad.key}"', () {
          expect(
            () => MidiRtpFmtp.parse(bad.key),
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

    group('toString()', () {
      test('writes the attribute line', () {
        const line = 'a=fmtp:96 j_sec=none; url="http://x/a.asc"';
        expect(MidiRtpFmtp.parse(line).toString(), line);
        expect(MidiRtpFmtp(payloadType: 5).toString(), 'a=fmtp:5');
      });
    });

    group('==, hashCode', () {
      test('compare by value', () {
        final fmtp = MidiRtpFmtp.parse('a=fmtp:96 j_sec=none');
        final same = MidiRtpFmtp.parse('a=fmtp:96  j_sec=none');
        expect(fmtp, same);
        expect(fmtp.hashCode, same.hashCode);
        expect(fmtp == MidiRtpFmtp.parse('a=fmtp:97 j_sec=none'), isFalse);
        expect(fmtp == MidiRtpFmtp.parse('a=fmtp:96 j_sec=recj'), isFalse);
      });
    });
  });
}
