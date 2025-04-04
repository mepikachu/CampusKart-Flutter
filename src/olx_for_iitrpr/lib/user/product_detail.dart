import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ProductDetail extends StatefulWidget {
  final String productId;

  const ProductDetail({Key? key, required this.productId}) : super(key: key);

  @override
  _ProductDetailState createState() => _ProductDetailState();
}

class _ProductDetailState extends State<ProductDetail> {
  Map<String, dynamic>? product;
  bool isLoading = true;
  String? currentUserId;
  bool hasExistingOffer = false;

  @override
  void initState() {
    super.initState();
    _loadProductDetails();
    _loadCurrentUser();
  }

  Future<void> _loadProductDetails() async {
    final response = await http.get(Uri.parse('https://example.com/api/products/${widget.productId}'));
    if (response.statusCode == 200) {
      setState(() {
        product = json.decode(response.body);
        isLoading = false;
      });
    } else {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _loadCurrentUser() async {
    final storage = FlutterSecureStorage();
    currentUserId = await storage.read(key: 'userId');
  }

  void _showMakeOfferDialog() {
    // Implement the dialog to make an offer
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (product == null) {
      return const Scaffold(
        body: Center(child: Text('Product not found')),
      );
    }

    bool isCurrentUserSeller = currentUserId != null && 
                             product!['seller'] != null &&
                             product!['seller']['_id'] == currentUserId;

    return Scaffold(
      appBar: AppBar(
        title: Text(product!['name'] ?? 'Product Details'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Display product images
            if (product!['images'] != null)
              SizedBox(
                height: 200,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: product!['images'].length,
                  itemBuilder: (context, index) {
                    return Image.network(product!['images'][index]);
                  },
                ),
              ),
            // Display product details
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product!['name'] ?? 'No name', style: TextStyle(fontSize: 24)),
                  Text(product!['description'] ?? 'No description'),
                  Text('Price: \$${product!['price']}'),
                  Text('Seller: ${product!['seller']['name']}'),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: product!['status'] == 'available' && !isCurrentUserSeller
          ? FloatingActionButton.extended(
              onPressed: _showMakeOfferDialog,
              label: Text(hasExistingOffer ? 'Update Offer' : 'Make Offer'),
              icon: const Icon(Icons.local_offer),
            )
          : null,
    );
  }
}
