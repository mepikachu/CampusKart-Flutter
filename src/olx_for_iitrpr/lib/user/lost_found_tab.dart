import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'lost_item_details.dart';  // Add this import

class LostFoundTab extends StatefulWidget {
  const LostFoundTab({super.key});

  @override
  State<LostFoundTab> createState() => _LostFoundTabState();
}

class _LostFoundTabState extends State<LostFoundTab> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<dynamic> lostItems = [];
  bool isLoading = true;
  String? errorMessage;
  
  @override
  void initState() {
    super.initState();
    fetchLostItems();
  }

  Future<void> fetchLostItems() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      // First get the current user's data
      final userResponse = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/me'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (userResponse.statusCode != 200) {
        throw Exception('Failed to get user data');
      }

      final userData = json.decode(userResponse.body);
      final currentUserId = userData['user']['_id'];

      // Then fetch lost items
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/lost-items'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            // Filter out items posted by the current user
            lostItems = (data['items'] as List).where((item) => 
              item['user']['_id'] != currentUserId
            ).toList();
            isLoading = false;
          });
        } else {
          throw Exception(data['error']);
        }
      } else {
        throw Exception('Failed to load lost items');
      }
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Widget buildLostItemCard(dynamic item) {
    List<dynamic> imagesList = item['images'] ?? [];
    Widget imageWidget;

    if (imagesList.isNotEmpty && imagesList[0] is Map && imagesList[0]['data'] != null) {
      try {
        final String base64Str = imagesList[0]['data'];
        final Uint8List bytes = base64Decode(base64Str);
        imageWidget = Image.memory(
          bytes,
          fit: BoxFit.cover,
          height: 200,
          width: double.infinity,
        );
      } catch (e) {
        imageWidget = Container(
          color: Colors.grey[300],
          height: 200,
          child: const Center(child: Text('Error loading image')),
        );
      }
    } else {
      imageWidget = Container(
        color: Colors.grey[300],
        height: 200,
        child: const Center(child: Text('No image')),
      );
    }

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LostItemDetailsScreen(item: item),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: imageWidget,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item['name'] ?? 'Unnamed Item',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: item['status'] == 'found' ? Colors.green[100] : Colors.orange[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          item['status']?.toUpperCase() ?? 'LOST',
                          style: TextStyle(
                            color: item['status'] == 'found' ? Colors.green[700] : Colors.orange[700],
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item['description'] ?? 'No description',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Posted by ${item['user']?['userName'] ?? 'Unknown'}',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _formatDate(item['createdAt']),
                        style: TextStyle(
                          color: Colors.grey[600],
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
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    final date = DateTime.parse(dateString);
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (errorMessage != null) {
      return Center(child: Text('Error: $errorMessage'));
    }

    if (lostItems.isEmpty) {
      return const Center(child: Text('No lost items reported'));
    }

    return RefreshIndicator(
      onRefresh: fetchLostItems,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: lostItems.length,
        itemBuilder: (context, index) => buildLostItemCard(lostItems[index]),
      ),
    );
  }
}
