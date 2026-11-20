import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'photo_storage.dart';
import 'app_state.dart';
import 'package:provider/provider.dart';
import 'widgets/custom_slider.dart';

class PhotoAlignmentPage extends StatefulWidget {
  final File photo;
  final DateTime forDate;
  final String referenceImagePath;
  final bool isNewPhoto; // true = from camera, false = editing existing

  const PhotoAlignmentPage({
    super.key,
    required this.photo,
    required this.forDate,
    required this.referenceImagePath,
    this.isNewPhoto = true,
  });

  @override
  State<PhotoAlignmentPage> createState() => _PhotoAlignmentPageState();
}

class _PhotoAlignmentPageState extends State<PhotoAlignmentPage> {
  // Transform parameters
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  double _rotation = 0.0;

  // UI state
  double _overlayOpacity = 0.5;
  bool _isSaving = false;

  // Gesture state
  Offset _lastFocalPoint = Offset.zero;
  double _lastScale = 1.0;
  double _lastRotation = 0.0;

  // Key for capturing the rendered widget
  final GlobalKey _transformedPhotoKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.isNewPhoto ? 'Align Photo' : 'Edit Alignment'),
        actions: [
          if (!_isSaving)
            IconButton(
              icon: const Icon(Icons.check, color: Colors.green),
              onPressed: _saveAlignedPhoto,
            ),
        ],
      ),
      body: Stack(
        children: [
          // Photo (transformable) - bottom layer with RepaintBoundary for capturing
          Positioned.fill(
            child: RepaintBoundary(
              key: _transformedPhotoKey,
              child: GestureDetector(
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                child: Transform(
                  transform: Matrix4.identity()
                    ..translate(_offset.dx, _offset.dy, 0.0)
                    ..scale(_scale, _scale, 1.0)
                    ..rotateZ(_rotation),
                  alignment: Alignment.center,
                  child: Image.file(
                    widget.photo,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),

          // Reference overlay (fixed) - top layer
          Positioned.fill(
            child: RepaintBoundary(
              child: IgnorePointer(
                child: Opacity(
                  opacity: _overlayOpacity,
                  child: Image.file(
                    File(widget.referenceImagePath),
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),

          // Loading overlay
          if (_isSaving)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Saving aligned photo...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom controls
          if (!_isSaving)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                  top: 16,
                  left: 16,
                  right: 16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Opacity slider
                    Row(
                      children: [
                        const Icon(Icons.opacity, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CustomSlider(
                            value: _overlayOpacity,
                            min: 0.0,
                            max: 1.0,
                            onChanged: (value) {
                              setState(() {
                                _overlayOpacity = value;
                              });
                            },
                          ),
                        ),
                        Text(
                          '${(_overlayOpacity * 100).round()}%',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Reset button
                        ElevatedButton.icon(
                          onPressed: _resetTransform,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reset'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[800],
                            foregroundColor: Colors.white,
                          ),
                        ),
                        // Retake/Cancel button
                        if (widget.isNewPhoto)
                          ElevatedButton.icon(
                            onPressed: () => Navigator.pop(context, false),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Retake'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[800],
                              foregroundColor: Colors.white,
                            ),
                          )
                        else
                          ElevatedButton.icon(
                            onPressed: () => Navigator.pop(context, false),
                            icon: const Icon(Icons.close),
                            label: const Text('Cancel'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[800],
                              foregroundColor: Colors.white,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Instructions
                    const Text(
                      'Drag, pinch, and rotate to align with overlay',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    _lastFocalPoint = details.focalPoint;
    _lastScale = _scale;
    _lastRotation = _rotation;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      // Handle pan (drag)
      _offset += details.focalPoint - _lastFocalPoint;
      _lastFocalPoint = details.focalPoint;

      // Handle scale (pinch zoom)
      _scale = (_lastScale * details.scale).clamp(0.5, 3.0);

      // Handle rotation (two-finger twist)
      _rotation = _lastRotation + details.rotation;
    });
  }

  void _resetTransform() {
    setState(() {
      _offset = Offset.zero;
      _scale = 1.0;
      _rotation = 0.0;
    });
  }

  Future<void> _saveAlignedPhoto() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final appState = context.read<AppState>();

      // Get the correct photo storage directory
      final photosDir = await PhotoStorage.getPhotosDirectory();

      // Generate filenames using PhotoStorage format (YYYYMMDD.jpg)
      final dateStr = '${widget.forDate.year}'
          '${widget.forDate.month.toString().padLeft(2, '0')}'
          '${widget.forDate.day.toString().padLeft(2, '0')}';
      final alignedPath = '${photosDir.path}/$dateStr.jpg';
      final originalPath = '${photosDir.path}/${dateStr}_orig.jpg';

      // If this is editing an existing photo, backup the original if not already backed up
      if (!widget.isNewPhoto) {
        final origFile = File(originalPath);
        if (!await origFile.exists()) {
          // Backup the current aligned photo as original
          final existingPhoto = appState.getPhotoForDate(widget.forDate);
          if (existingPhoto != null && await existingPhoto.exists()) {
            await existingPhoto.copy(originalPath);
          }
        }
      } else {
        // For new photos, save the original
        await widget.photo.copy(originalPath);
      }

      // Apply transformations and save aligned photo
      // For existing photos, we need to write to a temp file first to avoid read/write conflicts
      if (!widget.isNewPhoto && widget.photo.path == alignedPath) {
        final tempPath = '$alignedPath.tmp';
        await _applyTransformAndSave(widget.photo.path, tempPath);

        // Replace the original with the transformed version
        final tempFile = File(tempPath);
        await tempFile.copy(alignedPath);
        await tempFile.delete();
      } else {
        await _applyTransformAndSave(widget.photo.path, alignedPath);
      }

      // Notify AppState that photo was updated so calendar refreshes
      await appState.refreshPhotos();

      if (mounted) {
        // Pop with success
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _applyTransformAndSave(String sourcePath, String destPath) async {
    // Capture the transformed photo as rendered on screen at high resolution
    final RenderRepaintBoundary boundary = _transformedPhotoKey.currentContext!
        .findRenderObject() as RenderRepaintBoundary;

    // Use 4x pixel ratio for good quality without freezing
    // This captures exactly what you see on screen during alignment
    final ui.Image image = await boundary.toImage(pixelRatio: 4.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      throw Exception('Failed to convert image to bytes');
    }

    final pngBytes = byteData.buffer.asUint8List();

    // Decode with image package to convert to JPEG for smaller file size
    final decodedImage = img.decodeImage(pngBytes);

    if (decodedImage == null) {
      throw Exception('Failed to decode captured image');
    }

    // Crop to 9:16 aspect ratio (portrait) for consistency with camera photos
    final targetAspectRatio = 9.0 / 16.0;
    final currentAspectRatio = decodedImage.width / decodedImage.height;

    img.Image finalImage;
    if ((currentAspectRatio - targetAspectRatio).abs() > 0.01) {
      // Need to crop
      int cropWidth, cropHeight;
      if (currentAspectRatio > targetAspectRatio) {
        // Image is too wide, crop width
        cropHeight = decodedImage.height;
        cropWidth = (cropHeight * targetAspectRatio).round();
      } else {
        // Image is too tall, crop height
        cropWidth = decodedImage.width;
        cropHeight = (cropWidth / targetAspectRatio).round();
      }

      // Center crop
      final x = ((decodedImage.width - cropWidth) / 2).round();
      final y = ((decodedImage.height - cropHeight) / 2).round();

      finalImage = img.copyCrop(decodedImage,
        x: x, y: y, width: cropWidth, height: cropHeight);
    } else {
      finalImage = decodedImage;
    }

    // Encode as JPEG with high quality
    final jpegBytes = img.encodeJpg(finalImage, quality: 95);

    // Save the transformed image
    await File(destPath).writeAsBytes(jpegBytes);
  }
}
