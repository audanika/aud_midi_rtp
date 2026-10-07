// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpPacket', () {
    final packet = MidiRtpPacket(
      header: MidiRtpHeader(
        marker: true,
        payloadType: 97,
        sequenceNumber: 0x0102,
        timestamp: 0x00000064,
        ssrc: 0x11223344,
      ),
      payload: MidiRtpPayload(
        commands: [
          const MidiRtpMessageCommand(
            message: MidiNoteOff(channel: 1, note: 0x40, velocity: 0x20),
          ),
        ],
        journal: MidiRtpJournal(checkpoint: 0x0101),
      ),
    );
    // RFC 6295 Figure 1: RTP header, MIDI command section, journal.
    const bytes = [
      0x80, 0xE1, 0x01, 0x02, 0x00, 0x00, 0x00, 0x64, //
      0x11, 0x22, 0x33, 0x44, //
      0x43, 0x81, 0x40, 0x20, //
      0x80, 0x01, 0x01, //
    ];

    group('toBytes()', () {
      test('codes header and payload', () {
        expect(packet.toBytes(), equals(bytes));
      });

      test('appends padding and sets the P bit', () {
        final padded = packet.copyWith(paddingLength: 3).toBytes();
        expect(padded.first, 0xA0);
        expect(padded.sublist(padded.length - 3), equals([0, 0, 3]));
      });
    });

    group('MidiRtpPacket.decode(bytes)', () {
      test('decodes the packet', () {
        expect(MidiRtpPacket.decode(bytes), packet);
      });

      test('strips padding', () {
        final padded = packet.copyWith(paddingLength: 4);
        expect(MidiRtpPacket.decode(padded.toBytes()), padded);
      });

      for (final count in [0, 9]) {
        test('rejects a padding count of $count', () {
          expect(
            () => MidiRtpPacket.decode([0xA0, ...bytes.sublist(1, 12), count]),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                'Illegal padding count $count',
              ),
            ),
          );
        });
      }

      test('fails on an empty packet', () {
        expect(
          () => MidiRtpPacket.decode(const []),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('copyWith()', () {
      test('replaces the given fields', () {
        expect(packet.copyWith(), packet);
        final header = packet.header.copyWith(sequenceNumber: 9);
        final payload = MidiRtpPayload();
        final changed = packet.copyWith(header: header, payload: payload);
        expect(changed.header, header);
        expect(changed.payload, payload);
      });
    });

    group('==, hashCode, toString', () {
      test('compare by value', () {
        expect(packet, MidiRtpPacket.decode(bytes));
        expect(packet.hashCode, MidiRtpPacket.decode(bytes).hashCode);
        expect(packet == packet.copyWith(paddingLength: 1), isFalse);
        expect(packet == packet.copyWith(payload: MidiRtpPayload()), isFalse);
        expect(
          packet ==
              packet.copyWith(header: packet.header.copyWith(timestamp: 1)),
          isFalse,
        );
        expect(packet.toString(), startsWith('MidiRtpPacket(header: '));
      });
    });
  });
}
