import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';

import '../shared/geocoding_service.dart';
import '../shared/pig_disease_ui.dart';

class DiseaseMapPage extends StatefulWidget {
  const DiseaseMapPage({Key? key}) : super(key: key);

  @override
  State<DiseaseMapPage> createState() => _DiseaseMapPageState();
}

class _DiseaseMapPageState extends State<DiseaseMapPage> {
  final MapController _mapController = MapController();

  List<CircleMarker> _heatmapCircles = [];
  List<Polygon> _municipalityPolygons = [];
  List<Polygon> _outsideMaskPolygons = [];
  List<Marker> _invisibleMarkers = [];
  List<_GeoMunicipalityFeature> _municipalityFeatures = [];
  Map<String, _MunicipalityHeatStats> _municipalityStats = {};

  String? _selectedDisease;
  LatLngBounds? _provinceBoundaryBounds;

  static const String _filterBoxName = 'diseaseMapFilterBox';
  static const String _filterKeySelectedDisease = 'selectedDisease';

  bool _isBoundaryLoading = true;
  bool _isReportLoading = true;
  bool _isMapReady = false;
  bool _hasAppliedInitialCamera = false;

  final List<String> _diseaseKeys = const [
    'swine_pox',
    'infected_bacterial_erysipelas',
    'infected_bacterial_greasy',
    'infected_environmental_sunburn',
    'infected_fungal_ringworm',
    'infected_parasitic_mange',
    'infected_viral_foot_and_mouth',
  ];

  static final LatLngBounds _davaoDelNorteBounds = LatLngBounds(
    const LatLng(6.95, 125.45),
    const LatLng(7.75, 126.05),
  );

  bool get _isLoading => _isBoundaryLoading || _isReportLoading;

  @override
  void initState() {
    super.initState();
    _initializeFilterAndLoad();
  }

  String _canonicalDiseaseKey(String raw) {
    final k = PigDiseaseUI.normalizeKey(raw);
    switch (k) {
      case 'erysipelas':
      case 'bacterial_erysipelas':
      case 'infected_bacterial_erysipelas':
        return 'infected_bacterial_erysipelas';
      case 'greasy_pig_disease':
      case 'greasy':
      case 'infected_bacterial_greasy':
        return 'infected_bacterial_greasy';
      case 'sunburn':
      case 'infected_environmental_sunburn':
        return 'infected_environmental_sunburn';
      case 'ringworm':
      case 'infected_fungal_ringworm':
        return 'infected_fungal_ringworm';
      case 'mange':
      case 'infected_parasitic_mange':
        return 'infected_parasitic_mange';
      case 'foot_and_mouth':
      case 'foot-and-mouth_disease':
      case 'infected_viral_foot_and_mouth':
        return 'infected_viral_foot_and_mouth';
      case 'swine_pox':
        return 'swine_pox';
      case 'dermatatis':
      case 'dermatitis':
        return 'dermatatis';
      case 'pityriasis_rosea':
        return 'pityriasis_rosea';
      default:
        return k;
    }
  }

  Future<void> _initializeFilterAndLoad() async {
    try {
      final box = await Hive.openBox(_filterBoxName);
      final saved = box.get(_filterKeySelectedDisease);
      final savedKey = saved?.toString();
      if (savedKey != null && _diseaseKeys.contains(savedKey)) {
        _selectedDisease = savedKey;
      } else {
        _selectedDisease = null;
      }
    } catch (_) {
      _selectedDisease = null;
    }

    if (!mounted) return;

    await Future.wait<void>([
      _loadProvinceBoundaries(),
      _loadDiseaseLocations(),
    ]);
  }

  Future<void> _saveSelectedDiseaseFilter(String? value) async {
    try {
      final box = await Hive.openBox(_filterBoxName);
      if (value == null || !_diseaseKeys.contains(value)) {
        await box.delete(_filterKeySelectedDisease);
      } else {
        await box.put(_filterKeySelectedDisease, value);
      }
    } catch (_) {}
  }

