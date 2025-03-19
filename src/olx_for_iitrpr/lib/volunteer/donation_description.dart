import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

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

  Future<void> _collectDonation() async {
    try {
      setState(() => isProcessing = true);
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final donationId = widget.donation['_id'];
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/donations/$donationId/collect'),
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

  List<Widget> _buildImageSlides() {
    final List<dynamic> images = widget.donation['images'] ?? [];
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

  @override
  Widget build(BuildContext context) {
    final List<Widget> slides = _buildImageSlides();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.donation['name'] ?? 'Donation Details'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 80), // Extra padding for bottom bar
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image carousel
            if (slides.isNotEmpty)
              Stack(
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
                  // Pagination dots
                  Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
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
                ],
              )
            else
              Container(
                height: 300,
                color: Colors.grey[300],
                child: const Center(child: Text('No Images')),
              ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                widget.donation['name'] ?? 'Donation',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                widget.donation['description'] ?? 'No description available',
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 16),
            // Additional info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'Status: ${widget.donation['status'] ?? 'Unknown'}',
                    style: TextStyle(
                        fontSize: 16,
                        color: widget.donation['status'] == 'available' ? Colors.green : Colors.blue),
                  ),
                  const Spacer(),
                  Text(
                    'Donated by: ${widget.donation['donatedBy']?['userName'] ?? 'Anonymous'}',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: widget.donation['status'] == 'available'
          ? Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: ElevatedButton(
                onPressed: isProcessing ? null : _collectDonation,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.green,
                ),
                child: Text(
                  isProcessing ? 'Processing...' : 'Collect Donation',
                  style: const TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            )
          : null,
    );
  }
}