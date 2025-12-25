import 'dart:convert';
import 'package:flutter/services.dart';

/// Static location data for Davao del Norte province.
/// This provides reliable, offline access to cities, municipalities, and barangays.
class DavaoDelNorteLocations {
  static Map<String, dynamic>? _data;
  static bool _loaded = false;

  /// Load location data from assets
  static Future<void> load() async {
    if (_loaded) return;
    try {
      final String jsonString = await rootBundle.loadString(
        'assets/davao_del_norte_locations.json',
      );
      _data = jsonDecode(jsonString) as Map<String, dynamic>;
      _loaded = true;
    } catch (e) {
      print('❌ Error loading Davao del Norte locations: $e');
      _data = null;
    }
  }

  /// Get province information
  static Map<String, dynamic>? getProvince() {
    return _data?['province'] as Map<String, dynamic>?;
  }

  /// Get all cities/municipalities
  static List<Map<String, dynamic>> getCities() {
    if (_data == null) return [];
    final cities = _data!['cities'] as List<dynamic>?;
    if (cities == null) return [];
    return cities.map((c) => Map<String, dynamic>.from(c as Map)).toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
  }

  /// Get barangays for a specific city (by code or name)
  static List<Map<String, dynamic>> getBarangaysForCity(String cityCodeOrName) {
    if (_data == null) return [];
    final cities = _data!['cities'] as List<dynamic>?;
    if (cities == null) return [];

    for (final city in cities) {
      final cityMap = Map<String, dynamic>.from(city as Map);
      final code = (cityMap['code'] as String?) ?? '';
      final name = (cityMap['name'] as String?) ?? '';

      // Match by code or name (case-insensitive)
      if (code == cityCodeOrName ||
          name.toLowerCase().trim() == cityCodeOrName.toLowerCase().trim()) {
        final barangays = cityMap['barangays'] as List<dynamic>?;
        if (barangays == null) return [];
        return barangays.map((b) {
            // Handle both string and object formats
            if (b is String) {
              return {'name': b};
            }
            return Map<String, dynamic>.from(b as Map);
          }).toList()
          ..sort(
            (a, b) => (a['name'] as String).compareTo(b['name'] as String),
          );
      }
    }
    return [];
  }

  /// Get city by code
  static Map<String, dynamic>? getCityByCode(String cityCode) {
    final cities = getCities();
    try {
      return cities.firstWhere((c) => c['code'] == cityCode);
    } catch (_) {
      return null;
    }
  }

  /// Get city by name (fuzzy match)
  static Map<String, dynamic>? getCityByName(String cityName) {
    final cities = getCities();
    final normalized = cityName.toLowerCase().trim();
    try {
      return cities.firstWhere(
        (c) => (c['name'] as String).toLowerCase().trim() == normalized,
      );
    } catch (_) {
      return null;
    }
  }

  /// Get coordinates for a city
  static Map<String, double>? getCityCoordinates(String cityCode) {
    final city = getCityByCode(cityCode);
    if (city == null) return null;
    final lat = (city['lat'] as num?)?.toDouble();
    final lng = (city['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return {'lat': lat, 'lng': lng};
  }
}
