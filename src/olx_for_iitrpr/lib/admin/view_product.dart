import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:carousel_slider/carousel_slider.dart';
import 'package:intl/intl.dart';

class AdminProductView extends StatefulWidget {
  final String productId;
  
  const AdminProductView({Key? key, required this.productId}) : super(key: key);

  @override
  State<AdminProductView> createState() => _AdminProductViewState();
}

class _AdminProductViewState extends State<AdminProductView> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  bool isLoading = true;
  bool isError = false;
  String errorMessage = '';
  Map<String, dynamic>? productData;
  List<dynamic> productReports = [];
  bool isPerformingAction = false;
  int _currentImageIndex = 0;
  final CarouselSliderController _carouselController = CarouselSliderController();

  @override
  void initState() {
    super.initState();
    _fetchProductDetails();
  }

  Future<void> _fetchProductDetails() async {
    setState(() {
      isLoading = true;
      isError = false;
    });
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      // Using admin route to get product details
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/admin/products/${widget.productId}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            productData = data['product'];
            productReports = data['reports'] ?? [];
            isLoading = false;
          });
        } else {
          setState(() {
            isLoading = false;
            isError = true;
            errorMessage = data['message'] ?? 'Failed to load product details';
          });
        }
      } else {
        setState(() {
          isLoading = false;
          isError = true;
          errorMessage = 'Failed to load product details. Status: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        isError = true;
        errorMessage = 'Error: $e';
      });
      print('Error fetching product details: $e');
    }
  }

  Future<void> _deleteProduct() async {
    // Ask for confirmation
    bool confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: const Text('Are you sure you want to delete this product? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ?? false;
    
    if (!confirmed) return;
    
    setState(() {
      isPerformingAction = true;
    });
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      final response = await http.delete(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/admin/products/${widget.productId}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product deleted successfully')),
        );
        Navigator.pop(context);
      } else {
        throw Exception('Failed to delete product');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting product: $e')),
      );
    } finally {
      setState(() {
        isPerformingAction = false;
      });
    }
  }

  Future<void> _viewSellerProfile() async {
    if (productData == null || productData!['seller'] == null || productData!['seller']['_id'] == null) {
      return;
    }
    
    Navigator.pushNamed(
      context, 
      '/admin/user-profile',
      arguments: productData!['seller']['_id'],
    );
  }

  Widget _buildReportItem(Map<String, dynamic> report) {
    final reportDate = _formatDate(report['createdAt'] ?? '');
    final reporterName = report['reporter'] != null ? report['reporter']['userName'] ?? 'Unknown' : 'Unknown';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flag, color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Reported by $reporterName on $reportDate',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Reason: ${report['reason'] ?? 'Not specified'}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            if (report['description'] != null)
              Text(report['description']),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      '/admin/user-profile',
                      arguments: report['reporter']['_id'],
                    );
                  },
                  child: const Text('View Reporter'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildImageSlides() {
    final List images = productData != null && productData!['images'] != null 
        ? productData!['images'] 
        : [];
        
    return images.map<Widget>((image) {
      if (image != null && image['data'] != null) {
        try {
          final imageBytes = base64Decode(image['data']);
          return Container(
            width: double.infinity,
            child: Image.memory(
              imageBytes,
              fit: BoxFit.cover,
            ),
          );
        } catch (e) {
          return const Center(child: Icon(Icons.error));
        }
      }
      return const Center(child: Icon(Icons.image_not_supported));
    }).toList();
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMM d, yyyy').format(date);
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Details'),
        actions: [
          if (!isLoading && !isError && productData != null)
            IconButton(
              icon: const Icon(Icons.delete),
              color: Colors.red,
              onPressed: _deleteProduct,
              tooltip: 'Delete Product',
            ),
        ],
      ),
      body: Stack(
        children: [
          if (isLoading) 
            const Center(child: CircularProgressIndicator())
          else if (isError)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(errorMessage, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _fetchProductDetails,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else if (productData == null)
            const Center(child: Text('Product not found'))
          else
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Images Carousel
                  _buildImageCarousel(),
                  
                  // Product Info
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Product Name
                        Text(
                          productData!['name'] ?? 'Unknown Product',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Price
                        Text(
                          '₹${productData!['price']?.toString() ?? '0'}',
                          style: const TextStyle(
                            fontSize: 20,
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Seller Info with button to view profile
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Seller: ${productData!['seller']?['userName'] ?? 'Unknown'}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            ElevatedButton(
                              onPressed: _viewSellerProfile,
                              child: const Text('View Seller'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Date posted
                        if (productData!['createdAt'] != null)
                          Text(
                            'Posted on: ${_formatDate(productData!['createdAt'])}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        const SizedBox(height: 16),
                        // Status info
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _getStatusColor(productData!['status']),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            productData!['status']?.toUpperCase() ?? 'AVAILABLE',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
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
                          productData!['description'] ?? 'No description available',
                          style: const TextStyle(fontSize: 16),
                        ),
                        
                        // Reports section
                        if (productReports.isNotEmpty) ...[
                          const SizedBox(height: 32),
                          const Text(
                            'Reports:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...productReports.map<Widget>((report) => _buildReportItem(report)).toList(),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
          // Loading overlay
          if (isPerformingAction)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
      bottomNavigationBar: !isLoading && !isError && productData != null
        ? Container(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _deleteProduct,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                'Delete Product',
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
          )
        : null,
    );
  }

  Widget _buildImageCarousel() {
    final images = _buildImageSlides();
    
    if (images.isEmpty) {
      return Container(
        height: 200,
        color: Colors.grey.shade200,
        child: const Center(
          child: Icon(Icons.image_not_supported, size: 48, color: Colors.grey),
        ),
      );
    }
    
    return Stack(
      alignment: Alignment.center,
      children: [
        CarouselSlider(
          carouselController: _carouselController,
          items: images,
          options: CarouselOptions(
            height: 300,
            viewportFraction: 1.0,
            enableInfiniteScroll: false,
            onPageChanged: (index, reason) {
              setState(() {
                _currentImageIndex = index;
              });
            },
          ),
        ),
        // Left Arrow
        if (_currentImageIndex > 0)
          Positioned(
            left: 10,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(24),
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios,
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: () {
                  _carouselController.previousPage();
                },
              ),
            ),
          ),
        // Right Arrow
        if (_currentImageIndex < images.length - 1)
          Positioned(
            right: 10,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(24),
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: () {
                  _carouselController.nextPage();
                },
              ),
            ),
          ),
        // Page indicator
        Positioned(
          bottom: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: images.asMap().entries.map((entry) {
                return Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(
                      _currentImageIndex == entry.key ? 0.9 : 0.4
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'available':
        return Colors.green;
      case 'sold':
        return Colors.blue;
      case 'reserved':
        return Colors.orange;
      case 'removed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
