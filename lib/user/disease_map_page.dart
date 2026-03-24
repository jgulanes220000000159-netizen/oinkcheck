import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'dart:async';
import 'dart:math' as math;
import '../shared/pig_disease_ui.dart';
import '../shared/geocoding_service.dart';

class DiseaseMapPage extends StatefulWidget {
  const DiseaseMapPage({Key? key}) : super(key: key);

  @override
  State<DiseaseMapPage> createState() => _DiseaseMapPageState();
}

class _DiseaseMapPageState extends State<DiseaseMapPage> {
  final MapController _mapController = MapController();
  List<CircleMarker> _heatmapCircles = [];
  List<Marker> _invisibleMarkers = []; // For click interaction
  String? _selectedDisease;
  static const String _filterBoxName = 'diseaseMapFilterBox';
  static const String _filterKeySelectedDisease = 'selectedDisease';

  // Use model label keys for filtering/colors (exclude healthy/unknown).
  final List<String> _diseaseKeys = const [
    'swine_pox',
    'infected_bacterial_erysipelas',
    'infected_bacterial_greasy',
    'infected_environmental_sunburn',
    'infected_fungal_ringworm',
    'infected_parasitic_mange',
    'infected_viral_foot_and_mouth',
  ];

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

  bool _isLoading = true;

  // Davao del Norte (approx bounds). Used to force the map to start focused on the province.
  // You can tighten/adjust these bounds anytime if you want a closer initial view.
  static final LatLngBounds _davaoDelNorteBounds = LatLngBounds(
    const LatLng(6.95, 125.45), // SW
    const LatLng(7.75, 126.05), // NE
  );

  @override
  void initState() {
    super.initState();
    _initializeFilterAndLoad();
  }

