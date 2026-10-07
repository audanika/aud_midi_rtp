// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// #############################################################################
/// The recovery journal sending policies a sender uses to choose the
/// checkpoint packet of each journal, the values of the j_update parameter
/// (RFC 6295 C.2.2).
enum MidiRtpSendingPolicy {
  /// The first packet of the stream is the checkpoint of every journal
  /// (RFC 6295 C.2.2.1); no feedback is needed, journals grow with the
  /// state of the stream.
  anchor('anchor'),

  /// The checkpoint follows the receiver feedback: one after the highest
  /// sequence number every receiver acknowledged (RFC 6295 C.2.2.2). The
  /// default policy; AppleMIDI's receiver feedback drives it.
  closedLoop('closed-loop'),

  /// The checkpoint follows no feedback; receivers repair uncovered losses
  /// themselves (RFC 6295 C.2.2.3).
  openLoop('open-loop');

  /// Creates a policy with its j_update [token].
  const MidiRtpSendingPolicy(this.token);

  // ...........................................................................
  /// The j_update parameter value.
  final String token;

  // ...........................................................................
  /// Returns the policy of the j_update [token].
  ///
  /// Throws a [FormatException] for unknown tokens, which a party must not
  /// accept (RFC 6295 C.2.2).
  static MidiRtpSendingPolicy fromToken(String token) => values.firstWhere(
    (policy) => policy.token == token,
    orElse: () => throw FormatException('Unknown j_update value', token),
  );
}
