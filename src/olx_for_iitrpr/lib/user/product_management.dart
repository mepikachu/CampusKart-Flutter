import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'product_details.dart';
import 'edit_product_screen.dart'; // Import the new screen

class SellerOfferManagementScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  const SellerOfferManagementScreen({super.key, required this.product});

  @override
  State<SellerOfferManagementScreen> createState() => _SellerOfferManagementScreenState();
}

class _SellerOfferManagementScreenState extends State<SellerOfferManagementScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<dynamic> offers = [];
  bool isLoading = true;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    fetchOffers();
  }

  Future<void> fetchOffers() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/products/${widget.product['_id']}/offers'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          offers = data['offerRequests'] ?? [];
          isLoading = false;
        });
      } else {
        throw Exception(data['error'] ?? 'Failed to fetch offers');
      }
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> _handleOfferAction(String offerId, String action) async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/offers/$offerId/$action'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({'productId': widget.product['_id']}),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Offer $action successfully')),
        );
        fetchOffers(); // Refresh the offers list
      } else {
        throw Exception('Failed to $action offer');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.product['name'] ?? 'Manage Product'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EditProductScreen(product: widget.product),
                ),
              );
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
              ? Center(child: Text('Error: $errorMessage'))
              : offers.isEmpty
                  ? const Center(child: Text('No offers yet'))
                  : ListView.builder(
                      itemCount: offers.length,
                      itemBuilder: (context, index) {
                        final offer = offers[index];
                        return ListTile(
                          title: Text('Offer: ₹${offer['offerPrice']}'),
                          subtitle: Text('By: ${offer['buyer']?['userName'] ?? 'Unknown'}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check, color: Colors.green),
                                onPressed: () => _handleOfferAction(offer['_id'], 'accept'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.clear, color: Colors.red),
                                onPressed: () => _handleOfferAction(offer['_id'], 'decline'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}