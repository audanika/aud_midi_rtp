// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:math';

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpLossyChannel', () {
    List<int> sendAll(MidiRtpLossyChannel channel, int count) {
      for (var i = 0; i < count; i++) {
        channel.send([i >> 8, i & 0xFF]);
      }
      return [for (final p in channel.flush()) p[0] << 8 | p[1]];
    }

    test('passes every packet in order by default', () {
      final channel = MidiRtpLossyChannel();
      expect(sendAll(channel, 5), equals([0, 1, 2, 3, 4]));
      expect(channel.sent, 5);
      expect(channel.lost, 0);
      expect(channel.duplicated, 0);
      expect(channel.reordered, 0);
    });

    test('copies the packets', () {
      final channel = MidiRtpLossyChannel();
      final packet = [1, 2];
      channel.send(packet);
      packet[0] = 9;
      expect(channel.receive().single, equals([1, 2]));
      expect(channel.receive(), isEmpty);
    });

    test('loses packets at the loss rate', () {
      final channel = MidiRtpLossyChannel(seed: 1, lossRate: 0.5);
      final arrived = sendAll(channel, 1000);
      expect(channel.lost, 1000 - arrived.length);
      expect(arrived.length, inInclusiveRange(400, 600));
      expect(arrived, equals([...arrived]..sort()));
    });

    test('loses bursts of packets', () {
      final channel = MidiRtpLossyChannel(
        seed: 2,
        burstLossRate: 0.1,
        burstLength: 5,
      );
      final arrived = sendAll(channel, 1000);
      var longest = 0;
      for (var i = 1; i < arrived.length; i++) {
        longest = max(longest, arrived[i] - arrived[i - 1] - 1);
      }
      expect(longest, greaterThan(1));
      expect(channel.lost, 1000 - arrived.length);
      final single = MidiRtpLossyChannel(seed: 2, burstLossRate: 1);
      expect(sendAll(single, 10), isEmpty);
    });

    test('duplicates packets', () {
      final channel = MidiRtpLossyChannel(seed: 3, duplicateRate: 0.2);
      final arrived = sendAll(channel, 100);
      expect(arrived.length, 100 + channel.duplicated);
      expect(channel.duplicated, greaterThan(0));
    });

    test('reorders packets within the depth', () {
      final channel = MidiRtpLossyChannel(
        seed: 4,
        reorderRate: 0.2,
        reorderDepth: 2,
      );
      final arrived = sendAll(channel, 100);
      expect(arrived..sort(), equals(List.generate(100, (i) => i)));
      expect(channel.reordered, greaterThan(0));
      final again = MidiRtpLossyChannel(
        seed: 4,
        reorderRate: 0.2,
        reorderDepth: 2,
      );
      for (var i = 0; i < 100; i++) {
        again.send([i]);
      }
      final order = [for (final p in again.flush()) p.single];
      expect(order, hasLength(100));
      for (var i = 0; i < order.length; i++) {
        expect((order[i] - i).abs(), lessThanOrEqualTo(2));
      }
      expect(order, isNot(equals(List.generate(100, (i) => i))));
    });

    test('takes a random generator and keeps its settings', () {
      final channel = MidiRtpLossyChannel(
        random: Random(5),
        lossRate: 0.1,
        burstLossRate: 0.2,
        burstLength: 4,
        duplicateRate: 0.3,
        reorderRate: 0.4,
        reorderDepth: 6,
      );
      expect([
        channel.lossRate,
        channel.burstLossRate,
        channel.burstLength,
        channel.duplicateRate,
        channel.reorderRate,
        channel.reorderDepth,
      ], equals([0.1, 0.2, 4, 0.3, 0.4, 6]));
    });

    test('yields the same fate for the same seed', () {
      List<int> run() => sendAll(
        MidiRtpLossyChannel(
          seed: 9,
          lossRate: 0.2,
          duplicateRate: 0.1,
          reorderRate: 0.1,
        ),
        200,
      );
      expect(run(), equals(run()));
    });
  });
}
