import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'view_profile.dart';

class DonationLabels {
  final String imagesSectionTitle;
  final String imagesSubtitle;
  final String nameLabel;
  final String nameHint;
  final String descriptionLabel;
  final String descriptionHint;
  final String submitButtonText;

  const DonationLabels({
    this.imagesSectionTitle = 'Product Images',
    this.imagesSubtitle = 'Add up to 5 images',
    this.nameLabel = 'Item Name',
    this.nameHint = 'Enter item name',
    this.descriptionLabel = 'Description',
    this.descriptionHint = 'Enter description',
    this.submitButtonText = 'Submit Donation',
  });
}

class DonationsTab extends StatefulWidget {
  final bool showLeaderboard;
  final DonationLabels labels;
  
  const DonationsTab({
    super.key, 
    this.showLeaderboard = true,
    this.labels = const DonationLabels(),
  });

  @override
  State<DonationsTab> createState() => _DonationsTabState();
}

class _DonationsTabState extends State<DonationsTab> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<File> _images = [];
  bool _isLoading = false;
  bool _isLoadingLeaderboard = true;
  List<dynamic> _donorsLeaderboard = [];
  List<dynamic> _volunteersLeaderboard = [];
  String _errorMessage = '';

  static const primaryColor = Color(0xFF1A73E8);
  static const surfaceColor = Color(0xFFFFFFFF); // Changed to pure white
  static const backgroundColor = Color(0xFFFFFFFF);
  static const outlineColor = Color(0xFFE1E3E6);
  static const textPrimaryColor = Color(0xFF202124);
  static const textSecondaryColor = Color(0xFF5F6368);

  @override
  void initState() {
    super.initState();
    _fetchLeaderboard();
  }

  Future<void> _fetchLeaderboard() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/donations/leaderboard'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          _donorsLeaderboard = data['donors'];
          _volunteersLeaderboard = data['volunteers'];
          _isLoadingLeaderboard = false;
        });
      } else {
        throw Exception(data['error'] ?? 'Failed to load leaderboard');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoadingLeaderboard = false;
      });
    }
  }

  Future<void> _pickImages() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile>? pickedFiles = await picker.pickMultiImage();
    
    if (pickedFiles != null && pickedFiles.isNotEmpty) {
      setState(() {
        _images.addAll(pickedFiles.map((xfile) => File(xfile.path)));
        if (_images.length > 5) {
          _images = _images.sublist(0, 5);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maximum 5 images allowed')),
          );
        }
      });
    }
  }

  Future<void> _submitDonation() async {
    if (!_formKey.currentState!.validate()) return;
    if (_images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select at least one image")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final uri = Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/donations');
      var request = http.MultipartRequest('POST', uri)
        ..headers['auth-cookie'] = authCookie ?? '';

      request.fields['name'] = _nameController.text.trim();
      request.fields['description'] = _descriptionController.text.trim();

      for (File image in _images) {
        request.files.add(await http.MultipartFile.fromPath('images', image.path));
      }

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 201) {
        final resData = json.decode(responseBody);
        if (resData['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Donation submitted successfully")),
          );
          _nameController.clear();
          _descriptionController.clear();
          setState(() {
            _images.clear();
          });
          _fetchLeaderboard(); // Refresh leaderboard
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildLeaderboardSection(String title, List<dynamic> leaderboard, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: textPrimaryColor,
          ),
        ),
        const SizedBox(height: 16),
        ...List.generate(5, (index) {
          final bool hasData = index < leaderboard.length;
          final user = hasData ? leaderboard[index] : null;
          
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              onTap: hasData ? () {
                // Navigate to profile view when user is clicked
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ViewProfileScreen(userId: user['_id']),
                  ),
                );
              } : null,
              leading: CircleAvatar(
                backgroundColor: hasData ? color.withOpacity(0.2) : Colors.grey[200],
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: hasData ? color : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                hasData ? (user['userName'] ?? 'Unknown') : '--------------',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: hasData ? textPrimaryColor : Colors.grey,
                ),
              ),
              trailing: hasData
                  ? Text(
                      '${user['totalDonations']} ${title == 'Top Donors' ? 'donations' : 'collected'}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : Text(
                      '0 ${title == 'Top Donors' ? 'donations' : 'collected'}',
                      style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildLeaderboard() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildLeaderboardSection('Top Donors', _donorsLeaderboard, Colors.blue[700]!),
        const SizedBox(height: 24),
        _buildLeaderboardSection('Top Volunteers', _volunteersLeaderboard, Colors.green[700]!),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showLeaderboard) {
      // Only show the donation form when showLeaderboard is false
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Center(child: _buildImagePreviews()),
                const SizedBox(height: 24),
                // ... rest of the donation form fields ...
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: widget.labels.nameLabel,
                    hintText: widget.labels.nameHint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: outlineColor),
                    ),
                    // ...existing decoration properties...
                  ),
                  validator: (value) =>
                      value?.isEmpty ?? true ? "Enter item name" : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: widget.labels.descriptionLabel,
                    hintText: widget.labels.descriptionHint,
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: outlineColor),
                    ),
                    // ...existing decoration properties...
                  ),
                  maxLines: null,
                  minLines: 3,
                  // ...existing properties...
                ),
                const SizedBox(height: 32),
                Container(
                  width: double.infinity,
                  height: 54,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitDonation,
                    style: ElevatedButton.styleFrom(
                      // ...existing style properties...
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            widget.labels.submitButtonText,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Original tab view with leaderboard
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Leaderboard'),
              Tab(text: 'Make Donation'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                // Leaderboard Tab
                _isLoadingLeaderboard
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage.isNotEmpty
                        ? Center(child: Text('Error: $_errorMessage'))
                        : RefreshIndicator(
                            onRefresh: _fetchLeaderboard,
                            child: _buildLeaderboard(),
                          ),

                // Make Donation Tab - Similar to SellTab
                SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Center(child: _buildImagePreviews()),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: widget.labels.nameLabel,
                              hintText: widget.labels.nameHint,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: outlineColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: outlineColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: primaryColor, width: 2),
                              ),
                              filled: true,
                              fillColor: surfaceColor,
                              labelStyle: TextStyle(color: textSecondaryColor),
                            ),
                            validator: (value) =>
                                value?.isEmpty ?? true ? "Enter item name" : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _descriptionController,
                            decoration: InputDecoration(
                              labelText: widget.labels.descriptionLabel,
                              hintText: widget.labels.descriptionHint,
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: outlineColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: outlineColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: primaryColor, width: 2),
                              ),
                              filled: true,
                              fillColor: surfaceColor,
                              labelStyle: TextStyle(color: textSecondaryColor),
                            ),
                            maxLines: null,
                            minLines: 3,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            validator: (value) =>
                                value?.isEmpty ?? true ? "Enter description" : null,
                          ),
                          const SizedBox(height: 32),
                          Container(
                            width: double.infinity,
                            height: 54,
                            margin: const EdgeInsets.only(bottom: 16),
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _submitDonation,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2E7D32),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : Text(
                                      widget.labels.submitButtonText,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreviews() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: outlineColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.labels.imagesSectionTitle,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: textPrimaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.labels.imagesSubtitle,
            style: TextStyle(
              fontSize: 14,
              color: textSecondaryColor,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            height: 120,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _images.length + (_images.length < 5 ? 1 : 0),
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (oldIndex < _images.length && newIndex <= _images.length) {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final File item = _images.removeAt(oldIndex);
                    _images.insert(newIndex, item);
                  }
                });
              },
              itemBuilder: (context, index) {
                if (index == _images.length) {
                  return Container(
                    key: const ValueKey('add_image'),
                    width: 120,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: outlineColor),
                    ),
                    child: InkWell(
                      onTap: _pickImages,
                      borderRadius: BorderRadius.circular(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: surfaceColor,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.add_photo_alternate_rounded,
                              color: primaryColor,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add Image',
                            style: TextStyle(
                              color: primaryColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Container(
                  key: ValueKey(_images[index]),
                  width: 120,
                  margin: const EdgeInsets.only(right: 12),
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            _images[index],
                            height: 120,
                            width: 120,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            shape: BoxShape.circle,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => setState(() => _images.removeAt(index)),
                              customBorder: const CircleBorder(),
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (index == 0)
                        Positioned(
                          bottom: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: primaryColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'MAIN',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}
