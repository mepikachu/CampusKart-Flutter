import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'edit_product_screen.dart';

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
      // Fix the URL to match backend routes
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/products/offers/$offerId/$action'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({'productId': widget.product['_id']}),
      );

      if (response.statusCode == 200) {
        if (action == 'accept') {
          setState(() {
            widget.product['status'] = 'sold';
            offers = []; // Clear all offers
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Offer accepted. Product marked as sold.')),
          );
          
          // Navigate back after a short delay
          Future.delayed(const Duration(seconds: 2), () {
            Navigator.of(context).pop();
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Offer rejected successfully')),
          );
          fetchOffers(); // Refresh the offers list
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to $action offer');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
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
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Product Details'),
              Tab(text: 'Offers'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildProductDetails(),
            _buildOffersList(),
          ],
        ),
      ),
    );
  }

  Widget _buildProductDetails() {
    List<Widget> imageSlides = [];
    if (widget.product['images'] != null) {
      imageSlides = widget.product['images'].map<Widget>((image) {
        if (image != null && image['data'] != null) {
          try {
            final imageBytes = base64Decode(image['data']);
            return Image.memory(
              imageBytes,
              fit: BoxFit.cover,
              width: double.infinity,
            );
          } catch (e) {
            return const Center(child: Icon(Icons.error));
          }
        }
        return const Center(child: Icon(Icons.image_not_supported));
      }).toList();
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageSlides.isNotEmpty)
            CarouselSlider(
              items: imageSlides,
              options: CarouselOptions(
                height: 300,
                viewportFraction: 1.0,
                enableInfiniteScroll: false,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.product['name'] ?? 'Unknown Product',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '₹${widget.product['price']?.toString() ?? '0'}',
                  style: const TextStyle(
                    fontSize: 20,
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
                Text(
                  'Status: ${widget.product['status']?.toUpperCase() ?? 'AVAILABLE'}',
                  style: TextStyle(
                    fontSize: 16,
                    color: widget.product['status'] == 'sold' ? Colors.red : Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOffersList() {
    return isLoading
        ? const Center(child: CircularProgressIndicator())
        : errorMessage.isNotEmpty
            ? Center(child: Text('Error: $errorMessage'))
            : offers.isEmpty
                ? const Center(child: Text('No offers yet'))
                : ListView.builder(
                    itemCount: offers.length,
                    itemBuilder: (context, index) {
                      final offer = offers[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          title: Text(
                            '₹${offer['offerPrice']}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            'From: ${offer['buyer']?['userName'] ?? 'Unknown'}\n'
                            'Date: ${DateTime.parse(offer['createdAt']).toString().split('.')[0]}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton.icon(
                                icon: const Icon(Icons.check, color: Colors.white),
                                label: const Text('Accept'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                ),
                                onPressed: () => _showConfirmationDialog(
                                  'Accept Offer',
                                  'Are you sure you want to accept this offer? This will mark the product as sold.',
                                  () => _handleOfferAction(offer['_id'], 'accept'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.clear, color: Colors.white),
                                label: const Text('Reject'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                onPressed: () => _showConfirmationDialog(
                                  'Reject Offer',
                                  'Are you sure you want to reject this offer?',
                                  () => _handleOfferAction(offer['_id'], 'decline'),
                                ),
                              ),
                            ],
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  );
  }

  Future<void> _showConfirmationDialog(String title, String message, Function onConfirm) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text('Confirm'),
              onPressed: () {
                Navigator.of(context).pop();
                onConfirm();
              },
            ),
          ],
        );
      },
    );
  }
}