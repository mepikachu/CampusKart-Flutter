import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
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
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showSearchBar = true;
  String _sortBy = '';
  String? _selectedCategory;
  List<dynamic> products = [];
  List<dynamic> filteredProducts = [];
  bool isLoading = true;
  String? errorMessage;
  
  // Image caching
  final Map<String, Uint8List> _loadedImages = {};
  final Set<String> _loadingProductIds = {};

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    fetchProducts();
  }

  void _onScroll() {
    setState(() {
      _showSearchBar = _scrollController.offset <= 10;
    });
  }

  Future<void> fetchProducts({bool forceRefresh = false}) async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
      
      // Try to load from cache first if not forcing refresh
      if (!forceRefresh) {
        final cachedProducts = await ProductCacheService.getCachedProducts();
        if (cachedProducts != null) {
          setState(() {
            products = cachedProducts;
            filteredProducts = cachedProducts;
            isLoading = false;
          });
          
          // Load cached images for all products
          for (var product in products) {
            if (product['_id'] != null) {
              _loadCachedImage(product['_id']);
            }
          }
        }
      }
      
      // Always fetch fresh data in the background (or as primary source if no cache)
      await _fetchFreshProducts();
      
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }
  
  Future<void> _loadCachedImage(String productId) async {
    try {
      // Skip if already loaded or loading
      if (_loadedImages.containsKey(productId) || _loadingProductIds.contains(productId)) {
        return;
      }
      
      final cachedImage = await ProductCacheService.getCachedImage(productId);
      if (cachedImage != null && mounted) {
        setState(() {
          _loadedImages[productId] = cachedImage;
        });
      } else {
        // If not in cache, fetch from network
        _fetchProductImage(productId);
      }
    } catch (e) {
      print('Error loading cached image: $e');
    }
  }

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
        final fetchedProducts = data['products'];
        
        // Cache the products
        await ProductCacheService.cacheProducts(fetchedProducts);
        
        if (mounted) {
          setState(() {
            products = fetchedProducts;
            // Only update filtered products if no filter is active
            if (_searchController.text.isEmpty && _selectedCategory == null) {
              filteredProducts = fetchedProducts;
            } else {
              // Re-apply current filters
              _filterAndSortProducts();
            }
            isLoading = false;
          });
        }
        
        // Fetch images for any products that don't have them
        for (var product in fetchedProducts) {
          if (product['_id'] != null && !_loadedImages.containsKey(product['_id'])) {
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

  Future<void> _fetchProductImage(String productId) async {
    // Skip if already loading or loaded
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
            
            // Cache the image with number of images
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
      print('Error fetching image: $e');
    } finally {
      _loadingProductIds.remove(productId);
    }
  }

  void _onProductTap(dynamic product) {
    final String productId = product['_id'];
    // Pass the loaded image if available to avoid reloading
    if (_loadedImages.containsKey(productId)) {
      product['imageData'] = _loadedImages[productId];
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailsScreen(product: product),
      ),
    ).then((_) {
      // Refresh when coming back (without forcing refresh)
      fetchProducts(forceRefresh: false);
    });
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final String productId = product['_id'];
    Widget imageWidget;
    
    if (_loadedImages.containsKey(productId)) {
      imageWidget = Image.memory(
        _loadedImages[productId]!,
        fit: BoxFit.cover,
        height: 200,
        width: double.infinity,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey[300],
            height: 200,
            child: const Center(
              child: Icon(Icons.image_not_supported, size: 50, color: Colors.grey)
            ),
          );
        },
      );
    } else if (_loadingProductIds.contains(productId)) {
      imageWidget = Container(
        color: Colors.grey[200],
        height: 200,
        child: const Center(child: CircularProgressIndicator(color: Colors.black)),
      );
    } else {
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
              builder: (context) => ProductDetailsScreen(
                product: product,
              ),
            ),
          ).then((_) => fetchProducts(forceRefresh: true));
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
                          (product['name'] ?? 'Unnamed Product').toUpperCase(),
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
                          color: Colors.blue[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '₹${product['price'] ?? '0'}',
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
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
                        'Posted by ${product['seller']?['userName'] ?? 'Unknown'}',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _formatDate(product['createdAt']),
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

  void _filterAndSortProducts() {
    var filtered = List.from(products);
    
    // Apply category filter
    if (_selectedCategory != null && _selectedCategory != 'all') {
      filtered = filtered.where((p) => p['category'] == _selectedCategory).toList();
    }
    
    // Apply text search filter
    if (_searchController.text.isNotEmpty) {
      final searchTerm = _searchController.text.toLowerCase();
      filtered = filtered.where((product) =>
        (product['name']?.toLowerCase().contains(searchTerm) ?? false) ||
        (product['description']?.toLowerCase().contains(searchTerm) ?? false)
      ).toList();
    }
    
    // Apply sorting
    switch (_sortBy) {
      case 'price_asc':
        filtered.sort((a, b) => (a['price'] as num).compareTo(b['price'] as num));
        break;
      case 'price_desc':
        filtered.sort((a, b) => (b['price'] as num).compareTo(a['price'] as num));
        break;
      case 'date_desc':
        filtered.sort((a, b) => DateTime.parse(b['createdAt'])
            .compareTo(DateTime.parse(a['createdAt'])));
        break;
      case 'date_asc':
        filtered.sort((a, b) => DateTime.parse(a['createdAt'])
            .compareTo(DateTime.parse(b['createdAt'])));
        break;
    }
    
    setState(() {
      filteredProducts = filtered;
    });
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
            // Animated search bar
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
                                  hintText: 'Search products...',
                                  border: InputBorder.none,
                                  hintStyle: TextStyle(color: Colors.grey[500]),
                                ),
                                onChanged: (value) {
                                  _filterAndSortProducts();
                                },
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
                          if (value.toString().startsWith('category_')) {
                            setState(() {
                              _selectedCategory = value.toString().substring(9) == 'all' 
                                  ? null 
                                  : value.toString().substring(9);
                            });
                          } else {
                            setState(() {
                              _sortBy = value.toString();
                            });
                          }
                          _filterAndSortProducts();
                        },
                        itemBuilder: (context) => <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            value: 'price_asc',
                            child: Text('Price: Low to High'),
                          ),
                          const PopupMenuItem<String>(
                            value: 'price_desc',
                            child: Text('Price: High to Low'),
                          ),
                          const PopupMenuItem<String>(
                            value: 'date_desc',
                            child: Text('Newest First'),
                          ),
                          const PopupMenuItem<String>(
                            value: 'date_asc',
                            child: Text('Oldest First'),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem<String>(
                            value: 'category_all',
                            child: Text('All Categories'),
                          ),
                          const PopupMenuItem<String>(
                            value: 'category_electronics',
                            child: Text('Electronics'),
                          ),
                          const PopupMenuItem<String>(
                            value: 'category_books',
                            child: Text('Books'),
                          ),
                          const PopupMenuItem<String>(
                            value: 'category_furniture',
                            child: Text('Furniture'),
                          ),
                          const PopupMenuItem<String>(
                            value: 'category_clothing',
                            child: Text('Clothing'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Products grid with ScrollController
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => fetchProducts(forceRefresh: true),
                color: Colors.black,
                child: isLoading && filteredProducts.isEmpty
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
                    : filteredProducts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'No products found',
                                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: filteredProducts.length,
                          itemBuilder: (context, index) => _buildProductCard(filteredProducts[index]),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
