//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class PreloginResponse {
  /// Returns a new [PreloginResponse] instance.
  PreloginResponse({
    required this.kdf,
  });

  KdfParams kdf;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PreloginResponse &&
    other.kdf == kdf;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (kdf.hashCode);

  @override
  String toString() => 'PreloginResponse[kdf=$kdf]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'kdf'] = this.kdf;
    return json;
  }

  /// Returns a new [PreloginResponse] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static PreloginResponse? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'kdf'), 'Required key "PreloginResponse[kdf]" is missing from JSON.');
        assert(json[r'kdf'] != null, 'Required key "PreloginResponse[kdf]" has a null value in JSON.');
        return true;
      }());

      return PreloginResponse(
        kdf: KdfParams.fromJson(json[r'kdf'])!,
      );
    }
    return null;
  }

  static List<PreloginResponse> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PreloginResponse>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PreloginResponse.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PreloginResponse> mapFromJson(dynamic json) {
    final map = <String, PreloginResponse>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PreloginResponse.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of PreloginResponse-objects as value to a dart map
  static Map<String, List<PreloginResponse>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<PreloginResponse>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PreloginResponse.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'kdf',
  };
}

