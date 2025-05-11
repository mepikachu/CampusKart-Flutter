import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:typed_data';
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

  @override
  void initState() {
    super.initState();
    _loadCachedImages();
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

  Future<void> _markAsFound() async {
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
          // Update the item in cache with the new status
          final cachedItem = await LostFoundCacheService.getCachedItem(widget.item['_id']);
          if (cachedItem != null) {
            cachedItem['status'] = 'found';
            cachedItem['foundDate'] = DateTime.now().toIso8601String();
            await LostFoundCacheService.cacheItem(widget.item['_id'], cachedItem);
          }
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Item marked as found successfully')),
            );
            Navigator.pop(context, true);
          }
        } else {
          throw Exception(responseData['error'] ?? 'Failed to update item status');
        }
      } else {
        throw Exception('Server returned invalid response');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
        print('Error updating status: ${e.toString()}');
      }
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
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lost Item Details'),
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
                          options: CarouselOptions(
                            height: 300,
                            viewportFraction: 1.0,
                            enableInfiniteScroll: false,
                            autoPlay: images.length > 1,
                            autoPlayInterval: const Duration(seconds: 3),
                            onPageChanged: (index, reason) {
                              setState(() => _currentImageIndex = index);
                            },
                          ),
                          items: images,
                        ),
                        // Image navigation arrows
                        if (images.length > 1) ...[
                          Positioned(
                            left: 10,
                            child: IconButton(
                              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                              onPressed: _currentImageIndex > 0
                                  ? () => setState(() => _currentImageIndex--)
                                  : null,
                            ),
                          ),
                          Positioned(
                            right: 10,
                            child: IconButton(
                              icon: const Icon(Icons.arrow_forward_ios, color: Colors.white),
                              onPressed: _currentImageIndex < images.length - 1
                                  ? () => setState(() => _currentImageIndex++)
                                  : null,
                            ),
                          ),
                        ],
                      ],
                    ),
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
                                widget.item['name'] ?? 'Unknown Item',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: status == 'found'
                                    ? Colors.green.withOpacity(0.1)
                                    : Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                status.toUpperCase(),
                                style: TextStyle(
                                  color: status == 'found'
                                      ? Colors.green[900]
                                      : Colors.orange[900],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Details section
                        const Text(
                          'Item Details',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Card(
                          elevation: 2,
                          child: Column(
                            children: [
                              _buildDetailTile(
                                Icons.person,
                                'Posted By',
                                _getUserName(),
                              ),
                              _buildDetailTile(
                                Icons.calendar_today,
                                'Posted Date',
                                _formatDate(widget.item['createdAt']),
                              ),
                              _buildDetailTile(
                                Icons.location_on,
                                'Last Seen Location',
                                widget.item['lastSeenLocation'] ?? 'Not specified',
                              ),
                              if (widget.item['lostDate'] != null)
                                _buildDetailTile(
                                  Icons.event,
                                  'Lost Date',
                                  _formatDate(widget.item['lostDate']),
                                ),
                              if (status == 'found')
                                _buildDetailTile(
                                  Icons.check_circle,
                                  'Found Date',
                                  _formatDate(widget.item['foundDate']),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Description section
                        const Text(
                          'Description',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Card(
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              widget.item['description'] ?? 'No description available',
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                        if (widget.item['additionalInfo'] != null &&
                            widget.item['additionalInfo'].isNotEmpty) ...[
                          const SizedBox(height: 24),
                          const Text(
                            'Additional Information',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Card(
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                widget.item['additionalInfo'],
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.isOwner && status != 'found')
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _markAsFound,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    disabledBackgroundColor: Colors.grey,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'Mark as Found',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
