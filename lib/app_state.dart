import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'photo_storage.dart';

class AppState extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  bool _cameraOverlayEnabled = true;
  bool _viewerOverlayEnabled = true;
  String? _referenceImagePath;
  Map<DateTime, File> _photos = {};
  double _cameraZoomLevel = 1.0;
  bool _notificationsEnabled = false;
  TimeOfDay _notificationTime = const TimeOfDay(hour: 9, minute: 0);
  int _photoVersion = 0;

  /// Thumbnail decode width used by the calendar.
  static const int thumbnailCacheWidth = 200;

  ThemeMode get themeMode => _themeMode;
  bool get cameraOverlayEnabled => _cameraOverlayEnabled;
  bool get viewerOverlayEnabled => _viewerOverlayEnabled;
  @Deprecated('Use cameraOverlayEnabled or viewerOverlayEnabled instead')
  bool get referenceOverlayEnabled => _cameraOverlayEnabled;
  String? get referenceImagePath => _referenceImagePath;
  Map<DateTime, File> get photos => _photos;
  double get cameraZoomLevel => _cameraZoomLevel;
  bool get notificationsEnabled => _notificationsEnabled;
  TimeOfDay get notificationTime => _notificationTime;

  /// Bumped whenever a photo file is written/replaced/deleted, so image
  /// widgets can re-key and reload instead of showing a stale cached image.
  int get photoVersion => _photoVersion;

  AppState() {
    _loadThemeMode();
    _loadReferenceImage();
    _loadPhotos();
    _loadCameraZoomLevel();
    _loadNotificationSettings();
  }

  /// Normalize date to midnight (remove time component)
  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  Future<void> setThemeMode(ThemeMode? mode) async {
    if (mode == null || mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt('themeMode');
    if (index != null && index >= 0 && index < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[index];
      notifyListeners();
    }
  }

  /// Evict both the full-size and calendar-thumbnail cache entries for a file.
  void _evictPhoto(File file) {
    final provider = FileImage(file);
    provider.evict();
    ResizeImage(provider, width: thumbnailCacheWidth).evict();
  }

  void toggleCameraOverlay(bool value) {
    if (_cameraOverlayEnabled == value) return;
    _cameraOverlayEnabled = value;
    _saveOverlaySettings();
    notifyListeners();
  }

  void toggleViewerOverlay(bool value) {
    if (_viewerOverlayEnabled == value) return;
    _viewerOverlayEnabled = value;
    _saveOverlaySettings();
    notifyListeners();
  }

  @Deprecated('Use toggleCameraOverlay or toggleViewerOverlay instead')
  void toggleReferenceOverlay(bool value) {
    toggleCameraOverlay(value);
  }

  Future<void> setReferenceImagePath(String path) async {
    _referenceImagePath = path;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('referenceImagePath', path);
  }

  Future<void> clearReferenceImagePath() async {
    _referenceImagePath = null;
    _cameraOverlayEnabled = false;
    _viewerOverlayEnabled = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('referenceImagePath');
    await prefs.setBool('cameraOverlayEnabled', false);
    await prefs.setBool('viewerOverlayEnabled', false);
  }

  Future<void> _loadReferenceImage() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('referenceImagePath');

    // Load separate overlay settings, with migration from old single setting
    final oldOverlayEnabled = prefs.getBool('referenceOverlayEnabled');
    _cameraOverlayEnabled = prefs.getBool('cameraOverlayEnabled') ?? oldOverlayEnabled ?? true;
    _viewerOverlayEnabled = prefs.getBool('viewerOverlayEnabled') ?? oldOverlayEnabled ?? true;

    _referenceImagePath = path;
    notifyListeners();
  }

  Future<void> _saveOverlaySettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cameraOverlayEnabled', _cameraOverlayEnabled);
    await prefs.setBool('viewerOverlayEnabled', _viewerOverlayEnabled);
  }

  Future<void> setCameraZoomLevel(double zoom) async {
    if (_cameraZoomLevel == zoom) return;
    _cameraZoomLevel = zoom;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('cameraZoomLevel', zoom);
  }

  Future<void> _loadCameraZoomLevel() async {
    final prefs = await SharedPreferences.getInstance();
    _cameraZoomLevel = prefs.getDouble('cameraZoomLevel') ?? 1.0;
    notifyListeners();
  }

  /// Load notification settings
  Future<void> _loadNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _notificationsEnabled = prefs.getBool('notifications_enabled') ?? false;
    final hour = prefs.getInt('notification_hour') ?? 9;
    final minute = prefs.getInt('notification_minute') ?? 0;
    _notificationTime = TimeOfDay(hour: hour, minute: minute);
    notifyListeners();
  }

  /// Set notification time and enabled status
  Future<void> setNotificationTime(TimeOfDay time, bool enabled) async {
    _notificationTime = time;
    _notificationsEnabled = enabled;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notification_hour', time.hour);
    await prefs.setInt('notification_minute', time.minute);
    await prefs.setBool('notifications_enabled', enabled);
  }

  /// Toggle notifications on/off
  Future<void> toggleNotifications(bool enabled) async {
    _notificationsEnabled = enabled;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', enabled);
  }

  /// Load all photos from storage
  Future<void> _loadPhotos() async {
    final photosMap = await PhotoStorage.getAllPhotos();
    // Normalize all date keys
    final newPhotos = <DateTime, File>{};
    photosMap.forEach((date, file) {
      newPhotos[_normalizeDate(date)] = file;
    });

    // Only notify if photos actually changed
    if (!_photosEqual(_photos, newPhotos)) {
      _photos = newPhotos;
      notifyListeners();
    }
  }

  /// Check if two photo maps are equal
  bool _photosEqual(Map<DateTime, File> a, Map<DateTime, File> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key]?.path != entry.value.path) {
        return false;
      }
    }
    return true;
  }

  /// Save a photo for a specific date
  Future<void> savePhotoForDate(File sourceFile, DateTime date) async {
    final normalizedDate = _normalizeDate(date);

    // Evict old cached image if it exists
    final oldPhoto = _photos[normalizedDate];
    if (oldPhoto != null) _evictPhoto(oldPhoto);

    final savedFile = await PhotoStorage.savePhotoForDate(sourceFile, normalizedDate);
    _photos[normalizedDate] = savedFile;

    // Evict the new file's cache too (in case the path is the same)
    _evictPhoto(savedFile);
    _photoVersion++;

    notifyListeners();
  }

  /// Delete a photo for a specific date
  Future<void> deletePhotoForDate(DateTime date) async {
    final normalizedDate = _normalizeDate(date);

    // Evict cached image before deleting
    final photo = _photos[normalizedDate];
    if (photo != null) _evictPhoto(photo);

    final success = await PhotoStorage.deletePhotoForDate(normalizedDate);
    if (success) {
      _photos.remove(normalizedDate);
      _photoVersion++;
      notifyListeners();
    }
  }

  /// Get photo for a specific date
  File? getPhotoForDate(DateTime date) {
    final normalizedDate = _normalizeDate(date);
    return _photos[normalizedDate];
  }

  /// Check if photo exists for date
  bool hasPhotoForDate(DateTime date) {
    final normalizedDate = _normalizeDate(date);
    return _photos.containsKey(normalizedDate);
  }

  /// Refresh photos from storage and clear image cache
  Future<void> refreshPhotos() async {
    // Clear Flutter's image cache for all photos to force reload
    for (final photo in _photos.values) {
      _evictPhoto(photo);
    }
    // Files may have been rewritten in place (same paths), so force a reload
    _photoVersion++;
    notifyListeners();

    await _loadPhotos();
  }
}