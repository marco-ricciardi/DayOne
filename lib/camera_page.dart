import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'app_state.dart';
import 'photo_review_page.dart';
import 'widgets/custom_slider.dart';
import 'utils/date_utils.dart';

class CameraPage extends StatefulWidget {
  /// Explicit date to save for (e.g. from the calendar). When null, the
  /// date is "today" with a 5am cutoff, evaluated when the photo is taken.
  final DateTime? forDate;
  final VoidCallback? onPhotoSaved;

  const CameraPage({
    super.key,
    this.forDate,
    this.onPhotoSaved,
  });

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;

  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 8.0;

  Offset? _focusPoint;
  bool _showFocus = false;

  double _overlayOpacity = 0.5;
  bool _isInitializing = false;
  bool _photoExistsNotificationDismissed = false;
  bool _isTakingPhoto = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCameras();
  }

  // Release the camera when the app goes to the background and re-open it on
  // return; otherwise the preview freezes and takePicture() fails.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final controller = _controller;
      if (controller != null) {
        setState(() => _controller = null);
        controller.dispose();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null) _initCameras();
    }
  }

  Future<void> _initCameras() async {
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      _cameras ??= await availableCameras();
      if (_cameras!.isEmpty || !mounted) return;

      // Work on a local controller and only publish it once it's ready, so a
      // lifecycle change mid-initialisation can't leave a half-built one.
      final controller = CameraController(
        _cameras!.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();

      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = await controller.getMaxZoomLevel();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      // Load saved zoom level from AppState
      final savedZoom = context.read<AppState>().cameraZoomLevel;
      _currentZoom = savedZoom.clamp(_minZoom, _maxZoom);
      await controller.setZoomLevel(_currentZoom);

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (e) {
      debugPrint('Camera init failed: $e');
    } finally {
      _isInitializing = false;
    }
  }

  // --- Persistent Reference Image Picker ---
  Future<void> _pickReferenceImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null && mounted) {
      final appState = context.read<AppState>();
      await appState.setReferenceImagePath(image.path);
      appState.toggleCameraOverlay(true);
    }
  }

  /// The date this photo will be saved under.
  DateTime get _targetDate {
    final explicit = widget.forDate;
    return explicit != null
        ? AppDateUtils.normalizeDate(explicit)
        : AppDateUtils.photoDayFor(DateTime.now());
  }

  // --- Take Photo ---
  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    // Ignore extra taps while a capture/review is already in progress
    if (_isTakingPhoto) return;
    _isTakingPhoto = true;
    try {
      await _captureAndReview();
    } finally {
      _isTakingPhoto = false;
    }
  }

  Future<void> _captureAndReview() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final appState = context.read<AppState>();
    final dateToSave = _targetDate;

    // Check if photo already exists for this date
    if (appState.hasPhotoForDate(dateToSave)) {
      final shouldReplace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace Photo?'),
          content: const Text(
            'A photo already exists for this date. Do you want to replace it?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );

      if (shouldReplace != true) return;
    }

    try {
      final XFile xFile = await _controller!.takePicture();
      final file = File(xFile.path);

      if (mounted) {
        // Navigate to review page - always show review, never auto-save
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => PhotoReviewPage(
              photo: file,
              forDate: dateToSave,
              autoSave: false, // Always show review page
            ),
          ),
        );

        // If user saved the photo (result == true), call the callback to switch tabs
        if (result == true && mounted) {
          widget.onPhotoSaved?.call();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error taking photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- Tap to Focus ---
  void _onViewTap(TapDownDetails details, BoxConstraints constraints) {
    if (_controller == null) return;

    final dx = details.localPosition.dx / constraints.maxWidth;
    final dy = details.localPosition.dy / constraints.maxHeight;

    _controller!.setFocusPoint(Offset(dx, dy));
    _controller!.setExposurePoint(Offset(dx, dy));

    setState(() {
      _focusPoint = details.localPosition;
      _showFocus = true;
    });

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _showFocus = false;
        });
      }
    });
  }

  // --- Calculate scale to fill screen ---
  double _calculateScale(BoxConstraints constraints, double cameraAspectRatio) {
    final screenAspectRatio = constraints.maxWidth / constraints.maxHeight;
    if (cameraAspectRatio > screenAspectRatio) {
      // Camera is wider, scale based on height
      return constraints.maxHeight / (constraints.maxWidth / cameraAspectRatio);
    } else {
      // Camera is taller, scale based on width
      return constraints.maxWidth / (constraints.maxHeight * cameraAspectRatio);
    }
  }

  // --- Pinch to Zoom ---
  void _onScaleUpdate(ScaleUpdateDetails details) async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    double zoom = (_currentZoom * details.scale).clamp(_minZoom, _maxZoom);
    await _controller!.setZoomLevel(zoom);

    if (mounted) {
      setState(() {
        _currentZoom = zoom;
      });
      // Save zoom level to preferences
      context.read<AppState>().setCameraZoomLevel(zoom);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final referenceImagePath = appState.referenceImagePath;
    final overlayEnabled =
        appState.cameraOverlayEnabled && referenceImagePath != null;

    // Check if photo exists for current date
    final hasPhoto = appState.hasPhotoForDate(_targetDate);

    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // 1️⃣ Full-Screen Camera Preview
          LayoutBuilder(
            builder: (context, constraints) {
              // Camera aspectRatio is width/height, but in portrait mode we need height/width
              final cameraAspectRatio = 1 / _controller!.value.aspectRatio;

              return GestureDetector(
                onTapDown: (details) => _onViewTap(details, constraints),
                onScaleUpdate: _onScaleUpdate,
                child: ClipRect(
                  child: Transform.scale(
                    scale: _calculateScale(constraints, cameraAspectRatio),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: cameraAspectRatio,
                        child: CameraPreview(_controller!),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // 2️⃣ Reference Overlay (centered on screen with natural aspect ratio)
          if (overlayEnabled && referenceImagePath != null)
            IgnorePointer(
              child: Opacity(
                opacity: _overlayOpacity,
                child: Center(
                  child: Image.file(
                    File(referenceImagePath),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      // If image fails to load, clear the reference and show error
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          appState.clearReferenceImagePath();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Reference image not found. Please select a new one.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      });
                      return const Center(
                        child: Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 48,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

          // Photo exists indicator (dismissible)
          if (hasPhoto && !_photoExistsNotificationDismissed)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      widget.forDate == null
                          ? "Photo exists for today"
                          : "Photo exists for this day",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _photoExistsNotificationDismissed = true;
                        });
                      },
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 4️⃣ Focus Indicator
          if (_showFocus && _focusPoint != null)
            Positioned(
              left: _focusPoint!.dx - 25,
              top: _focusPoint!.dy - 25,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.yellow, width: 2),
                  shape: BoxShape.circle,
                ),
              ),
            ),

          // 5️⃣ Overlay Controls (top-right)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 20,
            child: Column(
              children: [
                // Image picker button
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: _pickReferenceImage,
                    icon: const Icon(Icons.image, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 12),
                // Overlay toggle button
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: () {
                      if (referenceImagePath == null) {
                        _pickReferenceImage();
                      } else {
                        appState.toggleCameraOverlay(!overlayEnabled);
                      }
                    },
                    icon: Icon(
                      overlayEnabled
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: overlayEnabled ? Colors.green : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 6️⃣ Bottom Controls (Zoom Slider + FAB + Opacity Slider)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 32,
            left: 0,
            right: 0,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Zoom Slider (left side)
                Positioned(
                  left: 16,
                  right: MediaQuery.of(context).size.width / 2 + 50,
                  child: Container(
                    constraints: const BoxConstraints(
                      maxWidth: 140,
                      minWidth: 80,
                    ),
                    child: CustomSlider(
                      value: _currentZoom,
                      min: _minZoom,
                      max: _maxZoom,
                      label: "${_currentZoom.toStringAsFixed(1)}x",
                      onChanged: (value) {
                        _controller!.setZoomLevel(value);
                        setState(() {
                          _currentZoom = value;
                        });
                        // Save zoom level to preferences
                        context.read<AppState>().setCameraZoomLevel(value);
                      },
                    ),
                  ),
                ),

                // FAB (always centered)
                FloatingActionButton.large(
                  onPressed: _takePhoto,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  child: const Icon(Icons.camera_alt, size: 32),
                ),

                // Opacity Slider (right side, appears only if overlay enabled)
                if (overlayEnabled)
                  Positioned(
                    left: MediaQuery.of(context).size.width / 2 + 50,
                    right: 16,
                    child: Container(
                      constraints: const BoxConstraints(
                        maxWidth: 140,
                        minWidth: 80,
                      ),
                      child: CustomSlider(
                        value: _overlayOpacity,
                        min: 0.05,
                        max: 0.95,
                        divisions: 18,
                        label: "${(_overlayOpacity * 100).round()}%",
                        onChanged: (value) {
                          setState(() {
                            _overlayOpacity = value;
                          });
                        },
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
}