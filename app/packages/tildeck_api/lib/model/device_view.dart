//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DeviceView {
  /// Returns a new [DeviceView] instance.
  DeviceView({
    required this.createdAt,
    required this.current,
    required this.id,
    required this.lastSeenAt,
    required this.name,
    required this.status,
  });

  DateTime createdAt;

  bool current;

  String id;

  DateTime? lastSeenAt;

  String name;

  DeviceViewStatusEnum status;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DeviceView &&
    other.createdAt == createdAt &&
    other.current == current &&
    other.id == id &&
    other.lastSeenAt == lastSeenAt &&
    other.name == name &&
    other.status == status;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (createdAt.hashCode) +
    (current.hashCode) +
    (id.hashCode) +
    (lastSeenAt == null ? 0 : lastSeenAt!.hashCode) +
    (name.hashCode) +
    (status.hashCode);

  @override
  String toString() => 'DeviceView[createdAt=$createdAt, current=$current, id=$id, lastSeenAt=$lastSeenAt, name=$name, status=$status]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'created_at'] = this.createdAt.toUtc().toIso8601String();
      json[r'current'] = this.current;
      json[r'id'] = this.id;
    if (this.lastSeenAt != null) {
      json[r'last_seen_at'] = this.lastSeenAt!.toUtc().toIso8601String();
    } else {
      json[r'last_seen_at'] = null;
    }
      json[r'name'] = this.name;
      json[r'status'] = this.status;
    return json;
  }

  /// Returns a new [DeviceView] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static DeviceView? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'created_at'), 'Required key "DeviceView[created_at]" is missing from JSON.');
        assert(json[r'created_at'] != null, 'Required key "DeviceView[created_at]" has a null value in JSON.');
        assert(json.containsKey(r'current'), 'Required key "DeviceView[current]" is missing from JSON.');
        assert(json[r'current'] != null, 'Required key "DeviceView[current]" has a null value in JSON.');
        assert(json.containsKey(r'id'), 'Required key "DeviceView[id]" is missing from JSON.');
        assert(json[r'id'] != null, 'Required key "DeviceView[id]" has a null value in JSON.');
        assert(json.containsKey(r'last_seen_at'), 'Required key "DeviceView[last_seen_at]" is missing from JSON.');
        assert(json.containsKey(r'name'), 'Required key "DeviceView[name]" is missing from JSON.');
        assert(json[r'name'] != null, 'Required key "DeviceView[name]" has a null value in JSON.');
        assert(json.containsKey(r'status'), 'Required key "DeviceView[status]" is missing from JSON.');
        assert(json[r'status'] != null, 'Required key "DeviceView[status]" has a null value in JSON.');
        return true;
      }());

      return DeviceView(
        createdAt: mapDateTime(json, r'created_at', r'')!,
        current: mapValueOfType<bool>(json, r'current')!,
        id: mapValueOfType<String>(json, r'id')!,
        lastSeenAt: mapDateTime(json, r'last_seen_at', r''),
        name: mapValueOfType<String>(json, r'name')!,
        status: DeviceViewStatusEnum.fromJson(json[r'status'])!,
      );
    }
    return null;
  }

  static List<DeviceView> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DeviceView>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DeviceView.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DeviceView> mapFromJson(dynamic json) {
    final map = <String, DeviceView>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DeviceView.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of DeviceView-objects as value to a dart map
  static Map<String, List<DeviceView>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DeviceView>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DeviceView.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'created_at',
    'current',
    'id',
    'last_seen_at',
    'name',
    'status',
  };
}


enum DeviceViewStatusEnum {
  pending._(r'pending'),
  active._(r'active'),
  revoked._(r'revoked'),
  ;

  /// Instantiate a new enum with the provided value.
  const DeviceViewStatusEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [DeviceViewStatusEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static DeviceViewStatusEnum? fromJson(dynamic value) => DeviceViewStatusEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [DeviceViewStatusEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<DeviceViewStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DeviceViewStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DeviceViewStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [DeviceViewStatusEnum] to String,
/// and [decode] dynamic data back to [DeviceViewStatusEnum].
class DeviceViewStatusEnumTypeTransformer {
  factory DeviceViewStatusEnumTypeTransformer() => _instance ??= const DeviceViewStatusEnumTypeTransformer._();

  const DeviceViewStatusEnumTypeTransformer._();

  String encode(DeviceViewStatusEnum data) => data._value;

  /// Returns the instance of [DeviceViewStatusEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  DeviceViewStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DeviceViewStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'pending': return DeviceViewStatusEnum.pending;
        case r'active': return DeviceViewStatusEnum.active;
        case r'revoked': return DeviceViewStatusEnum.revoked;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static DeviceViewStatusEnumTypeTransformer? _instance;
}


