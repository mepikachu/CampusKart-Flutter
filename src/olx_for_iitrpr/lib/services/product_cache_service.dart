import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for caching product data and images to improve loading times
class ProductCacheService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const Duration _cacheLifetime = Duration(minutes: 10);

  // In-memory cache
  static final Map<String, Uint8List> _mainImageCache = {};
  static final Map<String, List<Uint8List>> _allImagesCache = {};
  static final Map<String, Map<String, dynamic>> _productCache = {};
  static final Map<String, int> _numImagesCache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};

  // Cache keys
  static String _productKey(String id) => 'product_$id';
  static String _imageKey(String id) => 'image_$id';
  static String _allImagesKey(String id) => 'all_images_$id';
  static String _numImagesKey(String id) => 'num_images_$id';
  static String _timestampKey(String id) => 'timestamp_$id';
  static String _imageTimestampKey(String id) => 'image_timestamp_$id';
  static const String _productsListKey = 'products_list';

  /// Cache a single product
  static Future<void> cacheProduct(String id, Map<String, dynamic> product) async {
    try {
      // Store in memory
      _productCache[id] = Map.from(product);
      _cacheTimestamps[id] = DateTime.now();
      
      // Store in secure storage
      await _secureStorage.write(key: _productKey(id), value: jsonEncode(product));
      await _secureStorage.write(key: _timestampKey(id), value: DateTime.now().toIso8601String());
    } catch (e) {
      print('Error caching product: $e');
    }
  }

  /// Cache a list of products
  static Future<void> cacheProducts(List<dynamic> products) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_productsListKey, jsonEncode(products));
      
      for (var product in products) {
        if (product != null && product['_id'] != null) {
          await cacheProduct(product['_id'], product);
        }
      }
    } catch (e) {
      print('Error caching products: $e');
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
      await _secureStorage.write(key: _imageTimestampKey(id), value: DateTime.now().toIso8601String());
    } catch (e) {
      print('Error caching image: $e');
    }
  }

  /// Cache all images for a product
  static Future<void> cacheAllImages(String id, List<Uint8List> images) async {
    try {
      // Store in memory
      _allImagesCache[id] = List.from(images);
      _numImagesCache[id] = images.length;
      _cacheTimestamps[id] = DateTime.now();
      
      // Convert to base64 for storage
      final List<String> base64Images = [];
      for (var img in images) {
        base64Images.add(base64Encode(img));
      }
      
      // Use SharedPreferences for larger data
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_allImagesKey(id), base64Images);
      
      // Store timestamp and number of images in secure storage
      await _secureStorage.write(key: _numImagesKey(id), value: images.length.toString());
      await _secureStorage.write(key: _imageTimestampKey(id), value: DateTime.now().toIso8601String());
    } catch (e) {
      print('Error caching all images: $e');
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

  /// Get cached products list
  static Future<List<dynamic>?> getCachedProducts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonData = prefs.getString(_productsListKey);
      if (jsonData == null) return null;
      return jsonDecode(jsonData);
    } catch (e) {
      print('Error getting cached products: $e');
      return null;
    }
  }

  /// Get a cached product
  static Future<Map<String, dynamic>?> getCachedProduct(String id) async {
    try {
      // Check memory cache first
      if (_productCache.containsKey(id)) {
        final timestamp = _cacheTimestamps[id];
        if (timestamp != null && DateTime.now().difference(timestamp) <= _cacheLifetime) {
          return _productCache[id];
        }
      }
      
      // Check secure storage
      final timestampStr = await _secureStorage.read(key: _timestampKey(id));
      if (timestampStr == null) return null;
      
      final timestamp = DateTime.parse(timestampStr);
      if (DateTime.now().difference(timestamp) > _cacheLifetime) {
        // Cache expired
        await _clearProductCache(id);
        return null;
      }
      
      final jsonData = await _secureStorage.read(key: _productKey(id));
      if (jsonData == null) return null;
      
      final product = jsonDecode(jsonData);
      
      // Update memory cache
      _productCache[id] = Map<String, dynamic>.from(product);
      _cacheTimestamps[id] = DateTime.now();
      
      return product;
    } catch (e) {
      print('Error getting cached product: $e');
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
      final timestampStr = await _secureStorage.read(key: _imageTimestampKey(id));
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
      print('Error getting cached image: $e');
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
      final timestampStr = await _secureStorage.read(key: _imageTimestampKey(id));
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
      
      final List<Uint8List> images = [];
      for (var base64Image in base64Images) {
        images.add(base64Decode(base64Image));
      }
      
      // Update memory cache
      _allImagesCache[id] = List.from(images);
      _cacheTimestamps[id] = DateTime.now();
      
      return images;
    } catch (e) {
      print('Error getting all cached images: $e');
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

  /// Get product's last updated timestamp
  static Future<DateTime?> getProductLastUpdated(String id) async {
    try {
      final product = await getCachedProduct(id);
      if (product == null || !product.containsKey('lastUpdatedAt')) return null;
      return DateTime.parse(product['lastUpdatedAt']);
    } catch (e) {
      print('Error getting product last updated: $e');
      return null;
    }
  }

  /// Clear product cache
  static Future<void> _clearProductCache(String id) async {
    try {
      await _secureStorage.delete(key: _productKey(id));
      await _secureStorage.delete(key: _timestampKey(id));
      _productCache.remove(id);
      _cacheTimestamps.remove(id);
    } catch (e) {
      print('Error clearing product cache: $e');
    }
  }

  /// Clear image cache
  static Future<void> _clearImageCache(String id) async {
    try {
      await _secureStorage.delete(key: _imageKey(id));
      await _secureStorage.delete(key: _numImagesKey(id));
      await _secureStorage.delete(key: _imageTimestampKey(id));
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_allImagesKey(id));
      
      _mainImageCache.remove(id);
      _allImagesCache.remove(id);
      _numImagesCache.remove(id);
    } catch (e) {
      print('Error clearing image cache: $e');
    }
  }

  /// Clear specific product's cache
  static Future<void> clearCache(String id) async {
    try {
      await _clearProductCache(id);
      await _clearImageCache(id);
    } catch (e) {
      print('Error clearing cache: $e');
    }
  }

  /// Clear all caches
  static Future<void> clearAllCaches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_productsListKey);
      
      // Clear all memory caches
      _mainImageCache.clear();
      _allImagesCache.clear();
      _productCache.clear();
      _numImagesCache.clear();
      _cacheTimestamps.clear();
    } catch (e) {
      print('Error clearing all caches: $e');
    }
  }
}
