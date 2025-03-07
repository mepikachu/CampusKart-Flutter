import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'product_details.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Listings'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
              ? Center(child: Text('Error: $errorMessage'))
              : myListings.isEmpty
                  ? const Center(child: Text('No listings yet'))
                  : RefreshIndicator(
                      onRefresh: fetchMyListings,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: myListings.length,
                        itemBuilder: (context, index) {
                          final product = myListings[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 16),
                            child: ListTile(
                              leading: product['images']?.isNotEmpty ?? false
                                  ? SizedBox(
                                      width: 50,
                                      height: 50,
                                      child: Image.memory(
                                        base64Decode(
                                            product['images'][0]['data']),
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : const Icon(Icons.image_not_supported),
                              title: Text(product['name'] ?? 'Unnamed Product'),
                              subtitle: Text(
                                  '₹${product['price']}\nStatus: ${product['status']}'),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        ProductDetailsScreen(product: product),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}