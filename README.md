# aud_midi_rtp

RFC 6295 (RTP-MIDI) as Dart: payload format and the complete recovery journal, sender and receiver, codec only without sockets.

Part of the aud_midi family, see [aud_midi](https://github.com/audanika/aud_midi).

## Goals

- RTP-MIDI payload and MIDI command section
- Complete recovery journal, all channel and system chapters
- Sender policies and receiver repair
- Session configuration per Appendix C
- In-memory lossy channel for tests

## State

Boilerplate only. The implementation follows in later tickets, see the plan in [audanika_midi_pm](https://github.com/audanika/audanika_midi_pm/blob/main/doc/2026-Q4/tickets/2026-10-06-aud_midi_01-initial-midi-implementation.md).

## Installation

```bash
dart pub add aud_midi_rtp
```

## Contributing

See [doc/guides/develop-guide.md](doc/guides/develop-guide.md).
