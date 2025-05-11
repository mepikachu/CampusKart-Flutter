import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/profile_service.dart';
import '../services/donation_cache_service.dart';
import 'server.dart';

class MyDonationsPage extends StatefulWidget {
  const MyDonationsPage({super.key});

  @override
  State<MyDonationsPage> createState() => _MyDonationsPageState();
}

class _MyDonationsPageState extends State<MyDonationsPage> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<Map<String, dynamic>> donations = [];
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

  Future<void> _loadMyDonations() async {
    try {
      if (mounted) {
        setState(() => isLoading = true);
      }
      
      // First try to get cached donation IDs
      final activityIds = ProfileService.activityIds;
      if (activityIds != null && activityIds['donations'] != null) {
        // Get cached donations
        List<Map<String, dynamic>> cachedDonations = [];
        for (String id in activityIds['donations']!) {
          final donation = await DonationCacheService.getCachedDonation(id);
          if (donation != null) {
            cachedDonations.add(donation);
          }
        }
        
        if (cachedDonations.isNotEmpty && mounted) {
          setState(() {
            donations = cachedDonations;
            isLoading = false;
          });
        }
      }
      
      // If no cache or expired, refresh from server
      if (donations.isEmpty || !ProfileService.hasValidActivityCache) {
        await ProfileService.fetchAndUpdateProfile();
        
        // Try loading from cache again
        final freshIds = ProfileService.activityIds;
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
        if (donation['_id'] != null && !_loadedImages.containsKey(donation['_id'])) {
          await _loadCachedImage(donation['_id']);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = e.toString();
          isLoading = false;
        });
      }
    } finally {
      if (mounted && isLoading) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _loadCachedImage(String donationId) async {
    try {
      final cachedImage = await DonationCacheService.getCachedImage(donationId);
      if (cachedImage != null && mounted) {
        setState(() {
          _loadedImages[donationId] = cachedImage;
        });
      } else {
        await _fetchDonationImage(donationId);
      }
    } catch (e) {
      print('Error loading cached image: $e');
    }
  }

  Future<void> _fetchDonationImage(String donationId) async {
    if (_loadingDonationIds.contains(donationId)) return;
    
    _loadingDonationIds.add(donationId);
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
            
            // Cache the image
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

  Widget _buildDonationCard(Map<String, dynamic> donation) {
    final status = donation['status'] ?? 'available';
    final collectedBy = donation['collectedBy']?['userName'];
    final donationDate = DateTime.parse(
      donation['donationDate'] ?? donation['createdAt'],
    );
    final formattedDate = "${donationDate.day}/${donationDate.month}/${donationDate.year}";
    
    Widget imageWidget;
    
    if (_loadedImages.containsKey(donation['_id'])) {
      // Use cached image
      imageWidget = Image.memory(
        _loadedImages[donation['_id']]!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: 200,
      );
    } else if (_loadingDonationIds.contains(donation['_id'])) {
      // Show loading indicator
      imageWidget = Container(
        color: Colors.grey[200],
        height: 200,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.black),
        ),
      );
    } else {
      // No image available
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
        appBar: AppBar(
          title: const Text('My Donations'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: RefreshIndicator(
          color: Colors.black,
          onRefresh: _loadMyDonations,
          child: isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.black))
              : errorMessage.isNotEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 64, color: Colors.black),
                          const SizedBox(height: 16),
                          Text('Error: $errorMessage'),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _loadMyDonations(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : donations.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.volunteer_activism_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No donations found',
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
                          itemBuilder: (context, index) => _buildDonationCard(
                            donations[index],
                          ),
                        ),
        ),
      ),
    );
  }
}
