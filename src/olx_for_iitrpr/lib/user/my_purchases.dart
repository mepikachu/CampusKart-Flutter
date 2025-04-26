import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/profile_service.dart';
import '../services/product_cache_service.dart';
import 'product_description.dart';
import 'server.dart';

class MyPurchasesPage extends StatefulWidget {
  const MyPurchasesPage({super.key});

  @override
  State<MyPurchasesPage> createState() => _MyPurchasesPageState();
}

class _MyPurchasesPageState extends State<MyPurchasesPage> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<dynamic> myPurchases = [];
  bool isLoading = true;
  String errorMessage = '';

  // For image caching
  final Map<String, Uint8List> _loadedImages = {};
  final Set<String> _loadingProductIds = {};

  @override
  void initState() {
    super.initState();
    _loadMyPurchases();
  }

  Future<void> _loadMyPurchases() async {
    try {
      // First try to get cached purchase IDs
      final activityIds = await ProfileService.activityIds;

      if (activityIds != null && activityIds['purchasedProducts'] != null) {
        // Get cached products
        List<Map<String, dynamic>> cachedPurchases = [];
        for (String id in activityIds['purchasedProducts']!) {
          final product = await ProductCacheService.getCachedProduct(id);
          if (product != null) {
            cachedPurchases.add(product);
          }
        }

        if (cachedPurchases.isNotEmpty) {
          setState(() {
            myPurchases = cachedPurchases;
            isLoading = false;
          });
        }
      }

      // If no cache or expired, refresh from server
      if (myPurchases.isEmpty || !ProfileService.hasValidActivityCache) {
        await ProfileService.fetchAndCacheUserProfile();

        // Try loading from cache again
        final freshIds = await ProfileService.activityIds;
        if (freshIds != null && freshIds['purchasedProducts'] != null) {
          List<Map<String, dynamic>> freshPurchases = [];
          for (String id in freshIds['purchasedProducts']!) {
            final product = await ProductCacheService.getCachedProduct(id);
            if (product != null) {
              freshPurchases.add(product);
            }
          }

          if (mounted) {
            setState(() {
              myPurchases = freshPurchases;
              isLoading = false;
            });
          }
        }
      }

      // Load images for all purchases
      for (var purchase in myPurchases) {
        if (!_loadedImages.containsKey(purchase['_id'])) {
          await _loadCachedImage(purchase['_id']);
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
    final cachedImage = await ProductCacheService.getCachedImage(productId);
    if (cachedImage != null && mounted) {
      setState(() {
        _loadedImages[productId] = cachedImage;
      });
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

  Widget _buildPurchaseCard(dynamic product) {
    Widget imageWidget;
    if (_loadedImages.containsKey(product['_id'])) {
      imageWidget = Image.memory(
        _loadedImages[product['_id']]!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: 200,
      );
    } else {
      imageWidget = Container(
        color: Colors.grey[300],
        height: 200,
        child: Center(
          child: _loadingProductIds.contains(product['_id'])
              ? const CircularProgressIndicator()
              : const Icon(Icons.image_not_supported, size: 50),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailsScreen(
              product: product,
              showOfferButton: false,
            ),
          ),
        );
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
              child: imageWidget,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product['name'] ?? 'Unknown Product',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    product['description'] ?? 'No description provided',
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
                        '₹${product['price']?.toString() ?? '0'}',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Seller: ${product['seller']?['userName'] ?? 'Unknown'}',
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
          title: const Text('My Purchases'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: RefreshIndicator(
          color: Colors.black,
          onRefresh: _loadMyPurchases,
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
                            onPressed: () => _loadMyPurchases(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: myPurchases.length,
                      itemBuilder: (context, index) =>
                          _buildPurchaseCard(myPurchases[index]),
                    ),
        ),
      ),
    );
  }
}