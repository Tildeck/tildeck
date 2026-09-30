//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class PushResponse {
  /// Returns a new [PushResponse] instance.
  PushResponse({
    this.accepted = const [],
    this.conflicts = const [],
    required this.revision,
  });

  List<Accepted> accepted;

  List<Conflict> conflicts;

  int revision;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PushResponse &&
    _deepEquality.equals(other.accepted, accepted) &&
    _deepEquality.equals(other.conflicts, conflicts) &&
    other.revision == revision;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (accepted.hashCode) +
    (conflicts.hashCode) +
    (revision.hashCode);

  @override
  String toString() => 'PushResponse[accepted=$accepted, conflicts=$conflicts, revision=$revision]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'accepted'] = this.accepted;
      json[r'conflicts'] = this.conflicts;
      json[r'revision'] = this.revision;
    return json;
  }

  /// Returns a new [PushResponse] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static PushResponse? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'accepted'), 'Required key "PushResponse[accepted]" is missing from JSON.');
        assert(json[r'accepted'] != null, 'Required key "PushResponse[accepted]" has a null value in JSON.');
        assert(json.containsKey(r'conflicts'), 'Required key "PushResponse[conflicts]" is missing from JSON.');
        assert(json[r'conflicts'] != null, 'Required key "PushResponse[conflicts]" has a null value in JSON.');
        assert(json.containsKey(r'revision'), 'Required key "PushResponse[revision]" is missing from JSON.');
        assert(json[r'revision'] != null, 'Required key "PushResponse[revision]" has a null value in JSON.');
        return true;
      }());

      return PushResponse(
        accepted: Accepted.listFromJson(json[r'accepted']),
        conflicts: Conflict.listFromJson(json[r'conflicts']),
        revision: mapValueOfType<int>(json, r'revision')!,
      );
    }
    return null;
  }

  static List<PushResponse> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PushResponse>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PushResponse.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PushResponse> mapFromJson(dynamic json) {
    final map = <String, PushResponse>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PushResponse.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of PushResponse-objects as value to a dart map
  static Map<String, List<PushResponse>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<PushResponse>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PushResponse.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'accepted',
    'conflicts',
    'revision',
  };
}

