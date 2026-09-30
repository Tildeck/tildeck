//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class Conflict {
  /// Returns a new [Conflict] instance.
  Conflict({
    required this.current,
    required this.id,
    required this.reason,
  });

  StoredRecord? current;

  String id;

  ConflictReasonEnum reason;

  @override
  bool operator ==(Object other) => identical(this, other) || other is Conflict &&
    other.current == current &&
    other.id == id &&
    other.reason == reason;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (current == null ? 0 : current!.hashCode) +
    (id.hashCode) +
    (reason.hashCode);

  @override
  String toString() => 'Conflict[current=$current, id=$id, reason=$reason]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.current != null) {
      json[r'current'] = this.current;
    } else {
      json[r'current'] = null;
    }
      json[r'id'] = this.id;
      json[r'reason'] = this.reason;
    return json;
  }

  /// Returns a new [Conflict] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static Conflict? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'current'), 'Required key "Conflict[current]" is missing from JSON.');
        assert(json.containsKey(r'id'), 'Required key "Conflict[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "Conflict[id]" has a null value in JSON.');
        assert(json.containsKey(r'reason'), 'Required key "Conflict[reason]" is missing from JSON.');
        assert(json[r'reason'] != null, 'Required key "Conflict[reason]" has a null value in JSON.');
        return true;
      }());

      return Conflict(
        current: StoredRecord.fromJson(json[r'current']),
        id: mapValueOfType<String>(json, r'id')!,
        reason: ConflictReasonEnum.fromJson(json[r'reason'])!,
      );
    }
    return null;
  }

  static List<Conflict> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <Conflict>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Conflict.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Conflict> mapFromJson(dynamic json) {
    final map = <String, Conflict>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Conflict.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of Conflict-objects as value to a dart map
  static Map<String, List<Conflict>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<Conflict>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Conflict.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'current',
    'id',
    'reason',
  };
}


enum ConflictReasonEnum {
  versionConflict._(r'version_conflict'),
  ;

  /// Instantiate a new enum with the provided value.
  const ConflictReasonEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [ConflictReasonEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static ConflictReasonEnum? fromJson(dynamic value) => ConflictReasonEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [ConflictReasonEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<ConflictReasonEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ConflictReasonEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ConflictReasonEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [ConflictReasonEnum] to String,
/// and [decode] dynamic data back to [ConflictReasonEnum].
class ConflictReasonEnumTypeTransformer {
  factory ConflictReasonEnumTypeTransformer() => _instance ??= const ConflictReasonEnumTypeTransformer._();

  const ConflictReasonEnumTypeTransformer._();

  String encode(ConflictReasonEnum data) => data._value;

  /// Returns the instance of [ConflictReasonEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  ConflictReasonEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is ConflictReasonEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'version_conflict': return ConflictReasonEnum.versionConflict;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static ConflictReasonEnumTypeTransformer? _instance;
}


