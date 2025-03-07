import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'chats.dart';

class ProductDetailsScreen extends StatefulWidget {
  final dynamic product;
  
  const ProductDetailsScreen({super.key, required this.product});

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  String currentUserName = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentUserName();
  }

  Future<void> _loadCurrentUserName() async {
    String? name = await _secureStorage.read(key: 'userName');
    if (mounted) {
      setState(() {
        currentUserName = name ?? '';
      });
    }
  }

  void _startChat() async {
    if (widget.product['seller']?['_id'] == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          conversationId: '', // This will be created by the API
          partnerNames: widget.product['seller']['userName'],
          sellerId: widget.product['seller']['_id'],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageData = widget.product['images']?[0]?['data'];
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Details'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image
            if (imageData != null)
              Image.memory(
                base64Decode(imageData),
                height: 300,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product Name
                  Text(
                    widget.product['name'] ?? 'Unknown Product',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Price
                  Text(
                    '₹${widget.product['price']?.toString() ?? '0'}',
                    style: const TextStyle(
                      fontSize: 20,
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Seller Info
                  Text(
                    'Seller: ${widget.product['seller']?['userName'] ?? 'Unknown'}',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Description
                  const Text(
                    'Description:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.product['description'] ?? 'No description available',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  
                  // Chat with Seller Button (only show if not the current user's product)
                  if (widget.product['seller']?['userName'] != currentUserName)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _startChat,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.blue,
                        ),
                        child: const Text(
                          'Chat with Seller',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}