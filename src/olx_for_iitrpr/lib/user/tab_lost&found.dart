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
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<dynamic> lostItems = [];
  List<dynamic> filteredItems = [];
  bool isLoading = true;
  String? errorMessage;
  bool _showSearchBar = true;
  String _sortBy = '';
  
  // Image caching
  final Map<String, Uint8List> _loadedImages = {};
  final Set<String> _loadingItemIds = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    fetchLostItems();
  }

  void _onScroll() {
    setState(() {
      _showSearchBar = _scrollController.offset <= 10;
    });
  }

  Future<void> fetchLostItems({bool forceRefresh = false}) async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
      
      // Try to load from cache first if not forcing refresh
      if (!forceRefresh) {
        final cachedItems = await LostFoundCacheService.getCachedItems();
        if (cachedItems != null && cachedItems.isNotEmpty) {
          setState(() {
            lostItems = cachedItems;
            filteredItems = cachedItems;
            isLoading = false;
          });
          
          // Load cached images for all items
          for (var item in lostItems) {
            if (item['_id'] != null) {
              _loadCachedImage(item['_id']);
            }
          }
        }
      }
      
      // Always fetch fresh data in the background (or as primary source if no cache)
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
      // Skip if already loaded or loading
      if (_loadedImages.containsKey(itemId) || _loadingItemIds.contains(itemId)) {
        return;
      }
      
      final cachedImage = await LostFoundCacheService.getCachedImage(itemId);
      if (cachedImage != null && mounted) {
        setState(() {
          _loadedImages[itemId] = cachedImage;
        });
      } else {
        // If not in cache, fetch from network
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
          final items = data['items'] as List;
          
          // Cache the items
          await LostFoundCacheService.cacheItems(items);
          
          if (mounted) {
            setState(() {
              lostItems = items;
              
              // Only update filtered items if no filter is active
              if (_searchController.text.isEmpty) {
                filteredItems = items;
              } else {
                // Re-apply current filters
                _filterItems(_searchController.text);
              }
              
              isLoading = false;
            });
          }
          
          // Fetch images for any items that don't have them
          for (var item in items) {
            if (item['_id'] != null && !_loadedImages.containsKey(item['_id'])) {
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
      if (mounted) {
        setState(() {
          errorMessage = e.toString();
          isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchItemImage(String itemId) async {
    // Skip if already loading or loaded
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
            
            // Cache the image with number of images
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
      print('Error fetching image: $e');
    } finally {
      _loadingItemIds.remove(itemId);
    }
  }

  void _filterItems(String query) {
    if (query.isEmpty) {
      setState(() {
        filteredItems = lostItems;
      });
      return;
    }
    
    final searchTerm = query.toLowerCase();
    setState(() {
      filteredItems = lostItems.where((item) => 
        (item['name']?.toLowerCase().contains(searchTerm) ?? false) ||
        (item['description']?.toLowerCase().contains(searchTerm) ?? false) ||
        (item['lastSeenLocation']?.toLowerCase().contains(searchTerm) ?? false)
      ).toList();
    });
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    final date = DateTime.parse(dateString);
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget buildLostItemCard(dynamic item) {
    final String itemId = item['_id'];
    Widget imageWidget;
    
    if (_loadedImages.containsKey(itemId)) {
      // Use cached image
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
    } else if (_loadingItemIds.contains(itemId)) {
      // Show loading indicator
      imageWidget = Container(
        color: Colors.grey[200],
        height: 200,
        child: const Center(child: CircularProgressIndicator(color: Colors.black)),
      );
    } else {
      // No image and not loading
      imageWidget = Container(
        color: Colors.grey[300],
        height: 200,
        child: const Center(
          child: Icon(Icons.image_not_supported, size: 50, color: Colors.grey),
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
          ).then((_) => fetchLostItems(forceRefresh: false));
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
        body: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: _showSearchBar ? 68 : 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.search, color: Colors.grey[600], size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: 'Search lost items...',
                                  border: InputBorder.none,
                                  hintStyle: TextStyle(color: Colors.grey[500]),
                                ),
                                onChanged: _filterItems,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.transparent,
                      child: PopupMenuButton(
                        icon: const Icon(Icons.filter_list),
                        onSelected: (value) {
                          setState(() {
                            _sortBy = value.toString();
                          });
                          _applySorting();
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'date_desc',
                            child: Text('Newest First'),
                          ),
                          const PopupMenuItem(
                            value: 'date_asc',
                            child: Text('Oldest First'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Lost items list with filtered results
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => fetchLostItems(forceRefresh: true),
                color: Colors.black,
                child: isLoading && filteredItems.isEmpty
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
                              onPressed: () => fetchLostItems(forceRefresh: true),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : filteredItems.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'No lost items found',
                                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: filteredItems.length,
                          itemBuilder: (context, index) => buildLostItemCard(filteredItems[index]),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _applySorting() {
    final sorted = List.from(filteredItems);
    
    switch (_sortBy) {
      case 'date_desc':
        sorted.sort((a, b) => 
          DateTime.parse(b['createdAt']).compareTo(DateTime.parse(a['createdAt'])));
        break;
      case 'date_asc':
        sorted.sort((a, b) => 
          DateTime.parse(a['createdAt']).compareTo(DateTime.parse(b['createdAt'])));
        break;
      default:
        // Default is newest first
        sorted.sort((a, b) => 
          DateTime.parse(b['createdAt']).compareTo(DateTime.parse(a['createdAt'])));
    }
    
    setState(() {
      filteredItems = sorted;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;
}
