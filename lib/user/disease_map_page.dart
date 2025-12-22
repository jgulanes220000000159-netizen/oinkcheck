import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../shared/pig_disease_ui.dart';
import '../shared/geocoding_service.dart';

class DiseaseMapPage extends StatefulWidget {
  const DiseaseMapPage({Key? key}) : super(key: key);

  @override
  State<DiseaseMapPage> createState() => _DiseaseMapPageState();
}

class _DiseaseMapPageState extends State<DiseaseMapPage> {
  final MapController _mapController = MapController();
  List<Marker> _markers = [];
  String? _selectedDisease;

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
    _loadDiseaseLocations();
  }

  Future<void> _loadDiseaseLocations() async {
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
        if (cleaned.isEmpty) continue;

        // Collect all disease labels present in this report (no dominant logic).
        final Set<String> diseaseKeysInReport =
            cleaned
                .map((e) => _canonicalDiseaseKey(e['label']?.toString() ?? ''))
                .where((k) => k.isNotEmpty)
                .toSet();
        // If a specific disease is selected, skip reports that don't contain it.
        if (_selectedDisease != null &&
            !diseaseKeysInReport.contains(_selectedDisease)) {
          continue;
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

        // Group by CITY + PROVINCE (not barangay) so each city has one pin.
        final key = '${city.toLowerCase()}|${province.toLowerCase()}';
        agg.putIfAbsent(
          key,
          () => _BarangayAgg(
            // For display we just pick one disease present in this barangay;
            // filtering is handled above using the full set.
            diseaseKey:
                diseaseKeysInReport.isNotEmpty
                    ? diseaseKeysInReport.first
                    : 'swine_pox',
            province: province,
            city: city,
            // Keep first barangay seen for this city for informational text.
            barangay: barangay,
          ),
        );
        agg[key]!.count++;
      }

      // Geocode CITY centroid (best-effort, cached) so pins sit at city center,
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

      final markers = <Marker>[];
      for (final a in agg.values) {
        if (a.lat == null || a.lng == null) continue;
        final count = a.count;
        final severityColor = _severityColor(count);

        // Simple visual rule: Pin color = severity (mild/moderate/severe)
        // Pin size = case volume (count)
        final double pinSize = (32 + (count * 4)).clamp(32, 56).toDouble();
        markers.add(
          Marker(
            point: LatLng(a.lat!, a.lng!),
            width: pinSize,
            height: pinSize,
            child: GestureDetector(
              onTap: () {
                _showMarkerInfo(
                  a.diseaseKey,
                  count,
                  barangay: a.barangay,
                  city: a.city,
                  province: a.province,
                );
              },
              child: Icon(
                Icons.location_pin,
                color: severityColor,
                size: pinSize,
              ),
            ),
          ),
        );
      }

      print(
        '✅ Disease Map: Created ${markers.length} markers from validated reports',
      );
      setState(() {
        _markers = markers;
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
    String diseaseKey,
    int count, {
    required String barangay,
    required String city,
    required String province,
  }) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(PigDiseaseUI.displayName(diseaseKey)),
            content: Text(
              'Location: $barangay, $city, $province\nCases: $count\nSeverity: ${_getSeverityLabel(count)}',
              style: const TextStyle(fontSize: 16),
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

  String _getSeverityLabel(int count) {
    if (count >= 5) return 'Severe';
    if (count >= 3) return 'Moderate';
    return 'Mild';
  }

  Color _severityColor(int count) {
    if (count >= 5) return Colors.red;
    if (count >= 3) return Colors.orange;
    return Colors.green;
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
                        // Pin color = severity (mild/moderate/severe)
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildLegendItem(Colors.green, 'Mild'),
                                  _buildLegendItem(Colors.orange, 'Moderate'),
                                  _buildLegendItem(Colors.red, 'Severe'),
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
                                'Pin color = Severity • Pin size = Number of completed reports',
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
                          hint: const Text('All Diseases'),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('All Diseases'),
                            ),
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
                        MarkerLayer(markers: _markers),
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
    required this.diseaseKey,
    required this.province,
    required this.city,
    required this.barangay,
  });

  final String diseaseKey;
  final String province;
  final String city;
  final String barangay;
  int count = 0;
  double? lat;
  double? lng;
}
