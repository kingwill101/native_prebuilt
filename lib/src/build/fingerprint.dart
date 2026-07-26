import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Compute a reproducible SHA-256 hex digest for use in build fingerprints.
///
/// Replaces `String.hashCode` which is non-deterministic across runs.
String fingerprintHash(String input) {
  return sha256.convert(utf8.encode(input)).toString();
}

/// Compute a SHA-256 hex digest from multiple string inputs.
String fingerprintHashMultiple(List<String> inputs) {
  final buffer = StringBuffer();
  for (final input in inputs) {
    buffer.write(input);
    buffer.write('\x00');
  }
  return sha256.convert(utf8.encode(buffer.toString())).toString();
}
