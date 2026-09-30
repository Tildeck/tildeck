//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class Accepted {
  /// Returns a new [Accepted] instance.
  Accepted({
    required this.id,
    required this.revision,
    required this.version,
  });

  String id;

  int revision;

  int version;

  @override
  bool operator ==(Object other) => identical(this, other) || other is Accepted &&
    other.id == id &&
    other.revision == revision &&
    other.version == version;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id.hashCode) +
    (revision.hashCode) +
    (version.hashCode);

  @override
  String toString() => 'Accepted[id=$id, revision=$revision, version=$version]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'id'] = this.id;
      json[r'revision'] = this.revision;
      json[r'version'] = this.version;
    return json;
  }

  /// Returns a new [Accepted] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static Accepted? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'), 'Required key "Accepted[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "Accepted[id]" has a null value in JSON.');
        assert(json.containsKey(r'revision'), 'Required key "Accepted[revision]" is missing from JSON.');
        assert(json[r'revision'] != null, 'Required key "Accepted[revision]" has a null value in JSON.');
        assert(json.containsKey(r'version'), 'Required key "Accepted[version]" is missing from JSON.');
        assert(json[r'version'] != null, 'Required key "Accepted[version]" has a null value in JSON.');
        return true;
      }());

      return Accepted(
        id: mapValueOfType<String>(json, r'id')!,
        revision: mapValueOfType<int>(json, r'revision')!,
        version: mapValueOfType<int>(json, r'version')!,
      );
    }
    return null;
  }

  static List<Accepted> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <Accepted>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Accepted.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Accepted> mapFromJson(dynamic json) {
    final map = <String, Accepted>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Accepted.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of Accepted-objects as value to a dart map
  static Map<String, List<Accepted>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<Accepted>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Accepted.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'revision',
    'version',
  };
}

