//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class SignedIn {
  /// Returns a new [SignedIn] instance.
  SignedIn({
    required this.deviceToken,
    required this.emailVerified,
    required this.vault,
  });

  String deviceToken;

  bool emailVerified;

  VaultKeys vault;

  @override
  bool operator ==(Object other) => identical(this, other) || other is SignedIn &&
    other.deviceToken == deviceToken &&
    other.emailVerified == emailVerified &&
    other.vault == vault;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (deviceToken.hashCode) +
    (emailVerified.hashCode) +
    (vault.hashCode);

  @override
  String toString() => 'SignedIn[deviceToken=$deviceToken, emailVerified=$emailVerified, vault=$vault]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'device_token'] = this.deviceToken;
      json[r'email_verified'] = this.emailVerified;
      json[r'vault'] = this.vault;
    return json;
  }

  /// Returns a new [SignedIn] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static SignedIn? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'device_token'), 'Required key "SignedIn[device_token]" is missing from JSON.');
        assert(json[r'device_token'] != null, 'Required key "SignedIn[device_token]" has a null value in JSON.');
        assert(json.containsKey(r'email_verified'), 'Required key "SignedIn[email_verified]" is missing from JSON.');
        assert(json[r'email_verified'] != null, 'Required key "SignedIn[email_verified]" has a null value in JSON.');
        assert(json.containsKey(r'vault'), 'Required key "SignedIn[vault]" is missing from JSON.');
        assert(json[r'vault'] != null, 'Required key "SignedIn[vault]" has a null value in JSON.');
        return true;
      }());

      return SignedIn(
        deviceToken: mapValueOfType<String>(json, r'device_token')!,
        emailVerified: mapValueOfType<bool>(json, r'email_verified')!,
        vault: VaultKeys.fromJson(json[r'vault'])!,
      );
    }
    return null;
  }

  static List<SignedIn> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SignedIn>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SignedIn.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SignedIn> mapFromJson(dynamic json) {
    final map = <String, SignedIn>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SignedIn.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of SignedIn-objects as value to a dart map
  static Map<String, List<SignedIn>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<SignedIn>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SignedIn.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'device_token',
    'email_verified',
    'vault',
  };
}

