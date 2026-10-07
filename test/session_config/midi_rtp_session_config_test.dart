// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpSessionConfig', () {
    MidiRtpSessionConfig parse(String line, {bool reliable = false}) =>
        MidiRtpSessionConfig.fromFmtp(
          MidiRtpFmtp.parse(line),
          clockRate: 44100,
          reliableTransport: reliable,
        );

    group('appleMidi', () {
      test('is the preset of Apple network MIDI sessions', () {
        const apple = MidiRtpSessionConfig.appleMidi;
        expect(apple.clockRate, 10000);
        expect(apple.payloadType, 97);
        expect(apple.journal, isTrue);
        expect(apple.sendingPolicy, MidiRtpSendingPolicy.closedLoop);
        expect(apple.usesEnhancedChapterC(0), isFalse);
        expect(apple.maxPacketSize, 1472);
        expect(apple.toFmtp().toString(), 'a=fmtp:97');
      });
    });

    group('MidiRtpSessionConfig.fromFmtp(fmtp, clockRate, reliable)', () {
      test('parses the codec parameters and keeps the others', () {
        final config = parse(
          'a=fmtp:96 j_sec=recj; j_update=anchor; cm_unused=ABC; '
          'cm_used=1C7; ch_never=D; ch_anchor=0C135; tsmode=async; '
          'octpos=first; linerate=320000; mperiod=44; rtp_ptime=0; '
          'rtp_maxptime=441; guardtime=44100; musicport=12; '
          'render=synthetic; rinit=audio/asc; url="http://x/a.asc"',
        );
        expect(config.clockRate, 44100);
        expect(config.payloadType, 96);
        expect(config.journal, isTrue);
        expect(config.sendingPolicy, MidiRtpSendingPolicy.anchor);
        expect(
          [for (final a in config.assignments) '${a.parameter}=$a'],
          equals([
            'cm_unused=ABC',
            'cm_used=1C7',
            'ch_never=D',
            'ch_anchor=0C135',
          ]),
        );
        expect(config.timestampMode, MidiRtpTimestampMode.async);
        expect(config.octetPosition, 'first');
        expect(config.lineRate, 320000);
        expect(config.samplingPeriod, 44);
        expect(config.packetTime, 0);
        expect(config.maxPacketTime, 441);
        expect(config.guardTime, 44100);
        expect(config.musicPort, 12);
        expect(
          config.otherParameters,
          equals([
            const MidiRtpFmtpParameter('render', 'synthetic'),
            const MidiRtpFmtpParameter('rinit', 'audio/asc'),
            const MidiRtpFmtpParameter('url', 'http://x/a.asc', quoted: true),
          ]),
        );
      });

      test('follows the transport without j_sec', () {
        expect(parse('a=fmtp:96').journal, isTrue);
        expect(parse('a=fmtp:96', reliable: true).journal, isFalse);
        expect(parse('a=fmtp:96 j_sec=none').journal, isFalse);
        expect(parse('a=fmtp:96 j_sec=recj', reliable: true).journal, isTrue);
      });

      for (final bad in <String, String>{
        'j_sec=fec': 'Unknown j_sec value',
        'j_update=fast': 'Unknown j_update value',
        'tsmode=exact': 'Unknown tsmode value',
        'octpos=middle': 'Unknown octpos value',
        'guardtime=x': 'Illegal guardtime value',
        'musicport=4294967296': 'Illegal musicport value',
        'rtp_ptime=-1': 'Illegal rtp_ptime value',
        'cm_used=n': 'Illegal assignment',
      }.entries) {
        test('rejects ${bad.key}', () {
          expect(
            () => parse('a=fmtp:96 ${bad.key}'),
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

    group('toFmtp(journalSection)', () {
      test('writes the parameters that differ from the defaults', () {
        const line =
            'a=fmtp:96 j_sec=none; j_update=open-loop; cm_unused=X; '
            'ch_never=4.11-13N; tsmode=buffer; octpos=last; '
            'linerate=320000; mperiod=44; rtp_ptime=0; rtp_maxptime=0; '
            'guardtime=44100; musicport=1; render=api';
        final config = parse(line);
        expect(config.toFmtp().toString(), line);
        expect(
          MidiRtpSessionConfig.fromFmtp(config.toFmtp(), clockRate: 44100),
          config,
        );
      });

      test('writes j_sec=recj on request', () {
        expect(
          MidiRtpSessionConfig.appleMidi
              .toFmtp(journalSection: true)
              .toString(),
          'a=fmtp:97 j_sec=recj',
        );
      });
    });

    group('allowsCommand(letter, channel, field)', () {
      test('excludes the undefined commands by default', () {
        const config = MidiRtpSessionConfig.appleMidi;
        for (final letter in 'JKYZ'.split('')) {
          expect(config.allowsCommand(letter), isFalse);
        }
        for (final letter in 'ABCFGHMNPQTVWX'.split('')) {
          expect(config.allowsCommand(letter), isTrue);
        }
      });

      test('applies cm_used and cm_unused in order', () {
        final config = parse(
          'a=fmtp:96 cm_unused=CN; cm_used=2C7.64; cm_used=JY; '
          'ch_never=C',
        );
        expect(config.allowsCommand('C', channel: 1, field: 7), isFalse);
        expect(config.allowsCommand('C', channel: 2, field: 7), isTrue);
        expect(config.allowsCommand('C', channel: 2, field: 8), isFalse);
        expect(config.allowsCommand('N', channel: 0, field: 60), isFalse);
        expect(config.allowsCommand('J'), isTrue);
        expect(config.allowsCommand('Y'), isTrue);
        expect(config.allowsCommand('K'), isFalse);
      });
    });

    group('allowsSysEx(data)', () {
      test('applies classes and sizes in order', () {
        final config = parse(
          'a=fmtp:96 cm_unused=X; cm_used=__7E_00-7F_09_01.02.03__; '
          'cm_used=X0-2',
        );
        expect(config.allowsSysEx([0x7E, 0x10, 0x09, 0x01]), isTrue);
        expect(config.allowsSysEx([0x41, 1]), isTrue);
        expect(config.allowsSysEx([0x41, 1, 2, 3]), isFalse);
        expect(MidiRtpSessionConfig.appleMidi.allowsSysEx([1]), isTrue);
      });
    });

    group('chapterSemantics(letter, channel, field)', () {
      test('applies the chapter inclusion parameters in order', () {
        final config = parse(
          'a=fmtp:96 cm_unused=C; ch_never=ABCDEFGHJKMNPQTVWXYZ; '
          'ch_never=4.11-13N; ch_anchor=P; ch_anchor=C7.64; ch_default=0N',
        );
        expect(
          config.chapterSemantics('P', channel: 1),
          MidiRtpChapterSemantics.anchor,
        );
        expect(
          config.chapterSemantics('C', channel: 1, field: 7),
          MidiRtpChapterSemantics.anchor,
        );
        expect(
          config.chapterSemantics('C', channel: 1, field: 8),
          MidiRtpChapterSemantics.never,
        );
        expect(
          config.chapterSemantics('N', channel: 0),
          MidiRtpChapterSemantics.standard,
        );
        expect(
          config.chapterSemantics('N', channel: 4),
          MidiRtpChapterSemantics.never,
        );
        expect(
          MidiRtpSessionConfig.appleMidi.chapterSemantics('W'),
          MidiRtpChapterSemantics.standard,
        );
      });

      test('applies D to its subchapters', () {
        final config = parse('a=fmtp:96 ch_never=D; ch_anchor=G');
        expect(config.chapterSemantics('B'), MidiRtpChapterSemantics.never);
        expect(config.chapterSemantics('G'), MidiRtpChapterSemantics.anchor);
      });

      test('matches both field values of a controller', () {
        final config = parse('a=fmtp:96 ch_anchor=C135');
        expect(
          config.chapterSemantics('C', channel: 0, field: 7),
          MidiRtpChapterSemantics.anchor,
        );
        expect(
          config.chapterSemantics('C', channel: 0, field: 8),
          MidiRtpChapterSemantics.standard,
        );
      });
    });

    group('sysExSemantics(data)', () {
      test('applies classes and sizes in order', () {
        final config = parse(
          'a=fmtp:96 ch_never=X; ch_anchor=__7E_00-7F_09_01__; '
          'ch_default=X0-3; cm_used=X',
        );
        expect(
          config.sysExSemantics([0x7E, 0x10, 0x09, 0x01, 5]),
          MidiRtpChapterSemantics.anchor,
        );
        expect(config.sysExSemantics([1, 2]), MidiRtpChapterSemantics.standard);
        expect(
          config.sysExSemantics([1, 2, 3, 4, 5]),
          MidiRtpChapterSemantics.never,
        );
      });
    });

    group('isEnhanced(channel, controller)', () {
      test('follows the field values above 127', () {
        final config = parse(
          'a=fmtp:96 ch_default=0C135.138; ch_anchor=0C7; ch_never=0C138; '
          'ch_default=1C; ch_default=2C192',
        );
        expect(config.isEnhanced(0, 7), isFalse);
        expect(config.isEnhanced(0, 10), isTrue);
        expect(config.isEnhanced(0, 11), isFalse);
        expect(config.isEnhanced(1, 7), isFalse);
        expect(config.isEnhanced(2, 64), isTrue);
        expect(config.isEnhanced(3, 64), isFalse);
        expect(config.usesEnhancedChapterC(0), isTrue);
        expect(
          parse('a=fmtp:96 ch_default=4C7').usesEnhancedChapterC(4),
          isFalse,
        );
      });

      test('a later assignment without field list ends the encoding', () {
        final config = parse('a=fmtp:96 ch_default=0C135; ch_default=0C');
        expect(config.isEnhanced(0, 7), isFalse);
      });
    });

    group('copyWith()', () {
      test('replaces the given fields', () {
        const config = MidiRtpSessionConfig(clockRate: 1);
        final assignment = MidiRtpAssignment.parse('N', parameter: 'ch_never');
        expect(config.copyWith(), config);
        final changed = config.copyWith(
          clockRate: 2,
          payloadType: 3,
          journal: false,
          sendingPolicy: MidiRtpSendingPolicy.openLoop,
          assignments: [assignment],
          timestampMode: MidiRtpTimestampMode.buffer,
          octetPosition: 'last',
          lineRate: 4,
          samplingPeriod: 5,
          packetTime: 6,
          maxPacketTime: 7,
          guardTime: 8,
          musicPort: 9,
          otherParameters: [const MidiRtpFmtpParameter('a', 'b')],
          maxPacketSize: 100,
        );
        expect(
          changed,
          MidiRtpSessionConfig(
            clockRate: 2,
            payloadType: 3,
            journal: false,
            sendingPolicy: MidiRtpSendingPolicy.openLoop,
            assignments: [assignment],
            timestampMode: MidiRtpTimestampMode.buffer,
            octetPosition: 'last',
            lineRate: 4,
            samplingPeriod: 5,
            packetTime: 6,
            maxPacketTime: 7,
            guardTime: 8,
            musicPort: 9,
            otherParameters: const [MidiRtpFmtpParameter('a', 'b')],
            maxPacketSize: 100,
          ),
        );
      });
    });

    group('==, hashCode, toString', () {
      test('compare by value', () {
        const config = MidiRtpSessionConfig(clockRate: 1);
        expect(config, const MidiRtpSessionConfig(clockRate: 1));
        expect(
          config.hashCode,
          const MidiRtpSessionConfig(clockRate: 1).hashCode,
        );
        final assignment = MidiRtpAssignment.parse('N', parameter: 'ch_never');
        for (final other in [
          config.copyWith(clockRate: 2),
          config.copyWith(payloadType: 3),
          config.copyWith(journal: false),
          config.copyWith(sendingPolicy: MidiRtpSendingPolicy.anchor),
          config.copyWith(assignments: [assignment]),
          config.copyWith(timestampMode: MidiRtpTimestampMode.async),
          config.copyWith(octetPosition: 'first'),
          config.copyWith(lineRate: 1),
          config.copyWith(samplingPeriod: 1),
          config.copyWith(packetTime: 1),
          config.copyWith(maxPacketTime: 1),
          config.copyWith(guardTime: 1),
          config.copyWith(musicPort: 1),
          config.copyWith(
            otherParameters: [const MidiRtpFmtpParameter('a', 'b')],
          ),
          config.copyWith(maxPacketSize: 100),
        ]) {
          expect(config == other, isFalse);
        }
        expect(
          config.toString(),
          'MidiRtpSessionConfig(clockRate: 1, maxPacketSize: 1472, '
          'a=fmtp:96)',
        );
      });
    });
  });
}
