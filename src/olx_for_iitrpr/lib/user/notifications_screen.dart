import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'my_purchases.dart';
import 'product_description.dart';
import 'product_management.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  _NotificationsScreenState createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<dynamic> notifications = [];
  bool isLoading = true;
  String? error;
  String selectedFilter = 'all';

  final List<Map<String, dynamic>> filterOptions = [
    {'value': 'all', 'label': 'All Notifications'},
    {'value': 'offer_accepted', 'label': 'Accepted Offers'},
    {'value': 'offer_rejected', 'label': 'Rejected Offers'},
    {'value': 'new_offer', 'label': 'New Offers'},
    {'value': 'product_updated', 'label': 'Product Updates'},
  ];

  List<dynamic> get filteredNotifications {
    if (selectedFilter == 'all') return notifications;
    if (selectedFilter == 'new_offer') {
      return notifications.where((notification) => 
        notification['type'] == 'offer_received' ||
        notification['type'] == 'received_offer' ||
        notification['type'] == 'new_offer'
      ).toList();
    }
    return notifications.where((notification) => 
      notification['type'] == selectedFilter
    ).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final notificationsJson = await _secureStorage.read(key: 'notifications');
      
      if (mounted) {
        setState(() {
          if (notificationsJson != null) {
            notifications = json.decode(notificationsJson);
          }
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Error: ${error ?? 'Failed to load notifications'}',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadNotifications,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: filterOptions.map((filter) => 
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      selected: selectedFilter == filter['value'],
                      label: Text(filter['label']),
                      onSelected: (bool selected) {
                        setState(() {
                          selectedFilter = filter['value'];
                        });
                      },
                    ),
                  )
                ).toList(),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadNotifications,
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : error != null
                      ? _buildErrorWidget()
                      : filteredNotifications.isEmpty
                          ? const Center(
                              child: Text(
                                'No notifications',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredNotifications.length,
                              itemBuilder: (context, index) {
                                final notification = filteredNotifications[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  child: ListTile(
                                    leading: Icon(
                                      _getNotificationIcon(notification['type']),
                                      color: _getNotificationColor(notification['type']),
                                      size: 28,
                                    ),
                                    title: Text(
                                      notification['message'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    subtitle: Text(
                                      DateTime.parse(notification['createdAt'])
                                          .toLocal()
                                          .toString()
                                          .split('.')[0],
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    onTap: () async {
                                      switch (notification['type']) {
                                        case 'offer_accepted':
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => const MyPurchasesPage(),
                                            ),
                                          );
                                          break;
                                        
                                        case 'new_offer':
                                        case 'offer_received':
                                        case 'received_offer':
                                          if (notification['productId'] != null) {
                                            try {
                                              final authCookie = await _secureStorage.read(key: 'authCookie');
                                              
                                              // First, check if the offer is still valid
                                              final offerResponse = await http.get(
                                                Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/offers/${notification['offerId']}'),
                                                headers: {
                                                  'Content-Type': 'application/json',
                                                  'auth-cookie': authCookie ?? '',
                                                },
                                              );

                                              if (offerResponse.statusCode == 200) {
                                                final offerData = json.decode(offerResponse.body);
                                                
                                                if (!offerData['valid']) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      content: Text('This offer has expired'),
                                                      backgroundColor: Colors.orange,
                                                    ),
                                                  );
                                                  return;
                                                }

                                                // Then check the product status
                                                final productResponse = await http.get(
                                                  Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/products/${notification['productId']}'),
                                                  headers: {
                                                    'Content-Type': 'application/json',
                                                    'auth-cookie': authCookie ?? '',
                                                  },
                                                );

                                                if (productResponse.statusCode == 200) {
                                                  final productData = json.decode(productResponse.body);
                                                  
                                                  if (productData['success'] && mounted) {
                                                    if (productData['product']['status'] == 'available') {
                                                      // Navigate to product management if both product and offer are valid
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (context) => SellerOfferManagementScreen(
                                                            product: productData['product'],
                                                          ),
                                                        ),
                                                      );
                                                    } else {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(
                                                          content: Text('This product is no longer available'),
                                                          backgroundColor: Colors.red,
                                                        ),
                                                      );
                                                    }
                                                  }
                                                }
                                              }
                                            } catch (e) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Error loading details'),
                                                  backgroundColor: Colors.red,
                                                ),
                                              );
                                            }
                                          }
                                          break;

                                        case 'offer_rejected':
                                        case 'product_updated':
                                          if (notification['productId'] != null) {
                                            try {
                                              final authCookie = await _secureStorage.read(key: 'authCookie');
                                              final response = await http.get(
                                                Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/products/${notification['productId']}'),
                                                headers: {
                                                  'Content-Type': 'application/json',
                                                  'auth-cookie': authCookie ?? '',
                                                },
                                              );

                                              if (response.statusCode == 200) {
                                                final productData = json.decode(response.body);
                                                if (productData['success'] && mounted) {
                                                  if (productData['product']['status'] == 'available') {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) => ProductDetailsScreen(
                                                          product: productData['product'],
                                                        ),
                                                      ),
                                                    );
                                                  } else {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(
                                                        content: Text('This product is no longer available'),
                                                        duration: Duration(seconds: 2),
                                                        backgroundColor: Colors.red,
                                                      ),
                                                    );
                                                  }
                                                }
                                              }
                                            } catch (e) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Error loading product details'),
                                                  backgroundColor: Colors.red,
                                                ),
                                              );
                                            }
                                          }
                                          break;
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'offer_accepted':
        return Icons.check_circle;
      case 'offer_rejected':
        return Icons.cancel;
      case 'offer_received':
      case 'received_offer':
      case 'new_offer':
        return Icons.local_offer;
      case 'product_updated':
        return Icons.update;
      default:
        return Icons.notifications;
    }
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'offer_accepted':
        return Colors.green;
      case 'offer_rejected':
        return Colors.red;
      case 'offer_received':
      case 'received_offer':
      case 'new_offer':
        return Colors.orange;
      case 'product_updated':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}
