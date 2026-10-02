//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class RecoveryComplete {
  /// Returns a new [RecoveryComplete] instance.
  RecoveryComplete({
    required this.device,
    required this.email,
    required this.new_,
    required this.recoveryAuthKey,
    this.totpCode,
  });

  DeviceInfo device;

  String email;

  NewPassword new_;

  String recoveryAuthKey;

  String? totpCode;

  @override
  bool operator ==(Object other) => identical(this, other) || other is RecoveryComplete &&
    other.device == device &&
    other.email == email &&
    other.new_ == new_ &&
    other.recoveryAuthKey == recoveryAuthKey &&
    other.totpCode == totpCode;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (device.hashCode) +
    (email.hashCode) +
    (new_.hashCode) +
    (recoveryAuthKey.hashCode) +
    (totpCode == null ? 0 : totpCode!.hashCode);

  @override
  String toString() => 'RecoveryComplete[device=$device, email=$email, new_=$new_, recoveryAuthKey=$recoveryAuthKey, totpCode=$totpCode]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'device'] = this.device;
      json[r'email'] = this.email;
      json[r'new'] = this.new_;
      json[r'recovery_auth_key'] = this.recoveryAuthKey;
    if (this.totpCode != null) {
      json[r'totp_code'] = this.totpCode;
    } else {
      json[r'totp_code'] = null;
    }
    return json;
  }

  /// Returns a new [RecoveryComplete] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static RecoveryComplete? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'device'), 'Required key "RecoveryComplete[device]" is missing from JSON.');
        assert(json[r'device'] != null, 'Required key "RecoveryComplete[device]" has a null value in JSON.');
        assert(json.containsKey(r'email'), 'Required key "RecoveryComplete[email]" is missing from JSON.');
        assert(json[r'email'] != null, 'Required key "RecoveryComplete[email]" has a null value in JSON.');
        assert(json.containsKey(r'new'), 'Required key "RecoveryComplete[new]" is missing from JSON.');
        assert(json[r'new'] != null, 'Required key "RecoveryComplete[new]" has a null value in JSON.');
        assert(json.containsKey(r'recovery_auth_key'), 'Required key "RecoveryComplete[recovery_auth_key]" is missing from JSON.');
        assert(json[r'recovery_auth_key'] != null, 'Required key "RecoveryComplete[recovery_auth_key]" has a null value in JSON.');
        return true;
      }());

      return RecoveryComplete(
        device: DeviceInfo.fromJson(json[r'device'])!,
        email: mapValueOfType<String>(json, r'email')!,
        new_: NewPassword.fromJson(json[r'new'])!,
        recoveryAuthKey: mapValueOfType<String>(json, r'recovery_auth_key')!,
        totpCode: mapValueOfType<String>(json, r'totp_code'),
      );
    }
    return null;
  }

  static List<RecoveryComplete> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <RecoveryComplete>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RecoveryComplete.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, RecoveryComplete> mapFromJson(dynamic json) {
    final map = <String, RecoveryComplete>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = RecoveryComplete.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of RecoveryComplete-objects as value to a dart map
  static Map<String, List<RecoveryComplete>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<RecoveryComplete>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = RecoveryComplete.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'device',
    'email',
    'new',
    'recovery_auth_key',
  };
}

