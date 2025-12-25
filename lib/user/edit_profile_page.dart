import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mime/mime.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../shared/geocoding_service.dart';
import '../shared/davao_del_norte_locations.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({Key? key}) : super(key: key);

  @override
  _EditProfilePageState createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _isLoadingData = true;
  final ImagePicker _picker = ImagePicker();
  File? _profileImage;
  String? _profileImageUrl;
  bool _hasValidated = false;
  Map<String, String?> _fieldErrors = {};

  // Location state (same model as registration)
  List<Map<String, String>> _provinces = [];
  List<Map<String, String>> _cities = [];
  List<Map<String, String>> _barangays = [];
  String? _selectedProvinceCode;
  String? _selectedCityCode;
  String? _selectedProvinceName;
  String? _selectedCityName;
  String? _selectedBarangayName;

  @override
  void initState() {
    super.initState();
    _loadLocations();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Fetch user profile from Firestore
        final userDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();

        if (userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>;

          // Prefer structured address fields if present
          final street = (data['street'] ?? '').toString();
          final combinedAddress = (data['address'] ?? '').toString();

          final firstName = (data['firstName'] ?? '').toString().trim();
          final lastName = (data['lastName'] ?? '').toString().trim();
          final fullName = (data['fullName'] ?? '').toString().trim();

          String fallbackFirst = '';
          String fallbackLast = '';
          if (firstName.isEmpty && lastName.isEmpty && fullName.isNotEmpty) {
            final parts =
                fullName.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
            if (parts.isNotEmpty) {
              fallbackFirst = parts.first;
              if (parts.length > 1) {
                fallbackLast = parts.sublist(1).join(' ');
              }
            }
          }

          setState(() {
            _firstNameController.text =
                firstName.isNotEmpty ? firstName : fallbackFirst;
            _lastNameController.text =
                lastName.isNotEmpty ? lastName : fallbackLast;
            _addressController.text =
                street.isNotEmpty ? street : combinedAddress;
            _phoneController.text = (data['phoneNumber'] ?? '').toString();
            _emailController.text = (data['email'] ?? '').toString();
            _profileImageUrl = data['imageProfile']?.toString();

            // Existing structured location (if any)
            _selectedProvinceName =
                (data['province'] ?? '').toString().isNotEmpty
                    ? (data['province'] ?? '').toString()
                    : null;
            // Normalize city name to match JSON format (e.g., "City of Panabo" -> "Panabo City")
            final rawCityName = (data['cityMunicipality'] ?? '').toString();
            _selectedCityName = rawCityName.isNotEmpty
                ? _normalizeCityName(rawCityName)
                : null;
            _selectedBarangayName =
                (data['barangay'] ?? '').toString().isNotEmpty
                    ? (data['barangay'] ?? '').toString()
                    : null;

            _isLoadingData = false;
          });
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
      setState(() {
        _isLoadingData = false;
      });
    }
  }

  // --- Location loading using static Davao del Norte data ---
  Future<void> _loadLocations() async {
    await DavaoDelNorteLocations.load();
    final province = DavaoDelNorteLocations.getProvince();
    if (province != null) {
      final provinceName = province['name']?.toString() ?? 'Davao del Norte';
      setState(() {
        _provinces = [
          {
            'code': province['code']?.toString() ?? '',
            'name': provinceName,
          }
        ];
        // If we already know the province name from Firestore, use it (but normalize to match)
        if (_selectedProvinceName == null) {
          _selectedProvinceCode = province['code']?.toString();
          _selectedProvinceName = provinceName; // Use exact same string
        } else {
          // Match existing province name - normalize to match JSON value
          _selectedProvinceCode = province['code']?.toString();
          _selectedProvinceName = provinceName; // Always use the JSON value to ensure match
        }
      });
      _loadCitiesForProvince();
    }
  }

  Future<void> _loadCitiesForProvince() async {
    setState(() {
      _cities = [];
      _barangays = [];
      _selectedCityCode = null;
      // keep _selectedCityName / _selectedBarangayName; we'll remap after load
    });
    
    final cities = DavaoDelNorteLocations.getCities();
    setState(() {
      _cities = cities
          .map<Map<String, String>>(
            (c) => {
              'code': c['code']?.toString() ?? '',
              'name': c['name']?.toString() ?? '',
            },
          )
          .toList();

      print('✅ Loaded ${_cities.length} cities/municipalities for Davao del Norte');

      if (_selectedCityName != null) {
        // Try exact match first
        var match = _cities.firstWhere(
          (c) => c['name'] == _selectedCityName,
          orElse: () => {},
        );
        
        // If no exact match, try normalized match
        if (match.isEmpty) {
          final normalized = _normalizeCityName(_selectedCityName!);
          match = _cities.firstWhere(
            (c) => _normalizeCityName(c['name'] ?? '') == normalized,
            orElse: () => {},
          );
        }
        
        if (match.isNotEmpty) {
          _selectedCityCode = match['code'];
          _selectedCityName = match['name']; // Use the exact JSON name
          _loadBarangaysForCity(_selectedCityCode!);
        } else {
          // No match found, clear selection
          _selectedCityName = null;
          _selectedCityCode = null;
        }
      }
    });
  }

  Future<void> _loadBarangaysForCity(String cityCode) async {
    setState(() {
      _barangays = [];
      // keep _selectedBarangayName; we'll remap after load
    });
    
    final barangays = DavaoDelNorteLocations.getBarangaysForCity(cityCode);
    setState(() {
      _barangays = barangays
          .map<Map<String, String>>(
            (b) => {
              'code': b['code']?.toString() ?? '',
              'name': b['name']?.toString() ?? '',
            },
          )
          .toList();
      
      print('✅ Loaded ${_barangays.length} barangays for city code $cityCode');
    });
  }

  Future<void> _pickProfileImage() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (pickedFile != null) {
      setState(() {
        _profileImage = File(pickedFile.path);
      });
    }
  }

  Future<String?> _uploadProfileImage(String imagePath) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final file = File(imagePath);
        final ref = FirebaseStorage.instance
            .ref()
            .child('profile')
            .child('${user.uid}.jpg');

        final detectedMime = lookupMimeType(file.path) ?? 'image/jpeg';
        await ref.putFile(file, SettableMetadata(contentType: detectedMime));
        final url = await ref.getDownloadURL();
        return url;
      }
      return null;
    } catch (e) {
      print('Error uploading profile image: $e');
      rethrow;
    }
  }

  // Normalize city name to match JSON format
  // Handles variations like "City of Panabo" -> "Panabo City"
  String _normalizeCityName(String cityName) {
    final name = cityName.trim();
    final lower = name.toLowerCase();
    
    // Handle "City of X" -> "X City"
    if (lower.startsWith('city of ')) {
      final cityPart = name.substring(8).trim(); // Remove "City of "
      return '$cityPart City';
    }
    
    // Handle "Municipality of X" -> "X"
    if (lower.startsWith('municipality of ')) {
      return name.substring(15).trim(); // Remove "Municipality of "
    }
    
    // Handle "Island Garden City of X" -> "Island Garden City of X" (keep as-is)
    if (lower.startsWith('island garden city of ')) {
      return name; // Keep full name
    }
    
    // Return as-is if already in correct format
    return name;
  }

  // Validation Functions
  String? _validateFirstName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Please enter your first name';
    if (value.trim().length < 2) return 'First name must be at least 2 characters';
    return null;
  }

  String? _validateLastName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Please enter your last name';
    if (value.trim().length < 2) return 'Last name must be at least 2 characters';
    return null;
  }

  String? _validateAddress(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your address';
    }
    if (value.trim().length < 5) {
      return 'Please enter a complete address';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your phone number';
    }
    // Philippine phone number validation: 09XXXXXXXXX (11 digits starting with 09)
    final phoneRegex = RegExp(r'^09\d{9}$');
    String cleanNumber = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (!phoneRegex.hasMatch(cleanNumber)) {
      return 'Please enter a valid mobile number (09XXXXXXXXX)';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your email';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  Future<void> _handleSave() async {
    setState(() {
      _hasValidated = true;
      // Validate all fields and store errors
      _fieldErrors = {
        'firstName': _validateFirstName(_firstNameController.text),
        'lastName': _validateLastName(_lastNameController.text),
        'address': _validateAddress(_addressController.text),
        'phone': _validatePhone(_phoneController.text),
        'email': _validateEmail(_emailController.text),
        // Location validation – must match registration rules
        'province': _selectedProvinceName == null
            ? 'Please select your province'
            : null,
        'city': _selectedCityName == null
            ? 'Please select your city/municipality'
            : null,
        'barangay': _selectedBarangayName == null
            ? 'Please select your barangay'
            : null,
      };
    });

    // Check if there are any validation errors
    if (_fieldErrors.values.any((error) => error != null && error.isNotEmpty)) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        String? newImageUrl = _profileImageUrl;

        // Upload new profile image if selected
        if (_profileImage != null) {
          newImageUrl = await _uploadProfileImage(_profileImage!.path);
        }

        final firstName = _firstNameController.text.trim();
        final lastName = _lastNameController.text.trim();
        final fullName = ('$firstName $lastName').trim();
        final street = _addressController.text.trim();
        final province = _selectedProvinceName ?? '';
        final city = _selectedCityName ?? '';
        final barangay = _selectedBarangayName ?? '';

        final combinedAddress =
            '$street, $barangay, $city, $province'.replaceAll(RegExp(r',\\s*,'),
                ',').trim();

        final userRef =
            FirebaseFirestore.instance.collection('users').doc(user.uid);

        // Update user profile in Firestore (structured address same as registration)
        await userRef.update({
          'firstName': firstName,
          'lastName': lastName,
          'fullName': fullName,
          'street': street,
          'province': province,
          'cityMunicipality': city,
          'barangay': barangay,
          'address': combinedAddress,
          'phoneNumber': _phoneController.text.trim(),
          'email': _emailController.text.trim(),
          if (newImageUrl != null) 'imageProfile': newImageUrl,
        });

        // Best-effort geocode for Disease Map (Barangay centroid).
        // Must never block/save failure even if lookup fails.
        try {
          final geo = await GeocodingService().geocode(
            barangay: barangay,
            cityMunicipality: city,
            province: province,
          );
          if (geo != null) {
            await userRef.set({
              'latitude': geo['lat'],
              'longitude': geo['lng'],
              'geoSource': 'nominatim_barangay_centroid',
              'geoUpdatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        } catch (e) {
          // Ignore geocode errors to allow profile save to succeed
          debugPrint('Geocode skipped on profile save: $e');
        }

        setState(() {
          _isLoading = false;
        });

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate back
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating profile: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String fieldKey,
    IconData? prefixIcon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final errorText = _hasValidated ? _fieldErrors[fieldKey] : null;
    final hasError = errorText != null && errorText.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          onChanged: (value) {
            if (_hasValidated && _fieldErrors.containsKey(fieldKey)) {
              setState(() {
                _fieldErrors[fieldKey] = validator?.call(value);
              });
            }
          },
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white70),
            filled: true,
            fillColor:
                hasError ? Colors.redAccent.withOpacity(0.1) : Colors.transparent,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: hasError ? Colors.redAccent : Colors.white70,
                width: hasError ? 1.5 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: hasError ? Colors.redAccent : Colors.white,
                width: hasError ? 1.5 : 1,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Colors.redAccent,
                width: 1.5,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Colors.redAccent,
                width: 1.5,
              ),
            ),
            prefixIcon:
                prefixIcon != null ? Icon(prefixIcon, color: Colors.white70) : null,
            errorStyle: const TextStyle(height: 0, fontSize: 0),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 6, right: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      errorText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLocationDropdowns() {
    final bool showProvinceError =
        _hasValidated && (_fieldErrors['province'] ?? '').isNotEmpty;
    final bool showCityError =
        _hasValidated && (_fieldErrors['city'] ?? '').isNotEmpty;
    final bool showBarangayError =
        _hasValidated && (_fieldErrors['barangay'] ?? '').isNotEmpty;

    TextStyle labelStyle = const TextStyle(
      color: Colors.white70,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Province', style: labelStyle),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _provinces.isNotEmpty && 
                 _provinces.any((p) => p['name'] == _selectedProvinceName)
              ? _selectedProvinceName
              : null,
          dropdownColor: Colors.white,
          decoration: InputDecoration(
            filled: true,
            fillColor: showProvinceError
                ? Colors.redAccent.withOpacity(0.08)
                : Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: showProvinceError ? Colors.redAccent : Colors.grey[400]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: showProvinceError ? Colors.redAccent : Colors.green,
                width: 1.2,
              ),
            ),
          ),
          iconEnabledColor: Colors.grey,
          style: const TextStyle(color: Colors.black87),
          hint: const Text(
            'Select Province',
            style: TextStyle(color: Colors.grey),
          ),
          items: _provinces
              .map(
                (p) => DropdownMenuItem<String>(
                  value: p['name'],
                  child: Text(
                    p['name'] ?? '',
                    style: const TextStyle(color: Colors.black87),
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            setState(() {
              _selectedProvinceName = value;
              _selectedCityName = null;
              _selectedBarangayName = null;
              if (_hasValidated) {
                _fieldErrors['province'] =
                    value == null ? 'Please select your province' : null;
              }
            });
            final match =
                _provinces.firstWhere((p) => p['name'] == value, orElse: () => {});
            if (match.isNotEmpty && match['code'] != null) {
              _selectedProvinceCode = match['code'];
                                  _loadCitiesForProvince();
            }
          },
        ),
        if (showProvinceError)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 6, right: 12),
            child: Text(
              _fieldErrors['province']!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
        const SizedBox(height: 14),
        Text('City / Municipality', style: labelStyle),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _cities.isNotEmpty && 
                 _cities.any((c) => c['name'] == _selectedCityName)
              ? _selectedCityName
              : null,
          dropdownColor: Colors.white,
          decoration: InputDecoration(
            filled: true,
            fillColor: showCityError
                ? Colors.redAccent.withOpacity(0.08)
                : Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: showCityError ? Colors.redAccent : Colors.grey[400]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: showCityError ? Colors.redAccent : Colors.green,
                width: 1.2,
              ),
            ),
          ),
          iconEnabledColor: Colors.grey,
          style: const TextStyle(color: Colors.black87),
          hint: const Text(
            'Select City / Municipality',
            style: TextStyle(color: Colors.grey),
          ),
          items: _cities
              .map(
                (c) => DropdownMenuItem<String>(
                  value: c['name'],
                  child: Text(
                    c['name'] ?? '',
                    style: const TextStyle(color: Colors.black87),
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            setState(() {
              _selectedCityName = value;
              _selectedBarangayName = null;
              if (_hasValidated) {
                _fieldErrors['city'] =
                    value == null ? 'Please select your city/municipality' : null;
              }
            });
            final match =
                _cities.firstWhere((c) => c['name'] == value, orElse: () => {});
            if (match.isNotEmpty && match['code'] != null) {
              _selectedCityCode = match['code'];
              _loadBarangaysForCity(_selectedCityCode!);
            }
          },
        ),
        if (showCityError)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 6, right: 12),
            child: Text(
              _fieldErrors['city']!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
        const SizedBox(height: 14),
        Text('Barangay', style: labelStyle),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _selectedBarangayName,
          dropdownColor: Colors.white,
          decoration: InputDecoration(
            filled: true,
            fillColor: showBarangayError
                ? Colors.redAccent.withOpacity(0.08)
                : Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: showBarangayError ? Colors.redAccent : Colors.grey[400]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: showBarangayError ? Colors.redAccent : Colors.green,
                width: 1.2,
              ),
            ),
          ),
          iconEnabledColor: Colors.grey,
          style: const TextStyle(color: Colors.black87),
          hint: const Text(
            'Select Barangay',
            style: TextStyle(color: Colors.grey),
          ),
          items: _barangays
              .map(
                (b) => DropdownMenuItem<String>(
                  value: b['name'],
                  child: Text(
                    b['name'] ?? '',
                    style: const TextStyle(color: Colors.black87),
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            setState(() {
              _selectedBarangayName = value;
              if (_hasValidated) {
                _fieldErrors['barangay'] =
                    value == null ? 'Please select your barangay' : null;
              }
            });
          },
        ),
        if (showBarangayError)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 6, right: 12),
            child: Text(
              _fieldErrors['barangay']!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: Colors.green,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Edit Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body:
          user == null
              ? const Center(child: Text('Not logged in'))
              : _isLoadingData
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 20),
                          // Profile Picture
                          Center(
                            child: Stack(
                              children: [
                                Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 4,
                                    ),
                                    color: Colors.white,
                                  ),
                                  child:
                                      _isLoadingData
                                          ? const CircularProgressIndicator(
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                          )
                                          : _profileImage != null
                                          ? ClipOval(
                                            child: Image.file(
                                              _profileImage!,
                                              width: 120,
                                              height: 120,
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                          : _profileImageUrl != null &&
                                              _profileImageUrl!.isNotEmpty
                                          ? ClipOval(
                                            child: Image.network(
                                              _profileImageUrl!,
                                              width: 120,
                                              height: 120,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) => const Icon(
                                                    Icons.person,
                                                    size: 70,
                                                    color: Colors.green,
                                                  ),
                                            ),
                                          )
                                          : const Icon(
                                            Icons.person,
                                            size: 70,
                                            color: Colors.green,
                                          ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: GestureDetector(
                                    onTap: _pickProfileImage,
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: Colors.green[700],
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 3,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.2,
                                            ),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.camera_alt,
                                          size: 18,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 30),
                          // Form Fields
                          _buildTextField(
                            label: 'First Name',
                            controller: _firstNameController,
                            fieldKey: 'firstName',
                            prefixIcon: Icons.person,
                            validator: _validateFirstName,
                            keyboardType: TextInputType.name,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            label: 'Last Name',
                            controller: _lastNameController,
                            fieldKey: 'lastName',
                            prefixIcon: Icons.person_outline,
                            validator: _validateLastName,
                            keyboardType: TextInputType.name,
                          ),
                          const SizedBox(height: 16),
                          _buildLocationDropdowns(),
                          const SizedBox(height: 16),
                          _buildTextField(
                            label: 'Street / Purok / House No.',
                            controller: _addressController,
                            fieldKey: 'address',
                            prefixIcon: Icons.home,
                            validator: _validateAddress,
                            keyboardType: TextInputType.streetAddress,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            label: 'Phone Number',
                            controller: _phoneController,
                            fieldKey: 'phone',
                            prefixIcon: Icons.phone,
                            validator: _validatePhone,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(15),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            label: 'Email',
                            controller: _emailController,
                            fieldKey: 'email',
                            prefixIcon: Icons.email,
                            validator: _validateEmail,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 30),
                          // Save Button
                          SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleSave,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child:
                                  _isLoading
                                      ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.green,
                                              ),
                                        ),
                                      )
                                      : const Text(
                                        'Save Changes',
                                        style: TextStyle(
                                          color: Colors.green,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
    );
  }
}
