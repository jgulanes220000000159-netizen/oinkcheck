import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class DiseaseMapPage extends StatefulWidget {
  const DiseaseMapPage({Key? key}) : super(key: key);

  @override
  State<DiseaseMapPage> createState() => _DiseaseMapPageState();
}

class _DiseaseMapPageState extends State<DiseaseMapPage> {
  final MapController _mapController = MapController();
  List<Marker> _markers = [];
  String? _selectedDisease;

  // Static list of diseases
  final List<String> _diseases = [
    'Swine Pox',
    'Erysipelas',
    'Greasy Pig Disease',
    'Ringworm',
    'Mange',
    'Foot and Mouth Disease',
    'Sunburn',
  ];

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
      // Load scan requests with location data
      final snapshot =
          await FirebaseFirestore.instance
              .collection('scan_requests')
              .where('status', whereIn: ['completed', 'reviewed'])
              .get();

      final markers = <Marker>[];

      for (var doc in snapshot.docs) {
        final data = doc.data();

        // Get disease summary
        final diseaseSummary = data['diseaseSummary'] as List<dynamic>?;
        if (diseaseSummary == null || diseaseSummary.isEmpty) continue;

        // Get dominant disease
        final sortedDiseases = List<Map<String, dynamic>>.from(
          diseaseSummary.map((d) => d as Map<String, dynamic>),
        )..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

        final dominantDisease = sortedDiseases.first['name'] as String;
        final count = sortedDiseases.first['count'] as int;

        // Filter by selected disease if set
        if (_selectedDisease != null && dominantDisease != _selectedDisease) {
          continue;
        }

        // Try to get location from user data
        final userId = data['userId'] as String?;
        if (userId == null) continue;

        final userDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .get();

        if (!userDoc.exists) continue;

        final userData = userDoc.data() as Map<String, dynamic>;

        // Get location coordinates (latitude/longitude)
        // You'll need to add these fields to user profiles or scan_requests
        final lat = userData['latitude'] as double?;
        final lng = userData['longitude'] as double?;

        if (lat == null || lng == null) continue;

        // Determine severity color based on count
        Color markerColor;
        if (count >= 5) {
          markerColor = Colors.red; // Severe
        } else if (count >= 3) {
          markerColor = Colors.orange; // Moderate
        } else {
          markerColor = Colors.green; // Mild
        }

        markers.add(
          Marker(
            point: LatLng(lat, lng),
            width: 40,
            height: 40,
            child: GestureDetector(
              onTap: () {
                _showMarkerInfo(dominantDisease, count);
              },
              child: Icon(Icons.location_pin, color: markerColor, size: 40),
            ),
          ),
        );
      }

      setState(() {
        _markers = markers;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading disease locations: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showMarkerInfo(String disease, int count) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(disease),
            content: Text(
              'Cases: $count\nSeverity: ${_getSeverityLabel(count)}',
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
                        // Legend
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildLegendItem(Colors.green, 'Mild'),
                            _buildLegendItem(Colors.orange, 'Moderate'),
                            _buildLegendItem(Colors.red, 'Severe'),
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
                            ..._diseases.map((disease) {
                              return DropdownMenuItem<String>(
                                value: disease,
                                child: Text(disease),
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
