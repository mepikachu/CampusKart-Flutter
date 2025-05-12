import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
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
    print('MyDonations - Starting to load donations');
    try {
      if (mounted) {
        setState(() => isLoading = true);
      }

      print('MyDonations - Checking cached donation IDs');
      final activityIds = ProfileService.activityIds;
      if (activityIds != null && activityIds['donations'] != null) {
        print('MyDonations - Found ${activityIds['donations']!.length} cached donation IDs');
        List<Map<String, dynamic>> cachedDonations = [];
        for (var id in activityIds['donations']!) {
          print('MyDonations - Loading cached donation: $id');
          final donationId = id.toString();
          final donation = await DonationCacheService.getCachedDonation(donationId);
          if (donation != null) {
            cachedDonations.add(donation);
            print('MyDonations - Successfully loaded cached donation: $donationId');
          }
        }
        
        if (cachedDonations.isNotEmpty && mounted) {
          print('MyDonations - Setting ${cachedDonations.length} cached donations');
          setState(() {
            donations = cachedDonations;
            isLoading = false;
          });
        }
      }
      
      print('MyDonations - Checking if refresh needed');
      if (donations.isEmpty || !ProfileService.hasValidActivityCache) {
        print('MyDonations - Refreshing from server');
        await ProfileService.fetchAndUpdateProfile();
        
        print('MyDonations - Loading fresh donation IDs');
        final freshIds = ProfileService.activityIds;
        if (freshIds != null && freshIds['donations'] != null) {
          print('MyDonations - Found ${freshIds['donations']!.length} fresh donation IDs');
          List<Map<String, dynamic>> freshDonations = [];
          for (String id in freshIds['donations']!) {
            print('MyDonations - Loading fresh donation: $id');
            final donation = await DonationCacheService.getCachedDonation(id);
            if (donation != null) {
              freshDonations.add(donation);
              print('MyDonations - Successfully loaded fresh donation: $id');
            }
          }
          
          if (mounted) {
            print('MyDonations - Setting ${freshDonations.length} fresh donations');
            setState(() {
              donations = freshDonations;
              isLoading = false;
            });
          }
        }
      }
      
      print('MyDonations - Loading images for donations');
      for (var donation in donations) {
        if (donation['_id'] != null && !_loadedImages.containsKey(donation['_id'])) {
          print('MyDonations - Loading image for donation: ${donation['_id']}');
          await _loadCachedImage(donation['_id']);
        }
      }
    } catch (e) {
      print('MyDonations - Error loading donations: $e');
      if (mounted) {
        setState(() {
          errorMessage = e.toString();
          isLoading = false;
        });
      }
    } finally {
      print('MyDonations - Finished loading donations');
      if (mounted && isLoading) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _loadCachedImage(String donationId) async {
    print('MyDonations - Starting to load cached image for: $donationId');
    try {
      final cachedImage = await DonationCacheService.getCachedImage(donationId);
      if (cachedImage != null && mounted) {
        print('MyDonations - Found cached image for: $donationId');
        setState(() {
          _loadedImages[donationId] = cachedImage;
        });
      } else {
        print('MyDonations - No cached image found, fetching from server: $donationId');
        await _fetchDonationImage(donationId);
      }
    } catch (e) {
      print('MyDonations - Error loading cached image for $donationId: $e');
    }
  }

  Future<void> _fetchDonationImage(String donationId) async {
    print('MyDonations - Starting to fetch image for: $donationId');
    if (_loadingDonationIds.contains(donationId)) {
      print('MyDonations - Already loading image for: $donationId');
      return;
    }
    
    _loadingDonationIds.add(donationId);
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      print('MyDonations - Making API request for image: $donationId');
      final response = await http.get(
        Uri.parse('$serverUrl/api/donations/$donationId/main_image'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      print('MyDonations - Received response for image: $donationId (${response.statusCode})');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] && data['image'] != null) {
          print('MyDonations - Successfully got image data for: $donationId');
          final image = data['image'];
          final numImages = data['numImages'] ?? 1;
          
          if (image != null && image['data'] != null) {
            final bytes = base64Decode(image['data']);
            print('MyDonations - Decoded image data for: $donationId');
            
            await DonationCacheService.cacheImage(donationId, bytes, numImages);
            print('MyDonations - Cached image for: $donationId');
            
            if (mounted) {
              setState(() {
                _loadedImages[donationId] = bytes;
              });
            }
          }
        }
      }
    } catch (e) {
      print('MyDonations - Error fetching image for $donationId: $e');
    } finally {
      _loadingDonationIds.remove(donationId);
      print('MyDonations - Finished fetching image for: $donationId');
    }
  }

  Widget _buildDonationCard(Map<String, dynamic> donation) {
    print('MyDonations - Building card for donation: ${donation['_id']}');
    try {
      final donationId = donation['_id']?.toString();
      print('MyDonations - Donation ID: $donationId');
      if (donationId == null) {
        print('MyDonations - Error: Null donation ID');
        return const SizedBox.shrink();
      }
      
      print('MyDonations - Processing donation date');
      final donationDate = DateTime.parse(
        donation['donationDate']?.toString() ?? 
        donation['createdAt']?.toString() ?? 
        DateTime.now().toIso8601String()
      );
      
      // Fix: Use proper DateFormat pattern that returns numbers, not indices
      final formattedDate = DateFormat('dd/MM/yyyy').format(donationDate);
      print('MyDonations - Formatted date: $formattedDate');
      
      final status = donation['status']?.toString() ?? 'available';
      
      // Fix: Handle collectedBy when it's just a userId string
      final collectedBy = donation['collectedBy'] is Map ? 
                         donation['collectedBy']['userName']?.toString() : 
                         'Someone'; // Use a generic term when we only have userId

      print('MyDonations - Building image widget');
      Widget imageWidget;
      
      if (_loadedImages.containsKey(donation['_id'])) {
        print('MyDonations - Using cached image');
        imageWidget = Image.memory(
          _loadedImages[donation['_id']]!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: 200,
          errorBuilder: (context, error, stackTrace) {
            print('MyDonations - Error building image: $error');
            return Container(
              color: Colors.grey[300],
              height: 200,
              child: const Center(
                child: Icon(Icons.error_outline, size: 50, color: Colors.grey),
              ),
            );
          },
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

      print('MyDonations - Building card widget');
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          donation['name'] ?? 'Untitled Donation',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (status == 'collected')
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Collected by $collectedBy',
                            style: TextStyle(
                              color: Colors.green[900],
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
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
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Posted on: $formattedDate',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      if (status != 'collected')
                        Container(
                          margin: EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Available',
                            style: TextStyle(
                              color: Colors.blue[900],
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
    } catch (e, stackTrace) {
      print('MyDonations - Error building donation card: $e');
      print('MyDonations - Stack trace: $stackTrace');
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ListTile(
          title: Text('Error displaying donation'),
          subtitle: Text('Error: $e'),
        ),
      );
    }
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
          leading: Container(
            margin: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.black),
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
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
