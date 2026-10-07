// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// #############################################################################
/// The STA field of a Chapter X command log: the status of the System
/// Exclusive command the log codes (RFC 6295 B.5.1).
enum MidiRtpSysExStatus {
  /// STA 0: the command is unfinished; more segments follow.
  unfinished,

  /// STA 1: the command was cancelled.
  cancelled,

  /// STA 2: the command is finished and uses the dropped 0xF7
  /// construction.
  droppedF7,

  /// STA 3: the command is finished.
  finished;

  // ...........................................................................
  /// Whether the command is finished: completed or cancelled.
  bool get isFinished => this != unfinished;

  /// Whether the command was completed, with or without its 0xF7.
  bool get isComplete => this == droppedF7 || this == finished;
}
