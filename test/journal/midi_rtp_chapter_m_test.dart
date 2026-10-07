// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpChapterM', () {
    const log = MidiRtpParameterLog(
      number: 3 << 7 | 5,
      t: true,
      entryMsb: (value: 10, x: false),
      entryLsb: (value: 20, x: true),
      aButton: (count: -3, x: true),
      cButton: 7,
      count: (value: 9, x: false),
    );
    final chapter = MidiRtpChapterM(
      pending: (value: 5, nrpn: true),
      logs: [log],
    );
    // RFC 6295 Figure A.4.1: |S|P|E|U|W|Z|LENGTH|, |Q|PENDING|, the logs.
    const bytes = [
      0xC0, 0x0D, 0x85, //
      0x85, 0x03, 0xFE, 0x0A, 0x94, 0xC0, 0x03, 0x00, 0x07, 0x09, //
    ];

    group('toBytes()', () {
      test('codes header, PENDING and logs', () {
        expect(chapter.toBytes(), equals(bytes));
      });

      test('codes the E bit and an empty log list', () {
        expect(
          MidiRtpChapterM(s: false, e: true).toBytes(),
          equals([0x20, 0x02]),
        );
      });

      test('uses short log headers with Z and U or W', () {
        final short = MidiRtpChapterM(
          u: true,
          z: true,
          logs: [
            const MidiRtpParameterLog(
              number: 6,
              entryMsb: (value: 2, x: false),
            ),
          ],
        );
        expect(short.shortHeaders, isTrue);
        expect(short.toBytes(), equals([0x94, 0x05, 0x86, 0x82, 0x02]));
        expect(MidiRtpChapterM.read(MidiRtpByteReader(short.toBytes())), short);
        final nrpn = MidiRtpChapterM(
          w: true,
          z: true,
          logs: [
            const MidiRtpParameterLog(
              nrpn: true,
              number: 6,
              entryMsb: (value: 2, x: false),
            ),
          ],
        );
        expect(nrpn.toBytes().sublist(0, 2), equals([0x8C, 0x05]));
        expect(MidiRtpChapterM.read(MidiRtpByteReader(nrpn.toBytes())), nrpn);
      });

      test('rejects chapters beyond 1023 octets', () {
        final huge = MidiRtpChapterM(
          logs: [
            for (var n = 0; n < 103; n++)
              MidiRtpParameterLog(
                number: n,
                t: true,
                entryMsb: (value: 1, x: false),
                entryLsb: (value: 1, x: false),
                aButton: (count: 1, x: false),
                cButton: 2,
                count: (value: 1, x: false),
              ),
          ],
        );
        expect(
          huge.toBytes,
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              'Chapter M is too long',
            ),
          ),
        );
      });
    });

    group('MidiRtpChapterM.read(reader)', () {
      test('decodes the chapter', () {
        expect(MidiRtpChapterM.read(MidiRtpByteReader(bytes)), chapter);
      });

      test('stops at LENGTH', () {
        final reader = MidiRtpByteReader([...bytes, 0x55]);
        MidiRtpChapterM.read(reader);
        expect(reader.readUint8(), 0x55);
      });

      test('rejects a LENGTH below the header', () {
        expect(
          () => MidiRtpChapterM.read(MidiRtpByteReader([0x80, 0x01])),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'Chapter M LENGTH 1 is too small',
            ),
          ),
        );
      });
    });

    group('MidiRtpChapterM()', () {
      test('rejects inconsistent U, W and Z bits', () {
        for (final create in [
          () => MidiRtpChapterM(
            u: true,
            logs: [const MidiRtpParameterLog(nrpn: true, number: 1)],
          ),
          () => MidiRtpChapterM(
            w: true,
            logs: [const MidiRtpParameterLog(number: 1)],
          ),
          () => MidiRtpChapterM(
            z: true,
            logs: [const MidiRtpParameterLog(number: 128)],
          ),
        ]) {
          expect(create, throwsA(isA<AssertionError>()));
        }
      });
    });

    group('copyWith()', () {
      test('replaces the given fields', () {
        expect(chapter.copyWith(), chapter);
        final changed = chapter.copyWith(
          s: false,
          pending: (value: 1, nrpn: false),
          e: true,
          u: false,
          w: false,
          z: false,
          logs: [],
        );
        expect(
          changed,
          MidiRtpChapterM(s: false, pending: (value: 1, nrpn: false), e: true),
        );
        expect(
          MidiRtpChapterM().copyWith(u: true, w: true, z: true),
          MidiRtpChapterM(u: true, w: true, z: true),
        );
      });
    });

    group('==, hashCode, toString', () {
      test('compare by value', () {
        final same = MidiRtpChapterM.read(MidiRtpByteReader(bytes));
        expect(chapter, same);
        expect(chapter.hashCode, same.hashCode);
        for (final other in [
          chapter.copyWith(s: false),
          chapter.copyWith(pending: (value: 4, nrpn: true)),
          chapter.copyWith(e: true),
          MidiRtpChapterM(pending: chapter.pending, u: true),
          MidiRtpChapterM(pending: chapter.pending, w: true),
          MidiRtpChapterM(pending: chapter.pending, z: true),
          chapter.copyWith(logs: []),
        ]) {
          expect(chapter == other, isFalse);
        }
        expect(chapter.toString(), startsWith('MidiRtpChapterM(s: true, '));
      });
    });
  });
}
