import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'server.dart';
import '../utils/image_processor.dart';

class AddLostItemScreen extends StatefulWidget {
  const AddLostItemScreen({super.key});

  @override
  State<AddLostItemScreen> createState() => _AddLostItemScreenState();
}

class _AddLostItemScreenState extends State<AddLostItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _lastSeenLocationController = TextEditingController();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<File> _images = [];
  bool _isLoading = false;

  static const primaryColor = Color(0xFF1A73E8);
  static const surfaceColor = Color(0xFFFFFFFF);
  static const backgroundColor = Color(0xFFFFFFFF);
  static const outlineColor = Color(0xFFE1E3E6);
  static const textPrimaryColor = Color(0xFF202124);
  static const textSecondaryColor = Color(0xFF5F6368);

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

  Future<void> _submitLostItem() async {
    if (!_formKey.currentState!.validate()) return;
    if (_images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select at least one image")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final compressedImages = await ImageProcessor.compressImages(_images);
      
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final uri = Uri.parse('$serverUrl/api/lost-items');
      var request = http.MultipartRequest('POST', uri)
        ..headers['auth-cookie'] = authCookie ?? '';

      request.fields['name'] = _nameController.text.trim();
      request.fields['description'] = _descriptionController.text.trim();
      request.fields['lastSeenLocation'] = _lastSeenLocationController.text.trim();

      for (File image in compressedImages) {
        request.files.add(await http.MultipartFile.fromPath('images', image.path));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        final resData = json.decode(response.body);
        if (resData['success'] == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Lost item posted successfully")),
            );
            Navigator.pop(context, true);
          }
        } else {
          throw Exception(resData['error'] ?? 'Failed to post lost item');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString()}")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
          const Text(
            'Item Images',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: textPrimaryColor,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add up to 5 images',
            style: TextStyle(
              fontSize: 14,
              color: textSecondaryColor,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
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
                  return _buildAddImageButton();
                }
                return _buildImagePreview(index);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddImageButton() {
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
          children: const [
            Icon(
              Icons.add_photo_alternate_rounded,
              color: primaryColor,
              size: 28,
            ),
            SizedBox(height: 8),
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

  Widget _buildImagePreview(int index) {
    return Container(
      key: ValueKey(_images[index]),
      width: 120,
      margin: const EdgeInsets.only(right: 12),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              _images[index],
              height: 120,
              width: 120,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: _buildDeleteButton(index),
          ),
          if (index == 0) _buildMainLabel(),
        ],
      ),
    );
  }

  Widget _buildDeleteButton(int index) {
    return InkWell(
      onTap: () => setState(() => _images.removeAt(index)),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.close,
          color: Colors.white,
          size: 16,
        ),
      ),
    );
  }

  Widget _buildMainLabel() {
    return Positioned(
      bottom: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Lost Item'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildImagePreviews(),
              const SizedBox(height: 24),
              _buildFormFields(),
              const SizedBox(height: 32),
              _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormFields() {
    return Column(
      children: [
        TextFormField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: 'Item Name',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: outlineColor),
            ),
          ),
          validator: (value) =>
              value?.isEmpty ?? true ? "Enter item name" : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _lastSeenLocationController,
          decoration: InputDecoration(
            labelText: 'Last Seen Location',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: outlineColor),
            ),
          ),
          validator: (value) =>
              value?.isEmpty ?? true ? "Enter last seen location" : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _descriptionController,
          decoration: InputDecoration(
            labelText: 'Description',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: outlineColor),
            ),
          ),
          maxLines: 3,
          validator: (value) =>
              value?.isEmpty ?? true ? "Enter description" : null,
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submitLostItem,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2E7D32),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: _isLoading
            ? const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              )
            : const Text(
                'Report Lost Item',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }
}
