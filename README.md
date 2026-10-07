# aud_midi_rtp

RFC 6295 (RTP-MIDI) as Dart: payload format and the complete recovery journal, sender and receiver, codec only without sockets.

Part of the aud_midi family, see [aud_midi](https://github.com/audmidi/aud_midi).

## Goals

- RTP-MIDI payload and MIDI command section
- Complete recovery journal, all channel and system chapters
- Sender policies and receiver repair
- Session configuration per Appendix C
- In-memory lossy channel for tests

## State

Implemented as a codec without sockets and without `dart:io`:

- RTP header, MIDI command section (B, J, Z, P, LEN), delta times, running status, SysEx segmentation and cancel
- Complete recovery journal: channel chapters P, C, M, W, N, E, T, A, system chapters D, V, Q, F, X, enhanced Chapter C
- `MidiRtpSender`: session history, closed-loop (default), open-loop and anchor checkpoints, S bits, trimming after feedback
- `MidiRtpReceiver`: sequence tracking, checkpoint validation, per-chapter repair, loss diagnostics and counters
- `MidiRtpSessionConfig`: `fmtp` parameters of Appendix C, AppleMIDI preset
- `MidiRtpLossyChannel`: loss, bursts, reordering and duplication for tests

Open: tests against packet captures of Apple's driver, together with `aud_midi_network`. See the plan in [aud_midi_pm](https://github.com/audmidi/aud_midi_pm/blob/main/doc/2026-Q4/tickets/2026-10-06-aud_midi_01-initial-midi-implementation.md).

## Installation

```bash
dart pub add aud_midi_rtp
```

## Contributing

See [doc/guides/develop-guide.md](doc/guides/develop-guide.md).
