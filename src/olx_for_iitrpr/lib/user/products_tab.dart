import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ProductsTab extends StatefulWidget {
  const ProductsTab({Key? key}) : super(key: key);

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

  // Build each product card, checking if image data is stored as Buffer data
  Widget buildProductCard(dynamic product, int index) {
    Widget imageWidget;
    if (product['images'] != null &&
        product['images'].isNotEmpty &&
        product['images'][0] is Map &&
        product['images'][0]['data'] != null) {
      // The image is stored in MongoDB as an object with a 'data' field (list of ints)
      List<dynamic> dataList = product['images'][0]['data'];
      Uint8List bytes = Uint8List.fromList(dataList.cast<int>());
      imageWidget = Image.memory(
        bytes,
        fit: BoxFit.cover,
      );
    } else if (product['images'] != null &&
        product['images'].isNotEmpty &&
        product['images'][0] is String) {
      // Otherwise, assume it's a URL (or base64 string if already prefixed)
      imageWidget = Image.network(
        product['images'][0],
        fit: BoxFit.cover,
      );
    } else {
      // Fallback image
      imageWidget = Image.network(
        'https://picsum.photos/200?random=$index',
        fit: BoxFit.cover,
      );
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
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
