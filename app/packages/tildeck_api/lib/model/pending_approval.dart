//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class PendingApproval {
  /// Returns a new [PendingApproval] instance.
  PendingApproval({
    required this.claimToken,
    required this.deviceId,
    required this.emailApproval,
    this.status = const PendingApprovalStatusEnum._('pending'),
  });

  String claimToken;

  String deviceId;

  /// An approval link was sent by email
  bool emailApproval;

  PendingApprovalStatusEnum status;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PendingApproval &&
    other.claimToken == claimToken &&
    other.deviceId == deviceId &&
    other.emailApproval == emailApproval &&
    other.status == status;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (claimToken.hashCode) +
    (deviceId.hashCode) +
    (emailApproval.hashCode) +
    (status.hashCode);

  @override
  String toString() => 'PendingApproval[claimToken=$claimToken, deviceId=$deviceId, emailApproval=$emailApproval, status=$status]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'claim_token'] = this.claimToken;
      json[r'device_id'] = this.deviceId;
      json[r'email_approval'] = this.emailApproval;
      json[r'status'] = this.status;
    return json;
  }

  /// Returns a new [PendingApproval] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static PendingApproval? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'claim_token'), 'Required key "PendingApproval[claim_token]" is missing from JSON.');
        assert(json[r'claim_token'] != null, 'Required key "PendingApproval[claim_token]" has a null value in JSON.');
        assert(json.containsKey(r'device_id'), 'Required key "PendingApproval[device_id]" is missing from JSON.');
        assert(json[r'device_id'] != null, 'Required key "PendingApproval[device_id]" has a null value in JSON.');
        assert(json.containsKey(r'email_approval'), 'Required key "PendingApproval[email_approval]" is missing from JSON.');
        assert(json[r'email_approval'] != null, 'Required key "PendingApproval[email_approval]" has a null value in JSON.');
        return true;
      }());

      return PendingApproval(
        claimToken: mapValueOfType<String>(json, r'claim_token')!,
        deviceId: mapValueOfType<String>(json, r'device_id')!,
        emailApproval: mapValueOfType<bool>(json, r'email_approval')!,
        status: PendingApprovalStatusEnum.fromJson(json[r'status']) ?? const PendingApprovalStatusEnum._('pending'),
      );
    }
    return null;
  }

  static List<PendingApproval> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PendingApproval>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PendingApproval.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PendingApproval> mapFromJson(dynamic json) {
    final map = <String, PendingApproval>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PendingApproval.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of PendingApproval-objects as value to a dart map
  static Map<String, List<PendingApproval>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<PendingApproval>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PendingApproval.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'claim_token',
    'device_id',
    'email_approval',
  };
}


enum PendingApprovalStatusEnum {
  pending._(r'pending'),
  ;

  /// Instantiate a new enum with the provided value.
  const PendingApprovalStatusEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [PendingApprovalStatusEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static PendingApprovalStatusEnum? fromJson(dynamic value) => PendingApprovalStatusEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [PendingApprovalStatusEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<PendingApprovalStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PendingApprovalStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PendingApprovalStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [PendingApprovalStatusEnum] to String,
/// and [decode] dynamic data back to [PendingApprovalStatusEnum].
class PendingApprovalStatusEnumTypeTransformer {
  factory PendingApprovalStatusEnumTypeTransformer() => _instance ??= const PendingApprovalStatusEnumTypeTransformer._();

  const PendingApprovalStatusEnumTypeTransformer._();

  String encode(PendingApprovalStatusEnum data) => data._value;

  /// Returns the instance of [PendingApprovalStatusEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  PendingApprovalStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is PendingApprovalStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'pending': return PendingApprovalStatusEnum.pending;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static PendingApprovalStatusEnumTypeTransformer? _instance;
}


