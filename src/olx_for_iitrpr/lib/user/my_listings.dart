import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  @override
  void initState() {
    super.initState();
    fetchMyListings();
  }

  Future<void> fetchMyListings() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) throw Exception('Not authenticated');

      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/me'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      );

      final responseBody = json.decode(response.body);
      if (response.statusCode == 200 && responseBody['success'] == true) {
        setState(() {
          // Assuming the sold products are returned in user.soldProducts
          myListings = responseBody['user']['soldProducts'] ?? [];
          isLoading = false;
        });
      } else {
        throw Exception(responseBody['error'] ?? 'Failed to fetch listings');
      }
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Widget buildProductCard(dynamic product, int index) {
    List<dynamic> imagesList = product['images'] ?? [];
    Widget imageWidget;

    if (imagesList.isNotEmpty &&
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
                      onRefresh: fetchMyListings,
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