import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'app_state.dart';
import 'photo_alignment_page.dart';
import 'utils/date_utils.dart' as app_date_utils;

class PhotoReviewPage extends StatefulWidget {
  final File photo;
  final DateTime forDate;
  final bool autoSave; // If true, saves automatically without confirmation
  final bool fromGallery; // If true, shows "Change" button that reopens gallery

  const PhotoReviewPage({
    super.key,
    required this.photo,
    required this.forDate,
    this.autoSave = false,
    this.fromGallery = false,
  });

  @override
  State<PhotoReviewPage> createState() => _PhotoReviewPageState();
}

class _PhotoReviewPageState extends State<PhotoReviewPage> {
  bool _showReferenceOverlay = false;
  double _overlayOpacity = 0.5;

  @override
  void initState() {
    super.initState();
    if (widget.autoSave) {
      _saveAndExit();
    }
  }

  Future<void> _saveAndExit() async {
    final appState = context.read<AppState>();
    await appState.savePhotoForDate(widget.photo, widget.forDate);

    if (mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Photo saved for ${_formatDate(widget.forDate)}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  bool _isSaving = false;

  Future<void> _confirmAndSave() async {
    // A double-tap would otherwise save twice and pop two routes
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final appState = context.read<AppState>();
    try {
      await appState.savePhotoForDate(widget.photo, widget.forDate);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Photo saved for ${_formatDate(widget.forDate)}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _openAlignmentEditor() async {
    final appState = context.read<AppState>();
    final referenceImagePath = appState.referenceImagePath;

    if (referenceImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please set a reference image first from the camera page'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PhotoAlignmentPage(
          photo: widget.photo,
          forDate: widget.forDate,
          referenceImagePath: referenceImagePath,
          isNewPhoto: true,
        ),
      ),
    );

    if (result == true && mounted) {
      // Photo was saved with alignment, exit review page
      Navigator.pop(context, true);
    }
  }

  Future<void> _changePhoto() async {
    if (widget.fromGallery) {
      // Reopen gallery picker
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery);

      if (image != null && mounted) {
        // Replace current page with new review page for the new photo
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => PhotoReviewPage(
              photo: File(image.path),
              forDate: widget.forDate,
              autoSave: false,
              fromGallery: true,
            ),
          ),
        );
      }
    } else {
      // From camera - just go back
      Navigator.pop(context, false);
    }
  }

  String _formatDate(DateTime date) => app_date_utils.AppDateUtils.formatShort(date);

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final referenceImagePath = appState.referenceImagePath;
    final hasReference = referenceImagePath != null;

    if (widget.autoSave) {
      // Just show a loading indicator while saving
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Review - ${_formatDate(widget.forDate)}'),
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Captured photo
          Center(
            child: Image.file(
              widget.photo,
              fit: BoxFit.contain,
            ),
          ),

          // Reference overlay
          if (_showReferenceOverlay && hasReference)
            IgnorePointer(
              child: Opacity(
                opacity: _overlayOpacity,
                child: Center(
                  child: Image.file(
                    File(referenceImagePath),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),

          // Reference overlay toggle button
          if (hasReference)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: () {
                    setState(() {
                      _showReferenceOverlay = !_showReferenceOverlay;
                    });
                  },
                  icon: Icon(
                    _showReferenceOverlay
                        ? Icons.visibility
                        : Icons.visibility_off,
                    color: _showReferenceOverlay ? Colors.green : Colors.white,
                  ),
                ),
              ),
            ),

          // Opacity slider
          if (_showReferenceOverlay && hasReference)
            Positioned(
              bottom: 120,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 200,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Overlay: ${(_overlayOpacity * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 12,
                          ),
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white30,
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          min: 0.05,
                          max: 0.95,
                          divisions: 18,
                          value: _overlayOpacity,
                          onChanged: (value) {
                            setState(() {
                              _overlayOpacity = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Bottom action buttons
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 24,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Align button (if reference image exists)
                  if (hasReference)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _openAlignmentEditor,
                          icon: const Icon(Icons.compare),
                          label: const Text('Align with Reference'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Primary buttons row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Change/Retake button
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ElevatedButton.icon(
                            onPressed: _isSaving ? null : _changePhoto,
                            icon: const Icon(Icons.close),
                            label: Text(widget.fromGallery ? 'Change' : 'Retake'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Save button
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ElevatedButton.icon(
                            onPressed: _isSaving ? null : _confirmAndSave,
                            icon: const Icon(Icons.check),
                            label: const Text('Save'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
