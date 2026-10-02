//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class SigninRequest {
  /// Returns a new [SigninRequest] instance.
  SigninRequest({
    required this.authKey,
    required this.device,
    required this.email,
    this.totpCode,
  });

  String authKey;

  DeviceInfo device;

  String email;

  /// Needed when two-factor sign-in is on
  String? totpCode;

  @override
  bool operator ==(Object other) => identical(this, other) || other is SigninRequest &&
    other.authKey == authKey &&
    other.device == device &&
    other.email == email &&
    other.totpCode == totpCode;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (authKey.hashCode) +
    (device.hashCode) +
    (email.hashCode) +
    (totpCode == null ? 0 : totpCode!.hashCode);

  @override
  String toString() => 'SigninRequest[authKey=$authKey, device=$device, email=$email, totpCode=$totpCode]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'auth_key'] = this.authKey;
      json[r'device'] = this.device;
      json[r'email'] = this.email;
    if (this.totpCode != null) {
      json[r'totp_code'] = this.totpCode;
    } else {
      json[r'totp_code'] = null;
    }
    return json;
  }

  /// Returns a new [SigninRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static SigninRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'auth_key'), 'Required key "SigninRequest[auth_key]" is missing from JSON.');
        assert(json[r'auth_key'] != null, 'Required key "SigninRequest[auth_key]" has a null value in JSON.');
        assert(json.containsKey(r'device'), 'Required key "SigninRequest[device]" is missing from JSON.');
        assert(json[r'device'] != null, 'Required key "SigninRequest[device]" has a null value in JSON.');
        assert(json.containsKey(r'email'), 'Required key "SigninRequest[email]" is missing from JSON.');
        assert(json[r'email'] != null, 'Required key "SigninRequest[email]" has a null value in JSON.');
        return true;
      }());

      return SigninRequest(
        authKey: mapValueOfType<String>(json, r'auth_key')!,
        device: DeviceInfo.fromJson(json[r'device'])!,
        email: mapValueOfType<String>(json, r'email')!,
        totpCode: mapValueOfType<String>(json, r'totp_code'),
      );
    }
    return null;
  }

  static List<SigninRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SigninRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SigninRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SigninRequest> mapFromJson(dynamic json) {
    final map = <String, SigninRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SigninRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of SigninRequest-objects as value to a dart map
  static Map<String, List<SigninRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<SigninRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SigninRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'auth_key',
    'device',
    'email',
  };
}

