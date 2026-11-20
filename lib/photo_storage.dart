import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class PhotoStorage {
  /// Get the app's photos directory
  static Future<Directory> getPhotosDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(path.join(appDir.path, 'physique_photos'));
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    return photosDir;
  }

  /// Save a photo for a specific date (YYYYMMDD format)
  /// Only one photo per date is allowed
  static Future<File> savePhotoForDate(File sourceFile, DateTime date) async {
    final photosDir = await getPhotosDirectory();
    final dateKey = _formatDateKey(date);
    final targetPath = path.join(photosDir.path, '$dateKey.jpg');

    // Delete existing photo for this date if it exists
    final existingFile = File(targetPath);
    if (await existingFile.exists()) {
      await existingFile.delete();
    }

    // Just copy the file - aspect ratio is handled during alignment capture
    return await sourceFile.copy(targetPath);
  }

  /// Get photo for a specific date
  static Future<File?> getPhotoForDate(DateTime date) async {
    final photosDir = await getPhotosDirectory();
    final dateKey = _formatDateKey(date);
    final file = File(path.join(photosDir.path, '$dateKey.jpg'));
    
    if (await file.exists()) {
      return file;
    }
    return null;
  }

  /// Delete photo for a specific date (including backup if it exists)
  static Future<bool> deletePhotoForDate(DateTime date) async {
    final file = await getPhotoForDate(date);
    bool deleted = false;

    if (file != null && await file.exists()) {
      await file.delete();
      deleted = true;
    }

    // Also delete the backup file if it exists
    final photosDir = await getPhotosDirectory();
    final dateKey = _formatDateKey(date);
    final backupFile = File(path.join(photosDir.path, '${dateKey}_orig.jpg'));
    if (await backupFile.exists()) {
      await backupFile.delete();
    }

    return deleted;
  }

  /// Get all photos as a map of date -> File
  static Future<Map<DateTime, File>> getAllPhotos() async {
    final photosDir = await getPhotosDirectory();
    final photos = <DateTime, File>{};
    
    if (!await photosDir.exists()) {
      return photos;
    }
    
    final files = photosDir.listSync();
    for (var entity in files) {
      if (entity is File && entity.path.endsWith('.jpg')) {
        final filename = path.basenameWithoutExtension(entity.path);

        // Skip backup files (ending with _orig)
        if (filename.endsWith('_orig')) {
          continue;
        }

        try {
          final date = _parseDateKey(filename);
          photos[date] = entity;
        } catch (e) {
          // Skip invalid filenames
          continue;
        }
      }
    }
    
    return photos;
  }

  /// Check if a photo exists for a date
  static Future<bool> hasPhotoForDate(DateTime date) async {
    final file = await getPhotoForDate(date);
    return file != null;
  }

  /// Format date as YYYYMMDD
  static String _formatDateKey(DateTime date) {
    return '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  }

  /// Parse YYYYMMDD string to DateTime
  static DateTime _parseDateKey(String key) {
    final year = int.parse(key.substring(0, 4));
    final month = int.parse(key.substring(4, 6));
    final day = int.parse(key.substring(6, 8));
    return DateTime(year, month, day);
  }
}