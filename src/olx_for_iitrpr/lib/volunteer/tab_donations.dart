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

class _VolunteerDonationsPageState extends State<VolunteerDonationsPage> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final Map<String, Uint8List> _loadedImages = {};
  final Set<String> _loadingProductIds = {};
  List<dynamic> donations = [];
  List<dynamic> filteredDonations = [];
  String searchQuery = '';
  bool isLoading = true;
  String errorMessage = '';
  SortOption _currentSort = SortOption.dateDesc;

  @override
  void initState() {
    super.initState();
    fetchDonations();
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
        // Filter out invalid donations
        final validDonations = (data['donations'] as List).where((donation) {
          return donation != null && 
                 donation['_id'] != null &&
                 donation['name'] != null;
        }).toList();

        print('Valid Donations: ${validDonations.length}'); // Debug log
        
        setState(() {
          donations = validDonations;
          filteredDonations = List.from(validDonations);
          _sortDonations();
          errorMessage = '';
        });

        // Load images for valid donations
        for (var donation in validDonations) {
          if (donation['_id'] != null) {
            _loadCachedImage(donation['_id']);
          }
        }
      } else {
        throw Exception(data['error'] ?? 'Failed to load donations');
      }
    } catch (e) {
      print('Error fetching donations: $e'); // Debug log
      setState(() => errorMessage = e.toString());
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _loadCachedImage(String donationId) async {
    try {
      if (_loadedImages.containsKey(donationId) || _loadingProductIds.contains(donationId)) {
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
      if (searchQuery.isEmpty) {
        filteredDonations = List.from(donations);
      } else {
        filteredDonations = donations.where((donation) {
          final name = donation['name']?.toString().toLowerCase() ?? '';
          final description = donation['description']?.toString().toLowerCase() ?? '';
          return name.contains(searchQuery) || description.contains(searchQuery);
        }).toList();
      }
      _sortDonations();
    });
  }

  void _sortDonations() {
    setState(() {
      filteredDonations.sort((a, b) {
        switch (_currentSort) {
          case SortOption.nameAsc:
            return (a['name'] ?? '').toString().toLowerCase().compareTo(
                (b['name'] ?? '').toString().toLowerCase());
          case SortOption.nameDesc:
            return (b['name'] ?? '').toString().toLowerCase().compareTo(
                (a['name'] ?? '').toString().toLowerCase());
          case SortOption.dateDesc:
            return (b['createdAt'] ?? '').toString()
                .compareTo((a['createdAt'] ?? '').toString());
          case SortOption.dateAsc:
            return (a['createdAt'] ?? '').toString()
                .compareTo((b['createdAt'] ?? '').toString());
        }
      });
    });
  }

  void _showSortMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Sort by'),
                subtitle: Text('Choose sorting option'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.sort_by_alpha),
                title: const Text('Name (A to Z)'),
                onTap: () {
                  setState(() {
                    _currentSort = SortOption.nameAsc;
                    _sortDonations();
                  });
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.sort_by_alpha),
                title: const Text('Name (Z to A)'),
                onTap: () {
                  setState(() {
                    _currentSort = SortOption.nameDesc;
                    _sortDonations();
                  });
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('Date (Newest First)'),
                onTap: () {
                  setState(() {
                    _currentSort = SortOption.dateDesc;
                    _sortDonations();
                  });
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('Date (Oldest First)'),
                onTap: () {
                  setState(() {
                    _currentSort = SortOption.dateAsc;
                    _sortDonations();
                  });
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDonationCard(Map<String, dynamic> donation, int index) {
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

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DonationDescriptionScreen(donation: donation),
          ),
        );
      },
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
              child: imageWidget,
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                donation['name'] ?? 'Donation ${index + 1}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: null, // Removed empty header by setting appBar to null
      body: Column(
        children: [
          // Row with search bar and filter button
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                // Search field
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search donations...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onChanged: _filterDonations,
                  ),
                ),
                const SizedBox(width: 8),
                // Sort/filter button
                IconButton(
                  icon: const Icon(Icons.sort),
                  onPressed: () => _showSortMenu(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage.isNotEmpty
                    ? Center(child: Text('Error: $errorMessage'))
                    : filteredDonations.isEmpty
                        ? const Center(child: Text('No donations found'))
                        : RefreshIndicator(
                            onRefresh: fetchDonations,
                            child: ListView.builder(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              itemCount: filteredDonations.length,
                              itemBuilder: (context, index) =>
                                  _buildDonationCard(
                                      filteredDonations[index], index),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}