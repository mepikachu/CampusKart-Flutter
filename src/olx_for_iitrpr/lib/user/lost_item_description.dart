import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:http/http.dart' as http;
import 'chat_screen.dart';
import '../services/lost_found_cache_service.dart';
import 'server.dart';
import 'view_profile.dart';
import 'package:intl/intl.dart';

class LostItemDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  final Uint8List? initialImage; // Allow passing pre-loaded image
  
  const LostItemDetailsScreen({
    Key? key,
    required this.item,
    this.initialImage,
  }) : super(key: key);

  @override
  State<LostItemDetailsScreen> createState() => _LostItemDetailsScreenState();
}

class _LostItemDetailsScreenState extends State<LostItemDetailsScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  int _currentImageIndex = 0;
  final CarouselSliderController _carouselController = CarouselSliderController();
  
  String currentUserName = '';
  String currentUserId = '';
  bool isLoadingImages = true;
  
  // Store images for display
  List<Uint8List> itemImages = [];
  Map<String, dynamic>? itemDetails;
  int totalNumImages = 1;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    
    // Initialize with data we already have
    setState(() {
      itemDetails = Map<String, dynamic>.from(widget.item);
      
      // If initial image was passed, use it
      if (widget.initialImage != null) {
        itemImages = [widget.initialImage!];
      }
    });
    
    // Check if we have all cached images and how many we expect
    _checkCachedImages();
    
    // Fetch full item details
    _fetchItemDetails();
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

  Future<void> _checkCachedImages() async {
    try {
      // Get the expected number of images
      final numImages = await LostFoundCacheService.getCachedNumImages(widget.item['_id']);
      if (numImages != null) {
        totalNumImages = numImages;
      }
      
      // Get cached images
      final cachedImages = await LostFoundCacheService.getCachedAllImages(widget.item['_id']);
      if (cachedImages != null && cachedImages.isNotEmpty) {
        setState(() {
          itemImages = cachedImages;
          // If we have all expected images, no need to fetch
          if (itemImages.length >= totalNumImages) {
            isLoadingImages = false;
          }
        });
      }
      
      // If we don't have all images, fetch them
      if (itemImages.isEmpty || itemImages.length < totalNumImages) {
        _fetchAllItemImages();
      }
    } catch (e) {
      print('Error checking cached images: $e');
    }
  }

  Future<void> _fetchItemDetails() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/lost-items/${widget.item['_id']}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          // Cache the full item data
          await LostFoundCacheService.cacheItem(widget.item['_id'], data['item']);
          
          if (mounted) {
            setState(() {
              itemDetails = data['item'];
            });
          }
        }
      }
    } catch (e) {
      print('Error fetching item details: $e');
    }
  }

  Future<void> _fetchAllItemImages() async {
    setState(() {
      isLoadingImages = true;
    });
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/lost-items/${widget.item['_id']}/images'),
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
                final String base64Str = image['data'];
                final Uint8List bytes = base64Decode(base64Str);
                loadedImages.add(bytes);
              } catch (e) {
                print('Error processing image: $e');
              }
            }
          }
          
          // Cache all images and update the total count
          if (loadedImages.isNotEmpty) {
            await LostFoundCacheService.cacheAllImages(widget.item['_id'], loadedImages);
            await LostFoundCacheService.cacheNumImages(widget.item['_id'], loadedImages.length);
            
            if (mounted) {
              setState(() {
                itemImages = loadedImages;
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

  void _startChat() async {
    if (widget.item['user']?['_id'] == null) return;
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      // First, get or create the conversation
      final conversationResponse = await http.post(
        Uri.parse('$serverUrl/api/conversations'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'participantId': widget.item['user']['_id'],
        }),
      );
      
      if (conversationResponse.statusCode == 200) {
        final conversationData = json.decode(conversationResponse.body);
        final conversationId = conversationData['conversation']['_id'];
        
        // Navigate to the chat screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              conversationId: conversationId,
              partnerNames: widget.item['user']['userName'],
              partnerId: widget.item['user']['_id'],
              initialProduct: null, // No product data for lost items
            ),
          ),
        );
      }
    } catch (e) {
      print('Error starting chat: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error starting chat. Please try again.')),
      );
    }
  }

  List<Widget> _buildImageSlides() {
    if (itemImages.isEmpty) {
      return [
        Container(
          width: double.infinity,
          height: 300,
          color: Colors.grey[200],
          child: Center(
            child: isLoadingImages
                ? const CircularProgressIndicator()
                : Icon(Icons.image_not_supported, color: Colors.grey[400], size: 50),
          ),
        ),
      ];
    }
    
    return itemImages.map((imageBytes) {
      return Container(
        width: double.infinity,
        child: Image.memory(
          imageBytes,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            print('Error displaying image: $error');
            return Container(
              width: double.infinity,
              color: Colors.grey[200],
              child: const Center(child: Icon(Icons.error)),
            );
          },
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final item = itemDetails ?? widget.item;
    final images = _buildImageSlides();
    
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
        backgroundColor: Colors.white,
        extendBodyBehindAppBar: false, // Prevents AppBar color change
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
          title: Text(
            'Lost Item Details',
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
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (images.isNotEmpty)
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          CarouselSlider(
                            carouselController: _carouselController,
                            items: images,
                            options: CarouselOptions(
                              height: 300,
                              viewportFraction: 1.0,
                              enableInfiniteScroll: images.length > 1,
                              onPageChanged: (index, reason) {
                                setState(() {
                                  _currentImageIndex = index;
                                });
                              },
                            ),
                          ),
                          
                          // Navigation arrows with better styling
                          if (_currentImageIndex > 0)
                            Positioned(
                              left: 16,
                              child: Container(
                                height: 40,
                                width: 40,
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white),
                                  onPressed: () => _carouselController.previousPage(),
                                ),
                              ),
                            ),
                            
                          if (_currentImageIndex < images.length - 1)
                            Positioned(
                              right: 16,
                              child: Container(
                                height: 40,
                                width: 40,
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.white),
                                  onPressed: () => _carouselController.nextPage(),
                                ),
                              ),
                            ),
                            
                          // Loading indicator
                          if (isLoadingImages)
                            Positioned(
                              top: 16,
                              right: 16,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(Colors.white),
                                  ),
                                ),
                              ),
                            ),
                            
                          // Image counter dots with improved style
                          if (images.length > 1)
                            Positioned(
                              bottom: 16,
                              left: 0,
                              right: 0,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: images.asMap().entries.map((entry) {
                                  return Container(
                                    width: 8.0,
                                    height: 8.0,
                                    margin: const EdgeInsets.symmetric(horizontal: 3.0),
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
                      
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Name and Status
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  item['name'] ?? 'Unknown Item',
                                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                                ),
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: item['status'] == 'found' ? Colors.green.shade50 : Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  (item['status'] ?? 'LOST').toUpperCase(),
                                  style: TextStyle(
                                    color: item['status'] == 'found' ? Colors.green.shade700 : Colors.orange.shade700,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),

                          // Tags Section with label on same line
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Tags: ',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[700],
                                ),
                              ),
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      _buildTag('Lost Item'),
                                      _buildTag('Campus'),
                                      if (item['category'] != null) _buildTag(item['category']),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 24),

                          // Founder Details Section
                          Text(
                            'Founder Details',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                          SizedBox(height: 12),

                          // Clickable Founder Box
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ViewProfileScreen(userId: item['user']['_id']),
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
                                      item['user']?['userName']?.substring(0, 1).toUpperCase() ?? '?',
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
                                          item['user']?['userName'] ?? 'Unknown',
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
                          SizedBox(height: 24),

                          // Last Seen Location (on same line)
                          Row(
                            children: [
                              Text(
                                'Last Seen at: ',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[700],
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  item['lastSeenLocation'] ?? 'Unknown',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[900],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),

                          // Posted Date in full-width blue box
                          Container(
                            width: double.infinity,
                            margin: EdgeInsets.symmetric(vertical: 16),
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Posted on ${_formatDateTime(item['createdAt'])}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.blue[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          SizedBox(height: 24),

                          // About This Item
                          Text(
                            'About This Item',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            item['description'] ?? 'No description available',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey[800],
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Chat button with improved styling
            if (item['user'] != null && item['user']['_id'] != currentUserId)
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      offset: const Offset(0, -4),
                      blurRadius: 8,
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
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Chat with Owner',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Helper method for building info rows
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: Colors.grey.shade600,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      final DateTime dateTime = DateTime.parse(date.toString());
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } catch (e) {
      return date.toString();
    }
  }

  // Update the tag builder method
  Widget _buildTag(String text) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Colors.blue[700],
        ),
      ),
    );
  }

  // Add formatDateTime method for date and time
  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return 'N/A';
    try {
      final DateTime date = DateTime.parse(dateTime.toString());
      return '${_formatDate(date)} • ${DateFormat('h:mm a').format(date)}';
    } catch (e) {
      return 'N/A';
    }
  }
}
