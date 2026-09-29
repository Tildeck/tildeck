//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class Readiness {
  /// Returns a new [Readiness] instance.
  Readiness({
    required this.database,
    this.error,
    required this.status,
  });

  ReadinessDatabaseEnum database;

  ErrorCode? error;

  ReadinessStatusEnum status;

  @override
  bool operator ==(Object other) => identical(this, other) || other is Readiness &&
    other.database == database &&
    other.error == error &&
    other.status == status;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (database.hashCode) +
    (error == null ? 0 : error!.hashCode) +
    (status.hashCode);

  @override
  String toString() => 'Readiness[database=$database, error=$error, status=$status]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'database'] = this.database;
    if (this.error != null) {
      json[r'error'] = this.error;
    } else {
      json[r'error'] = null;
    }
      json[r'status'] = this.status;
    return json;
  }

  /// Returns a new [Readiness] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static Readiness? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'database'), 'Required key "Readiness[database]" is missing from JSON.');
        assert(json[r'database'] != null, 'Required key "Readiness[database]" has a null value in JSON.');
        assert(json.containsKey(r'status'), 'Required key "Readiness[status]" is missing from JSON.');
        assert(json[r'status'] != null, 'Required key "Readiness[status]" has a null value in JSON.');
        return true;
      }());

      return Readiness(
        database: ReadinessDatabaseEnum.fromJson(json[r'database'])!,
        error: ErrorCode.fromJson(json[r'error']),
        status: ReadinessStatusEnum.fromJson(json[r'status'])!,
      );
    }
    return null;
  }

  static List<Readiness> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <Readiness>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Readiness.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Readiness> mapFromJson(dynamic json) {
    final map = <String, Readiness>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Readiness.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of Readiness-objects as value to a dart map
  static Map<String, List<Readiness>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<Readiness>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Readiness.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'database',
    'status',
  };
}


enum ReadinessDatabaseEnum {
  ok._(r'ok'),
  error._(r'error'),
  ;

  /// Instantiate a new enum with the provided value.
  const ReadinessDatabaseEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [ReadinessDatabaseEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static ReadinessDatabaseEnum? fromJson(dynamic value) => ReadinessDatabaseEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [ReadinessDatabaseEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<ReadinessDatabaseEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ReadinessDatabaseEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ReadinessDatabaseEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [ReadinessDatabaseEnum] to String,
/// and [decode] dynamic data back to [ReadinessDatabaseEnum].
class ReadinessDatabaseEnumTypeTransformer {
  factory ReadinessDatabaseEnumTypeTransformer() => _instance ??= const ReadinessDatabaseEnumTypeTransformer._();

  const ReadinessDatabaseEnumTypeTransformer._();

  String encode(ReadinessDatabaseEnum data) => data._value;

  /// Returns the instance of [ReadinessDatabaseEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  ReadinessDatabaseEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is ReadinessDatabaseEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ok': return ReadinessDatabaseEnum.ok;
        case r'error': return ReadinessDatabaseEnum.error;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static ReadinessDatabaseEnumTypeTransformer? _instance;
}



enum ReadinessStatusEnum {
  ok._(r'ok'),
  error._(r'error'),
  ;

  /// Instantiate a new enum with the provided value.
  const ReadinessStatusEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [ReadinessStatusEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static ReadinessStatusEnum? fromJson(dynamic value) => ReadinessStatusEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [ReadinessStatusEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<ReadinessStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ReadinessStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ReadinessStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [ReadinessStatusEnum] to String,
/// and [decode] dynamic data back to [ReadinessStatusEnum].
class ReadinessStatusEnumTypeTransformer {
  factory ReadinessStatusEnumTypeTransformer() => _instance ??= const ReadinessStatusEnumTypeTransformer._();

  const ReadinessStatusEnumTypeTransformer._();

  String encode(ReadinessStatusEnum data) => data._value;

  /// Returns the instance of [ReadinessStatusEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  ReadinessStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is ReadinessStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ok': return ReadinessStatusEnum.ok;
        case r'error': return ReadinessStatusEnum.error;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static ReadinessStatusEnumTypeTransformer? _instance;
}


