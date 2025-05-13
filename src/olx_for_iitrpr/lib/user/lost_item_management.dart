import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:http/http.dart' as http;
import '../services/lost_found_cache_service.dart';
import 'server.dart';

class LostItemDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  final bool isOwner;
  
  const LostItemDetailsScreen({
    super.key,
    required this.item,
    this.isOwner = false,
  });

  @override
  State<LostItemDetailsScreen> createState() => _LostItemDetailsScreenState();
}

class _LostItemDetailsScreenState extends State<LostItemDetailsScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  int _currentImageIndex = 0;
  bool _isLoading = false;
  
  // Image caching fields
  final Map<String, List<Uint8List>> _imageCache = {};
  final Set<String> _loadingItemIds = {};
  bool _isLoadingImages = true;
  int _totalExpectedImages = 1;

  // Add these state variables
  String? errorMessageDisplay;
  String? successMessage;
  Timer? _messageTimer;

  @override
  void initState() {
    super.initState();
    _loadCachedImages();
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCachedImages() async {
    setState(() {
      _isLoadingImages = true;
    });
    
    try {
      // Check if we have cached number of images first
      final numImages = await LostFoundCacheService.getCachedNumImages(widget.item['_id']);
      if (numImages != null) {
        _totalExpectedImages = numImages;
      }
      
      // Try to get cached images
      final cachedImages = await LostFoundCacheService.getCachedAllImages(widget.item['_id']);
      if (cachedImages != null && cachedImages.isNotEmpty) {
        setState(() {
          _imageCache[widget.item['_id']] = cachedImages;
          _isLoadingImages = false;
        });
      } else {
        // If no cached images or we don't have all expected images, fetch them
        await _fetchAllItemImages();
      }
    } catch (e) {
      print('Error loading cached images: $e');
      // Try to fetch fresh images if caching failed
      await _fetchAllItemImages();
    }
  }
  
  Future<void> _fetchAllItemImages() async {
    if (_loadingItemIds.contains(widget.item['_id'])) return;
    
    _loadingItemIds.add(widget.item['_id']);
    setState(() => _isLoadingImages = true);
    
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
          final images = data['images'] as List;
          final List<Uint8List> imagesList = [];
          
          for (var image in images) {
            if (image != null && image['data'] != null) {
              final imageBytes = base64Decode(image['data']);
              imagesList.add(imageBytes);
            }
          }
          
          // Cache the images
          if (imagesList.isNotEmpty) {
            await LostFoundCacheService.cacheAllImages(widget.item['_id'], imagesList);
            await LostFoundCacheService.cacheNumImages(widget.item['_id'], imagesList.length);
            
            if (mounted) {
              setState(() {
                _imageCache[widget.item['_id']] = imagesList;
                _totalExpectedImages = imagesList.length;
                _isLoadingImages = false;
              });
            }
          } else {
            // If no images were found, set loading to false
            setState(() => _isLoadingImages = false);
          }
        }
      }
    } catch (e) {
      print('Error fetching all item images: $e');
      setState(() => _isLoadingImages = false);
    } finally {
      _loadingItemIds.remove(widget.item['_id']);
    }
  }

  // Add helper method for showing messages
  void _showMessage({String? error, String? success}) {
    _messageTimer?.cancel();
    setState(() {
      errorMessageDisplay = error;
      successMessage = success;
    });
    _messageTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          errorMessageDisplay = null;
          successMessage = null;
        });
      }
    });
  }

  Future<bool?> _showConfirmationDialog() async {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle_outline,
                    size: 48,
                    color: Colors.green.shade600,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Mark as Found?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Are you sure you want to mark this item as found? This action cannot be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Confirm',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _markAsFound() async {
    final bool? confirm = await _showConfirmationDialog();
    if (confirm != true) return;

    try {
      setState(() => _isLoading = true);
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) throw Exception('Not authenticated');
      
      final response = await http.patch(
        Uri.parse('$serverUrl/api/lost-items/${widget.item['_id']}/status'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'auth-cookie': authCookie,
        },
        body: json.encode({
          'status': 'found'
        }),
      );
      
      if (response.headers['content-type']?.contains('application/json') == true) {
        final responseData = json.decode(response.body);
        if (response.statusCode == 200 && responseData['success'] == true) {
          final cachedItem = await LostFoundCacheService.getCachedItem(widget.item['_id']);
          if (cachedItem != null) {
            cachedItem['status'] = 'found';
            cachedItem['foundDate'] = DateTime.now().toIso8601String();
            await LostFoundCacheService.cacheItem(widget.item['_id'], cachedItem);
          }
          
          if (mounted) {
            _showMessage(success: 'Item marked as found successfully');
            // Navigate back after a short delay
            Future.delayed(const Duration(seconds: 2), () {
              Navigator.pop(context, true);
            });
          }
        } else {
          throw Exception(responseData['error'] ?? 'Failed to update item status');
        }
      } else {
        throw Exception('Server returned invalid response');
      }
    } catch (e) {
      _showMessage(error: e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Widget> _buildImageSlides() {
    final String itemId = widget.item['_id'];
    if (_imageCache.containsKey(itemId)) {
      final images = _imageCache[itemId]!;
      return images.asMap().entries.map((entry) {
        final index = entry.key;
        final imageBytes = entry.value;
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              imageBytes,
              fit: BoxFit.cover,
              width: double.infinity,
            ),
            // Image counter
            Positioned(
              right: 16,
              top: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${index + 1}/${images.length}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        );
      }).toList();
    }

    // Show loading or placeholder
    return [
      Container(
        width: double.infinity,
        height: 300,
        color: Colors.grey[200],
        child: Center(
          child: _isLoadingImages
              ? const CircularProgressIndicator()
              : const Icon(Icons.image_not_supported, size: 50),
        ),
      ),
    ];
  }

  Widget _buildDetailTile(IconData icon, String title, String value) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey[700]),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(fontSize: 16),
      ),
    );
  }

  String _formatDate(String? date) {
    if (date == null) return 'Unknown';
    final parsedDate = DateTime.parse(date);
    return "${parsedDate.day}/${parsedDate.month}/${parsedDate.year}";
  }

  // Get username safely from user object
  String _getUserName() {
    if (widget.item.containsKey('user')) {
      // If user is a map with userName
      if (widget.item['user'] is Map) {
        return widget.item['user']['userName'] ?? 'Unknown';
      }
      // If user is just a string ID
      return 'User';
    }
    return 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    final images = _buildImageSlides();
    final status = widget.item['status'] ?? 'lost';
    
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
            // Add message boxes at the top
            if (errorMessageDisplay != null)
              Container(
                width: double.infinity,
                color: Colors.red.shade50,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        errorMessageDisplay!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            if (successMessage != null)
              Container(
                width: double.infinity,
                color: Colors.green.shade50,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        successMessage!,
                        style: TextStyle(color: Colors.green.shade700),
                      ),
                    ),
                  ],
                ),
              ),
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
                                  onPressed: () => setState(() => _currentImageIndex--),
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
                                  onPressed: () => setState(() => _currentImageIndex++),
                                ),
                              ),
                            ),
                            
                          // Loading indicator
                          if (_isLoadingImages)
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
                            
                          // Image counter dots
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
                                  widget.item['name'] ?? 'Unknown Item',
                                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                                ),
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: status == 'found' ? Colors.green.shade50 : Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  status.toUpperCase(),
                                  style: TextStyle(
                                    color: status == 'found' ? Colors.green.shade700 : Colors.orange.shade700,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),

                          // Tags Section
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
                                      if (widget.item['category'] != null) 
                                        _buildTag(widget.item['category']),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 24),

                          // Last Seen Location
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
                                  widget.item['lastSeenLocation'] ?? 'Unknown',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[900],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),

                          // Posted Date in blue box
                          Container(
                            width: double.infinity,
                            margin: EdgeInsets.symmetric(vertical: 16),
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Posted on ${_formatDate(widget.item['createdAt'])}',
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
                            widget.item['description'] ?? 'No description available',
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
          ],
        ),
        bottomNavigationBar: status == 'lost' ? Container(
          width: double.infinity,
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
          child: ElevatedButton(
            onPressed: _markAsFound,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Mark as Found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ) : null,
      ),
    );
  }

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
}