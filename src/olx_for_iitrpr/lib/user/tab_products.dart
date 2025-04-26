import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:isolate';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'product_description.dart';
import '../services/product_cache_service.dart';
import 'server.dart';

class ProductsTab extends StatefulWidget {
  const ProductsTab({super.key});

  @override
  State<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab> with AutomaticKeepAliveClientMixin {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<dynamic> products = [];
  bool isLoading = true;
  String? errorMessage;
  
  // Tracking loaded images
  final Map<String, Uint8List> _loadedImages = {};
  final Set<String> _loadingProductIds = {};

  @override
  void initState() {
    super.initState();
    fetchProducts();
  }

  Future<void> fetchProducts({bool forceRefresh = false}) async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
      
      // Check cache first if not forcing refresh
      if (!forceRefresh) {
        final cachedProducts = await ProductCacheService.getCachedProducts();
        if (cachedProducts != null) {
          setState(() {
            products = cachedProducts;
            isLoading = false;
          });
          
          // Load cached images
          for (var product in products) {
            _loadCachedImage(product['_id']);
          }
          
          // Still fetch fresh data in background
          _fetchFreshProducts();
          return;
        }
      }
      
      await _fetchFreshProducts();
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }
  
  // Load cached image
  Future<void> _loadCachedImage(String productId) async {
    final cachedImage = await ProductCacheService.getCachedImage(productId);
    if (cachedImage != null && mounted) {
      setState(() {
        _loadedImages[productId] = cachedImage;
      });
    } else {
      // If no cached image, fetch from network
      _fetchProductImage(productId);
    }
  }
  
  // Fetch fresh product list
  Future<void> _fetchFreshProducts() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/products'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Cache the products
        await ProductCacheService.cacheProducts(data['products']);
        
        if (mounted) {
          setState(() {
            products = data['products'];
            isLoading = false;
          });
        }
        
        // Fetch images for each product using threading
        for (var product in products) {
          if (!_loadedImages.containsKey(product['_id'])) {
            _fetchProductImage(product['_id']);
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
        throw Exception('Failed to load products');
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

  // Fetch product image using threading
  Future<void> _fetchProductImage(String productId) async {
    // Skip if already loading
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
            final String base64Str = image['data'];
            final Uint8List bytes = base64Decode(base64Str);
            
            // Cache the image
            await ProductCacheService.cacheImage(productId, bytes, numImages);
            
            if (mounted) {
              setState(() {
                _loadedImages[productId] = bytes;
                _loadingProductIds.remove(productId);
              });
            }
          }
        }
      }
    } catch (e) {
      print('Error fetching image directly: $e');
      if (mounted) {
        setState(() {
          _loadingProductIds.remove(productId);
        });
      }
    }
  }
  
  // Fallback direct image fetching without threading
  Future<void> _fetchProductImageDirect(String productId) async {
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
        final image = data['image'];
        final numImages = data['numImages'] ?? 1;
        
        if (image != null && image['data'] != null) {
          final String base64Str = image['data'];
          final Uint8List bytes = base64Decode(base64Str);
          
          // Cache the image
          ProductCacheService.cacheImage(productId, bytes, numImages);
          
          if (mounted) {
            setState(() {
              _loadedImages[productId] = bytes;
              _loadingProductIds.remove(productId);
            });
          }
        }
      }
    } catch (e) {
      print('Error fetching image directly: $e');
      if (mounted) {
        setState(() {
          _loadingProductIds.remove(productId);
        });
      }
    }
  }
  
  // Static method for isolate to fetch image
  static void _isolateImageFetcher(Map<String, dynamic> data) async {
    final String productId = data['productId'];
    final SendPort sendPort = data['sendPort'];
    final String? authCookie = data['authCookie'];
    
    try {
      final response = await http.get(
        Uri.parse('$serverUrl/api/products/$productId/main_image'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final image = data['image']?[0];
        final numImages = data['numImages'] ?? 1;
        
        if (image != null && image['data'] != null) {
          final String base64Str = image['data'];
          final Uint8List bytes = base64Decode(base64Str);
          
          sendPort.send({
            'imageBytes': bytes,
            'numImages': numImages,
          });
          return;
        }
      }
      
      sendPort.send('error');
    } catch (e) {
      print('Error in isolate: $e');
      sendPort.send('error');
    }
  }

  void _onProductTap(dynamic product) {
    // Pass the loaded image to product details screen
    String productId = product['_id'];
    if (_loadedImages.containsKey(productId)) {
      product['imageData'] = _loadedImages[productId];
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailsScreen(product: product),
      ),
    ).then((_) {
      // Refresh when coming back
      fetchProducts(forceRefresh: false);
    });
  }

  Widget buildProductCard(dynamic product) {
    final String productId = product['_id'];
    Widget imageWidget;

    // Simple image display
    if (_loadedImages.containsKey(productId)) {
      imageWidget = Image.memory(
        _loadedImages[productId]!,
        fit: BoxFit.cover,
        height: 200,
        width: double.infinity,
        errorBuilder: (context, error, stackTrace) {
          print('Error displaying image: $error');
          return Container(
            color: Colors.grey[300],
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        },
      );
    } else {
      imageWidget = Container(
        color: Colors.grey[300],
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _onProductTap(product),
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
                    product['name'] ?? 'Unnamed Product',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    product['description'] ?? 'No description',
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
                        '₹${product['price']?.toString() ?? '0'}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      Text(
                        'By ${product['seller']?['userName'] ?? 'Unknown'}',
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
        body: isLoading && products.isEmpty
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
                          onPressed: () => fetchProducts(forceRefresh: true),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    color: Colors.black,
                    onRefresh: () => fetchProducts(forceRefresh: true),
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: products.length,
                      itemBuilder: (context, index) => buildProductCard(products[index]),
                    ),
                  ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
