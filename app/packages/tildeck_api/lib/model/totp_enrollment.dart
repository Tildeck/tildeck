//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class TotpEnrollment {
  /// Returns a new [TotpEnrollment] instance.
  TotpEnrollment({
    required this.qrImage,
    required this.secret,
    required this.uri,
  });

  String qrImage;

  String secret;

  String uri;

  @override
  bool operator ==(Object other) => identical(this, other) || other is TotpEnrollment &&
    other.qrImage == qrImage &&
    other.secret == secret &&
    other.uri == uri;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (qrImage.hashCode) +
    (secret.hashCode) +
    (uri.hashCode);

  @override
  String toString() => 'TotpEnrollment[qrImage=$qrImage, secret=$secret, uri=$uri]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'qr_image'] = this.qrImage;
      json[r'secret'] = this.secret;
      json[r'uri'] = this.uri;
    return json;
  }

  /// Returns a new [TotpEnrollment] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static TotpEnrollment? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'qr_image'), 'Required key "TotpEnrollment[qr_image]" is missing from JSON.');
        assert(json[r'qr_image'] != null, 'Required key "TotpEnrollment[qr_image]" has a null value in JSON.');
        assert(json.containsKey(r'secret'), 'Required key "TotpEnrollment[secret]" is missing from JSON.');
        assert(json[r'secret'] != null, 'Required key "TotpEnrollment[secret]" has a null value in JSON.');
        assert(json.containsKey(r'uri'), 'Required key "TotpEnrollment[uri]" is missing from JSON.');
        assert(json[r'uri'] != null, 'Required key "TotpEnrollment[uri]" has a null value in JSON.');
        return true;
      }());

      return TotpEnrollment(
        qrImage: mapValueOfType<String>(json, r'qr_image')!,
        secret: mapValueOfType<String>(json, r'secret')!,
        uri: mapValueOfType<String>(json, r'uri')!,
      );
    }
    return null;
  }

  static List<TotpEnrollment> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <TotpEnrollment>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = TotpEnrollment.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, TotpEnrollment> mapFromJson(dynamic json) {
    final map = <String, TotpEnrollment>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = TotpEnrollment.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of TotpEnrollment-objects as value to a dart map
  static Map<String, List<TotpEnrollment>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<TotpEnrollment>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = TotpEnrollment.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'qr_image',
    'secret',
    'uri',
  };
}

