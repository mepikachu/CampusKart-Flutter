import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../services/product_cache_service.dart';
import 'chat_screen.dart';
import 'server.dart';

class DonationDescriptionScreen extends StatefulWidget {
  final Map<String, dynamic> donation;
  const DonationDescriptionScreen({super.key, required this.donation});

  @override
  State<DonationDescriptionScreen> createState() => _DonationDescriptionScreenState();
}

class _DonationDescriptionScreenState extends State<DonationDescriptionScreen> {
  final CarouselSliderController _carouselController = CarouselSliderController();
  int _currentImageIndex = 0;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  bool isProcessing = false;
  String errorMessage = '';
  List<Uint8List> _loadedImages = [];
  bool _loadingImages = false;
  String currentUserId = '';
  String currentUserName = '';

  @override
  void initState() {
    super.initState();
    _loadImages();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    String? name = await _secureStorage.read(key: 'userName');
    String? id = await _secureStorage.read(key: 'userId');
    if (mounted) {
      setState(() {
        currentUserName = name ?? '';
        currentUserId = id ?? '';
      });
    }
  }

  Future<void> _collectDonation() async {
    try {
      setState(() => isProcessing = true);
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final donationId = widget.donation['_id'];
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
    } finally {
      setState(() => isProcessing = false);
    }
  }

  Future<void> _loadImages() async {
    if (_loadingImages) return;
    setState(() => _loadingImages = true);

    try {
      final donationId = widget.donation['_id'];
      // Try to load from cache first
      final cachedImage = await ProductCacheService.getCachedImage(donationId);
      if (cachedImage != null) {
        setState(() {
          _loadedImages = [cachedImage];
        });
      }

      // Fetch all images
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/donations/$donationId/images'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] && data['images'] != null) {
          final List<Uint8List> images = [];
          for (var image in data['images']) {
            if (image != null && image['data'] != null) {
              final bytes = base64Decode(image['data']);
              images.add(bytes);
            }
          }

          if (mounted) {
            setState(() {
              _loadedImages = images;
            });
          }

          // Cache the first image
          if (images.isNotEmpty) {
            await ProductCacheService.cacheImage(donationId, images[0], images.length);
          }
        }
      }
    } catch (e) {
      print('Error loading images: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingImages = false);
      }
    }
  }

  void _startChat() async {
    if (widget.donation['donatedBy']?['_id'] == null) return;

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final userRole = await _secureStorage.read(key: 'userRole') ?? 'volunteer';

      final conversationResponse = await http.post(
        Uri.parse('$serverUrl/api/conversations'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'participantId': widget.donation['donatedBy']['_id'],
        }),
      );

      if (conversationResponse.statusCode == 200) {
        final conversationData = json.decode(conversationResponse.body);
        final conversationId = conversationData['conversation']['_id'];

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                conversationId: conversationId,
                partnerNames: widget.donation['donatedBy']['userName'],
                partnerId: widget.donation['donatedBy']['_id'],
                initialDonation: null,
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('Error starting chat: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error starting chat. Please try again.')),
      );
    }
  }

  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return 'N/A';
    try {
      final DateTime date = DateTime.parse(dateTime.toString());
      return DateFormat('MMM d, yyyy • h:mm a').format(date);
    } catch (e) {
      return 'N/A';
    }
  }

  List<Widget> _buildImageSlides() {
    if (_loadingImages && _loadedImages.isEmpty) {
      return [
        Container(
          color: Colors.grey[200],
          child: const Center(
            child: CircularProgressIndicator(color: Colors.black),
          ),
        ),
      ];
    }

    if (_loadedImages.isEmpty) {
      return [
        Container(
          color: Colors.grey[300],
          child: const Center(
            child: Icon(Icons.image_not_supported, size: 50, color: Colors.grey),
          ),
        ),
      ];
    }

    return _loadedImages.map<Widget>((imageData) {
      return Container(
        width: double.infinity,
        child: Image.memory(
          imageData,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[300],
              child: const Center(
                child: Icon(Icons.error, size: 50, color: Colors.grey),
              ),
            );
          },
        ),
      );
    }).toList();
  }

  Widget _buildImageCarousel() {
    final List<Widget> slides = _buildImageSlides();
    return slides.isNotEmpty
        ? Stack(
            alignment: Alignment.center,
            children: [
              CarouselSlider(
                carouselController: _carouselController,
                items: slides,
                options: CarouselOptions(
                  viewportFraction: 1.0,
                  height: 300,
                  enableInfiniteScroll: false,
                  onPageChanged: (index, reason) {
                    setState(() {
                      _currentImageIndex = index;
                    });
                  },
                ),
              ),
              if (_currentImageIndex > 0)
                Positioned(
                  left: 10,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: () => _carouselController.previousPage(),
                    ),
                  ),
                ),
              if (_currentImageIndex < slides.length - 1)
                Positioned(
                  right: 10,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: () => _carouselController.nextPage(),
                    ),
                  ),
                ),
              Positioned(
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: slides.asMap().entries.map((entry) {
                      return Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
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
              ),
            ],
          )
        : Container(
            height: 300,
            color: Colors.grey[300],
            child: const Center(child: Text('No Images')),
          );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: Text(
          widget.donation['name'] ?? 'Donation Details',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildImageCarousel(),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                widget.donation['name'] ?? 'Unknown Donation',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                widget.donation['status']?.toUpperCase() ?? "AVAILABLE",
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Donor Details',
                          style: TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: Colors.grey[200],
                                child: Icon(Icons.person, color: Colors.grey[400]),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.donation['donatedBy']?['userName'] ?? 'Anonymous',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.withOpacity(0.1)),
                          ),
                          child: Column(
                            children: [
                              _buildTimeDetail(
                                'Donated on',
                                _formatDateTime(widget.donation['createdAt']),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'About this donation',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.donation['description'] ?? 'No description available',
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
        ],
      ),
      bottomNavigationBar: widget.donation['status'] == 'available'
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _startChat,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Chat with Donor',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isProcessing ? null : _collectDonation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        isProcessing ? 'Processing...' : 'Collect Donation',
                        style: const TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _buildTimeDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}