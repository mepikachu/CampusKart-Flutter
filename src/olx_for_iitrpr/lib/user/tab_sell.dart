import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

class SellTab extends StatefulWidget {
  const SellTab({super.key});

  @override
  State<SellTab> createState() => _SellTabState();
}

class _SellTabState extends State<SellTab> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  String _selectedCategory = 'electronics';
  List<File> _images = [];
  bool _isLoading = false;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  final List<String> _categories = ['electronics', 'furniture', 'books', 'clothing', 'others'];

  // Updated Material Design 3 inspired colors
  static const primaryColor = Color(0xFF1A73E8);
  static const surfaceColor = Color(0xFFFFFFFF); // Changed to pure white
  static const backgroundColor = Color(0xFFFFFFFF);
  static const outlineColor = Color(0xFFE1E3E6);
  static const textPrimaryColor = Color(0xFF202124);
  static const textSecondaryColor = Color(0xFF5F6368);

  Future<File?> _compressImage(File file) async {
    try {
      final String tempPath = (await getTemporaryDirectory()).path;
      final String targetPath = '$tempPath/${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      // Read the image as bytes
      final bytes = await file.readAsBytes();
      
      // Write to new file
      final File targetFile = File(targetPath);
      await targetFile.writeAsBytes(bytes);
      
      return targetFile;
    } catch (e) {
      print('Image compression error: $e');
      return null;
    }
  }

  Future<void> _pickImages() async {
    if (_images.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 5 images allowed')),
      );
      return;
    }

    try {
      final ImagePicker picker = ImagePicker();
      final List<XFile>? pickedFiles = await picker.pickMultiImage();
      
      if (pickedFiles != null) {
        for (var xFile in pickedFiles) {
          if (_images.length >= 5) break;
          
          File originalFile = File(xFile.path);
          File? processedFile = await _compressImage(originalFile);
          
          if (processedFile != null) {
            setState(() {
              _images.add(processedFile);
            });
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error selecting images: ${e.toString()}')),
      );
    }
  }

  // Submits the product using a multipart POST request
  Future<void> _submitProduct() async {
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
      if (authCookie == null) throw Exception("Not authenticated");

      final uri = Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/products');
      var request = http.MultipartRequest('POST', uri);
      request.headers['auth-cookie'] = authCookie;

      // Add form fields
      request.fields.addAll({
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'price': _priceController.text.trim(),
        'category': _selectedCategory,
      });

      // Add images
      for (var image in _images) {
        final stream = http.ByteStream(image.openRead());
        final length = await image.length();
        request.files.add(http.MultipartFile(
          'images',
          stream,
          length,
          filename: image.path.split('/').last,
          contentType: MediaType('image', 'jpeg'),
        ));
      }

      final response = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('Request timed out'),
      );

      final responseData = await response.stream.bytesToString();
      final jsonResponse = json.decode(responseData);

      if (response.statusCode == 201) {
        _clearForm();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product added successfully')),
        );
      } else {
        throw Exception(jsonResponse['error'] ?? 'Failed to add product');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _clearForm() {
    setState(() {
      _nameController.clear();
      _descriptionController.clear();
      _priceController.clear();
      _images = [];
      _selectedCategory = 'electronics';
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
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
            'Product Images',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: textPrimaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add up to 5 images',
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
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Center the product images section
                    Center(child: _buildImagePreviews()),
                    const SizedBox(height: 24),
                    // ... existing TextFormFields with updated decoration ...
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: "Product Name",
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
                          (value?.isEmpty ?? true) ? "Enter product name" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        labelText: "Description",
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
                          (value?.isEmpty ?? true) ? "Enter description" : null,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _priceController,
                            decoration: InputDecoration(
                              labelText: "Price",
                              prefixText: '₹ ',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: outlineColor),
                              ),
                              filled: true,
                              fillColor: surfaceColor,
                              labelStyle: TextStyle(color: textSecondaryColor),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) => 
                                (value?.isEmpty ?? true) ? "Enter price" : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            value: _selectedCategory,
                            decoration: InputDecoration(
                              labelText: "Category",
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: outlineColor),
                              ),
                              filled: true,
                              fillColor: surfaceColor,
                              labelStyle: TextStyle(color: textSecondaryColor),
                            ),
                            items: _categories.map((cat) {
                              return DropdownMenuItem(
                                value: cat,
                                child: Text(
                                  cat[0].toUpperCase() + cat.substring(1),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _selectedCategory = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    // List for Sale button at the bottom of content
                    Container(
                      width: double.infinity,
                      height: 54,
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submitProduct,
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
                            : const Text(
                                'List for Sale',
                                style: TextStyle(
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
            ],
          ),
        ),
      ),
    );
  }
}
