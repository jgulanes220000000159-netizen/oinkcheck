import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

/// Very small geocoder using OpenStreetMap Nominatim.
/// We use it only to get an approximate centroid for a Barangay/City/Province
/// so we can place aggregated markers on the Disease Map.
///
/// Notes:
/// - Nominatim has usage policies and rate limits.
/// - This is best-effort and cached locally (Hive) to reduce calls.
class GeocodingService {
  static const String _boxName = 'geoCache';

  Future<Map<String, double>?> geocode({
    required String barangay,
    required String cityMunicipality,
    required String province,
  }) async {
    final b = barangay.trim();
    final c = cityMunicipality.trim();
    final p = province.trim();
    if (b.isEmpty || c.isEmpty || p.isEmpty) return null;

    final key = '${b.toLowerCase()}|${c.toLowerCase()}|${p.toLowerCase()}';
    final box = await Hive.openBox(_boxName);
    final cached = box.get(key);
    if (cached is Map) {
      final lat = (cached['lat'] as num?)?.toDouble();
      final lng = (cached['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) return {'lat': lat, 'lng': lng};
    }

    // Nominatim query: be explicit with locality + Philippines
    final q = 'Barangay $b, $c, $p, Philippines';
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': q,
      'format': 'json',
      'limit': '1',
    });

    try {
      final resp = await http.get(
        uri,
        headers: const {
          // Nominatim requires a proper User-Agent
          'User-Agent': 'OinkCheck/1.0 (disease-map)',
        },
      ).timeout(const Duration(seconds: 6));

      if (resp.statusCode != 200) return null;
      final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;
      if (data.isEmpty) return null;
      final m = data.first as Map<String, dynamic>;
      final lat = double.tryParse(m['lat']?.toString() ?? '');
      final lng = double.tryParse(m['lon']?.toString() ?? '');
      if (lat == null || lng == null) return null;

      await box.put(key, {'lat': lat, 'lng': lng});
      return {'lat': lat, 'lng': lng};
    } catch (_) {
      return null;
    }
  }

  /// Geocode a City + Province to an approximate centroid.
  /// Used for city-level pins on the Disease Map.
  Future<Map<String, double>?> geocodeCity({
    required String cityMunicipality,
    required String province,
  }) async {
    final c = cityMunicipality.trim();
    final p = province.trim();
    if (c.isEmpty || p.isEmpty) return null;

    final key = 'city|${c.toLowerCase()}|${p.toLowerCase()}';
    final box = await Hive.openBox(_boxName);
    final cached = box.get(key);
    if (cached is Map) {
      final lat = (cached['lat'] as num?)?.toDouble();
      final lng = (cached['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) return {'lat': lat, 'lng': lng};
    }

    final q = '$c, $p, Philippines';
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': q,
      'format': 'json',
      'limit': '1',
    });

    try {
      final resp = await http.get(
        uri,
        headers: const {
          'User-Agent': 'OinkCheck/1.0 (disease-map-city)',
        },
      ).timeout(const Duration(seconds: 6));

      if (resp.statusCode != 200) return null;
      final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;
      if (data.isEmpty) return null;
      final m = data.first as Map<String, dynamic>;
      final lat = double.tryParse(m['lat']?.toString() ?? '');
      final lng = double.tryParse(m['lon']?.toString() ?? '');
      if (lat == null || lng == null) return null;

      await box.put(key, {'lat': lat, 'lng': lng});
      return {'lat': lat, 'lng': lng};
    } catch (_) {
      return null;
    }
  }
}


