//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class KdfParams {
  /// Returns a new [KdfParams] instance.
  KdfParams({
    required this.alg,
    required this.mem,
    required this.ops,
    required this.salt,
  });

  String alg;

  /// Minimum value: 67108864
  /// Maximum value: 1073741824
  int mem;

  /// Minimum value: 3
  /// Maximum value: 20
  int ops;

  String salt;

  @override
  bool operator ==(Object other) => identical(this, other) || other is KdfParams &&
    other.alg == alg &&
    other.mem == mem &&
    other.ops == ops &&
    other.salt == salt;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (alg.hashCode) +
    (mem.hashCode) +
    (ops.hashCode) +
    (salt.hashCode);

  @override
  String toString() => 'KdfParams[alg=$alg, mem=$mem, ops=$ops, salt=$salt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'alg'] = this.alg;
      json[r'mem'] = this.mem;
      json[r'ops'] = this.ops;
      json[r'salt'] = this.salt;
    return json;
  }

  /// Returns a new [KdfParams] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static KdfParams? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'alg'), 'Required key "KdfParams[alg]" is missing from JSON.');
        assert(json[r'alg'] != null, 'Required key "KdfParams[alg]" has a null value in JSON.');
        assert(json.containsKey(r'mem'), 'Required key "KdfParams[mem]" is missing from JSON.');
        assert(json[r'mem'] != null, 'Required key "KdfParams[mem]" has a null value in JSON.');
        assert(json.containsKey(r'ops'), 'Required key "KdfParams[ops]" is missing from JSON.');
        assert(json[r'ops'] != null, 'Required key "KdfParams[ops]" has a null value in JSON.');
        assert(json.containsKey(r'salt'), 'Required key "KdfParams[salt]" is missing from JSON.');
        assert(json[r'salt'] != null, 'Required key "KdfParams[salt]" has a null value in JSON.');
        return true;
      }());

      return KdfParams(
        alg: mapValueOfType<String>(json, r'alg')!,
        mem: mapValueOfType<int>(json, r'mem')!,
        ops: mapValueOfType<int>(json, r'ops')!,
        salt: mapValueOfType<String>(json, r'salt')!,
      );
    }
    return null;
  }

  static List<KdfParams> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <KdfParams>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = KdfParams.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, KdfParams> mapFromJson(dynamic json) {
    final map = <String, KdfParams>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = KdfParams.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of KdfParams-objects as value to a dart map
  static Map<String, List<KdfParams>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<KdfParams>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = KdfParams.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'alg',
    'mem',
    'ops',
    'salt',
  };
}

