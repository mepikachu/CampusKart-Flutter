import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'lost_item_description.dart';
import '../services/lost_found_cache_service.dart';
import 'server.dart';

class LostFoundTab extends StatefulWidget {
  const LostFoundTab({super.key});

  @override
  State<LostFoundTab> createState() => _LostFoundTabState();
}

class _LostFoundTabState extends State<LostFoundTab> with AutomaticKeepAliveClientMixin {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<dynamic> lostItems = [];
  bool isLoading = true;
  String? errorMessage;
  
  // For image caching
  final Map<String, Uint8List> _loadedImages = {};
  final Set<String> _loadingItemIds = {};

  @override
  void initState() {
    super.initState();
    fetchLostItems();
  }

  Future<void> fetchLostItems() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
      
      // Check cached items first
      final cachedItems = await LostFoundCacheService.getCachedItems();
      if (cachedItems != null && cachedItems.isNotEmpty) {
        setState(() {
          lostItems = cachedItems;
          isLoading = false;
        });
        
        // Load cached images
        for (var item in lostItems) {
          _loadCachedImage(item['_id']);
        }
        
        // Still fetch fresh data in background
        _fetchFreshLostItems();
        return;
      }
      
      await _fetchFreshLostItems();
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }
  
  Future<void> _loadCachedImage(String itemId) async {
    try {
      final cachedImage = await LostFoundCacheService.getCachedImage(itemId);
      if (cachedImage != null && mounted) {
        setState(() {
          _loadedImages[itemId] = cachedImage;
        });
      } else {
        // If no cached image, try to fetch it
        _fetchItemImage(itemId);
      }
    } catch (e) {
      print('Error loading cached image: $e');
    }
  }

  Future<void> _fetchFreshLostItems() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      final response = await http.get(
        Uri.parse('$serverUrl/api/lost-items'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success']) {
          // Modify the filter to only exclude 'found' items
          final filteredItems = (data['items'] as List).where((item) =>
            item['status'] != 'found'
          ).toList();
          
          // Cache the items
          await LostFoundCacheService.cacheItems(filteredItems);
          
          if (mounted) {
            setState(() {
              lostItems = filteredItems;
              isLoading = false;
            });
          }
          
          // Fetch images for each item
          for (var item in lostItems) {
            if (!_loadedImages.containsKey(item['_id'])) {
              _fetchItemImage(item['_id']);
            }
          }
        }
      } else if (response.statusCode == 401) {
        await _secureStorage.delete(key: 'authCookie');
        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            '/login',
            arguments: {'errorMessage': 'Authentication failed. Please login again.'}
          );
        }
      } else {
        throw Exception('Failed to load lost items');
      }
    } catch (e) {
      print('Error fetching fresh items: $e');
      if (mounted) {
        setState(() {
          errorMessage = e.toString();
          isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchItemImage(String itemId) async {
    // Skip if already loading
    if (_loadingItemIds.contains(itemId)) return;
    _loadingItemIds.add(itemId);
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/lost-items/$itemId/main_image'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] && data['image'] != null) {
          // main_image endpoint returns a single image directly (not as a list)
          final image = data['image'];
          final numImages = data['numImages'] ?? 1;
          
          if (image != null && image['data'] != null) {
            final String base64Str = image['data'];
            final Uint8List bytes = base64Decode(base64Str);
            
            // Cache the image and number of images
            await LostFoundCacheService.cacheImage(itemId, bytes, numImages);
            
            if (mounted) {
              setState(() {
                _loadedImages[itemId] = bytes;
                _loadingItemIds.remove(itemId);
              });
            }
          }
        }
      }
    } catch (e) {
      print('Error fetching image: $e');
      if (mounted) {
        setState(() {
          _loadingItemIds.remove(itemId);
        });
      }
    }
  }

  Widget buildLostItemCard(dynamic item) {
    final String itemId = item['_id'];
    Widget imageWidget;

    // Display image if loaded
    if (_loadedImages.containsKey(itemId)) {
      imageWidget = Image.memory(
        _loadedImages[itemId]!,
        fit: BoxFit.cover,
        height: 200,
        width: double.infinity,
        errorBuilder: (context, error, stackTrace) {
          print('Error displaying image: $error');
          return Container(
            color: Colors.grey[300],
            height: 200,
            child: const Center(child: Icon(Icons.image_not_supported, size: 50, color: Colors.grey)),
          );
        },
      );
    } else {
      // Show loading indicator
      imageWidget = Container(
        color: Colors.grey[300],
        height: 200,
        child: Center(
          child: _loadingItemIds.contains(itemId)
              ? const CircularProgressIndicator()
              : const Icon(Icons.image_not_supported, size: 50, color: Colors.grey),
        ),
      );
    }

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LostItemDetailsScreen(
                item: item,
                initialImage: _loadedImages[itemId],
              ),
            ),
          ).then((_) => fetchLostItems());
        },
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
                    children: [
                      Expanded(
                        child: Text(
                          item['name'] ?? 'Unnamed Item',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: item['status'] == 'found' ? Colors.green[100] : Colors.orange[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          item['status']?.toUpperCase() ?? 'LOST',
                          style: TextStyle(
                            color: item['status'] == 'found' ? Colors.green[700] : Colors.orange[700],
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item['description'] ?? 'No description',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Posted by ${item['user']?['userName'] ?? 'Unknown'}',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _formatDate(item['createdAt']),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
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
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    final date = DateTime.parse(dateString);
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
        body: isLoading && lostItems.isEmpty
            ? const Center(child: CircularProgressIndicator(color: Colors.black))
            : errorMessage != null
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
                          onPressed: fetchLostItems,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    color: Colors.black,
                    onRefresh: fetchLostItems,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: lostItems.length,
                      itemBuilder: (context, index) => buildLostItemCard(lostItems[index]),
                    ),
                  ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
