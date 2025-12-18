import 'package:flutter/material.dart';
import '../shared/review_manager.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'user_request_list.dart';

class UserRequestTabbedList extends StatefulWidget {
  final int initialTabIndex;
  const UserRequestTabbedList({Key? key, this.initialTabIndex = 0})
    : super(key: key);

  @override
  State<UserRequestTabbedList> createState() => _UserRequestTabbedListState();
}

class _UserRequestTabbedListState extends State<UserRequestTabbedList>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final ReviewManager _reviewManager = ReviewManager();
  final FocusNode _searchFocusNode = FocusNode();
  Stream<QuerySnapshot>? _requestsStream;

  // Add missing _buildSearchBar method
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText: tr('search'),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              suffixIcon:
                  _searchQuery.isNotEmpty
                      ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      )
                      : null,
              filled: true,
              fillColor: Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.search,
            enableSuggestions: false,
            autocorrect: false,
            onChanged: (value) {
              _searchQuery = value;
              // Avoid rebuilding the StreamBuilder while typing; only refresh inner lists
              if (mounted) setState(() {});
              // Keep focus
              if (!_searchFocusNode.hasFocus) {
                _searchFocusNode.requestFocus();
              }
            },
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              tr('try_searching_for'),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _requestsStream =
          FirebaseFirestore.instance
              .collection('scan_requests')
              .where('userId', isEqualTo: user.uid)
              .snapshots();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filterRequests(
    List<Map<String, dynamic>> requests,
  ) {
    if (_searchQuery.isEmpty) return requests;

    return requests.where((request) {
      // Safely get disease name with null and empty checks
      String diseaseName = '';
      try {
        final diseaseSummary = request['diseaseSummary'];
        if (diseaseSummary != null && 
            diseaseSummary is List && 
            diseaseSummary.isNotEmpty &&
            diseaseSummary[0] != null) {
          diseaseName = diseaseSummary[0]['name']?.toString().toLowerCase() ?? '';
        }
      } catch (e) {
        // Silently handle any errors in accessing disease summary
        diseaseName = '';
      }
      
      final status = request['status']?.toString().toLowerCase() ?? '';
      final submittedAt =
          request['submittedAt']?.toString().toLowerCase() ?? '';
      final query = _searchQuery.toLowerCase();

      return diseaseName.contains(query) ||
          status.contains(query) ||
          submittedAt.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Not logged in'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _requestsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _buildWithOfflineFallback();
        }

        final docs = snapshot.data?.docs ?? [];
        final allRequests =
            docs.map((d) {
              final data = d.data() as Map<String, dynamic>;
              // Attach Firestore document ID for actions like delete
              return {...data, '_docId': d.id};
            }).toList();

        // Cache requests for offline fallback
        _cacheRequestsToHive(allRequests);
        if (allRequests.isEmpty) {
          return Column(
            children: [
              _buildSearchBar(),
              Container(
                color: Colors.green,
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.white,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  tabs: [
                    Tab(text: '${tr('pending')} (0)'),
                    Tab(text: '${tr('completed')} (0)'),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.description_outlined,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No requests yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start scanning to see your requests here',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        final pending = _filterRequests(
          allRequests.where((r) => r['status'] == 'pending').toList(),
        );
        final completed = _filterRequests(
          allRequests.where((r) => r['status'] == 'completed').toList(),
        );
        return Column(
          children: [
            // Keep search bar outside of TabBarView rebuilds to avoid losing focus
            _buildSearchBar(),
            Container(
              color: Colors.green,
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: [
                  Tab(text: '${tr('pending')} (${pending.length})'),
                  Tab(text: '${tr('completed')} (${completed.length})'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  pending.isEmpty
                      ? _buildEmptyState(
                        _searchQuery.isNotEmpty
                            ? 'No pending requests found for "$_searchQuery"'
                            : 'No pending requests',
                      )
                      : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: UserRequestList(requests: pending),
                      ),
                  completed.isEmpty
                      ? _buildEmptyState(
                        _searchQuery.isNotEmpty
                            ? 'No completed requests found for "$_searchQuery"'
                            : 'No completed requests',
                      )
                      : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: UserRequestList(requests: completed),
                      ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // Cache requests to Hive for offline access
  Future<void> _cacheRequestsToHive(List<Map<String, dynamic>> requests) async {
    try {
      final box = await Hive.openBox('userRequestsBox');
      await box.put('cachedRequests', requests);
      await box.put('lastUpdated', DateTime.now().toIso8601String());
    } catch (e) {
      print('Error caching requests to Hive: $e');
    }
  }

  // Load requests with fallback to cached data
  Future<List<Map<String, dynamic>>> _loadRequestsWithFallback(
    String userId,
  ) async {
    try {
      // Try to load from Firestore first
      final query =
          await FirebaseFirestore.instance
              .collection('scan_requests')
              .where('userId', isEqualTo: userId)
              .get();

      final allRequests =
          query.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            // Attach Firestore document ID for actions like delete
            return {...data, '_docId': doc.id};
          }).toList();

      // Cache requests to Hive for offline access
      await _cacheRequestsToHive(allRequests);

      return allRequests;
    } catch (e) {
      print('Error loading from Firestore: $e');
      // Fallback to local Hive data
      return await _loadCachedRequests();
    }
  }

  // Load cached requests from Hive for offline access
  Future<List<Map<String, dynamic>>> _loadCachedRequests() async {
    try {
      final box = await Hive.openBox('userRequestsBox');
      final cachedRequests = box.get('cachedRequests', defaultValue: []);
      if (cachedRequests is List) {
        return cachedRequests
            .whereType<Map>()
            .map<Map<String, dynamic>>(
              (e) => Map<String, dynamic>.from(e as Map),
            )
            .toList();
      }
    } catch (e) {
      print('Error loading cached requests: $e');
    }
    return [];
  }

  // Build widget with offline fallback
  Widget _buildWithOfflineFallback() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Not logged in'));
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadCachedRequests(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final cachedRequests = snapshot.data!;
        final pending = _filterRequests(
          cachedRequests.where((r) => r['status'] == 'pending').toList(),
        );
        final completed = _filterRequests(
          cachedRequests.where((r) => r['status'] == 'completed').toList(),
        );

        return Column(
          children: [
            // Offline indicator banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.orange.withOpacity(0.1),
              child: Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.orange, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Offline mode - Showing cached data',
                    style: TextStyle(
                      color: Colors.orange[700],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            _buildSearchBar(),
            // Quick Overview Section
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Overview',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildOverviewCard(
                          'Pending',
                          pending.length.toString(),
                          Colors.orange,
                          Icons.pending,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildOverviewCard(
                          'Completed',
                          completed.length.toString(),
                          Colors.green,
                          Icons.check_circle,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              color: Colors.green,
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: [Tab(text: tr('pending')), Tab(text: tr('completed'))],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  pending.isEmpty
                      ? _buildEmptyState(
                        _searchQuery.isNotEmpty
                            ? 'No pending requests found for "$_searchQuery"'
                            : 'No pending requests',
                      )
                      : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: UserRequestList(requests: pending),
                      ),
                  completed.isEmpty
                      ? _buildEmptyState(
                        _searchQuery.isNotEmpty
                            ? 'No completed requests found for "$_searchQuery"'
                            : 'No completed requests',
                      )
                      : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: UserRequestList(requests: completed),
                      ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _searchQuery.isNotEmpty ? Icons.search_off : Icons.inbox,
              size: 64,
              color: Colors.green[200],
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(fontSize: 18, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard(
    String title,
    String count,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            count,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
