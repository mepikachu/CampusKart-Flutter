import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'product_details.dart';

enum SortOption {
  nameAsc,
  nameDesc,
  priceAsc,
  priceDesc,
  dateAsc,
  dateDesc,
}

class ProductsTab extends StatefulWidget {
  const ProductsTab({super.key});

  @override
  State<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<dynamic> products = [];
  List<dynamic> filteredProducts = [];
  String searchQuery = '';
  bool isLoading = true;
  String errorMessage = '';
  SortOption _currentSort = SortOption.dateDesc;

  @override
  void initState() {
    super.initState();
    fetchProducts();
  }

  Future<void> fetchProducts() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/products?status=available'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            products = data['products'];
            filteredProducts = List.from(products);
            _sortProducts();
            isLoading = false;
          });
        } else {
          throw Exception(data['error']);
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  void _filterProducts(String query) {
    setState(() {
      searchQuery = query.toLowerCase();
      if (searchQuery.isEmpty) {
        filteredProducts = List.from(products);
      } else {
        filteredProducts = products.where((product) {
          final name = product['name']?.toString().toLowerCase() ?? '';
          final description = product['description']?.toString().toLowerCase() ?? '';
          final category = product['category']?.toString().toLowerCase() ?? '';
          final seller = product['seller']?['userName']?.toString().toLowerCase() ?? '';
          
          return name.contains(searchQuery) ||
              description.contains(searchQuery) ||
              category.contains(searchQuery) ||
              seller.contains(searchQuery);
        }).toList();
      }
      _sortProducts();
    });
  }

  void _sortProducts() {
    setState(() {
      filteredProducts.sort((a, b) {
        switch (_currentSort) {
          case SortOption.nameAsc:
            return (a['name'] ?? '').toString()
                .toLowerCase()
                .compareTo((b['name'] ?? '').toString().toLowerCase());
          case SortOption.nameDesc:
            return (b['name'] ?? '').toString()
                .toLowerCase()
                .compareTo((a['name'] ?? '').toString().toLowerCase());
          case SortOption.priceAsc:
            return (a['price'] ?? 0).toString()
                .compareTo((b['price'] ?? 0).toString());
          case SortOption.priceDesc:
            return (b['price'] ?? 0).toString()
                .compareTo((a['price'] ?? 0).toString());
          case SortOption.dateDesc:
            return (b['createdAt'] ?? '').toString()
                .compareTo((a['createdAt'] ?? '').toString());
          case SortOption.dateAsc:
            return (a['createdAt'] ?? '').toString()
                .compareTo((b['createdAt'] ?? '').toString());
        }
      });
    });
  }

  void _showSortMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Sort by'),
                subtitle: const Text('Choose sorting option'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.sort_by_alpha),
                title: const Text('Name (A to Z)'),
                onTap: () {
                  setState(() {
                    _currentSort = SortOption.nameAsc;
                    _sortProducts();
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.sort_by_alpha),
                title: const Text('Name (Z to A)'),
                onTap: () {
                  setState(() {
                    _currentSort = SortOption.nameDesc;
                    _sortProducts();
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.arrow_upward),
                title: const Text('Price (Low to High)'),
                onTap: () {
                  setState(() {
                    _currentSort = SortOption.priceAsc;
                    _sortProducts();
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.arrow_downward),
                title: const Text('Price (High to Low)'),
                onTap: () {
                  setState(() {
                    _currentSort = SortOption.priceDesc;
                    _sortProducts();
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('Date (Newest First)'),
                onTap: () {
                  setState(() {
                    _currentSort = SortOption.dateDesc;
                    _sortProducts();
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('Date (Oldest First)'),
                onTap: () {
                  setState(() {
                    _currentSort = SortOption.dateAsc;
                    _sortProducts();
                  });
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget buildProductCard(dynamic product, int index) {
    Widget imageWidget;
    final List<dynamic> images = product['images'] ?? [];

    if (images.isNotEmpty && images[0]['data'] != null) {
      try {
        final bytes = base64Decode(images[0]['data']);
        imageWidget = Image.memory(bytes, fit: BoxFit.cover);
      } catch (e) {
        imageWidget = Container(
          color: Colors.grey[300],
          child: const Center(child: Text('Error loading image')),
        );
      }
    } else {
      imageWidget = Container(
        color: Colors.grey[300],
        child: const Center(child: Text('No image')),
      );
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailsScreen(product: product),
          ),
        );
      },
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                child: imageWidget,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product['name'] ?? 'Product ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${product['price']?.toString() ?? ''}',
                    style: const TextStyle(color: Colors.green),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Seller: ${product['seller']?['userName'] ?? 'Unknown'}',
                    style: const TextStyle(fontSize: 12),
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
    return Column(
      children: [
        // Search and Filter Bar
        Container(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search products...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onChanged: _filterProducts,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.sort),
                onPressed: () => _showSortMenu(context),
                tooltip: 'Sort products',
              ),
            ],
          ),
        ),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : errorMessage.isNotEmpty
                  ? Center(child: Text('Error: $errorMessage'))
                  : RefreshIndicator(
                      onRefresh: fetchProducts,
                      child: GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.75,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: filteredProducts.length,
                        itemBuilder: (context, index) => buildProductCard(filteredProducts[index], index),
                      ),
                    ),
        ),
      ],
    );
  }
}
