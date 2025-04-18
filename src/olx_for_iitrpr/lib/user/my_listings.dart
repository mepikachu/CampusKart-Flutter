import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/profile_service.dart';
import '../services/product_cache_service.dart';
import 'product_management.dart';

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<dynamic> myListings = [];
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
      // First try to get cached product IDs
      final activityIds = await ProfileService.activityIds;

      if (activityIds != null && activityIds['products'] != null) {
        // Get cached products
        List<Map<String, dynamic>> cachedProducts = [];
        for (String id in activityIds['products']!) {
          final product = await ProductCacheService.getCachedProduct(id);
          if (product != null) {
            cachedProducts.add(product);
          }
        }

        if (cachedProducts.isNotEmpty) {
          setState(() {
            myListings = cachedProducts;
            isLoading = false;
          });
        }
      }

      // If no cache or expired, refresh from server
      if (myListings.isEmpty || !ProfileService.hasValidActivityCache) {
        await ProfileService.fetchAndCacheUserProfile();

        // Try loading from cache again
        final freshIds = await ProfileService.activityIds;
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
        if (!_loadedImages.containsKey(product['_id'])) {
          await _loadCachedImage(product['_id']);
        }
      }
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
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
        _fetchProductImage(productId);
      }
    } catch (e) {
      print('Error loading cached image: $e');
    }
  }

  Future<void> _fetchMyListings() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) throw Exception('Not authenticated');

      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/users/me'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          // Cache ALL response data
          await ProfileService.cacheUserResponse(data);

          setState(() {
            myListings = data['activity']['products'] ?? [];
            isLoading = false;
          });

          // Fetch images for new/updated products
          for (var product in myListings) {
            if (!_loadedImages.containsKey(product['_id'])) {
              _fetchProductImage(product['_id']);
            }
          }
        }
      }
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> _fetchProductImage(String productId) async {
    if (_loadingProductIds.contains(productId)) return;
    _loadingProductIds.add(productId);

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/products/$productId/main_image'),
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

  Widget buildProductCard(dynamic product, int index) {
    List<dynamic> imagesList = product['images'] ?? [];
    Widget imageWidget;

    if (_loadedImages.containsKey(product['_id'])) {
      imageWidget = Image.memory(
        _loadedImages[product['_id']]!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: 200,
      );
    } else if (imagesList.isNotEmpty &&
        imagesList[0] is Map &&
        imagesList[0]['data'] != null) {
      try {
        final String base64Str = imagesList[0]['data'];
        final Uint8List bytes = base64Decode(base64Str);
        imageWidget = Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: double.infinity,
          height: 200,
        );
      } catch (e) {
        imageWidget = Container(
          color: Colors.grey[300],
          height: 200,
          child: const Center(
            child: Text('Error loading image', style: TextStyle(fontSize: 14)),
          ),
        );
      }
    } else {
      imageWidget = Container(
        color: Colors.grey[300],
        height: 200,
        child: const Center(child: Text('No image', style: TextStyle(fontSize: 14))),
      );
    }

    return GestureDetector(
      onTap: () {
        // Navigate to product management screen upon tap
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                SellerOfferManagementScreen(product: product),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image section taking full width
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: imageWidget,
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product name
                    Text(
                      product['name'] ?? 'Product ${index + 1}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // Product description
                    Text(
                      product['description'] ?? 'No description provided',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 12),
                    // Price and offer count row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '₹${product['price']?.toString() ?? '0'}',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (product['offerRequests'] != null &&
                            (product['offerRequests'] as List).isNotEmpty)
                          Text(
                            '${(product['offerRequests'] as List).length} offers',
                            style: const TextStyle(
                              color: Colors.blue,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Listings')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
              ? Center(child: Text('Error: $errorMessage'))
              : myListings.isEmpty
                  ? const Center(child: Text('No listings yet'))
                  : RefreshIndicator(
                      onRefresh: _fetchMyListings,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: myListings.length,
                        itemBuilder: (context, index) =>
                            buildProductCard(myListings[index], index),
                      ),
                    ),
    );
  }
}