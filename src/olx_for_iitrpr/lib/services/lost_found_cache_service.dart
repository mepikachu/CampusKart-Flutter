import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for caching lost and found item data and images to improve loading times
class LostFoundCacheService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const Duration _cacheLifetime = Duration(minutes: 10);

  // In-memory cache
  static final Map<String, Uint8List> _mainImageCache = {};
  static final Map<String, List<Uint8List>> _allImagesCache = {};
  static final Map<String, Map<String, dynamic>> _itemCache = {};
  static final Map<String, int> _numImagesCache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};

  // Cache keys
  static String _itemKey(String id) => 'lost_item_$id';
  static String _imageKey(String id) => 'lost_image_$id';
  static String _allImagesKey(String id) => 'lost_all_images_$id';
  static String _numImagesKey(String id) => 'lost_num_images_$id';
  static String _timestampKey(String id) => 'lost_timestamp_$id';
  static const String _itemsListKey = 'lost_items_list';

  /// Cache a single lost item
  static Future<void> cacheItem(String id, Map<String, dynamic> item) async {
    try {
      // Store in memory
      _itemCache[id] = Map.from(item);
      _cacheTimestamps[id] = DateTime.now();
      
      // Store in secure storage
      await _secureStorage.write(key: _itemKey(id), value: jsonEncode(item));
      await _secureStorage.write(key: _timestampKey(id), value: DateTime.now().toIso8601String());
    } catch (e) {
      print('Error caching lost item: $e');
    }
  }

  /// Cache a list of lost items
  static Future<void> cacheItems(List<dynamic> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_itemsListKey, jsonEncode(items));
      
      for (var item in items) {
        if (item != null && item['_id'] != null) {
          await cacheItem(item['_id'], item);
        }
      }
    } catch (e) {
      print('Error caching lost items: $e');
    }
  }

  /// Cache a single image (main image)
  static Future<void> cacheImage(String id, Uint8List imageBytes, int numImages) async {
    try {
      // Store in memory
      _mainImageCache[id] = imageBytes;
      _numImagesCache[id] = numImages;
      _cacheTimestamps[id] = DateTime.now();
      
      // Store in secure storage
      final String base64Image = base64Encode(imageBytes);
      await _secureStorage.write(key: _imageKey(id), value: base64Image);
      await _secureStorage.write(key: _numImagesKey(id), value: numImages.toString());
      await _secureStorage.write(key: _timestampKey(id), value: DateTime.now().toIso8601String());
    } catch (e) {
      print('Error caching lost item image: $e');
    }
  }

  /// Cache all images for a lost item
  static Future<void> cacheAllImages(String id, List<Uint8List> images) async {
    try {
      // Store in memory
      _allImagesCache[id] = List.from(images);
      _numImagesCache[id] = images.length;
      _cacheTimestamps[id] = DateTime.now();
      
      // Convert to base64 for storage
      final List<String> base64Images = images.map((e) => base64Encode(e)).toList();
      
      // Use SharedPreferences for larger data
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_allImagesKey(id), base64Images);
      
      // Store timestamp and number of images in secure storage
      await _secureStorage.write(key: _numImagesKey(id), value: images.length.toString());
      await _secureStorage.write(key: _timestampKey(id), value: DateTime.now().toIso8601String());
    } catch (e) {
      print('Error caching all lost item images: $e');
    }
  }

  /// Store number of images
  static Future<void> cacheNumImages(String id, int numImages) async {
    try {
      _numImagesCache[id] = numImages;
      await _secureStorage.write(key: _numImagesKey(id), value: numImages.toString());
    } catch (e) {
      print('Error caching num images: $e');
    }
  }

  /// Get cached lost items list
  static Future<List<dynamic>?> getCachedItems() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonData = prefs.getString(_itemsListKey);
      if (jsonData == null) return null;
      return jsonDecode(jsonData);
    } catch (e) {
      print('Error getting cached lost items: $e');
      return null;
    }
  }

  /// Get a cached lost item
  static Future<Map<String, dynamic>?> getCachedItem(String id) async {
    try {
      // Check memory cache first
      if (_itemCache.containsKey(id)) {
        final timestamp = _cacheTimestamps[id];
        if (timestamp != null && DateTime.now().difference(timestamp) <= _cacheLifetime) {
          return _itemCache[id];
        }
      }
      
      // Check secure storage
      final timestampStr = await _secureStorage.read(key: _timestampKey(id));
      if (timestampStr == null) return null;
      
      final timestamp = DateTime.parse(timestampStr);
      if (DateTime.now().difference(timestamp) > _cacheLifetime) {
        // Cache expired
        await _clearItemCache(id);
        return null;
      }
      
      final jsonData = await _secureStorage.read(key: _itemKey(id));
      if (jsonData == null) return null;
      
      final item = jsonDecode(jsonData);
      
      // Update memory cache
      _itemCache[id] = Map<String, dynamic>.from(item);
      _cacheTimestamps[id] = DateTime.now();
      
      return item;
    } catch (e) {
      print('Error getting cached lost item: $e');
      return null;
    }
  }

  /// Get cached image
  static Future<Uint8List?> getCachedImage(String id) async {
    try {
      // Check memory cache first
      if (_mainImageCache.containsKey(id)) {
        final timestamp = _cacheTimestamps[id];
        if (timestamp != null && DateTime.now().difference(timestamp) <= _cacheLifetime) {
          return _mainImageCache[id];
        }
      }
      
      // Check secure storage
      final timestampStr = await _secureStorage.read(key: _timestampKey(id));
      if (timestampStr == null) return null;
      
      final timestamp = DateTime.parse(timestampStr);
      if (DateTime.now().difference(timestamp) > _cacheLifetime) {
        // Cache expired
        await _clearImageCache(id);
        return null;
      }
      
      final base64Image = await _secureStorage.read(key: _imageKey(id));
      if (base64Image == null) return null;
      
      final imageBytes = base64Decode(base64Image);
      
      // Update memory cache
      _mainImageCache[id] = imageBytes;
      _cacheTimestamps[id] = DateTime.now();
      
      return imageBytes;
    } catch (e) {
      print('Error getting cached lost item image: $e');
      return null;
    }
  }

  /// Get all cached images
  static Future<List<Uint8List>?> getCachedAllImages(String id) async {
    try {
      // Check memory cache first
      if (_allImagesCache.containsKey(id)) {
        final timestamp = _cacheTimestamps[id];
        if (timestamp != null && DateTime.now().difference(timestamp) <= _cacheLifetime) {
          return _allImagesCache[id];
        }
      }
      
      // Check storage
      final timestampStr = await _secureStorage.read(key: _timestampKey(id));
      if (timestampStr == null) return null;
      
      final timestamp = DateTime.parse(timestampStr);
      if (DateTime.now().difference(timestamp) > _cacheLifetime) {
        // Cache expired
        await _clearImageCache(id);
        return null;
      }
      
      // Get from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final List<String>? base64Images = prefs.getStringList(_allImagesKey(id));
      if (base64Images == null || base64Images.isEmpty) return null;
      
      final List<Uint8List> images = base64Images.map((e) => base64Decode(e)).toList();
      
      // Update memory cache
      _allImagesCache[id] = List.from(images);
      _cacheTimestamps[id] = DateTime.now();
      
      return images;
    } catch (e) {
      print('Error getting all cached lost item images: $e');
      return null;
    }
  }

  /// Get cached number of images
  static Future<int?> getCachedNumImages(String id) async {
    try {
      // Check memory cache first
      if (_numImagesCache.containsKey(id)) {
        return _numImagesCache[id];
      }
      
      // Check secure storage
      final numImagesStr = await _secureStorage.read(key: _numImagesKey(id));
      if (numImagesStr == null) return null;
      
      final numImages = int.tryParse(numImagesStr);
      if (numImages != null) {
        _numImagesCache[id] = numImages;
      }
      
      return numImages;
    } catch (e) {
      print('Error getting cached num images: $e');
      return null;
    }
  }

  /// Check if cache is still valid
  static bool isCacheValid(String id) {
    return _cacheTimestamps.containsKey(id) && 
           DateTime.now().difference(_cacheTimestamps[id]!) <= _cacheLifetime;
  }

  /// Clear item cache
  static Future<void> _clearItemCache(String id) async {
    try {
      await _secureStorage.delete(key: _itemKey(id));
      await _secureStorage.delete(key: _timestampKey(id));
      _itemCache.remove(id);
      _cacheTimestamps.remove(id);
    } catch (e) {
      print('Error clearing lost item cache: $e');
    }
  }

  /// Clear image cache
  static Future<void> _clearImageCache(String id) async {
    try {
      await _secureStorage.delete(key: _imageKey(id));
      await _secureStorage.delete(key: _numImagesKey(id));
      await _secureStorage.delete(key: _timestampKey(id));
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_allImagesKey(id));
      
      _mainImageCache.remove(id);
      _allImagesCache.remove(id);
      _numImagesCache.remove(id);
    } catch (e) {
      print('Error clearing lost item image cache: $e');
    }
  }

  /// Clear specific lost item's cache
  static Future<void> clearCache(String id) async {
    try {
      await _clearItemCache(id);
      await _clearImageCache(id);
    } catch (e) {
      print('Error clearing lost item cache: $e');
    }
  }

  /// Clear all caches
  static Future<void> clearAllCaches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_itemsListKey);
      
      // Clear all memory caches
      _mainImageCache.clear();
      _allImagesCache.clear();
      _itemCache.clear();
      _numImagesCache.clear();
      _cacheTimestamps.clear();
    } catch (e) {
      print('Error clearing all lost item caches: $e');
    }
  }
}
