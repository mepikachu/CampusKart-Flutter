import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/profile_service.dart';
import '../services/donation_cache_service.dart';
import '../config/api_config.dart';

class MyDonationsPage extends StatefulWidget {
  const MyDonationsPage({super.key});

  @override
  State<MyDonationsPage> createState() => _MyDonationsPageState();
}

class _MyDonationsPageState extends State<MyDonationsPage> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<dynamic> donations = [];
  bool isLoading = true;
  String errorMessage = '';

  // For image caching
  final Map<String, Uint8List> _loadedImages = {};
  final Set<String> _loadingDonationIds = {};

  @override
  void initState() {
    super.initState();
    _loadMyDonations();
  }

  Future<void> _loadCachedImage(String itemId) async {
    final cachedImage = await DonationCacheService.getCachedImage(itemId);
    if (cachedImage != null && mounted) {
      setState(() {
        _loadedImages[itemId] = cachedImage;
      });
    } else {
      _fetchDonationImage(itemId);
    }
  }

  Future<void> _loadMyDonations() async {
    try {
      // First try to get cached donation IDs
      final activityIds = await ProfileService.activityIds;

      if (activityIds != null && activityIds['donations'] != null) {
        // Get cached donations
        List<Map<String, dynamic>> cachedDonations = [];
        for (String id in activityIds['donations']!) {
          final donation = await DonationCacheService.getCachedDonation(id);
          if (donation != null) {
            cachedDonations.add(donation);
          }
        }

        if (cachedDonations.isNotEmpty) {
          setState(() {
            donations = cachedDonations;
            isLoading = false;
          });
        }
      }

      // If no cache or expired, refresh from server
      if (donations.isEmpty || !ProfileService.hasValidActivityCache) {
        await ProfileService.fetchAndCacheUserProfile();

        // Try loading from cache again
        final freshIds = await ProfileService.activityIds;
        if (freshIds != null && freshIds['donations'] != null) {
          List<Map<String, dynamic>> freshDonations = [];
          for (String id in freshIds['donations']!) {
            final donation = await DonationCacheService.getCachedDonation(id);
            if (donation != null) {
              freshDonations.add(donation);
            }
          }

          if (mounted) {
            setState(() {
              donations = freshDonations;
              isLoading = false;
            });
          }
        }
      }

      // Load images for all donations
      for (var donation in donations) {
        if (!_loadedImages.containsKey(donation['_id'])) {
          await _loadCachedImage(donation['_id']);
        }
      }
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> _fetchDonationImage(String donationId) async {
    if (_loadingDonationIds.contains(donationId)) return;
    _loadingDonationIds.add(donationId);

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse(ApiConfig.getDonationImageUrl(donationId)),
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
            await DonationCacheService.cacheImage(donationId, bytes, numImages);

            if (mounted) {
              setState(() {
                _loadedImages[donationId] = bytes;
              });
            }
          }
        }
      }
    } catch (e) {
      print('Error fetching donation image: $e');
    } finally {
      _loadingDonationIds.remove(donationId);
    }
  }

  Widget _buildDonationCard(dynamic donation) {
    final List<dynamic> images = donation['images'] ?? [];
    final status = donation['status'] ?? 'available';
    final collectedBy = donation['collectedBy']?['userName'];
    final donationDate = DateTime.parse(
      donation['donationDate'] ?? donation['createdAt'],
    );
    final formattedDate =
        "${donationDate.day}/${donationDate.month}/${donationDate.year}";

    Widget imageWidget;
    if (_loadedImages.containsKey(donation['_id'])) {
      imageWidget = Image.memory(
        _loadedImages[donation['_id']]!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: 200,
      );
    } else if (images.isNotEmpty && images[0]['data'] != null) {
      try {
        final bytes = base64Decode(images[0]['data']);
        imageWidget = Image.memory(bytes, fit: BoxFit.cover);
      } catch (e) {
        imageWidget = Container(
          color: Colors.grey[300],
          child: const Icon(Icons.image_not_supported, size: 50),
        );
      }
    } else {
      imageWidget = Container(
        color: Colors.grey[300],
        child: const Icon(Icons.image_not_supported, size: 50),
      );
    }

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(12)),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: imageWidget,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  donation['name'] ?? 'Untitled Donation',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  donation['description'] ?? 'No description provided',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Posted on: $formattedDate',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: status == 'collected'
                            ? Colors.green[100]
                            : Colors.blue[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        status == 'collected'
                            ? 'Collected by $collectedBy'
                            : 'Available',
                        style: TextStyle(
                          color: status == 'collected'
                              ? Colors.green[900]
                              : Colors.blue[900],
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Donations'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadMyDonations,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage.isNotEmpty
                ? Center(
                    child: Text(
                      'Error: $errorMessage',
                      style: const TextStyle(color: Colors.red),
                    ),
                  )
                : donations.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.volunteer_activism,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No donations yet',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: donations.length,
                        itemBuilder: (context, index) {
                          // Ensure the donation at this index exists
                          if (index >= 0 && index < donations.length) {
                            return _buildDonationCard(donations[index]);
                          }
                          return const SizedBox(); // Return empty widget if index is invalid
                        },
                      ),
      ),
    );
  }
}