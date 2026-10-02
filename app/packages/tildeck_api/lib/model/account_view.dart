//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class AccountView {
  /// Returns a new [AccountView] instance.
  AccountView({
    this.devices = const [],
    required this.email,
    required this.emailVerified,
    required this.locale,
    required this.totpEnabled,
  });

  List<DeviceView> devices;

  String email;

  bool emailVerified;

  String locale;

  bool totpEnabled;

  @override
  bool operator ==(Object other) => identical(this, other) || other is AccountView &&
    _deepEquality.equals(other.devices, devices) &&
    other.email == email &&
    other.emailVerified == emailVerified &&
    other.locale == locale &&
    other.totpEnabled == totpEnabled;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (devices.hashCode) +
    (email.hashCode) +
    (emailVerified.hashCode) +
    (locale.hashCode) +
    (totpEnabled.hashCode);

  @override
  String toString() => 'AccountView[devices=$devices, email=$email, emailVerified=$emailVerified, locale=$locale, totpEnabled=$totpEnabled]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'devices'] = this.devices;
      json[r'email'] = this.email;
      json[r'email_verified'] = this.emailVerified;
      json[r'locale'] = this.locale;
      json[r'totp_enabled'] = this.totpEnabled;
    return json;
  }

  /// Returns a new [AccountView] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static AccountView? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'devices'), 'Required key "AccountView[devices]" is missing from JSON.');
        assert(json[r'devices'] != null, 'Required key "AccountView[devices]" has a null value in JSON.');
        assert(json.containsKey(r'email'), 'Required key "AccountView[email]" is missing from JSON.');
        assert(json[r'email'] != null, 'Required key "AccountView[email]" has a null value in JSON.');
        assert(json.containsKey(r'email_verified'), 'Required key "AccountView[email_verified]" is missing from JSON.');
        assert(json[r'email_verified'] != null, 'Required key "AccountView[email_verified]" has a null value in JSON.');
        assert(json.containsKey(r'locale'), 'Required key "AccountView[locale]" is missing from JSON.');
        assert(json[r'locale'] != null, 'Required key "AccountView[locale]" has a null value in JSON.');
        assert(json.containsKey(r'totp_enabled'), 'Required key "AccountView[totp_enabled]" is missing from JSON.');
        assert(json[r'totp_enabled'] != null, 'Required key "AccountView[totp_enabled]" has a null value in JSON.');
        return true;
      }());

      return AccountView(
        devices: DeviceView.listFromJson(json[r'devices']),
        email: mapValueOfType<String>(json, r'email')!,
        emailVerified: mapValueOfType<bool>(json, r'email_verified')!,
        locale: mapValueOfType<String>(json, r'locale')!,
        totpEnabled: mapValueOfType<bool>(json, r'totp_enabled')!,
      );
    }
    return null;
  }

  static List<AccountView> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <AccountView>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AccountView.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AccountView> mapFromJson(dynamic json) {
    final map = <String, AccountView>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AccountView.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of AccountView-objects as value to a dart map
  static Map<String, List<AccountView>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<AccountView>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AccountView.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'devices',
    'email',
    'email_verified',
    'locale',
    'totp_enabled',
  };
}

