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

    // Handle image display
    if (imagesList.isNotEmpty && imagesList[0] is Map) {
      final firstImage = imagesList[0];
      if (firstImage.containsKey('data') && firstImage['data'] != null) {
        try {
          final String base64Str = firstImage['data'];
          final Uint8List bytes = base64Decode(base64Str);
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
            builder: (context) => SellerOfferManagementScreen(product: product),
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
                  if (product['offerRequests'] != null &&
                      (product['offerRequests'] as List).isNotEmpty)
                    Text(
                      '${(product['offerRequests'] as List).length} offers',
                      style: const TextStyle(color: Colors.blue),
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
                      child: GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.75,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: myListings.length,
                        itemBuilder: (context, index) =>
                            buildProductCard(myListings[index], index),
                      ),
                    ),
    );
  }
}