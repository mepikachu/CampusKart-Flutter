import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:http/http.dart' as http;
import 'chat_screen.dart';
import '../services/lost_found_cache_service.dart';

class LostItemDetailsScreen extends StatefulWidget {
  final dynamic item;
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
  
  // Fixed: Using CarouselController instead of CarouselSliderController
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
      itemDetails = widget.item;
      
      // If initial image was passed, use it
      if (widget.initialImage != null) {
        itemImages.add(widget.initialImage!);
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
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/lost-items/${widget.item['_id']}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
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
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/lost-items/${widget.item['_id']}/images'),
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
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/conversations'),
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
                ? CircularProgressIndicator()
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
              child: Center(child: Icon(Icons.error)),
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
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lost Item Details'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
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
                        if (_currentImageIndex > 0)
                          Positioned(
                            left: 10,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                                onPressed: () => _carouselController.previousPage(),
                              ),
                            ),
                          ),
                        if (_currentImageIndex < images.length - 1)
                          Positioned(
                            right: 10,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.arrow_forward_ios, color: Colors.white),
                                onPressed: () => _carouselController.nextPage(),
                              ),
                            ),
                          ),
                        if (isLoadingImages)
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                            ),
                          ),
                          
                        // Add page indicator dots
                        if (images.length > 1)
                          Positioned(
                            bottom: 10,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: images.asMap().entries.map((entry) {
                                return Container(
                                  width: 8.0,
                                  height: 8.0,
                                  margin: const EdgeInsets.symmetric(horizontal: 4.0),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _currentImageIndex == entry.key
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.4),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                      ],
                    ),
                  
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['name'] ?? 'Unknown Item',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: item['status'] == 'found'
                                ? Colors.green[100]
                                : Colors.orange[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            item['status']?.toUpperCase() ?? 'LOST',
                            style: TextStyle(
                              color: item['status'] == 'found'
                                  ? Colors.green[700]
                                  : Colors.orange[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Posted by: ${item['user']?['userName'] ?? 'Unknown'}',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                        if (item['location'] != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.location_on, size: 18, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Location: ${item['location']}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (item['lostDate'] != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.calendar_today, size: 18, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Text(
                                'Lost on: ${_formatDate(item['lostDate'])}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        const Text(
                          'Description:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item['description'] ?? 'No description available',
                          style: const TextStyle(fontSize: 16),
                        ),
                        if (item['contactInfo'] != null && item['contactInfo'].isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Contact Information:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item['contactInfo'],
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Only show chat button if item has a user
          if (item['user'] != null)
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _startChat,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Chat with Owner',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
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
}