  Future<void> _loadProvinceBoundaries() async {
    try {
      final geoJsonString = await rootBundle.loadString('assets/DDN.geojson');
      final decoded = jsonDecode(geoJsonString) as Map<String, dynamic>;
      final rawFeatures = decoded['features'] as List<dynamic>? ?? const [];

      final municipalityFeatures = <_GeoMunicipalityFeature>[];
      final allPoints = <LatLng>[];

      for (final rawFeature in rawFeatures) {
        if (rawFeature is! Map) continue;

        final feature = Map<String, dynamic>.from(rawFeature);
        final properties =
            feature['properties'] is Map
                ? Map<String, dynamic>.from(feature['properties'] as Map)
                : const <String, dynamic>{};

        final municipalityName =
            (properties['MUNICIPALI'] ??
                    properties['municipality'] ??
                    properties['name'] ??
                    '')
                .toString()
                .trim();

        if (municipalityName.isEmpty) continue;

        final shapes = _parseGeoJsonGeometry(feature['geometry']);
        if (shapes.isEmpty) continue;

        for (final shape in shapes) {
          allPoints.addAll(shape.points);
          for (final hole in shape.holes) {
            allPoints.addAll(hole);
          }
        }

        municipalityFeatures.add(
          _GeoMunicipalityFeature(
            normalizedName: _normalizeMunicipalityName(municipalityName),
            shapes: shapes,
          ),
        );
      }

      final renderedPolygons = _buildMunicipalityPolygons(
        municipalityFeatures,
        _municipalityStats,
      );
      final outsideMaskPolygons = _buildOutsideMaskPolygons(
        municipalityFeatures,
      );

      if (!mounted) return;
      setState(() {
        _municipalityFeatures = municipalityFeatures;
        _municipalityPolygons = renderedPolygons;
        _outsideMaskPolygons = outsideMaskPolygons;
        _provinceBoundaryBounds =
            allPoints.isEmpty ? null : LatLngBounds.fromPoints(allPoints);
        _isBoundaryLoading = false;
      });
      _fitMapToProvinceIfReady();
    } catch (e) {
      debugPrint('Error loading Davao del Norte GeoJSON: $e');
      if (!mounted) return;
      setState(() {
        _isBoundaryLoading = false;
      });
      _fitMapToProvinceIfReady();
    }
  }

