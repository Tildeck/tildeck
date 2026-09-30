//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class RecoveryStart {
  /// Returns a new [RecoveryStart] instance.
  RecoveryStart({
    required this.email,
    required this.recoveryAuthKey,
  });

  String email;

  String recoveryAuthKey;

  @override
  bool operator ==(Object other) => identical(this, other) || other is RecoveryStart &&
    other.email == email &&
    other.recoveryAuthKey == recoveryAuthKey;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (email.hashCode) +
    (recoveryAuthKey.hashCode);

  @override
  String toString() => 'RecoveryStart[email=$email, recoveryAuthKey=$recoveryAuthKey]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'email'] = this.email;
      json[r'recovery_auth_key'] = this.recoveryAuthKey;
    return json;
  }

  /// Returns a new [RecoveryStart] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static RecoveryStart? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'email'), 'Required key "RecoveryStart[email]" is missing from JSON.');
        assert(json[r'email'] != null, 'Required key "RecoveryStart[email]" has a null value in JSON.');
        assert(json.containsKey(r'recovery_auth_key'), 'Required key "RecoveryStart[recovery_auth_key]" is missing from JSON.');
        assert(json[r'recovery_auth_key'] != null, 'Required key "RecoveryStart[recovery_auth_key]" has a null value in JSON.');
        return true;
      }());

      return RecoveryStart(
        email: mapValueOfType<String>(json, r'email')!,
        recoveryAuthKey: mapValueOfType<String>(json, r'recovery_auth_key')!,
      );
    }
    return null;
  }

  static List<RecoveryStart> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <RecoveryStart>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RecoveryStart.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, RecoveryStart> mapFromJson(dynamic json) {
    final map = <String, RecoveryStart>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = RecoveryStart.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of RecoveryStart-objects as value to a dart map
  static Map<String, List<RecoveryStart>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<RecoveryStart>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = RecoveryStart.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'email',
    'recovery_auth_key',
  };
}

