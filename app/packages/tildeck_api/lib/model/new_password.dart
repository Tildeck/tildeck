//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class NewPassword {
  /// Returns a new [NewPassword] instance.
  NewPassword({
    required this.authKey,
    required this.kdf,
    required this.wrapPw,
  });

  String authKey;

  KdfParams kdf;

  ModelSealed wrapPw;

  @override
  bool operator ==(Object other) => identical(this, other) || other is NewPassword &&
    other.authKey == authKey &&
    other.kdf == kdf &&
    other.wrapPw == wrapPw;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (authKey.hashCode) +
    (kdf.hashCode) +
    (wrapPw.hashCode);

  @override
  String toString() => 'NewPassword[authKey=$authKey, kdf=$kdf, wrapPw=$wrapPw]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'auth_key'] = this.authKey;
      json[r'kdf'] = this.kdf;
      json[r'wrap_pw'] = this.wrapPw;
    return json;
  }

  /// Returns a new [NewPassword] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static NewPassword? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'auth_key'), 'Required key "NewPassword[auth_key]" is missing from JSON.');
        assert(json[r'auth_key'] != null, 'Required key "NewPassword[auth_key]" has a null value in JSON.');
        assert(json.containsKey(r'kdf'), 'Required key "NewPassword[kdf]" is missing from JSON.');
        assert(json[r'kdf'] != null, 'Required key "NewPassword[kdf]" has a null value in JSON.');
        assert(json.containsKey(r'wrap_pw'), 'Required key "NewPassword[wrap_pw]" is missing from JSON.');
        assert(json[r'wrap_pw'] != null, 'Required key "NewPassword[wrap_pw]" has a null value in JSON.');
        return true;
      }());

      return NewPassword(
        authKey: mapValueOfType<String>(json, r'auth_key')!,
        kdf: KdfParams.fromJson(json[r'kdf'])!,
        wrapPw: ModelSealed.fromJson(json[r'wrap_pw'])!,
      );
    }
    return null;
  }

  static List<NewPassword> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <NewPassword>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = NewPassword.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, NewPassword> mapFromJson(dynamic json) {
    final map = <String, NewPassword>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = NewPassword.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of NewPassword-objects as value to a dart map
  static Map<String, List<NewPassword>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<NewPassword>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = NewPassword.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'auth_key',
    'kdf',
    'wrap_pw',
  };
}