  Future<void> _loadDiseaseLocations() async {
    if (mounted) {
      setState(() {
        _isReportLoading = true;
      });
    }

    if (_selectedDisease == null) {
      final renderedPolygons = _buildMunicipalityPolygons(
        _municipalityFeatures,
        const <String, _MunicipalityHeatStats>{},
      );

      if (!mounted) return;
      setState(() {
        _municipalityStats = {};
        _municipalityPolygons = renderedPolygons;
        _heatmapCircles = [];
        _invisibleMarkers = [];
        _isReportLoading = false;
      });
      return;
    }

    try {
      final snapshot =
          await FirebaseFirestore.instance
              .collection('scan_requests')
              .where('status', isEqualTo: 'completed')
              .get();

      final Map<String, _BarangayAgg> agg = {};
      int totalBackgroundReports = 0;
      final geocoder = GeocodingService();
      final Map<String, Map<String, dynamic>?> userCache = {};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final status = (data['status'] ?? '').toString();
        if (status != 'completed') continue;

        final rawSummary =
            (data['expertDiseaseSummary'] as List?) ??
            (data['diseaseSummary'] as List?) ??
            const [];

        final cleaned = <Map<String, dynamic>>[];
        for (final e in rawSummary) {
          if (e is Map) cleaned.add(Map<String, dynamic>.from(e));
        }

        final userId = (data['userId'] ?? '').toString();
        if (userId.trim().isEmpty) continue;

        String province = (data['province'] ?? '').toString();
        String city = (data['cityMunicipality'] ?? '').toString();
        String barangay = (data['barangay'] ?? '').toString();

        double? lat = (data['latitude'] as num?)?.toDouble();
        double? lng = (data['longitude'] as num?)?.toDouble();

        if (province.trim().isEmpty ||
            city.trim().isEmpty ||
            barangay.trim().isEmpty ||
            lat == null ||
            lng == null) {
          Map<String, dynamic>? userData = userCache[userId];
          if (userData == null && !userCache.containsKey(userId)) {
            try {
              final userDoc =
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(userId)
                      .get();
              userData = userDoc.data();
            } catch (_) {
              userData = null;
            }
            userCache[userId] = userData;
          } else {
            userData = userCache[userId];
          }

          if (userData != null) {
            province =
                province.trim().isEmpty
                    ? (userData['province'] ?? '').toString()
                    : province;
            city =
                city.trim().isEmpty
                    ? (userData['cityMunicipality'] ?? '').toString()
                    : city;
            barangay =
                barangay.trim().isEmpty
                    ? (userData['barangay'] ?? '').toString()
                    : barangay;
            lat ??= (userData['latitude'] as num?)?.toDouble();
            lng ??= (userData['longitude'] as num?)?.toDouble();
          }
        }

        if (barangay.trim().isEmpty && city.trim().isEmpty) continue;

        totalBackgroundReports++;

        final diseaseKeysInReport =
            cleaned
                .map(
                  (e) => _canonicalDiseaseKey(
                    (e['label'] ?? e['disease'] ?? e['name'] ?? '').toString(),
                  ),
                )
                .where((k) => _diseaseKeys.contains(k))
                .toSet();

        if (!diseaseKeysInReport.contains(_selectedDisease)) continue;

        final key =
            '${barangay.toLowerCase()}|${city.toLowerCase()}|${province.toLowerCase()}';
        agg.putIfAbsent(
          key,
          () => _BarangayAgg(
            province: province,
            city: city,
            barangay: barangay,
          ),
        );
        agg[key]!.count++;
        if (lat != null && lng != null) {
          agg[key]!.sumLat += lat;
          agg[key]!.sumLng += lng;
          agg[key]!.coordinateSamples++;
        }
        for (final diseaseKey in diseaseKeysInReport) {
          agg[key]!.diseaseCounts[diseaseKey] =
              (agg[key]!.diseaseCounts[diseaseKey] ?? 0) + 1;
        }
      }

      for (final a in agg.values) {
        if (a.coordinateSamples > 0) {
          a.lat = a.sumLat / a.coordinateSamples;
          a.lng = a.sumLng / a.coordinateSamples;
          continue;
        }

        if (a.province.trim().isEmpty || a.city.trim().isEmpty) continue;

        if (a.barangay.trim().isNotEmpty) {
          final geo = await geocoder.geocode(
            barangay: a.barangay,
            cityMunicipality: a.city,
            province: a.province,
          );
          if (geo != null) {
            a.lat = geo['lat'];
            a.lng = geo['lng'];
            continue;
          }
        }

        final cityGeo = await geocoder.geocodeCity(
          cityMunicipality: a.city,
          province: a.province,
        );
        if (cityGeo != null) {
          a.lat = cityGeo['lat'];
          a.lng = cityGeo['lng'];
        }
      }

      final heatmapCircles = <CircleMarker>[];
      final invisibleMarkers = <Marker>[];
      final municipalityStats = <String, _MunicipalityHeatStats>{};

      final totalCases = totalBackgroundReports;
      for (final a in agg.values) {
        if (a.lat == null || a.lng == null) continue;

        final count = a.count;
        if (count <= 0) continue;

        final percentage = totalCases > 0 ? (count / totalCases * 100) : 0.0;

        final municipalityKey = _normalizeMunicipalityName(a.city);
        final previousMunicipalityStats = municipalityStats[municipalityKey];
        if (previousMunicipalityStats == null ||
            percentage > previousMunicipalityStats.percentage) {
          municipalityStats[municipalityKey] = _MunicipalityHeatStats(
            count: count,
            percentage: percentage,
          );
        }

        double radius;
        if (percentage <= 10) {
          radius = 500.0 + ((percentage / 10.0) * 1000.0);
        } else if (percentage <= 30) {
          radius = 1500.0 + (((percentage - 10) / 20.0) * 1500.0);
        } else {
          final excess = percentage - 30;
          radius = 3000.0 + (math.min(excess / 70.0, 1.0) * 2000.0);
        }

        final heatmapColor = _getHeatmapColorByPercentage(percentage);

        const numLayers = 5;
        for (int i = 0; i < numLayers; i++) {
          final layerRadius = radius * (1.0 + (i * 0.2));
          final layerOpacity = 0.6 * math.exp(-i * 0.4);

          if (layerRadius > 50 && layerOpacity > 0.05) {
            heatmapCircles.add(
              CircleMarker(
                point: LatLng(a.lat!, a.lng!),
                radius: layerRadius,
                color: heatmapColor.withOpacity(layerOpacity),
                borderColor: Colors.transparent,
                borderStrokeWidth: 0,
                useRadiusInMeter: true,
              ),
            );
          }
        }

        heatmapCircles.add(
          CircleMarker(
            point: LatLng(a.lat!, a.lng!),
            radius: radius * 0.15,
            color: heatmapColor,
            borderColor: Colors.white.withOpacity(0.9),
            borderStrokeWidth: 2.0,
            useRadiusInMeter: true,
          ),
        );

        invisibleMarkers.add(
          Marker(
            point: LatLng(a.lat!, a.lng!),
            width: 40,
            height: 40,
            child: GestureDetector(
              onTap: () {
                _showMarkerInfo(
                  count,
                  percentage: percentage,
                  barangay: a.barangay,
                  city: a.city,
                  province: a.province,
                  diseaseCounts: a.diseaseCounts,
                );
              },
              child: Container(
                color: Colors.transparent,
                width: 40,
                height: 40,
              ),
            ),
          ),
        );
      }

      final renderedPolygons = _buildMunicipalityPolygons(
        _municipalityFeatures,
        municipalityStats,
      );

      if (!mounted) return;
      setState(() {
        _municipalityStats = municipalityStats;
        _municipalityPolygons = renderedPolygons;
        _heatmapCircles = heatmapCircles;
        _invisibleMarkers = invisibleMarkers;
        _isReportLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading disease locations: $e');
      if (!mounted) return;
      setState(() {
        _isReportLoading = false;
      });
    }
  }

  void _showMarkerInfo(
    int count, {
    required double percentage,
    required String barangay,
    required String city,
    required String province,
    required Map<String, int> diseaseCounts,
  }) {
    final severity = _getSeverityLabel(percentage);
    final severityColor = _severityColor(severity);
    final selectedDiseaseName = PigDiseaseUI.displayName(
      _selectedDisease ?? 'unknown',
    );

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(selectedDiseaseName),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Location',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                Text(
                  '$city, $province',
                  style: const TextStyle(fontSize: 16),
                ),
                if (barangay.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Barangay reference: $barangay',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        label: 'Cases',
                        value: '$count',
                        color: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMetricCard(
                        label: 'Share',
                        value: '${percentage.toStringAsFixed(1)}%',
                        color: Colors.indigo,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: severityColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: severityColor.withOpacity(0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: severityColor),
                      const SizedBox(width: 8),
                      Text(
                        'Severity: $severity',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: severityColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  String _getSeverityLabel(double percentage) {
    if (percentage > 30) return 'High';
    if (percentage > 10) return 'Medium';
    return 'Low';
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'High':
        return Colors.red;
      case 'Medium':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Color _getHeatmapColorByPercentage(double percentage) {
    final severity = _getSeverityLabel(percentage);
    return _severityColor(severity);
  }

  List<_GeoPolygonShape> _parseGeoJsonGeometry(dynamic rawGeometry) {
    if (rawGeometry is! Map) return [];

    final geometry = Map<String, dynamic>.from(rawGeometry);
    final type = (geometry['type'] ?? '').toString();
    final coordinates = geometry['coordinates'];

    switch (type) {
      case 'Polygon':
        return _parsePolygonCoordinates(coordinates);
      case 'MultiPolygon':
        final polygons = <_GeoPolygonShape>[];
        if (coordinates is List) {
          for (final polygonCoordinates in coordinates) {
            polygons.addAll(_parsePolygonCoordinates(polygonCoordinates));
          }
        }
        return polygons;
      default:
        return [];
    }
  }

  List<_GeoPolygonShape> _parsePolygonCoordinates(dynamic rawCoordinates) {
    if (rawCoordinates is! List || rawCoordinates.isEmpty) return [];

    final rings = <List<LatLng>>[];
    for (final rawRing in rawCoordinates) {
      if (rawRing is! List) continue;

      final points = <LatLng>[];
      for (final rawPoint in rawRing) {
        if (rawPoint is! List || rawPoint.length < 2) continue;

        final lng = (rawPoint[0] as num?)?.toDouble();
        final lat = (rawPoint[1] as num?)?.toDouble();
        if (lat == null || lng == null) continue;

        points.add(LatLng(lat, lng));
      }

      if (points.length < 3) continue;

      final first = points.first;
      final last = points.last;
      if (first.latitude == last.latitude &&
          first.longitude == last.longitude) {
        points.removeLast();
      }

      if (points.length >= 3) {
        rings.add(points);
      }
    }

    if (rings.isEmpty) return [];

    return [
      _GeoPolygonShape(
        points: rings.first,
        holes: rings.length > 1 ? rings.sublist(1) : const [],
      ),
    ];
  }

  List<Polygon> _buildMunicipalityPolygons(
    List<_GeoMunicipalityFeature> municipalityFeatures,
    Map<String, _MunicipalityHeatStats> municipalityStats,
  ) {
    final polygons = <Polygon>[];

    for (final feature in municipalityFeatures) {
      final stats = municipalityStats[feature.normalizedName];
      final fillColor = _getMunicipalityFillColor(stats);

      for (final shape in feature.shapes) {
        polygons.add(
          Polygon(
            points: shape.points,
            holePointsList: shape.holes.isEmpty ? null : shape.holes,
            color: fillColor,
            borderColor: Colors.black.withOpacity(0.82),
            borderStrokeWidth: 1.15,
            isFilled: true,
          ),
        );
      }
    }

    return polygons;
  }

  List<Polygon> _buildOutsideMaskPolygons(
    List<_GeoMunicipalityFeature> municipalityFeatures,
  ) {
    final holes = <List<LatLng>>[];

    for (final feature in municipalityFeatures) {
      for (final shape in feature.shapes) {
        holes.add(shape.points);
      }
    }

    if (holes.isEmpty) return [];

    return [
      Polygon(
        points: const [
          LatLng(-85, -180),
          LatLng(-85, 180),
          LatLng(85, 180),
          LatLng(85, -180),
        ],
        holePointsList: holes,
        color: Colors.white.withOpacity(0.84),
        borderColor: Colors.transparent,
        borderStrokeWidth: 0,
        disableHolesBorder: true,
        isFilled: true,
      ),
    ];
  }

  Color _getMunicipalityFillColor(_MunicipalityHeatStats? stats) {
    if (_selectedDisease == null) {
      return Colors.white.withOpacity(0.32);
    }

    if (stats == null || stats.count == 0) {
      return Colors.white.withOpacity(0.30);
    }

    final softened = Color.lerp(
      Colors.white,
      _getHeatmapColorByPercentage(stats.percentage),
      0.32,
    )!;

    double opacity;
    if (stats.percentage > 30) {
      opacity = 0.22;
    } else if (stats.percentage > 10) {
      opacity = 0.16;
    } else {
      opacity = 0.10 + (math.min(stats.percentage, 10) / 10 * 0.05);
    }

    return softened.withOpacity(opacity);
  }

  String _normalizeMunicipalityName(String raw) {
    var normalized = raw.toLowerCase().trim();
    normalized = normalized.replaceAll('&', ' and ');
    normalized = normalized.replaceAll(
      RegExp(r'\bisland garden city of\b'),
      'island garden',
    );
    normalized = normalized.replaceAll(RegExp(r'\bcity of\b'), '');
    normalized = normalized.replaceAll(RegExp(r'\bcity\b'), '');
    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    return normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  void _fitMapToProvinceIfReady() {
    if (!_isMapReady || _hasAppliedInitialCamera || _isBoundaryLoading) return;

    final bounds = _provinceBoundaryBounds ?? _davaoDelNorteBounds;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isMapReady || _hasAppliedInitialCamera) return;
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(28)),
      );
      _hasAppliedInitialCamera = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildLegendItem(Colors.green, 'Low'),
                                  _buildLegendItem(Colors.orange, 'Medium'),
                                  _buildLegendItem(Colors.red, 'High'),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Municipality shading = share of completed reports. Black outlines = Davao del Norte GeoJSON borders. Thresholds: Low (10% and below) | Medium (11% to 30%) | High (31% and above)',
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh, size: 20),
                              tooltip: 'Refresh map data',
                              onPressed:
                                  _isLoading ? null : _loadDiseaseLocations,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Filter by Disease Type',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _selectedDisease,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          hint: const Text('Select disease'),
                          items: [
                            ..._diseaseKeys.map((key) {
                              return DropdownMenuItem<String>(
                                value: key,
                                child: Text(PigDiseaseUI.displayName(key)),
                              );
                            }).toList(),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedDisease = value;
                            });
                            _saveSelectedDiseaseFilter(value);
                            _loadDiseaseLocations();
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter:
                            _provinceBoundaryBounds?.center ??
                            _davaoDelNorteBounds.center,
                        initialZoom: 9.0,
                        onMapReady: () {
                          _isMapReady = true;
                          _fitMapToProvinceIfReady();
                        },
                        minZoom: 5.0,
                        maxZoom: 18.0,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.capstone',
                        ),
                        if (_outsideMaskPolygons.isNotEmpty)
                          PolygonLayer(polygons: _outsideMaskPolygons),
                        if (_municipalityPolygons.isNotEmpty)
                          PolygonLayer(polygons: _municipalityPolygons),
                        if (_heatmapCircles.isNotEmpty)
                          CircleLayer(circles: _heatmapCircles),
                        MarkerLayer(markers: _invisibleMarkers),
                      ],
                    ),
                  ),
                ],
              ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.black87),
        ),
      ],
    );
  }
}

class _BarangayAgg {
  _BarangayAgg({
    required this.province,
    required this.city,
    required this.barangay,
  });

  final String province;
  final String city;
  final String barangay;
  final Map<String, int> diseaseCounts = {};
  int count = 0;
  double? lat;
  double? lng;
  double sumLat = 0;
  double sumLng = 0;
  int coordinateSamples = 0;
}

class _MunicipalityHeatStats {
  const _MunicipalityHeatStats({
    required this.count,
    required this.percentage,
  });

  final int count;
  final double percentage;
}

class _GeoMunicipalityFeature {
  const _GeoMunicipalityFeature({
    required this.normalizedName,
    required this.shapes,
  });

  final String normalizedName;
  final List<_GeoPolygonShape> shapes;
}

class _GeoPolygonShape {
  const _GeoPolygonShape({required this.points, required this.holes});

  final List<LatLng> points;
  final List<List<LatLng>> holes;
}