  Future<void> _initializeFilterAndLoad() async {
    try {
      final box = await Hive.openBox(_filterBoxName);
      final saved = box.get(_filterKeySelectedDisease);
      final savedKey = saved?.toString();
      if (savedKey != null && _diseaseKeys.contains(savedKey)) {
        _selectedDisease = savedKey;
      } else {
        _selectedDisease = null; // "Select disease" default
      }
    } catch (_) {
      _selectedDisease = null;
    }
    if (!mounted) return;
    _loadDiseaseLocations();
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

  Future<void> _loadDiseaseLocations() async {
    if (_selectedDisease == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _heatmapCircles = [];
        _invisibleMarkers = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Load ONLY completed reports (validated by expert).
      final snapshot =
          await FirebaseFirestore.instance
              .collection('scan_requests')
              .where('status', isEqualTo: 'completed')
              .get();

      print(
        '🔍 Disease Map: Found ${snapshot.docs.length} documents with status="completed"',
      );

      // Aggregate by City (focus area).
      // One marker per city for selected disease, with size based on case count.
      final Map<String, _BarangayAgg> agg = {};
      int totalBackgroundReports = 0; // Includes healthy + diseased reports.
      final geocoder = GeocodingService();
      final Map<String, Map<String, dynamic>?> userCache = {};

      for (final doc in snapshot.docs) {
        final data = doc.data();

        // Only condition: status must be exactly 'completed'.
        final status = (data['status'] ?? '').toString();
        if (status != 'completed') continue;

        // Use expertDiseaseSummary when present, otherwise fall back to model diseaseSummary.
        final rawSummary =
            (data['expertDiseaseSummary'] as List?) ??
            (data['diseaseSummary'] as List?) ??
            const [];

        final List<Map<String, dynamic>> cleaned = [];
        for (final e in rawSummary) {
          if (e is Map) cleaned.add(Map<String, dynamic>.from(e));
        }
        final userId = (data['userId'] ?? '').toString();
        if (userId.trim().isEmpty) continue;

        // Prefer address fields copied onto scan_requests; fall back to user profile.
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
          // Fetch user doc once per userId (cached) for older reports.
          Map<String, dynamic>? u = userCache[userId];
          if (u == null && !userCache.containsKey(userId)) {
            try {
              final userDoc =
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(userId)
                      .get();
              u = userDoc.data();
            } catch (_) {
              u = null;
            }
            userCache[userId] = u;
          } else {
            u = userCache[userId];
          }

          if (u != null) {
            province =
                province.trim().isEmpty
                    ? (u['province'] ?? '').toString()
                    : province;
            city =
                city.trim().isEmpty
                    ? (u['cityMunicipality'] ?? '').toString()
                    : city;
            barangay =
                barangay.trim().isEmpty
                    ? (u['barangay'] ?? '').toString()
                    : barangay;
            lat ??= (u['latitude'] as num?)?.toDouble();
            lng ??= (u['longitude'] as num?)?.toDouble();
          }
        }

        if (barangay.trim().isEmpty && city.trim().isEmpty) continue;

        // Count every completed report in the denominator (including healthy),
        // to compute real disease distribution percentages.
        totalBackgroundReports++;

        // Collect selected/real disease labels only for numerator aggregation.
        final Set<String> diseaseKeysInReport =
            cleaned
                .map(
                  (e) => _canonicalDiseaseKey(
                    (e['label'] ?? e['disease'] ?? e['name'] ?? '').toString(),
                  ),
                )
                .where((k) => _diseaseKeys.contains(k))
                .toSet();
        // Skip reports that do not match the selected disease.
        if (!diseaseKeysInReport.contains(_selectedDisease)) continue;

        // Group by CITY + PROVINCE (not barangay) so each city has one pin.
        final key = '${city.toLowerCase()}|${province.toLowerCase()}';
        agg.putIfAbsent(
          key,
          () => _BarangayAgg(
            province: province,
            city: city,
            // Keep first barangay seen for this city for informational text.
            barangay: barangay,
          ),
        );
        agg[key]!.count++;
        for (final diseaseKey in diseaseKeysInReport) {
          agg[key]!.diseaseCounts[diseaseKey] =
              (agg[key]!.diseaseCounts[diseaseKey] ?? 0) + 1;
        }
      }

      // Geocode CITY centroid (best-effort, cached) so heatmap circles sit at city center,
      // independent of individual farmer lat/lng.
      for (final a in agg.values) {
        if (a.province.trim().isEmpty || a.city.trim().isEmpty) continue;
        final geo = await geocoder.geocodeCity(
          cityMunicipality: a.city,
          province: a.province,
        );
        if (geo != null) {
          a.lat = geo['lat'];
          a.lng = geo['lng'];
        }
      }

      // Create heatmap circles with gradient layers
      final heatmapCircles = <CircleMarker>[];
      final invisibleMarkers = <Marker>[]; // For click interaction

      // Numerator is selected disease count per city; denominator includes
      // all completed reports (healthy + diseased) for real distribution.
      final totalCases = totalBackgroundReports;
      for (final a in agg.values) {
        if (a.lat == null || a.lng == null) continue;
        final count = a.count;
        if (count <= 0) continue;

        // Raw share in current filtered set (for display).
        final percentage = totalCases > 0 ? (count / totalCases * 100) : 0.0;

        // Convert raw percentage to intensity using the original thresholds.
        double intensity; // 0.0 to 1.0 for color gradient
        if (percentage <= 10) {
          intensity = (percentage / 10.0) * 0.33;
        } else if (percentage <= 30) {
          intensity = 0.33 + ((percentage - 10) / 20.0) * 0.34;
        } else {
          final excess = percentage - 30;
          intensity = 0.67 + (math.min(excess / 70.0, 1.0) * 0.33);
        }

        // Radius follows raw percentage with the same threshold bands.
        double radius;
        if (percentage <= 10) {
          radius = 500.0 + ((percentage / 10.0) * 1000.0);
        } else if (percentage <= 30) {
          radius = 1500.0 + (((percentage - 10) / 20.0) * 1500.0);
        } else {
          final excess = percentage - 30;
          radius = 3000.0 + (math.min(excess / 70.0, 1.0) * 2000.0);
        }

        // Get heatmap color based on intensity
        final heatmapColor = _getHeatmapColor(intensity);

        // Create smooth gradient heatmap effect using multiple overlapping circles
        // This simulates Kernel Density Estimation (KDE) for a smooth gradient
        const int numLayers = 5; // Layers for smoother gradient
        for (int i = 0; i < numLayers; i++) {
          // Each layer extends further with decreasing opacity
          final layerRadius = radius * (1.0 + (i * 0.2));
          // Opacity decreases exponentially for smooth falloff
          final layerOpacity = 0.6 * math.exp(-i * 0.4);

          if (layerRadius > 50 && layerOpacity > 0.05) {
            // Add gradient layers (semi-transparent for blending)
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

        // Add a solid center circle for the core intensity point
        // This creates the "hotspot" effect with white outline
        heatmapCircles.add(
          CircleMarker(
            point: LatLng(a.lat!, a.lng!),
            radius: radius * 0.15, // Smaller solid center
            color: heatmapColor, // Solid color (no opacity)
            borderColor: Colors.white.withOpacity(0.9), // White outline
            borderStrokeWidth: 2.0, // Visible outline
            useRadiusInMeter: true,
          ),
        );

        // Create invisible marker for click interaction
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

      print(
        '✅ Disease Map: Created ${heatmapCircles.length} heatmap circles from validated reports',
      );
      setState(() {
        _heatmapCircles = heatmapCircles;
        _invisibleMarkers = invisibleMarkers;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading disease locations: $e');
      setState(() {
        _isLoading = false;
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
                  '$barangay, $city, $province',
                  style: const TextStyle(fontSize: 16),
                ),
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

  /// Get heatmap color based on intensity (0.0 to 1.0)
  /// Returns gradient from green (low) -> yellow (medium) -> red (high)
  /// Thresholds: Low (10% below), Medium (11% to 30%), High (31% and above)
  Color _getHeatmapColor(double intensity) {
    if (intensity <= 0.0) return const Color(0xFF4CAF50); // Green
    if (intensity >= 1.0) return const Color(0xFFF44336); // Red

    // Define thresholds for Low/Medium/High
    const lowThreshold = 0.33; // 0.0 to 0.33 = Low (Green)
    const mediumThreshold = 0.67; // 0.33 to 0.67 = Medium (Yellow)
    // 0.67 to 1.0 = High (Red)

    if (intensity < lowThreshold) {
      // Low: Green to Light Green (0.0 to 0.33)
      final t = intensity / lowThreshold; // Scale to 0.0-1.0
      return Color.lerp(
        const Color(0xFF4CAF50), // Green
        const Color(0xFF8BC34A), // Light Green
        t,
      )!;
    } else if (intensity < mediumThreshold) {
      // Medium: Light Green to Yellow (0.33 to 0.67)
      final t =
          (intensity - lowThreshold) /
          (mediumThreshold - lowThreshold); // Scale to 0.0-1.0
      return Color.lerp(
        const Color(0xFF8BC34A), // Light Green
        const Color(0xFFFFEB3B), // Yellow
        t,
      )!;
    } else {
      // High: Yellow to Red (0.67 to 1.0)
      final t =
          (intensity - mediumThreshold) /
          (1.0 - mediumThreshold); // Scale to 0.0-1.0
      return Color.lerp(
        const Color(0xFFFFEB3B), // Yellow
        const Color(0xFFF44336), // Red
        t,
      )!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  // Legend and disease selector
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Legend (non-confusing):
                        // Pin color = severity (low/medium/high)
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
                                'Heatmap intensity = Number of completed reports • Thresholds: Low (10% below) | Medium (11% to 30%) | High (31% and above)',
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
                        // Disease selector
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
                  // Map
                  Expanded(
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        // Ensure tiles render immediately without requiring a manual drag.
                        initialCenter: _davaoDelNorteBounds.center,
                        initialZoom: 9.0,
                        onMapReady: () {
                          // Force zoom to Davao del Norte province on open.
                          // Delay one microtask to ensure the map has a size before fitting.
                          Future.microtask(() {
                            _mapController.fitCamera(
                              CameraFit.bounds(
                                bounds: _davaoDelNorteBounds,
                                padding: const EdgeInsets.all(32),
                              ),
                            );
                          });
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
}
