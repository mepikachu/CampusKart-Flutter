import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/profile_service.dart';
import '../services/product_cache_service.dart';
import 'product_management.dart';
import 'server.dart';

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<Map<String, dynamic>> myListings = [];
  bool isLoading = true;
  String errorMessage = '';
  
  // For image caching
  final Map<String, Uint8List> _loadedImages = {};
  final Set<String> _loadingProductIds = {};

  @override
  void initState() {
    super.initState();
    _loadMyListings();
  }

  Future<void> _loadMyListings() async {
    try {
      if (mounted) {
        setState(() => isLoading = true);
      }
      
      // First try to get cached product IDs
      final activityIds = ProfileService.activityIds;
      if (activityIds != null && activityIds['products'] != null) {
        // Get cached products
        List<Map<String, dynamic>> cachedProducts = [];
        for (String id in activityIds['products']!) {
          final product = await ProductCacheService.getCachedProduct(id);
          if (product != null) {
            cachedProducts.add(product);
          }
        }
        
        if (cachedProducts.isNotEmpty && mounted) {
          setState(() {
            myListings = cachedProducts;
            isLoading = false;
          });
        }
      }
      
      // If no cache or expired, refresh from server
      if (myListings.isEmpty || !ProfileService.hasValidActivityCache) {
        await ProfileService.fetchAndUpdateProfile();
        
        // Try loading from cache again
        final freshIds = ProfileService.activityIds;
        if (freshIds != null && freshIds['products'] != null) {
          List<Map<String, dynamic>> freshProducts = [];
          for (String id in freshIds['products']!) {
            final product = await ProductCacheService.getCachedProduct(id);
            if (product != null) {
              freshProducts.add(product);
            }
          }
          
          if (mounted) {
            setState(() {
              myListings = freshProducts;
              isLoading = false;
            });
          }
        }
      }
      
      // Load images for all products
      for (var product in myListings) {
        if (product['_id'] != null && !_loadedImages.containsKey(product['_id'])) {
          await _loadCachedImage(product['_id']);
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

  Future<void> _loadCachedImage(String productId) async {
    try {
      final cachedImage = await ProductCacheService.getCachedImage(productId);
      if (cachedImage != null && mounted) {
        setState(() {
          _loadedImages[productId] = cachedImage;
        });
      } else {
        await _fetchProductImage(productId);
      }
    } catch (e) {
      print('Error loading cached image: $e');
    }
  }

  Future<void> _fetchProductImage(String productId) async {
    if (_loadingProductIds.contains(productId)) return;
    
    _loadingProductIds.add(productId);
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/products/$productId/main_image'),
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
            await ProductCacheService.cacheImage(productId, bytes, numImages);
            
            if (mounted) {
              setState(() {
                _loadedImages[productId] = bytes;
              });
            }
          }
        }
      }
    } catch (e) {
      print('Error fetching product image: $e');
    } finally {
      _loadingProductIds.remove(productId);
    }
  }

  Widget _buildProductCard(Map<String, dynamic> product, int index) {
    Widget imageWidget;
    
    if (_loadedImages.containsKey(product['_id'])) {
      imageWidget = Image.memory(
        _loadedImages[product['_id']]!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: 150, // Reduced from 200
      );
    } else if (_loadingProductIds.contains(product['_id'])) {
      imageWidget = Container(
        color: Colors.grey[200],
        height: 150, // Reduced from 200
        child: const Center(
          child: CircularProgressIndicator(color: Colors.black),
        ),
      );
    } else {
      imageWidget = Container(
        color: Colors.grey[300],
        height: 150, // Reduced from 200
        child: const Center(
          child: Icon(Icons.image_not_supported, size: 50, color: Colors.grey),
        ),
      );
    }

    final status = (product['status'] ?? 'available').toString().toLowerCase();
    final statusColor = status == 'sold' ? Colors.orange : Colors.green;
    final statusText = status.substring(0, 1).toUpperCase() + status.substring(1);

    // Format the date
    String formattedDate = '';
    if (product['createdAt'] != null) {
      final date = DateTime.parse(product['createdAt']);
      formattedDate = '• ${date.day}/${date.month}/${date.year}';
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SellerOfferManagementScreen(product: product),
          ),
        ).then((_) => _loadMyListings());
      },
      child: Card(
        elevation: 2,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with rounded corners
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              child: imageWidget,
            ),
            // Product details section
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // First row: Name and Price
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          product['name'] ?? 'Product ${index + 1}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '₹${product['price']?.toString() ?? '0'}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Description (2 lines)
                  Text(
                    product['description'] ?? 'No description provided',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // Status, date and offer count
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              statusText,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[700],
                              ),
                            ),
                            if (formattedDate.isNotEmpty)
                              Text(
                                formattedDate,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (product['offerRequests'] != null &&
                          (product['offerRequests'] as List).isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${(product['offerRequests'] as List).length} offers',
                            style: TextStyle(
                              color: Colors.blue[700],
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
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
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
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
          title: const Text('My Listings'),
          foregroundColor: Colors.black,
        ),
        body: RefreshIndicator(
          color: Colors.black,
          onRefresh: _loadMyListings,
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
                            onPressed: () => _loadMyListings(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : myListings.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No listings found',
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
                          itemCount: myListings.length,
                          itemBuilder: (context, index) => _buildProductCard(
                            myListings[index],
                            index,
                          ),
                        ),
        ),
      ),
    );
  }
}
