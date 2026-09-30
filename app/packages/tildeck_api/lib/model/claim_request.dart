//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ClaimRequest {
  /// Returns a new [ClaimRequest] instance.
  ClaimRequest({
    required this.claimToken,
    required this.deviceId,
  });

  String claimToken;

  String deviceId;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ClaimRequest &&
    other.claimToken == claimToken &&
    other.deviceId == deviceId;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (claimToken.hashCode) +
    (deviceId.hashCode);

  @override
  String toString() => 'ClaimRequest[claimToken=$claimToken, deviceId=$deviceId]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'claim_token'] = this.claimToken;
      json[r'device_id'] = this.deviceId;
    return json;
  }

  /// Returns a new [ClaimRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ClaimRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'claim_token'), 'Required key "ClaimRequest[claim_token]" is missing from JSON.');
        assert(json[r'claim_token'] != null, 'Required key "ClaimRequest[claim_token]" has a null value in JSON.');
        assert(json.containsKey(r'device_id'), 'Required key "ClaimRequest[device_id]" is missing from JSON.');
        assert(json[r'device_id'] != null, 'Required key "ClaimRequest[device_id]" has a null value in JSON.');
        return true;
      }());

      return ClaimRequest(
        claimToken: mapValueOfType<String>(json, r'claim_token')!,
        deviceId: mapValueOfType<String>(json, r'device_id')!,
      );
    }
    return null;
  }

  static List<ClaimRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ClaimRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ClaimRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ClaimRequest> mapFromJson(dynamic json) {
    final map = <String, ClaimRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ClaimRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ClaimRequest-objects as value to a dart map
  static Map<String, List<ClaimRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ClaimRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ClaimRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'claim_token',
    'device_id',
  };
}

