import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import '../services/donation_cache_service.dart';
import 'donation_description.dart';
import 'server.dart';

class MyDonationCollections extends StatefulWidget {
  const MyDonationCollections({super.key});

  @override
  State<MyDonationCollections> createState() => _MyDonationCollectionsState();
}

class _MyDonationCollectionsState extends State<MyDonationCollections> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<dynamic> donations = [];
  bool isLoading = true;
  String errorMessage = '';
  final Map<String, Uint8List> _loadedImages = {};
  final Set<String> _loadingDonationIds = {};

  @override
  void initState() {
    super.initState();
    _loadDonations();
  }

  Future<void> _loadDonations() async {
    setState(() => isLoading = true);
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) throw Exception('Not authenticated');

      final response = await http.get(
        Uri.parse('$serverUrl/api/donations/volunteer/donations'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      );

      final responseBody = json.decode(response.body);
      if (response.statusCode == 200 && responseBody['success'] == true) {
        final donationsList = responseBody['donations'] as List<dynamic>;
        setState(() {
          donations = donationsList;
        });

        // Load images for all donations
        for (var donation in donations) {
          if (donation['_id'] != null) {
            await _loadDonationImage(donation['_id']);
          }
        }
      } else {
        throw Exception(responseBody['error'] ?? 'Failed to fetch donations');
      }
    } catch (e) {
      setState(() => errorMessage = e.toString());
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _loadDonationImage(String donationId) async {
    if (_loadingDonationIds.contains(donationId)) return;

    try {
      // Check cache first
      final cachedImage = await DonationCacheService.getCachedImage(donationId);
      if (cachedImage != null) {
        setState(() {
          _loadedImages[donationId] = cachedImage;
        });
        return;
      }

      _loadingDonationIds.add(donationId);
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
          final imageData = base64Decode(data['image']['data']);
          await DonationCacheService.cacheImage(donationId, imageData, 1);

          if (mounted) {
            setState(() {
              _loadedImages[donationId] = imageData;
            });
          }
        }
      }
    } catch (e) {
      print('Error loading donation image: $e');
    } finally {
      _loadingDonationIds.remove(donationId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          scrolledUnderElevation: 0, // Prevents color change on scroll
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.grey[50], // Light grey background to make white cards pop
        appBar: AppBar(
          title: const Text('My Donation Collections'),
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
          onRefresh: _loadDonations,
          child: isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.black))
              : errorMessage.isNotEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(errorMessage, style: TextStyle(color: Colors.grey[600])),
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
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: donations.length,
                          padding: const EdgeInsets.all(16),
                          itemBuilder: (context, index) {
                            final donation = donations[index];
                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DonationDetailsScreen(
                                      donation: donation,
                                      initialImage: _loadedImages[donation['_id']],
                                    ),
                                  ),
                                );
                              },
                              child: Card(
                                elevation: 2,
                                margin: const EdgeInsets.only(bottom: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                color: Colors.white, // Pure white background
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Image
                                    ClipRRect(
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(12),
                                      ),
                                      child: AspectRatio(
                                        aspectRatio: 16 / 9,
                                        child: _loadedImages.containsKey(donation['_id'])
                                            ? Image.memory(
                                                _loadedImages[donation['_id']]!,
                                                fit: BoxFit.cover,
                                              )
                                            : Container(
                                                color: Colors.grey[200],
                                                child: Icon(
                                                  Icons.image,
                                                  size: 48,
                                                  color: Colors.grey[400],
                                                ),
                                              ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Name and Status
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  donation['name'] ?? 'Unnamed Donation',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              // Replace status with collection date
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  _formatDate(donation['donationDate']),
                                                  style: TextStyle(
                                                    color: Colors.green[700],
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          // Description
                                          Text(
                                            donation['description'] ?? 'No description',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          // Donor and Date
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'Donated by: ${donation['donatedBy']?['userName'] ?? 'Unknown'}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              Text(
                                                'Created: ${_formatDate(donation['createdAt'])}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
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
                          },
                        ),
        ),
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMM d, yyyy').format(date);
    } catch (_) {
      return 'N/A';
    }
  }
}
