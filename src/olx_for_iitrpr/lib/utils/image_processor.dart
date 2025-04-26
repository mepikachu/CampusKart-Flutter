import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class ImageProcessor {
  static Future<File> compressImage(File imageFile) async {
    // Read image from file
    List<int> imageBytes = await imageFile.readAsBytes();
    img.Image? originalImage = img.decodeImage(Uint8List.fromList(imageBytes));

    if (originalImage == null) throw Exception('Failed to decode image');

    // Calculate new dimensions while maintaining aspect ratio
    int targetWidth = 800; // Standard width
    int targetHeight = (originalImage.height * targetWidth / originalImage.width).round();

    // Resize image
    img.Image resizedImage = img.copyResize(
      originalImage,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.linear,
    );

    // Compress image
    List<int> compressedBytes = img.encodeJpg(resizedImage, quality: 70);

    // Create temporary file to store compressed image
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg');
    await tempFile.writeAsBytes(compressedBytes);

    return tempFile;
  }

  static Future<List<File>> compressImages(List<File> images) async {
    List<File> compressedImages = [];
    for (var image in images) {
      compressedImages.add(await compressImage(image));
    }
    return compressedImages;
  }
}

