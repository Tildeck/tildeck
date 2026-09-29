//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ServerInfo {
  /// Returns a new [ServerInfo] instance.
  ServerInfo({
    required this.name,
    required this.protocolVersion,
    required this.version,
  });

  ServerInfoNameEnum name;

  int protocolVersion;

  String version;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ServerInfo &&
    other.name == name &&
    other.protocolVersion == protocolVersion &&
    other.version == version;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (name.hashCode) +
    (protocolVersion.hashCode) +
    (version.hashCode);

  @override
  String toString() => 'ServerInfo[name=$name, protocolVersion=$protocolVersion, version=$version]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'name'] = this.name;
      json[r'protocol_version'] = this.protocolVersion;
      json[r'version'] = this.version;
    return json;
  }

  /// Returns a new [ServerInfo] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ServerInfo? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'name'), 'Required key "ServerInfo[name]" is missing from JSON.');
        assert(json[r'name'] != null, 'Required key "ServerInfo[name]" has a null value in JSON.');
        assert(json.containsKey(r'protocol_version'), 'Required key "ServerInfo[protocol_version]" is missing from JSON.');
        assert(json[r'protocol_version'] != null, 'Required key "ServerInfo[protocol_version]" has a null value in JSON.');
        assert(json.containsKey(r'version'), 'Required key "ServerInfo[version]" is missing from JSON.');
        assert(json[r'version'] != null, 'Required key "ServerInfo[version]" has a null value in JSON.');
        return true;
      }());

      return ServerInfo(
        name: ServerInfoNameEnum.fromJson(json[r'name'])!,
        protocolVersion: mapValueOfType<int>(json, r'protocol_version')!,
        version: mapValueOfType<String>(json, r'version')!,
      );
    }
    return null;
  }

  static List<ServerInfo> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ServerInfo>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ServerInfo.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ServerInfo> mapFromJson(dynamic json) {
    final map = <String, ServerInfo>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ServerInfo.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ServerInfo-objects as value to a dart map
  static Map<String, List<ServerInfo>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ServerInfo>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ServerInfo.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'name',
    'protocol_version',
    'version',
  };
}


enum ServerInfoNameEnum {
  tildeck._(r'tildeck'),
  ;

  /// Instantiate a new enum with the provided value.
  const ServerInfoNameEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [ServerInfoNameEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static ServerInfoNameEnum? fromJson(dynamic value) => ServerInfoNameEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [ServerInfoNameEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<ServerInfoNameEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ServerInfoNameEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ServerInfoNameEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [ServerInfoNameEnum] to String,
/// and [decode] dynamic data back to [ServerInfoNameEnum].
class ServerInfoNameEnumTypeTransformer {
  factory ServerInfoNameEnumTypeTransformer() => _instance ??= const ServerInfoNameEnumTypeTransformer._();

  const ServerInfoNameEnumTypeTransformer._();

  String encode(ServerInfoNameEnum data) => data._value;

  /// Returns the instance of [ServerInfoNameEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  ServerInfoNameEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is ServerInfoNameEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'tildeck': return ServerInfoNameEnum.tildeck;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static ServerInfoNameEnumTypeTransformer? _instance;
}


