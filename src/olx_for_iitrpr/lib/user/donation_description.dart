import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:http/http.dart' as http;
import '../services/donation_cache_service.dart';
import 'server.dart';
import 'view_profile.dart';
import 'package:intl/intl.dart';

class DonationDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> donation;
  final Uint8List? initialImage;

  const DonationDetailsScreen({
    Key? key,
    required this.donation,
    this.initialImage,
  }) : super(key: key);

  @override
  State<DonationDetailsScreen> createState() => _DonationDetailsScreenState();
}

class _DonationDetailsScreenState extends State<DonationDetailsScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  int _currentImageIndex = 0;
  final CarouselSliderController _carouselController = CarouselSliderController();

  bool isLoadingImages = true;
  List<Uint8List> donationImages = [];
  Map<String, dynamic>? donationDetails;
  int totalNumImages = 1;

  @override
  void initState() {
    super.initState();

    setState(() {
      donationDetails = Map<String, dynamic>.from(widget.donation);
      if (widget.initialImage != null) {
        donationImages = [widget.initialImage!];
      }
    });

    _checkCachedImages();
    _fetchDonationDetails();
  }

  Future<void> _checkCachedImages() async {
    try {
      // Get the expected number of images
      final numImages = await DonationCacheService.getCachedNumImages(widget.donation['_id']);
      if (numImages != null) {
        totalNumImages = numImages;
      }

      // Get cached images
      final cachedImages = await DonationCacheService.getCachedAllImages(widget.donation['_id']);
      if (cachedImages != null && cachedImages.isNotEmpty) {
        setState(() {
          donationImages = cachedImages;
          if (donationImages.length >= totalNumImages) {
            isLoadingImages = false;
          }
        });
      }

      // If we don't have all images, fetch them
      if (donationImages.isEmpty || donationImages.length < totalNumImages) {
        _fetchAllDonationImages();
      }
    } catch (e) {
      print('Error checking cached images: $e');
    }
  }

  Future<void> _fetchDonationDetails() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/donations/${widget.donation['_id']}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          await DonationCacheService.cacheDonation(widget.donation['_id'], data['donation']);

          if (mounted) {
            setState(() {
              donationDetails = data['donation'];
            });
          }
        }
      }
    } catch (e) {
      print('Error fetching donation details: $e');
    }
  }

  Future<void> _fetchAllDonationImages() async {
    setState(() {
      isLoadingImages = true;
    });

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/donations/${widget.donation['_id']}/images'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] && data['images'] != null) {
          List<Uint8List> loadedImages = [];
          final images = data['images'];

          for (var image in images) {
            if (image != null && image['data'] != null) {
              try {
                final Uint8List bytes = base64Decode(image['data']);
                loadedImages.add(bytes);
              } catch (e) {
                print('Error processing image: $e');
              }
            }
          }

          if (loadedImages.isNotEmpty) {
            await DonationCacheService.cacheAllImages(widget.donation['_id'], loadedImages);
            await DonationCacheService.cacheNumImages(widget.donation['_id'], loadedImages.length);

            if (mounted) {
              setState(() {
                donationImages = loadedImages;
                totalNumImages = loadedImages.length;
                isLoadingImages = false;
              });
            }
          }
        }
      }
    } catch (e) {
      print('Error fetching all images: $e');
      if (mounted) {
        setState(() {
          isLoadingImages = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final donation = donationDetails ?? widget.donation;
    final images = _buildImageSlides();

    return Theme(
      data: Theme.of(context).copyWith(
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        extendBodyBehindAppBar: false,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
          title: Text(
            'Donation Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
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
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Images Carousel
              _buildImageCarousel(),

              // Main content
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Donation name and status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            donation['name'] ?? 'Unknown Donation',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${donation['status']?.toUpperCase() ?? "AVAILABLE"}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Donor Details Section
                    Text(
                      'Donated By',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Clickable Donor Box
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ViewProfileScreen(userId: donation['donatedBy']['_id']),
                          ),
                        );
                      },
                      child: Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.grey.shade200,
                              child: Text(
                                donation['donatedBy']?['userName']?.substring(0, 1).toUpperCase() ?? '?',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    donation['donatedBy']?['userName'] ?? 'Unknown',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'View Profile',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Timestamps in blue box
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.withOpacity(0.1)),
                      ),
                      child: Column(
                        children: [
                          _buildTimeDetail('Posted on', _formatDateTime(donation['createdAt'])),
                          if (donation['lastUpdatedAt'] != null) ...[
                            const SizedBox(height: 8),
                            _buildTimeDetail('Last updated', _formatDateTime(donation['lastUpdatedAt'])),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Description
                    Text(
                      'About This Donation',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      donation['description'] ?? 'No description available',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: Colors.grey[800],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageCarousel() {
    if (donationImages.isEmpty) {
      return Container(
        height: 200,
        color: Colors.grey[200],
        child: const Center(
          child: Text('No images available'),
        ),
      );
    }

    return Container(
      height: 200,
      child: Stack(
        children: [
          CarouselSlider(
            carouselController: _carouselController,
            options: CarouselOptions(
              height: 200,
              viewportFraction: 1.0,
              enableInfiniteScroll: false,
              onPageChanged: (index, reason) {
                setState(() {
                  _currentImageIndex = index;
                });
              },
            ),
            items: donationImages.map((image) {
              return Builder(
                builder: (BuildContext context) {
                  return Container(
                    margin: EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        image,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: 200,
                      ),
                    ),
                  );
                },
              );
            }).toList(),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_currentImageIndex > 0)
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: () {
                      _carouselController.previousPage();
                    },
                  ),
                if (_currentImageIndex < donationImages.length - 1)
                  IconButton(
                    icon: Icon(Icons.arrow_forward_ios, color: Colors.white),
                    onPressed: () {
                      _carouselController.nextPage();
                    },
                  ),
              ],
            ),
          ),
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: donationImages.asMap().entries.map((entry) {
                return Container(
                  width: 8,
                  height: 8,
                  margin: EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentImageIndex == entry.key
                        ? Colors.white
                        : Colors.white.withOpacity(0.5),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildImageSlides() {
    final List<dynamic> images = donationDetails?['images'] ?? [];
    return images.map<Widget>((image) {
      if (image != null && image['data'] != null) {
        try {
          final bytes = base64Decode(image['data']);
          return Container(
            width: double.infinity,
            child: Image.memory(bytes, fit: BoxFit.cover),
          );
        } catch (e) {
          return const Center(child: Icon(Icons.error));
        }
      }
      return const Center(child: Icon(Icons.image_not_supported));
    }).toList();
  }

  Future<void> _collectDonation() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final donationId = donationDetails!['_id'];
      final response = await http.post(
        Uri.parse('$serverUrl/api/donations/$donationId/collect'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Donation collected successfully')),
        );
        Navigator.pop(context);
      } else {
        throw Exception(data['error'] ?? 'Collection failed');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Widget _buildTimeDetail(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[700],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey[800],
          ),
        ),
      ],
    );
  }

  String _formatDateTime(String dateTimeString) {
    try {
      final dateTime = DateTime.parse(dateTimeString);
      final formatter = DateFormat('yyyy-MM-dd – kk:mm');
      return formatter.format(dateTime);
    } catch (e) {
      return dateTimeString; // Return the original string if parsing fails
    }
  }
}