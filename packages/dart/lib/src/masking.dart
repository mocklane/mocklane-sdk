// Redacts secrets in log messages before they are sent.

import 'dart:convert';

const _defaultHeaderKeys = {
  'authorization',
  'cookie',
  'set-cookie',
  'x-api-key',
  'x-auth-token',
  'proxy-authorization',
};

const _defaultJsonKeys = {
  'password',
  'token',
  'access_token',
  'refresh_token',
  'id_token',
  'secret',
  'client_secret',
  'api_key',
  'session',
  'session_id',
};

Map<String, String> maskHeaders(
  Map<String, String> headers, {
  Set<String> headerKeys = _defaultHeaderKeys,
  String replacement = '[REDACTED]',
}) {
  return {
    for (final e in headers.entries)
      e.key: headerKeys.contains(e.key.toLowerCase()) ? replacement : e.value,
  };
}

dynamic maskJsonValue(
  dynamic value, {
  Set<String> jsonKeys = _defaultJsonKeys,
  String replacement = '[REDACTED]',
}) {
  if (value is List) {
    return [for (final item in value) maskJsonValue(item, jsonKeys: jsonKeys, replacement: replacement)];
  }
  if (value is Map) {
    return {
      for (final e in value.entries)
        e.key: jsonKeys.contains(e.key.toString().toLowerCase())
            ? replacement
            : maskJsonValue(e.value, jsonKeys: jsonKeys, replacement: replacement),
    };
  }
  return value;
}

/// Masks secrets inside a JSON-shaped string; returns [raw] unchanged when it
/// is not valid JSON.
String maskJsonString(
  String raw, {
  Set<String> jsonKeys = _defaultJsonKeys,
  String replacement = '[REDACTED]',
}) {
  try {
    final parsed = jsonDecode(raw);
    return jsonEncode(
      maskJsonValue(parsed, jsonKeys: jsonKeys, replacement: replacement),
    );
  } on FormatException {
    return raw;
  }
}
