import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/product_cache_service.dart';
import 'donation_description.dart';
import 'server.dart';

enum SortOption {
  nameAsc,
  nameDesc,
  dateAsc,
  dateDesc,
}

class VolunteerDonationsPage extends StatefulWidget {
  const VolunteerDonationsPage({super.key});

  @override
  State<VolunteerDonationsPage> createState() => _VolunteerDonationsPageState();
}

class _VolunteerDonationsPageState extends State<VolunteerDonationsPage>
    with AutomaticKeepAliveClientMixin {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final Map<String, Uint8List> _loadedImages = {};
  final Set<String> _loadingProductIds = {};
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<dynamic> donations = [];
  List<dynamic> filteredDonations = [];
  String searchQuery = '';
  bool isLoading = true;
  String errorMessage = '';
  SortOption _currentSort = SortOption.dateDesc;
  bool _showSearchBar = true;
  String _sortBy = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    fetchDonations();
  }

  void _onScroll() {
    final show = _scrollController.offset <= 10;
    if (show != _showSearchBar) {
      setState(() {
        _showSearchBar = show;
      });
    }
  }

  Future<void> fetchDonations() async {
    try {
      setState(() => isLoading = true);
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/donations?status=available'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final validDonations = (data['donations'] as List).where((donation) {
          return donation != null &&
              donation['_id'] != null &&
              donation['name'] != null;
        }).toList();

        setState(() {
          donations = validDonations;
          filteredDonations = List.from(validDonations);
          _filterAndSortDonations();
          errorMessage = '';
        });

        for (var donation in validDonations) {
          if (donation['_id'] != null) {
            _loadCachedImage(donation['_id']);
          }
        }
      } else {
        throw Exception(data['error'] ?? 'Failed to load donations');
      }
    } catch (e) {
      setState(() => errorMessage = e.toString());
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _loadCachedImage(String donationId) async {
    try {
      if (_loadedImages.containsKey(donationId) ||
          _loadingProductIds.contains(donationId)) {
        return;
      }

      final cachedImage = await ProductCacheService.getCachedImage(donationId);
      if (cachedImage != null && mounted) {
        setState(() {
          _loadedImages[donationId] = cachedImage;
        });
      } else {
        _fetchProductImage(donationId);
      }
    } catch (e) {
      print('Error loading cached image: $e');
    }
  }

  Future<void> _fetchProductImage(String donationId) async {
    if (_loadingProductIds.contains(donationId)) return;
    _loadingProductIds.add(donationId);

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/donations/$donationId/main_image'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] && data['image'] != null) {
          final image = data['image'];
          final numImages = data['numImages'] ?? 1;

          if (image != null && image['data'] != null) {
            final bytes = base64Decode(image['data']);
            await ProductCacheService.cacheImage(donationId, bytes, numImages);

            if (mounted) {
              setState(() {
                _loadedImages[donationId] = bytes;
              });
            }
          }
        }
      }
    } catch (e) {
      print('Error fetching image: $e');
    } finally {
      _loadingProductIds.remove(donationId);
    }
  }

  void _filterDonations(String query) {
    setState(() {
      searchQuery = query.toLowerCase();
      _filterAndSortDonations();
    });
  }

  void _filterAndSortDonations() {
    var filtered = List.from(donations);

    if (_searchController.text.isNotEmpty) {
      final searchTerm = _searchController.text.toLowerCase();
      filtered = filtered.where((donation) =>
          (donation['name']?.toLowerCase().contains(searchTerm) ?? false) ||
          (donation['description']?.toLowerCase().contains(searchTerm) ?? false)).toList();
    }

    switch (_sortBy) {
      case 'name_asc':
        filtered.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
        break;
      case 'name_desc':
        filtered.sort((a, b) => (b['name'] ?? '').compareTo(a['name'] ?? ''));
        break;
      case 'date_desc':
        filtered.sort((a, b) => DateTime.parse(b['createdAt'])
            .compareTo(DateTime.parse(a['createdAt'])));
        break;
      case 'date_asc':
        filtered.sort((a, b) => DateTime.parse(a['createdAt'])
            .compareTo(DateTime.parse(b['createdAt'])));
        break;
    }

    setState(() {
      filteredDonations = filtered;
    });
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return 'Unknown';
    }
  }

  Widget _buildDonationCard(Map<String, dynamic> donation) {
    final String donationId = donation['_id'] ?? '';
    if (donationId.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget imageWidget;
    if (_loadedImages.containsKey(donationId)) {
      imageWidget = Image.memory(
        _loadedImages[donationId]!,
        fit: BoxFit.cover,
        height: 200,
        width: double.infinity,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey[300],
            height: 200,
            child: const Center(
              child: Icon(Icons.image_not_supported, size: 50, color: Colors.grey),
            ),
          );
        },
      );
    } else if (_loadingProductIds.contains(donationId)) {
      imageWidget = Container(
        color: Colors.grey[200],
        height: 200,
        child: const Center(child: CircularProgressIndicator(color: Colors.black)),
      );
    } else {
      imageWidget = Container(
        color: Colors.grey[300],
        height: 200,
        child: const Center(
          child: Icon(Icons.image_not_supported, size: 50, color: Colors.grey),
        ),
      );
    }

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DonationDescriptionScreen(
                donation: donation,
              ),
            ),
          ).then((_) => fetchDonations());
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: imageWidget,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (donation['name'] ?? 'Unnamed Donation').toUpperCase(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    donation['description'] ?? 'No description',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Donated by ${donation['donatedBy']?['userName'] ?? 'Unknown'}',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _formatDate(donation['createdAt']),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
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
    super.build(context);
    return Theme(
      data: ThemeData(
        primaryColor: Colors.black,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.light(
          primary: Colors.black,
          secondary: const Color(0xFF4CAF50),
          background: Colors.white,
          surface: Colors.white,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: _showSearchBar ? 68 : 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.search, color: Colors.grey[600], size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: 'Search donations...',
                                  border: InputBorder.none,
                                  hintStyle: TextStyle(color: Colors.grey[500]),
                                ),
                                onChanged: _filterDonations,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.transparent,
                      child: PopupMenuButton(
                        icon: const Icon(Icons.filter_list),
                        onSelected: (String value) {
                          setState(() {
                            _sortBy = value;
                            _filterAndSortDonations();
                          });
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'date_desc',
                            child: Text('Newest First'),
                          ),
                          const PopupMenuItem(
                            value: 'date_asc',
                            child: Text('Oldest First'),
                          ),
                          const PopupMenuItem(
                            value: 'name_asc',
                            child: Text('Name: A to Z'),
                          ),
                          const PopupMenuItem(
                            value: 'name_desc',
                            child: Text('Name: Z to A'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: fetchDonations,
                color: Colors.black,
                child: isLoading && filteredDonations.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.black))
                    : errorMessage.isNotEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline,
                                    size: 64, color: Colors.black),
                                const SizedBox(height: 16),
                                Text('Error: $errorMessage'),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: fetchDonations,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        : filteredDonations.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.search_off,
                                        size: 64, color: Colors.grey[400]),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No donations found',
                                      style: TextStyle(
                                          fontSize: 18,
                                          color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                controller: _scrollController,
                                physics: const BouncingScrollPhysics(
                                    parent: AlwaysScrollableScrollPhysics()),
                                itemCount: filteredDonations.length,
                                itemBuilder: (context, index) =>
                                    _buildDonationCard(
                                        filteredDonations[index]),
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}