import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/profile_service.dart';
import '../services/lost_found_cache_service.dart';
import 'lost_item_management.dart';
import 'server.dart';

class MyLostItemsPage extends StatefulWidget {
  const MyLostItemsPage({super.key});

  @override
  State<MyLostItemsPage> createState() => _MyLostItemsPageState();
}

class _MyLostItemsPageState extends State<MyLostItemsPage> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<Map<String, dynamic>> myLostItems = [];
  bool isLoading = true;
  String errorMessage = '';
  
  // For image caching
  final Map<String, Uint8List> _loadedImages = {};
  final Set<String> _loadingItemIds = {};

  @override
  void initState() {
    super.initState();
    _loadMyLostItems();
  }

  Future<void> _loadMyLostItems() async {
    try {
      if (mounted) {
        setState(() => isLoading = true);
      }
      
      // First try to get cached lost item IDs
      final activityIds = ProfileService.activityIds;
      if (activityIds != null && activityIds['lost_items'] != null) {
        // Get cached items
        List<Map<String, dynamic>> cachedItems = [];
        for (String id in activityIds['lost_items']!) {
          final item = await LostFoundCacheService.getCachedItem(id);
          if (item != null) {
            cachedItems.add(item);
          }
        }
        
        if (cachedItems.isNotEmpty && mounted) {
          setState(() {
            myLostItems = cachedItems;
            isLoading = false;
          });
        }
      }
      
      // If no cache or expired, refresh from server
      if (myLostItems.isEmpty || !ProfileService.hasValidActivityCache) {
        await ProfileService.fetchAndUpdateProfile();
        
        // Try loading from cache again
        final freshIds = ProfileService.activityIds;
        if (freshIds != null && freshIds['lost_items'] != null) {
          List<Map<String, dynamic>> freshItems = [];
          for (String id in freshIds['lost_items']!) {
            final item = await LostFoundCacheService.getCachedItem(id);
            if (item != null) {
              freshItems.add(item);
            }
          }
          
          if (mounted) {
            setState(() {
              myLostItems = freshItems;
              isLoading = false;
            });
          }
        }
      }
      
      // Load images for all items
      for (var item in myLostItems) {
        if (item['_id'] != null && !_loadedImages.containsKey(item['_id'])) {
          await _loadCachedImage(item['_id']);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = e.toString();
          isLoading = false;
        });
      }
    } finally {
      if (mounted && isLoading) {
        setState(() => isLoading = false);
      }
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
        await _fetchItemImage(itemId);
      }
    } catch (e) {
      print('Error loading cached image: $e');
    }
  }

  Future<void> _fetchItemImage(String itemId) async {
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
          final image = data['image'];
          final numImages = data['numImages'] ?? 1;
          
          if (image != null && image['data'] != null) {
            final bytes = base64Decode(image['data']);
            
            // Cache the image
            await LostFoundCacheService.cacheImage(itemId, bytes, numImages);
            
            if (mounted) {
              setState(() {
                _loadedImages[itemId] = bytes;
              });
            }
          }
        }
      }
    } catch (e) {
      print('Error fetching lost item image: $e');
    } finally {
      _loadingItemIds.remove(itemId);
    }
  }

  Widget _buildLostItemCard(Map<String, dynamic> item) {
    final status = item['status'] ?? 'lost';
    final datePosted = DateTime.parse(item['createdAt']);
    final formattedDate = "${datePosted.day}/${datePosted.month}/${datePosted.year}";
    
    Widget imageWidget;
    
    if (_loadedImages.containsKey(item['_id'])) {
      // Use cached image
      imageWidget = Image.memory(
        _loadedImages[item['_id']]!,
        fit: BoxFit.cover,
      );
    } else if (_loadingItemIds.contains(item['_id'])) {
      // Show loading indicator
      imageWidget = Container(
        color: Colors.grey[200],
        child: const Center(
          child: CircularProgressIndicator(color: Colors.black),
        ),
      );
    } else {
      // No image available
      imageWidget = Container(
        color: Colors.grey[300],
        child: const Center(
          child: Icon(Icons.image_not_supported, size: 50, color: Colors.grey),
        ),
      );
    }

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LostItemDetailsScreen(
              item: item,
              isOwner: true,
            ),
          ),
        ).then((result) {
          if (result == true) {
            _loadMyLostItems(); // Refresh list if item was updated
          }
        });
      },
      child: Card(
        elevation: 4,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: imageWidget,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['name'] ?? 'Untitled Item',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item['description'] ?? 'No description provided',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Posted on: $formattedDate',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: status == 'found' ? Colors.green[100] : Colors.orange[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: status == 'found' ? Colors.green[900] : Colors.orange[900],
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
      ),
    );
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
          title: const Text('My Lost Items'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: RefreshIndicator(
          color: Colors.black,
          onRefresh: _loadMyLostItems,
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
                            onPressed: () => _loadMyLostItems(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : myLostItems.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No lost items reported',
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
                          itemCount: myLostItems.length,
                          itemBuilder: (context, index) =>
                              _buildLostItemCard(myLostItems[index]),
                        ),
        ),
      ),
    );
  }
}
