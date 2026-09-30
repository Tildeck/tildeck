//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class SyncRecord {
  /// Returns a new [SyncRecord] instance.
  SyncRecord({
    this.ct,
    required this.deleted,
    required this.id,
    this.nonce,
    required this.version,
  });

  String? ct;

  bool deleted;

  String id;

  String? nonce;

  /// Minimum value: 1
  int version;

  @override
  bool operator ==(Object other) => identical(this, other) || other is SyncRecord &&
    other.ct == ct &&
    other.deleted == deleted &&
    other.id == id &&
    other.nonce == nonce &&
    other.version == version;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (ct == null ? 0 : ct!.hashCode) +
    (deleted.hashCode) +
    (id.hashCode) +
    (nonce == null ? 0 : nonce!.hashCode) +
    (version.hashCode);

  @override
  String toString() => 'SyncRecord[ct=$ct, deleted=$deleted, id=$id, nonce=$nonce, version=$version]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.ct != null) {
      json[r'ct'] = this.ct;
    } else {
      json[r'ct'] = null;
    }
      json[r'deleted'] = this.deleted;
      json[r'id'] = this.id;
    if (this.nonce != null) {
      json[r'nonce'] = this.nonce;
    } else {
      json[r'nonce'] = null;
    }
      json[r'version'] = this.version;
    return json;
  }

  /// Returns a new [SyncRecord] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static SyncRecord? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'deleted'), 'Required key "SyncRecord[deleted]" is missing from JSON.');
        assert(json[r'deleted'] != null, 'Required key "SyncRecord[deleted]" has a null value in JSON.');
        assert(json.containsKey(r'id'), 'Required key "SyncRecord[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "SyncRecord[id]" has a null value in JSON.');
        assert(json.containsKey(r'version'), 'Required key "SyncRecord[version]" is missing from JSON.');
        assert(json[r'version'] != null, 'Required key "SyncRecord[version]" has a null value in JSON.');
        return true;
      }());

      return SyncRecord(
        ct: mapValueOfType<String>(json, r'ct'),
        deleted: mapValueOfType<bool>(json, r'deleted')!,
        id: mapValueOfType<String>(json, r'id')!,
        nonce: mapValueOfType<String>(json, r'nonce'),
        version: mapValueOfType<int>(json, r'version')!,
      );
    }
    return null;
  }

  static List<SyncRecord> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SyncRecord>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SyncRecord.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SyncRecord> mapFromJson(dynamic json) {
    final map = <String, SyncRecord>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SyncRecord.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of SyncRecord-objects as value to a dart map
  static Map<String, List<SyncRecord>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<SyncRecord>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SyncRecord.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'deleted',
    'id',
    'version',
  };
}

