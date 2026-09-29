//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class Liveness {
  /// Returns a new [Liveness] instance.
  Liveness({
    required this.status,
  });

  LivenessStatusEnum status;

  @override
  bool operator ==(Object other) => identical(this, other) || other is Liveness &&
    other.status == status;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (status.hashCode);

  @override
  String toString() => 'Liveness[status=$status]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'status'] = this.status;
    return json;
  }

  /// Returns a new [Liveness] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static Liveness? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'status'), 'Required key "Liveness[status]" is missing from JSON.');
        assert(json[r'status'] != null, 'Required key "Liveness[status]" has a null value in JSON.');
        return true;
      }());

      return Liveness(
        status: LivenessStatusEnum.fromJson(json[r'status'])!,
      );
    }
    return null;
  }

  static List<Liveness> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <Liveness>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Liveness.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Liveness> mapFromJson(dynamic json) {
    final map = <String, Liveness>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Liveness.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of Liveness-objects as value to a dart map
  static Map<String, List<Liveness>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<Liveness>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Liveness.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'status',
  };
}


enum LivenessStatusEnum {
  ok._(r'ok'),
  ;

  /// Instantiate a new enum with the provided value.
  const LivenessStatusEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [LivenessStatusEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static LivenessStatusEnum? fromJson(dynamic value) => LivenessStatusEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [LivenessStatusEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<LivenessStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <LivenessStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = LivenessStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [LivenessStatusEnum] to String,
/// and [decode] dynamic data back to [LivenessStatusEnum].
class LivenessStatusEnumTypeTransformer {
  factory LivenessStatusEnumTypeTransformer() => _instance ??= const LivenessStatusEnumTypeTransformer._();

  const LivenessStatusEnumTypeTransformer._();

  String encode(LivenessStatusEnum data) => data._value;

  /// Returns the instance of [LivenessStatusEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  LivenessStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is LivenessStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ok': return LivenessStatusEnum.ok;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static LivenessStatusEnumTypeTransformer? _instance;
}


