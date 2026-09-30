//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ModelSealed {
  /// Returns a new [ModelSealed] instance.
  ModelSealed({
    required this.ct,
    required this.nonce,
  });

  String ct;

  String nonce;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ModelSealed &&
    other.ct == ct &&
    other.nonce == nonce;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (ct.hashCode) +
    (nonce.hashCode);

  @override
  String toString() => 'ModelSealed[ct=$ct, nonce=$nonce]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'ct'] = this.ct;
      json[r'nonce'] = this.nonce;
    return json;
  }

  /// Returns a new [ModelSealed] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ModelSealed? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'ct'), 'Required key "ModelSealed[ct]" is missing from JSON.');
        assert(json[r'ct'] != null, 'Required key "ModelSealed[ct]" has a null value in JSON.');
        assert(json.containsKey(r'nonce'), 'Required key "ModelSealed[nonce]" is missing from JSON.');
        assert(json[r'nonce'] != null, 'Required key "ModelSealed[nonce]" has a null value in JSON.');
        return true;
      }());

      return ModelSealed(
        ct: mapValueOfType<String>(json, r'ct')!,
        nonce: mapValueOfType<String>(json, r'nonce')!,
      );
    }
    return null;
  }

  static List<ModelSealed> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ModelSealed>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ModelSealed.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ModelSealed> mapFromJson(dynamic json) {
    final map = <String, ModelSealed>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ModelSealed.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ModelSealed-objects as value to a dart map
  static Map<String, List<ModelSealed>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ModelSealed>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ModelSealed.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'ct',
    'nonce',
  };
}

