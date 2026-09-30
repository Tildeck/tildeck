//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class VaultKeys {
  /// Returns a new [VaultKeys] instance.
  VaultKeys({
    required this.kdf,
    required this.vaultId,
    required this.wrapPw,
  });

  KdfParams kdf;

  String vaultId;

  ModelSealed wrapPw;

  @override
  bool operator ==(Object other) => identical(this, other) || other is VaultKeys &&
    other.kdf == kdf &&
    other.vaultId == vaultId &&
    other.wrapPw == wrapPw;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (kdf.hashCode) +
    (vaultId.hashCode) +
    (wrapPw.hashCode);

  @override
  String toString() => 'VaultKeys[kdf=$kdf, vaultId=$vaultId, wrapPw=$wrapPw]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'kdf'] = this.kdf;
      json[r'vault_id'] = this.vaultId;
      json[r'wrap_pw'] = this.wrapPw;
    return json;
  }

  /// Returns a new [VaultKeys] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static VaultKeys? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'kdf'), 'Required key "VaultKeys[kdf]" is missing from JSON.');
        assert(json[r'kdf'] != null, 'Required key "VaultKeys[kdf]" has a null value in JSON.');
        assert(json.containsKey(r'vault_id'), 'Required key "VaultKeys[vault_id]" is missing from JSON.');
        assert(json[r'vault_id'] != null, 'Required key "VaultKeys[vault_id]" has a null value in JSON.');
        assert(json.containsKey(r'wrap_pw'), 'Required key "VaultKeys[wrap_pw]" is missing from JSON.');
        assert(json[r'wrap_pw'] != null, 'Required key "VaultKeys[wrap_pw]" has a null value in JSON.');
        return true;
      }());

      return VaultKeys(
        kdf: KdfParams.fromJson(json[r'kdf'])!,
        vaultId: mapValueOfType<String>(json, r'vault_id')!,
        wrapPw: ModelSealed.fromJson(json[r'wrap_pw'])!,
      );
    }
    return null;
  }

  static List<VaultKeys> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <VaultKeys>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = VaultKeys.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, VaultKeys> mapFromJson(dynamic json) {
    final map = <String, VaultKeys>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = VaultKeys.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of VaultKeys-objects as value to a dart map
  static Map<String, List<VaultKeys>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<VaultKeys>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = VaultKeys.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'kdf',
    'vault_id',
    'wrap_pw',
  };
}

