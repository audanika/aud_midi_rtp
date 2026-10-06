# aud_midi_rtp

RFC 6295 (RTP-MIDI) als Dart: Payload-Format und vollständiges Recovery Journal, Sender und Empfänger, nur Codec ohne Sockets.

Teil der aud_midi-Familie, siehe [aud_midi](https://github.com/audanika/aud_midi).

## Ziele

- RTP-MIDI-Payload und MIDI-Command-Section
- Vollständiges Recovery Journal, alle Channel- und System-Chapter
- Sender-Policies und Reparatur beim Empfänger
- Session-Konfiguration nach Appendix C
- In-Memory-Kanal mit Paketverlust für Tests

## Stand

Nur Boilerplate. Die Implementierung folgt in späteren Tickets, siehe den Plan in [aud_midi_pm](https://github.com/audanika/aud_midi_pm/blob/main/doc/2026-Q4/tickets/2026-10-06-aud_midi_01-initial-midi-implementation.md).

## Installation

```bash
dart pub add aud_midi_rtp
```

## Mitwirken

Siehe [doc/guides/develop-guide.md](doc/guides/develop-guide.md).
