import 'package:flutter/material.dart';
import '../shared/treatments_repository.dart';
import '../shared/disease_image.dart';

class DiseasesPage extends StatefulWidget {
  const DiseasesPage({Key? key}) : super(key: key);

  @override
  State<DiseasesPage> createState() => _DiseasesPageState();
}

class _DiseasesPageState extends State<DiseasesPage> {
  final TreatmentsRepository _repo = TreatmentsRepository();

  static const List<Map<String, String>> _defaultDiseases = [
    {'id': 'swine_pox', 'name': 'Swine Pox'},
    {'id': 'erysipelas', 'name': 'Erysipelas'},
    {'id': 'greasy_pig_disease', 'name': 'Greasy Pig Disease'},
    {'id': 'ringworm', 'name': 'Ringworm'},
    {'id': 'mange', 'name': 'Mange'},
    {'id': 'foot_and_mouth', 'name': 'Foot and Mouth Disease'},
    {'id': 'sunburn', 'name': 'Sunburn'},
  ];

  // Static disease treatment information
  final Map<String, Map<String, dynamic>> _diseaseInfo = {
    'Swine Pox': {
      'scientificName': 'Swinepox virus',
      'treatments': [
        'No specific antiviral treatment available for swinepox',
        'Provide supportive care with proper nutrition and clean environment',
        'Administer antibiotics only if secondary bacterial infections occur (e.g., penicillin-streptomycin combination)',
        'Isolate affected animals to prevent spread via lice transmission',
        'Apply topical antiseptic solutions to prevent secondary infections',
        'Implement strict lice control measures using appropriate ectoparasiticides',
      ],
    },
    'Erysipelas': {
      'scientificName': 'Erysipelothrix rhusiopathiae',
      'treatments': [
        'Immediate administration of high-dose penicillin G (20,000-40,000 IU/kg intramuscularly twice daily)',
        'Continue antibiotic treatment for 3-5 days even after clinical improvement',
        'Provide anti-inflammatory medication (e.g., flunixin meglumine at 2.2 mg/kg)',
        'Ensure proper hydration with electrolyte solutions',
        'Vaccinate entire herd with erysipelas bacterin for prevention',
        'Isolate affected animals and improve sanitation practices',
      ],
    },
    'Greasy Pig Disease': {
      'scientificName': 'Staphylococcus hyicus (Exudative Epidermitis)',
      'treatments': [
        'Systemic antibiotics: amoxicillin (15 mg/kg IM/PO twice daily) or lincomycin (10 mg/kg IM once daily)',
        'Topical treatment with chlorhexidine or povidone-iodine shampoo baths',
        'Injectable vitamin supplements (especially vitamin E and selenium)',
        'Fluid therapy to combat dehydration in severe cases',
        'Improve environmental hygiene and reduce floor abrasiveness',
        'Consider treating sows before farrowing to reduce bacterial transmission',
      ],
    },
    'Ringworm': {
      'scientificName': 'Trichophyton or Microsporum spp.',
      'treatments': [
        'Topical antifungal treatment with miconazole or clotrimazole cream (apply twice daily for 2-4 weeks)',
        'Lime sulfur dips (2-3%) applied weekly for 4-6 weeks',
        'For severe cases: oral griseofulvin (20 mg/kg daily for 4-6 weeks mixed in feed)',
        'Disinfect all equipment and housing with 1:10 bleach solution',
        'Improve ventilation and reduce humidity in housing areas',
        'Quarantine affected animals to prevent spread to other pigs and humans',
      ],
    },
    'Mange': {
      'scientificName': 'Sarcoptes scabiei var. suis (Parasitic)',
      'treatments': [
        'Injectable ivermectin (300 mcg/kg subcutaneously, repeat after 10-14 days)',
        'Alternative: doramectin (300 mcg/kg IM, single dose or repeat after 10-14 days)',
        'Topical treatment with amitraz solution (weekly applications for 3-4 weeks)',
        'Treat entire herd simultaneously to prevent reinfection',
        'Thoroughly clean and disinfect all housing, equipment, and transport vehicles',
        'Implement regular preventive treatment programs for breeding stock',
      ],
    },
    'Foot and Mouth Disease': {
      'scientificName': 'Foot-and-Mouth Disease Virus (FMDV)',
      'treatments': [
        'No specific antiviral treatment available - supportive care is essential',
        'Provide soft, palatable feed and ensure easy access to water',
        'Administer anti-inflammatory drugs (e.g., flunixin meglumine at 2.2 mg/kg)',
        'Apply topical astringent solutions to lesions (e.g., copper sulfate solution)',
        'Provide antibiotics if secondary bacterial infections develop',
        'Strict biosecurity: immediate quarantine and notification to veterinary authorities as FMD is reportable',
      ],
    },
    'Sunburn': {
      'scientificName': 'Environmental/Solar Dermatitis',
      'treatments': [
        'Move affected pigs to shaded areas or provide artificial shade structures',
        'Apply topical zinc oxide cream or ointment to protect damaged skin',
        'Use aloe vera gel or hydrocortisone cream to reduce inflammation',
        'Provide cool water sprays or wallows to reduce body temperature',
        'Administer pain relief medication if severe (e.g., meloxicam 0.4 mg/kg)',
        'Prevention: apply sunscreen (pet-safe, zinc oxide-based) or provide adequate shade and shelter',
      ],
    },
  };

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  String _diseaseIdFromName(String name) {
    final n = name.toLowerCase().trim();
    if (n == 'swine pox') return 'swine_pox';
    if (n == 'erysipelas') return 'erysipelas';
    if (n == 'greasy pig disease') return 'greasy_pig_disease';
    if (n == 'ringworm') return 'ringworm';
    if (n == 'mange') return 'mange';
    if (n == 'foot and mouth disease') return 'foot_and_mouth';
    if (n == 'sunburn') return 'sunburn';
    return n.replaceAll(' ', '_');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildDiseaseInfoCard(
    String name, {
    List<String>? overrideTreatments,
  }) {
    final info = _diseaseInfo[name];
    final treatments =
        overrideTreatments ?? (info?['treatments'] as List<String>? ?? []);
    final diseaseId = _diseaseIdFromName(name);

    return _DiseaseCard(
      diseaseName: name,
      diseaseId: diseaseId,
      treatments: treatments,
      scientificName: info?['scientificName'] as String?,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // Search bar only
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[50],
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search for Treatments',
                  hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                  prefixIcon: Icon(
                    Icons.search,
                    color: Colors.grey[600],
                    size: 20,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          // Disease list
          Expanded(
            child: StreamBuilder(
              stream: _repo.watchApprovedTreatments(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Failed to load treatments: ${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? const [];
                final approvedByDiseaseId = <String, Map<String, dynamic>>{};
                for (final d in docs) {
                  final data = d.data();
                  final diseaseId = (data['diseaseId'] ?? d.id).toString();
                  approvedByDiseaseId[diseaseId] = data;
                }

                // ALWAYS show the 7 diseases. If approved exists, use it; otherwise fallback to static.
                var items =
                    _defaultDiseases.map((d) {
                        final id = d['id']!;
                        final name = d['name']!;
                        final approved = approvedByDiseaseId[id];
                        final treatments =
                            approved != null
                                ? (approved['treatments'] as List? ?? [])
                                    .map((e) => e.toString())
                                    .toList()
                                : (_diseaseInfo[name]?['treatments']
                                        as List<String>? ??
                                    []);
                        return {
                          'id': id,
                          'name': name,
                          'treatments': treatments,
                          'isApproved': approved != null,
                        };
                      }).toList()
                      ..sort((a, b) {
                        final an = (a['name'] as String).toLowerCase();
                        final bn = (b['name'] as String).toLowerCase();
                        return an.compareTo(bn);
                      });

                if (_searchQuery.isNotEmpty) {
                  items =
                      items
                          .where(
                            (m) => (m['name'] as String).toLowerCase().contains(
                              _searchQuery,
                            ),
                          )
                          .toList();
                }

                if (items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No treatments found',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final name = item['name'] as String;
                    final treatments =
                        (item['treatments'] as List).cast<String>();
                    return _buildDiseaseInfoCard(
                      name,
                      overrideTreatments: treatments,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Professional disease card with expandable details and larger image view
class _DiseaseCard extends StatefulWidget {
  final String diseaseName;
  final String diseaseId;
  final List<String> treatments;
  final String? scientificName;

  const _DiseaseCard({
    required this.diseaseName,
    required this.diseaseId,
    required this.treatments,
    this.scientificName,
  });

  @override
  State<_DiseaseCard> createState() => _DiseaseCardState();
}

class _DiseaseCardState extends State<_DiseaseCard> {
  bool _isExpanded = false;
  static const int _previewCount = 2;

  void _showFullImage() {
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: Stack(
              children: [
                Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.7,
                    maxWidth: MediaQuery.of(context).size.width * 0.9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                widget.diseaseName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.black87,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: DiseaseImage(
                              diseaseId: widget.diseaseId,
                              size: 300,
                              borderRadius: 12,
                            ),
                          ),
                        ),
                      ),
                      if (widget.scientificName != null) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            widget.scientificName!,
                            style: TextStyle(
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewTreatments =
        _isExpanded
            ? widget.treatments
            : widget.treatments.take(_previewCount).toList();
    final hasMore = widget.treatments.length > _previewCount;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with image and name
          InkWell(
            onTap: _showFullImage,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  // Disease image - clickable
                  Hero(
                    tag: 'disease_${widget.diseaseId}',
                    child: Material(
                      color: Colors.transparent,
                      child: DiseaseImage(
                        diseaseId: widget.diseaseId,
                        size: 80,
                        borderRadius: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.diseaseName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        if (widget.scientificName != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.scientificName!,
                            style: TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.medical_services,
                              size: 16,
                              color: Colors.green[700],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.treatments.length} Treatment${widget.treatments.length != 1 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.green[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.zoom_in, color: Colors.green[700], size: 24),
                ],
              ),
            ),
          ),
          // Treatment details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.healing, size: 20, color: Colors.green[700]),
                    const SizedBox(width: 8),
                    const Text(
                      'Treatment Strategies',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...previewTreatments.asMap().entries.map((entry) {
                  final index = entry.key;
                  final treatment = entry.value;
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index < previewTreatments.length - 1 ? 10 : 0,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 6, right: 12),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.green[600],
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            treatment,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                if (hasMore && !_isExpanded) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _isExpanded = true;
                      });
                    },
                    icon: const Icon(Icons.expand_more, size: 20),
                    label: Text(
                      'Show ${widget.treatments.length - _previewCount} more',
                      style: TextStyle(
                        color: Colors.green[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
                if (_isExpanded) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _isExpanded = false;
                      });
                    },
                    icon: const Icon(Icons.expand_less, size: 20),
                    label: const Text(
                      'Show less',
                      style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
