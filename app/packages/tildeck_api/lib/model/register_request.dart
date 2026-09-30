//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class RegisterRequest {
  /// Returns a new [RegisterRequest] instance.
  RegisterRequest({
    required this.authKey,
    required this.device,
    required this.email,
    required this.kdf,
    this.locale = 'en',
    required this.recoveryAuthKey,
    required this.vaultId,
    required this.wrapPw,
    required this.wrapRk,
  });

  String authKey;

  DeviceInfo device;

  String email;

  KdfParams kdf;

  String locale;

  String recoveryAuthKey;

  String vaultId;

  ModelSealed wrapPw;

  ModelSealed wrapRk;

  @override
  bool operator ==(Object other) => identical(this, other) || other is RegisterRequest &&
    other.authKey == authKey &&
    other.device == device &&
    other.email == email &&
    other.kdf == kdf &&
    other.locale == locale &&
    other.recoveryAuthKey == recoveryAuthKey &&
    other.vaultId == vaultId &&
    other.wrapPw == wrapPw &&
    other.wrapRk == wrapRk;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (authKey.hashCode) +
    (device.hashCode) +
    (email.hashCode) +
    (kdf.hashCode) +
    (locale.hashCode) +
    (recoveryAuthKey.hashCode) +
    (vaultId.hashCode) +
    (wrapPw.hashCode) +
    (wrapRk.hashCode);

  @override
  String toString() => 'RegisterRequest[authKey=$authKey, device=$device, email=$email, kdf=$kdf, locale=$locale, recoveryAuthKey=$recoveryAuthKey, vaultId=$vaultId, wrapPw=$wrapPw, wrapRk=$wrapRk]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'auth_key'] = this.authKey;
      json[r'device'] = this.device;
      json[r'email'] = this.email;
      json[r'kdf'] = this.kdf;
      json[r'locale'] = this.locale;
      json[r'recovery_auth_key'] = this.recoveryAuthKey;
      json[r'vault_id'] = this.vaultId;
      json[r'wrap_pw'] = this.wrapPw;
      json[r'wrap_rk'] = this.wrapRk;
    return json;
  }

  /// Returns a new [RegisterRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static RegisterRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'auth_key'), 'Required key "RegisterRequest[auth_key]" is missing from JSON.');
        assert(json[r'auth_key'] != null, 'Required key "RegisterRequest[auth_key]" has a null value in JSON.');
        assert(json.containsKey(r'device'), 'Required key "RegisterRequest[device]" is missing from JSON.');
        assert(json[r'device'] != null, 'Required key "RegisterRequest[device]" has a null value in JSON.');
        assert(json.containsKey(r'email'), 'Required key "RegisterRequest[email]" is missing from JSON.');
        assert(json[r'email'] != null, 'Required key "RegisterRequest[email]" has a null value in JSON.');
        assert(json.containsKey(r'kdf'), 'Required key "RegisterRequest[kdf]" is missing from JSON.');
        assert(json[r'kdf'] != null, 'Required key "RegisterRequest[kdf]" has a null value in JSON.');
        assert(json.containsKey(r'recovery_auth_key'), 'Required key "RegisterRequest[recovery_auth_key]" is missing from JSON.');
        assert(json[r'recovery_auth_key'] != null, 'Required key "RegisterRequest[recovery_auth_key]" has a null value in JSON.');
        assert(json.containsKey(r'vault_id'), 'Required key "RegisterRequest[vault_id]" is missing from JSON.');
        assert(json[r'vault_id'] != null, 'Required key "RegisterRequest[vault_id]" has a null value in JSON.');
        assert(json.containsKey(r'wrap_pw'), 'Required key "RegisterRequest[wrap_pw]" is missing from JSON.');
        assert(json[r'wrap_pw'] != null, 'Required key "RegisterRequest[wrap_pw]" has a null value in JSON.');
        assert(json.containsKey(r'wrap_rk'), 'Required key "RegisterRequest[wrap_rk]" is missing from JSON.');
        assert(json[r'wrap_rk'] != null, 'Required key "RegisterRequest[wrap_rk]" has a null value in JSON.');
        return true;
      }());

      return RegisterRequest(
        authKey: mapValueOfType<String>(json, r'auth_key')!,
        device: DeviceInfo.fromJson(json[r'device'])!,
        email: mapValueOfType<String>(json, r'email')!,
        kdf: KdfParams.fromJson(json[r'kdf'])!,
        locale: mapValueOfType<String>(json, r'locale') ?? 'en',
        recoveryAuthKey: mapValueOfType<String>(json, r'recovery_auth_key')!,
        vaultId: mapValueOfType<String>(json, r'vault_id')!,
        wrapPw: ModelSealed.fromJson(json[r'wrap_pw'])!,
        wrapRk: ModelSealed.fromJson(json[r'wrap_rk'])!,
      );
    }
    return null;
  }

  static List<RegisterRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <RegisterRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RegisterRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, RegisterRequest> mapFromJson(dynamic json) {
    final map = <String, RegisterRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = RegisterRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of RegisterRequest-objects as value to a dart map
  static Map<String, List<RegisterRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<RegisterRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = RegisterRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'auth_key',
    'device',
    'email',
    'kdf',
    'recovery_auth_key',
    'vault_id',
    'wrap_pw',
    'wrap_rk',
  };
}

