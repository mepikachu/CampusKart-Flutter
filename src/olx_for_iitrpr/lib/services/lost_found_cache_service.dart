import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LostFoundCacheService {
  static const _storage = FlutterSecureStorage();
  static const _cacheLifetime = Duration(minutes: 10);
  
  // Memory cache
  static final Map<String, Uint8List> _mainImages = {};
  static final Map<String, List<Uint8List>> _allImages = {};
  static final Map<String, Map<String, dynamic>> _items = {};
  static final Map<String, int> _numImages = {};
  static final Map<String, DateTime> _timestamps = {};

  // Keys
  static String _itemKey(String id) => 'lost_item_$id';
  static String _imageKey(String id) => 'lost_image_$id';
  static String _allImagesKey(String id) => 'lost_all_images_$id';
  static String _numImagesKey(String id) => 'lost_num_images_$id';
  static String _timestampKey(String id) => 'lost_timestamp_$id';
  static const String _itemsListKey = 'lost_items_list';

  static Future<void> cacheItems(List<dynamic> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_itemsListKey, jsonEncode(items));
      
      // Cache each item individually
      for (final item in items) {
        if (item != null && item['_id'] != null) {
          await cacheItem(item['_id'], item);
        }
      }
    } catch (e) {
      print('Error caching items: $e');
    }
  }

  static Future<void> cacheItem(String id, Map<String, dynamic> item) async {
    _items[id] = Map<String, dynamic>.from(item);
    _timestamps[id] = DateTime.now();
    await _storage.write(key: _itemKey(id), value: jsonEncode(item));
    await _storage.write(key: _timestampKey(id), value: DateTime.now().toIso8601String());
  }

  static Future<void> cacheImage(String id, Uint8List bytes, int numImages) async {
    _mainImages[id] = bytes;
    _numImages[id] = numImages;
    _timestamps[id] = DateTime.now();
    await _storage.write(key: _imageKey(id), value: base64Encode(bytes));
    await _storage.write(key: _numImagesKey(id), value: numImages.toString());
    await _storage.write(key: _timestampKey(id), value: DateTime.now().toIso8601String());
  }

  static Future<void> cacheAllImages(String id, List<Uint8List> images) async {
    _allImages[id] = List<Uint8List>.from(images);
    _numImages[id] = images.length;
    _timestamps[id] = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_allImagesKey(id), images.map((e) => base64Encode(e)).toList());
    await _storage.write(key: _numImagesKey(id), value: images.length.toString());
    await _storage.write(key: _timestampKey(id), value: DateTime.now().toIso8601String());
  }

  static Future<void> cacheNumImages(String id, int numImages) async {
    _numImages[id] = numImages;
    _timestamps[id] = DateTime.now();
    await _storage.write(key: _numImagesKey(id), value: numImages.toString());
    await _storage.write(key: _timestampKey(id), value: DateTime.now().toIso8601String());
  }

  static Future<List<dynamic>?> getCachedItems() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_itemsListKey);
    return data != null ? jsonDecode(data) : null;
  }

  static Future<Map<String, dynamic>?> getCachedItem(String id) async {
    if (_items.containsKey(id) && _isCacheValid(id)) return _items[id];
    
    final timestamp = await _storage.read(key: _timestampKey(id));
    if (timestamp == null || DateTime.now().difference(DateTime.parse(timestamp)) > _cacheLifetime) return null;
    
    final data = await _storage.read(key: _itemKey(id));
    if (data == null) return null;
    
    final item = jsonDecode(data);
    _items[id] = Map<String, dynamic>.from(item);
    return item;
  }

  static Future<Uint8List?> getCachedImage(String id) async {
    if (_mainImages.containsKey(id) && _isCacheValid(id)) return _mainImages[id];
    
    final timestamp = await _storage.read(key: _timestampKey(id));
    if (timestamp == null || DateTime.now().difference(DateTime.parse(timestamp)) > _cacheLifetime) return null;
    
    final data = await _storage.read(key: _imageKey(id));
    if (data == null) return null;
    
    final bytes = base64Decode(data);
    _mainImages[id] = bytes;
    return bytes;
  }

  static Future<List<Uint8List>?> getCachedAllImages(String id) async {
    if (_allImages.containsKey(id) && _isCacheValid(id)) return _allImages[id];
    
    final timestamp = await _storage.read(key: _timestampKey(id));
    if (timestamp == null || DateTime.now().difference(DateTime.parse(timestamp)) > _cacheLifetime) return null;
    
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_allImagesKey(id));
    if (data == null) return null;
    
    final images = data.map((e) => base64Decode(e)).toList();
    _allImages[id] = images;
    return images;
  }

  static Future<int?> getCachedNumImages(String id) async {
    if (_numImages.containsKey(id) && _isCacheValid(id)) return _numImages[id];
    
    final data = await _storage.read(key: _numImagesKey(id));
    return data != null ? int.tryParse(data) : null;
  }

  static Future<void> clearCache(String id) async {
    _items.remove(id);
    _mainImages.remove(id);
    _allImages.remove(id);
    _numImages.remove(id);
    _timestamps.remove(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_allImagesKey(id));
    await _storage.delete(key: _itemKey(id));
    await _storage.delete(key: _imageKey(id));
    await _storage.delete(key: _numImagesKey(id));
    await _storage.delete(key: _timestampKey(id));
  }

  static bool _isCacheValid(String id) {
    return _timestamps.containsKey(id) && 
      DateTime.now().difference(_timestamps[id]!) <= _cacheLifetime;
  }
}
