//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class PullResponse {
  /// Returns a new [PullResponse] instance.
  PullResponse({
    required this.more,
    this.records = const [],
    required this.revision,
  });

  /// More records are waiting beyond this page
  bool more;

  List<StoredRecord> records;

  /// The cursor to pull from next time
  int revision;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PullResponse &&
    other.more == more &&
    _deepEquality.equals(other.records, records) &&
    other.revision == revision;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (more.hashCode) +
    (records.hashCode) +
    (revision.hashCode);

  @override
  String toString() => 'PullResponse[more=$more, records=$records, revision=$revision]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'more'] = this.more;
      json[r'records'] = this.records;
      json[r'revision'] = this.revision;
    return json;
  }

  /// Returns a new [PullResponse] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static PullResponse? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'more'), 'Required key "PullResponse[more]" is missing from JSON.');
        assert(json[r'more'] != null, 'Required key "PullResponse[more]" has a null value in JSON.');
        assert(json.containsKey(r'records'), 'Required key "PullResponse[records]" is missing from JSON.');
        assert(json[r'records'] != null, 'Required key "PullResponse[records]" has a null value in JSON.');
        assert(json.containsKey(r'revision'), 'Required key "PullResponse[revision]" is missing from JSON.');
        assert(json[r'revision'] != null, 'Required key "PullResponse[revision]" has a null value in JSON.');
        return true;
      }());

      return PullResponse(
        more: mapValueOfType<bool>(json, r'more')!,
        records: StoredRecord.listFromJson(json[r'records']),
        revision: mapValueOfType<int>(json, r'revision')!,
      );
    }
    return null;
  }

  static List<PullResponse> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PullResponse>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PullResponse.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PullResponse> mapFromJson(dynamic json) {
    final map = <String, PullResponse>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PullResponse.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of PullResponse-objects as value to a dart map
  static Map<String, List<PullResponse>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<PullResponse>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PullResponse.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'more',
    'records',
    'revision',
  };
}

