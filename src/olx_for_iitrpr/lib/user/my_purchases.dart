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
  List<Map<String, dynamic>> myPurchases = [];
  bool isLoading = true;
  String errorMessage = '';
  String? userId;
  
  // For image caching
  final Map<String, Uint8List> _loadedImages = {};
  final Set<String> _loadingProductIds = {};

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      userId = await _secureStorage.read(key: 'userId');
      if (userId == null) {
        throw Exception('User ID not found');
      }
      await _loadMyPurchases();
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> _loadMyPurchases() async {
    if (userId == null) return;
    
    try {
      if (mounted) {
        setState(() => isLoading = true);
      }
      
      // First try to get cached purchase IDs
      final activityIds = ProfileService.getActivityIds(userId!);
      if (activityIds != null && activityIds['purchasedProducts'] != null) {
        // Get cached products
        List<Map<String, dynamic>> cachedPurchases = [];
        for (String id in activityIds['purchasedProducts']!) {
          final product = await ProductCacheService.getCachedProduct(id);
          if (product != null) {
            cachedPurchases.add(product);
          }
        }
        
        if (cachedPurchases.isNotEmpty && mounted) {
          setState(() {
            myPurchases = cachedPurchases;
            isLoading = false;
          });
        }
      }
      
      // If no cache or expired, refresh from server
      if (myPurchases.isEmpty || !ProfileService.hasValidActivityCache(userId!)) {
        final authCookie = await _secureStorage.read(key: 'authCookie');
        if (authCookie == null) {
          throw Exception('Not authenticated');
        }

        final response = await http.get(
          Uri.parse('$serverUrl/api/users/me'),
          headers: {
            'Content-Type': 'application/json',
            'auth-cookie': authCookie,
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success']) {
            // Cache the complete response
            await ProfileService.cacheUserProfile(data);
            
            // Try loading from cache again
            final freshIds = ProfileService.getActivityIds(userId!);
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
        }
      }
      
      // Load images for all purchases
      for (var purchase in myPurchases) {
        if (purchase['_id'] != null && !_loadedImages.containsKey(purchase['_id'])) {
          await _loadCachedImage(purchase['_id']);
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

  Widget _buildPurchaseCard(Map<String, dynamic> product) {
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

    // Format the purchase date if available
    String formattedDate = '';
    if (product['purchaseDate'] != null) {
      final date = DateTime.parse(product['purchaseDate']);
      formattedDate = '${date.day}/${date.month}/${date.year}';
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
        elevation: 2,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              child: imageWidget,
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          product['name'] ?? 'Unknown Product',
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Purchased',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (formattedDate.isNotEmpty)
                        Text(
                          formattedDate,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
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
                  : myPurchases.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.shopping_bag_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No purchases found',
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
                          itemCount: myPurchases.length,
                          itemBuilder: (context, index) => _buildPurchaseCard(
                            myPurchases[index],
                          ),
                        ),
        ),
      ),
    );
  }
}
