//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ResponseSignin {
  /// Returns a new [ResponseSignin] instance.
  ResponseSignin({
    required this.deviceToken,
    required this.emailVerified,
    this.status = const ResponseSigninStatusEnum._('pending'),
    required this.vault,
    required this.claimToken,
    required this.deviceId,
    required this.emailApproval,
  });

  String deviceToken;

  bool emailVerified;

  ResponseSigninStatusEnum status;

  VaultKeys vault;

  String claimToken;

  String deviceId;

  /// An approval link was sent by email
  bool emailApproval;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ResponseSignin &&
    other.deviceToken == deviceToken &&
    other.emailVerified == emailVerified &&
    other.status == status &&
    other.vault == vault &&
    other.claimToken == claimToken &&
    other.deviceId == deviceId &&
    other.emailApproval == emailApproval;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (deviceToken.hashCode) +
    (emailVerified.hashCode) +
    (status.hashCode) +
    (vault.hashCode) +
    (claimToken.hashCode) +
    (deviceId.hashCode) +
    (emailApproval.hashCode);

  @override
  String toString() => 'ResponseSignin[deviceToken=$deviceToken, emailVerified=$emailVerified, status=$status, vault=$vault, claimToken=$claimToken, deviceId=$deviceId, emailApproval=$emailApproval]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'device_token'] = this.deviceToken;
      json[r'email_verified'] = this.emailVerified;
      json[r'status'] = this.status;
      json[r'vault'] = this.vault;
      json[r'claim_token'] = this.claimToken;
      json[r'device_id'] = this.deviceId;
      json[r'email_approval'] = this.emailApproval;
    return json;
  }

  /// Returns a new [ResponseSignin] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ResponseSignin? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'device_token'), 'Required key "ResponseSignin[device_token]" is missing from JSON.');
        assert(json[r'device_token'] != null, 'Required key "ResponseSignin[device_token]" has a null value in JSON.');
        assert(json.containsKey(r'email_verified'), 'Required key "ResponseSignin[email_verified]" is missing from JSON.');
        assert(json[r'email_verified'] != null, 'Required key "ResponseSignin[email_verified]" has a null value in JSON.');
        assert(json.containsKey(r'vault'), 'Required key "ResponseSignin[vault]" is missing from JSON.');
        assert(json[r'vault'] != null, 'Required key "ResponseSignin[vault]" has a null value in JSON.');
        assert(json.containsKey(r'claim_token'), 'Required key "ResponseSignin[claim_token]" is missing from JSON.');
        assert(json[r'claim_token'] != null, 'Required key "ResponseSignin[claim_token]" has a null value in JSON.');
        assert(json.containsKey(r'device_id'), 'Required key "ResponseSignin[device_id]" is missing from JSON.');
        assert(json[r'device_id'] != null, 'Required key "ResponseSignin[device_id]" has a null value in JSON.');
        assert(json.containsKey(r'email_approval'), 'Required key "ResponseSignin[email_approval]" is missing from JSON.');
        assert(json[r'email_approval'] != null, 'Required key "ResponseSignin[email_approval]" has a null value in JSON.');
        return true;
      }());

      return ResponseSignin(
        deviceToken: mapValueOfType<String>(json, r'device_token')!,
        emailVerified: mapValueOfType<bool>(json, r'email_verified')!,
        status: ResponseSigninStatusEnum.fromJson(json[r'status']) ?? const ResponseSigninStatusEnum._('pending'),
        vault: VaultKeys.fromJson(json[r'vault'])!,
        claimToken: mapValueOfType<String>(json, r'claim_token')!,
        deviceId: mapValueOfType<String>(json, r'device_id')!,
        emailApproval: mapValueOfType<bool>(json, r'email_approval')!,
      );
    }
    return null;
  }

  static List<ResponseSignin> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ResponseSignin>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ResponseSignin.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ResponseSignin> mapFromJson(dynamic json) {
    final map = <String, ResponseSignin>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ResponseSignin.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ResponseSignin-objects as value to a dart map
  static Map<String, List<ResponseSignin>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ResponseSignin>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ResponseSignin.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'device_token',
    'email_verified',
    'vault',
    'claim_token',
    'device_id',
    'email_approval',
  };
}


enum ResponseSigninStatusEnum {
  pending._(r'pending'),
  ;

  /// Instantiate a new enum with the provided value.
  const ResponseSigninStatusEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [ResponseSigninStatusEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static ResponseSigninStatusEnum? fromJson(dynamic value) => ResponseSigninStatusEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [ResponseSigninStatusEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<ResponseSigninStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ResponseSigninStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ResponseSigninStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [ResponseSigninStatusEnum] to String,
/// and [decode] dynamic data back to [ResponseSigninStatusEnum].
class ResponseSigninStatusEnumTypeTransformer {
  factory ResponseSigninStatusEnumTypeTransformer() => _instance ??= const ResponseSigninStatusEnumTypeTransformer._();

  const ResponseSigninStatusEnumTypeTransformer._();

  String encode(ResponseSigninStatusEnum data) => data._value;

  /// Returns the instance of [ResponseSigninStatusEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  ResponseSigninStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is ResponseSigninStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'pending': return ResponseSigninStatusEnum.pending;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static ResponseSigninStatusEnumTypeTransformer? _instance;
}


