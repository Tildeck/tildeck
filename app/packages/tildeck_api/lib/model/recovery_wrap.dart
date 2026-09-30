//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class RecoveryWrap {
  /// Returns a new [RecoveryWrap] instance.
  RecoveryWrap({
    required this.vaultId,
    required this.wrapRk,
  });

  String vaultId;

  ModelSealed wrapRk;

  @override
  bool operator ==(Object other) => identical(this, other) || other is RecoveryWrap &&
    other.vaultId == vaultId &&
    other.wrapRk == wrapRk;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (vaultId.hashCode) +
    (wrapRk.hashCode);

  @override
  String toString() => 'RecoveryWrap[vaultId=$vaultId, wrapRk=$wrapRk]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'vault_id'] = this.vaultId;
      json[r'wrap_rk'] = this.wrapRk;
    return json;
  }

  /// Returns a new [RecoveryWrap] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static RecoveryWrap? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'vault_id'), 'Required key "RecoveryWrap[vault_id]" is missing from JSON.');
        assert(json[r'vault_id'] != null, 'Required key "RecoveryWrap[vault_id]" has a null value in JSON.');
        assert(json.containsKey(r'wrap_rk'), 'Required key "RecoveryWrap[wrap_rk]" is missing from JSON.');
        assert(json[r'wrap_rk'] != null, 'Required key "RecoveryWrap[wrap_rk]" has a null value in JSON.');
        return true;
      }());

      return RecoveryWrap(
        vaultId: mapValueOfType<String>(json, r'vault_id')!,
        wrapRk: ModelSealed.fromJson(json[r'wrap_rk'])!,
      );
    }
    return null;
  }

  static List<RecoveryWrap> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <RecoveryWrap>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RecoveryWrap.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, RecoveryWrap> mapFromJson(dynamic json) {
    final map = <String, RecoveryWrap>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = RecoveryWrap.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of RecoveryWrap-objects as value to a dart map
  static Map<String, List<RecoveryWrap>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<RecoveryWrap>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = RecoveryWrap.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'vault_id',
    'wrap_rk',
  };
}

