// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpHeader', () {
    final header = MidiRtpHeader(
      marker: true,
      payloadType: 97,
      sequenceNumber: 0x1234,
      timestamp: 0x89ABCDEF,
      ssrc: 0xAABBCCDD,
    );
    // RFC 3550 5.1: V=2 P=0 X=0 CC=0 | M=1 PT=97 | seq | timestamp | SSRC.
    const bytes = [
      0x80, 0xE1, 0x12, 0x34, //
      0x89, 0xAB, 0xCD, 0xEF, //
      0xAA, 0xBB, 0xCC, 0xDD, //
    ];

    final full = MidiRtpHeader(
      payloadType: 96,
      sequenceNumber: 1,
      timestamp: 2,
      ssrc: 3,
      csrcs: [0x01020304, 0x05060708],
      extension: MidiRtpHeaderExtension(profile: 9, data: [1, 2, 3, 4]),
    );
    const fullBytes = [
      0x92, 0x60, 0x00, 0x01, 0, 0, 0, 2, 0, 0, 0, 3, //
      1, 2, 3, 4, 5, 6, 7, 8, //
      0x00, 0x09, 0x00, 0x01, 1, 2, 3, 4, //
    ];

    group('toBytes(padding)', () {
      test('codes the fixed header', () {
        expect(header.toBytes(), equals(bytes));
        expect(header.length, 12);
      });

      test('sets the P bit', () {
        expect(header.toBytes(padding: true)[0], 0xA0);
      });

      test('codes CSRCs and the extension', () {
        expect(full.toBytes(), equals(fullBytes));
        expect(full.length, 28);
      });
    });

    group('MidiRtpHeader.read(reader)', () {
      test('decodes headers', () {
        expect(MidiRtpHeader.read(MidiRtpByteReader(bytes)), header);
        expect(MidiRtpHeader.read(MidiRtpByteReader(fullBytes)), full);
      });

      test('ignores the P bit', () {
        expect(
          MidiRtpHeader.read(MidiRtpByteReader([0xA0, ...bytes.skip(1)])),
          header,
        );
      });

      test('rejects other versions', () {
        expect(
          () => MidiRtpHeader.read(MidiRtpByteReader([0x40, ...bytes.skip(1)])),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'Unsupported RTP version 1',
            ),
          ),
        );
      });

      test('fails on a short header', () {
        expect(
          () => MidiRtpHeader.read(MidiRtpByteReader(bytes.sublist(0, 11))),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('copyWith()', () {
      test('replaces the given fields', () {
        expect(header.copyWith(), header);
        final changed = header.copyWith(
          marker: false,
          payloadType: 96,
          sequenceNumber: 1,
          timestamp: 2,
          ssrc: 3,
          csrcs: [0x01020304, 0x05060708],
          extension: full.extension,
        );
        expect(changed, full);
      });
    });

    group('==, hashCode, toString', () {
      test('compare by value', () {
        expect(header, MidiRtpHeader.read(MidiRtpByteReader(bytes)));
        expect(
          header.hashCode,
          MidiRtpHeader.read(MidiRtpByteReader(bytes)).hashCode,
        );
        for (final other in [
          header.copyWith(marker: false),
          header.copyWith(payloadType: 1),
          header.copyWith(sequenceNumber: 1),
          header.copyWith(timestamp: 1),
          header.copyWith(ssrc: 1),
          header.copyWith(csrcs: [1]),
          header.copyWith(extension: full.extension),
        ]) {
          expect(header == other, isFalse);
        }
        expect(
          header.toString(),
          'MidiRtpHeader(marker: true, payloadType: 97, sequenceNumber: 4660, '
          'timestamp: 2309737967, ssrc: 2864434397, csrcs: [], '
          'extension: null)',
        );
      });
    });

    group('version', () {
      test('is 2', () {
        expect(MidiRtpHeader.version, 2);
      });
    });
  });
}
