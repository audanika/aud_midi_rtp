// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// #############################################################################
/// Compares and hashes the list fields of the immutable models of the
/// package element by element.
///
/// The helper is internal: the barrel does not export it.
abstract final class MidiRtpEquality {
  // ...........................................................................
  /// Returns whether [a] and [b] are both null or hold equal elements in the
  /// same order.
  static bool lists(List<Object?>? a, List<Object?>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ...........................................................................
  /// Returns a hash of the elements of [list], or of null.
  static int hash(List<Object?>? list) =>
      list == null ? null.hashCode : Object.hashAll(list);

  // ...........................................................................
  /// Returns [bytes] as lower-case hex pairs separated by spaces, or `null`.
  static String hex(List<int>? bytes) => bytes == null
      ? 'null'
      : '[${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}]';
}
