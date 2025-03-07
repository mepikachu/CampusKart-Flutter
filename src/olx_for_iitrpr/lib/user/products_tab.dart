import 'dart:convert'; // for base64Decode
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ProductsTab extends StatefulWidget {
  const ProductsTab({super.key});

  @override
  State<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab> {
  List<dynamic> products = [];
  bool isLoading = true;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    fetchAvailableProducts();
  }

  Future<void> fetchAvailableProducts() async {
    try {
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/products?status=available'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final responseBody = json.decode(response.body);
        if (responseBody['success'] == true) {
          setState(() {
            products = responseBody['products'];
            isLoading = false;
          });
        } else {
          setState(() {
            errorMessage = responseBody['error'] ?? 'Failed to fetch products';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = 'Server error: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  // Helper function to convert the images field to a List
  List<dynamic> parseImages(dynamic imagesField) {
    if (imagesField == null) return [];
    if (imagesField is List) return imagesField;
    if (imagesField is Map) return [imagesField];
    return [];
  }

  Widget buildProductCard(dynamic product, int index) {
    Widget imageWidget;
    final imagesList = parseImages(product['images']);

    if (imagesList.isNotEmpty && imagesList[0] is Map) {
      final firstImage = imagesList[0];
      if (firstImage.containsKey('data') && firstImage['data'] != null) {
        try {
          // Decode the base64 image string to Uint8List.
          final String base64Str = firstImage['data'];
          final Uint8List bytes = base64Decode(base64Str);
          imageWidget = Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey[300],
                child: const Center(child: Text('Image could not be loaded')),
              );
            },
          );
        } catch (e) {
          imageWidget = Container(
            color: Colors.grey[300],
            child: const Center(child: Text('Image could not be loaded')),
          );
        }
      } else {
        imageWidget = Container(
          color: Colors.grey[300],
          child: const Center(child: Text('Image data not found')),
        );
      }
    } else {
      // Fallback if no valid image data is present
      imageWidget = Container(
        color: Colors.grey[300],
        child: const Center(child: Text('Image could not be loaded')),
      );
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product Image
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                child: imageWidget,
              ),
            ),
          ),
          // Product Details
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: fetchAvailableProducts,
      child: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
              ? Center(child: Text('Error: $errorMessage'))
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    return buildProductCard(products[index], index);
                  },
                ),
    );
  }
}
