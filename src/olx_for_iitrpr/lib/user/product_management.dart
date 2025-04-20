import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'edit_product_screen.dart';
import '../services/product_cache_service.dart';

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

  // Add image caching fields
  final Map<String, List<Uint8List>> _imageCache = {};
  final Set<String> _loadingImages = {};
  bool _hasLoadedImages = false;

  @override
  void initState() {
    super.initState();
    fetchOffers();
    _loadCachedImages();
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

  Future<void> _loadCachedImages() async {
    if (_hasLoadedImages) return;

    try {
      final cachedImages = await ProductCacheService.getCachedAllImages(widget.product['_id']);
      if (cachedImages != null) {
        setState(() {
          _imageCache[widget.product['_id']] = cachedImages;
          _hasLoadedImages = true;
        });
      }
    } catch (e) {
      print('Error loading cached images: $e');
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
    if (_imageCache.containsKey(widget.product['_id'])) {
      imageSlides = List.generate(_imageCache[widget.product['_id']]!.length, (index) {
        return Image.memory(
          _imageCache[widget.product['_id']]![index],
          fit: BoxFit.cover,
          width: double.infinity,
        );
      });
    } else {
      imageSlides = [
        Container(
          color: Colors.grey[200],
          child: Center(
            child: _loadingImages.contains(widget.product['_id'])
                ? const CircularProgressIndicator()
                : const Icon(Icons.image_not_supported),
          ),
        ),
      ];
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageSlides.isNotEmpty)
            Stack(
              children: [
                CarouselSlider(
                  items: imageSlides,
                  options: CarouselOptions(
                    height: 300,
                    viewportFraction: 1.0,
                    enableInfiniteScroll: false,
                    autoPlay: imageSlides.length > 1,
                    autoPlayInterval: const Duration(seconds: 3),
                  ),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.product['name'] ?? 'Unknown Product',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.product['status'] == 'sold' 
                            ? Colors.red.withOpacity(0.1) 
                            : Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.product['status']?.toUpperCase() ?? 'AVAILABLE',
                        style: TextStyle(
                          color: widget.product['status'] == 'sold' 
                              ? Colors.red 
                              : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '₹${widget.product['price']?.toString() ?? '0'}',
                  style: const TextStyle(
                    fontSize: 24,
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                // Category
                if (widget.product['category'] != null) ...[
                  const Text(
                    'Category:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.product['category'].toString(),
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                ],
                // Description
                const Text(
                  'Description:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.product['description'] ?? 'No description available',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                // Additional details
                const Text(
                  'Additional Details:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('Posted Date'),
                  subtitle: Text(_formatDate(widget.product['createdAt'])),
                ),
                if (widget.product['lastUpdatedAt'] != null)
                  ListTile(
                    leading: const Icon(Icons.update),
                    title: const Text('Last Updated'),
                    subtitle: Text(_formatDate(widget.product['lastUpdatedAt'])),
                  ),
                if (widget.product['status'] == 'sold')
                  ListTile(
                    leading: const Icon(Icons.sell),
                    title: const Text('Sold Date'),
                    subtitle: Text(_formatDate(widget.product['soldDate'])),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'Invalid date';
    }
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