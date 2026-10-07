// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpByteReader', () {
    final bytes = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A];

    group('MidiRtpByteReader(bytes, offset, end)', () {
      test('reads a plain list and a Uint8List', () {
        expect(MidiRtpByteReader(bytes).bytes, isA<Uint8List>());
        final view = Uint8List.fromList(bytes);
        expect(MidiRtpByteReader(view).bytes, same(view));
      });

      test('starts at offset and stops at end', () {
        final reader = MidiRtpByteReader(bytes, offset: 2, end: 4);
        expect(reader.position, 2);
        expect(reader.end, 4);
        expect(reader.remaining, 2);
        expect(reader.isAtEnd, isFalse);
      });

      test('rejects an offset or end outside the list', () {
        expect(
          () => MidiRtpByteReader(bytes, end: 11),
          throwsA(isA<RangeError>()),
        );
        expect(
          () => MidiRtpByteReader(bytes, offset: 5, end: 4),
          throwsA(isA<RangeError>()),
        );
      });
    });

    group('read methods', () {
      test('read big-endian integers in order', () {
        final reader = MidiRtpByteReader(bytes);
        expect(reader.peek(), 0x01);
        expect(reader.readUint8(), 0x01);
        expect(reader.readUint16(), 0x0203);
        expect(reader.readUint24(), 0x040506);
        expect(reader.readUint32(), 0x0708090A);
        expect(reader.isAtEnd, isTrue);
      });

      test('readBytes copies the next bytes', () {
        final reader = MidiRtpByteReader(bytes, offset: 1);
        expect(reader.readBytes(3), equals([0x02, 0x03, 0x04]));
        expect(reader.position, 4);
      });

      test('skip moves forward', () {
        final reader = MidiRtpByteReader(bytes)..skip(9);
        expect(reader.readUint8(), 0x0A);
      });

      test('take returns a bounded reader and moves past it', () {
        final reader = MidiRtpByteReader(bytes, offset: 1);
        final part = reader.take(2);
        expect(part.readUint16(), 0x0203);
        expect(part.isAtEnd, isTrue);
        expect(reader.readUint8(), 0x04);
      });

      for (final read in <String, void Function(MidiRtpByteReader)>{
        'peek': (r) => r.peek(),
        'readUint8': (r) => r.readUint8(),
        'readUint32': (r) => r.readUint32(),
        'readBytes': (r) => r.readBytes(5),
        'take': (r) => r.take(5),
        'skip': (r) => r.skip(-1),
      }.entries) {
        test('${read.key} fails beyond the end', () {
          final reader = MidiRtpByteReader(bytes, offset: 8, end: 9);
          if (read.key == 'peek' || read.key == 'readUint8') reader.skip(1);
          expect(
            () => read.value(reader),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                startsWith('Unexpected end of data'),
              ),
            ),
          );
        });
      }
    });
  });
}
