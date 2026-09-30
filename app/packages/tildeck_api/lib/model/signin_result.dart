//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class SigninResult {
  /// Returns a new [SigninResult] instance.
  SigninResult({
    this.claimToken,
    this.deviceId,
    this.emailApproval,
    this.signedIn,
    required this.status,
  });

  String? claimToken;

  String? deviceId;

  /// An approval link was sent by email
  bool? emailApproval;

  SignedIn? signedIn;

  SigninResultStatusEnum status;

  @override
  bool operator ==(Object other) => identical(this, other) || other is SigninResult &&
    other.claimToken == claimToken &&
    other.deviceId == deviceId &&
    other.emailApproval == emailApproval &&
    other.signedIn == signedIn &&
    other.status == status;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (claimToken == null ? 0 : claimToken!.hashCode) +
    (deviceId == null ? 0 : deviceId!.hashCode) +
    (emailApproval == null ? 0 : emailApproval!.hashCode) +
    (signedIn == null ? 0 : signedIn!.hashCode) +
    (status.hashCode);

  @override
  String toString() => 'SigninResult[claimToken=$claimToken, deviceId=$deviceId, emailApproval=$emailApproval, signedIn=$signedIn, status=$status]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.claimToken != null) {
      json[r'claim_token'] = this.claimToken;
    } else {
      json[r'claim_token'] = null;
    }
    if (this.deviceId != null) {
      json[r'device_id'] = this.deviceId;
    } else {
      json[r'device_id'] = null;
    }
    if (this.emailApproval != null) {
      json[r'email_approval'] = this.emailApproval;
    } else {
      json[r'email_approval'] = null;
    }
    if (this.signedIn != null) {
      json[r'signed_in'] = this.signedIn;
    } else {
      json[r'signed_in'] = null;
    }
      json[r'status'] = this.status;
    return json;
  }

  /// Returns a new [SigninResult] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static SigninResult? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'status'), 'Required key "SigninResult[status]" is missing from JSON.');
        assert(json[r'status'] != null, 'Required key "SigninResult[status]" has a null value in JSON.');
        return true;
      }());

      return SigninResult(
        claimToken: mapValueOfType<String>(json, r'claim_token'),
        deviceId: mapValueOfType<String>(json, r'device_id'),
        emailApproval: mapValueOfType<bool>(json, r'email_approval'),
        signedIn: SignedIn.fromJson(json[r'signed_in']),
        status: SigninResultStatusEnum.fromJson(json[r'status'])!,
      );
    }
    return null;
  }

  static List<SigninResult> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SigninResult>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SigninResult.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SigninResult> mapFromJson(dynamic json) {
    final map = <String, SigninResult>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SigninResult.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of SigninResult-objects as value to a dart map
  static Map<String, List<SigninResult>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<SigninResult>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SigninResult.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'status',
  };
}


enum SigninResultStatusEnum {
  active._(r'active'),
  pending._(r'pending'),
  ;

  /// Instantiate a new enum with the provided value.
  const SigninResultStatusEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [SigninResultStatusEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static SigninResultStatusEnum? fromJson(dynamic value) => SigninResultStatusEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [SigninResultStatusEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<SigninResultStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SigninResultStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SigninResultStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [SigninResultStatusEnum] to String,
/// and [decode] dynamic data back to [SigninResultStatusEnum].
class SigninResultStatusEnumTypeTransformer {
  factory SigninResultStatusEnumTypeTransformer() => _instance ??= const SigninResultStatusEnumTypeTransformer._();

  const SigninResultStatusEnumTypeTransformer._();

  String encode(SigninResultStatusEnum data) => data._value;

  /// Returns the instance of [SigninResultStatusEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  SigninResultStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is SigninResultStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'active': return SigninResultStatusEnum.active;
        case r'pending': return SigninResultStatusEnum.pending;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static SigninResultStatusEnumTypeTransformer? _instance;
}


