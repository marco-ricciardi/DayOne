import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'photo_alignment_page.dart';
import 'utils/date_utils.dart';
import 'widgets/custom_slider.dart';

class PhotoViewerPage extends StatefulWidget {
  final File photo;
  final DateTime date;

  const PhotoViewerPage({
    super.key,
    required this.photo,
    required this.date,
  });

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late List<DateTime> _photoDates;
  late PageController _pageController;
  int _currentIndex = 0;
  bool _showControls = true;
  double _overlayOpacity = 0.5;
  int _imageRefreshKey = 0; // Used to force image reload
  bool _closing = false; // Guards against popping this route twice

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _photoDates = _getAllPhotoDates(appState);

    // Find the index of the initial date
    _currentIndex = _photoDates.indexWhere((d) => _isSameDay(d, widget.date));
    if (_currentIndex == -1) _currentIndex = 0;

    _pageController = PageController(initialPage: _currentIndex);

    // Precache adjacent images after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheAdjacentImages(_currentIndex, appState);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<DateTime> _getAllPhotoDates(AppState appState) {
    // Get all dates that have photos, sorted chronologically
    // Much more efficient: directly get dates from AppState instead of iterating through all possible dates
    final dates = appState.photos.keys.toList()..sort((a, b) => a.compareTo(b));
    return dates;
  }

  bool _isSameDay(DateTime a, DateTime b) => AppDateUtils.isSameDay(a, b);

  /// Precache images adjacent to current index for smooth swiping
  void _precacheAdjacentImages(int currentIndex, AppState appState) {
    if (!mounted) return;

    // Precache previous and next 2 images
    for (int offset = -2; offset <= 2; offset++) {
      if (offset == 0) continue; // Skip current image (already loaded)

      final targetIndex = currentIndex + offset;
      if (targetIndex >= 0 && targetIndex < _photoDates.length) {
        final photo = appState.getPhotoForDate(_photoDates[targetIndex]);
        if (photo != null) {
          precacheImage(FileImage(photo), context).catchError((_) {});
        }
      }
    }

    // Also precache reference image if enabled
    final referenceImagePath = appState.referenceImagePath;
    if (referenceImagePath != null && appState.viewerOverlayEnabled) {
      precacheImage(FileImage(File(referenceImagePath)), context).catchError((_) {});
    }
  }

  Future<void> _editAlignment(BuildContext context, AppState appState) async {
    final referenceImagePath = appState.referenceImagePath;

    if (referenceImagePath == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please set a reference image first from the camera page'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final currentDate = _photoDates[_currentIndex];
    final photo = appState.getPhotoForDate(currentDate);

    if (photo == null) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PhotoAlignmentPage(
          photo: photo,
          forDate: currentDate,
          referenceImagePath: referenceImagePath,
          isNewPhoto: false,
        ),
      ),
    );

    if (result == true && context.mounted) {
      // Photo was updated, clear image cache and refresh the view
      final photo = appState.getPhotoForDate(currentDate);
      if (photo != null) {
        // Evict the old image from cache
        final image = FileImage(photo);
        image.evict();
      }

      setState(() {
        // Increment key to force image reload
        _imageRefreshKey++;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo alignment updated'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    // Refresh photo dates list in case photos were added/deleted
    _photoDates = _getAllPhotoDates(appState);

    if (_photoDates.isEmpty) {
      // No photos available, go back (only once, even if we rebuild again)
      if (!_closing) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
      return const SizedBox();
    }

    // Ensure current index is valid
    if (_currentIndex >= _photoDates.length) {
      _currentIndex = _photoDates.length - 1;
    }

    final currentDate = _photoDates[_currentIndex];
    final hasPrevious = _currentIndex > 0;
    final hasNext = _currentIndex < _photoDates.length - 1;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _showControls
          ? AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(_formatDate(currentDate)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.compare, color: Colors.blue),
                  onPressed: () => _editAlignment(context, appState),
                  tooltip: 'Edit Alignment',
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deletePhoto(context, appState),
                ),
              ],
            )
          : null,
      body: GestureDetector(
        onTap: () {
          setState(() {
            _showControls = !_showControls;
          });
        },
        child: Stack(
          children: [
            // PageView for smooth swiping
            PageView.builder(
              controller: _pageController,
              itemCount: _photoDates.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
                // Precache adjacent images for smooth swiping
                _precacheAdjacentImages(index, appState);
              },
              itemBuilder: (context, index) {
                final date = _photoDates[index];
                final photo = appState.getPhotoForDate(date);
                final referenceImagePath = appState.referenceImagePath;
                final overlayEnabled = appState.viewerOverlayEnabled && referenceImagePath != null;

                return RepaintBoundary(
                  child: Stack(
                    children: [
                      // Main photo
                      Center(
                        child: InteractiveViewer(
                          maxScale: 4.0,
                          child: photo != null
                              ? Image.file(
                                  photo,
                                  key: ValueKey('${photo.path}_$_imageRefreshKey'),
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                  gaplessPlayback: true,
                                  frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                                    // Skip fade for cached images
                                    if (wasSynchronouslyLoaded) {
                                      return child;
                                    }
                                    // Fast fade-in for loading images
                                    return AnimatedOpacity(
                                      opacity: frame == null ? 0 : 1,
                                      duration: const Duration(milliseconds: 150),
                                      child: child,
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.error_outline, color: Colors.white, size: 48),
                                          SizedBox(height: 8),
                                          Text(
                                            'Error loading photo',
                                            style: TextStyle(color: Colors.white),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                )
                              : const Center(
                                  child: Text(
                                    'Photo not found',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                        ),
                      ),

                      // Reference overlay
                      if (overlayEnabled && photo != null)
                        IgnorePointer(
                          child: Opacity(
                            opacity: _overlayOpacity,
                            child: Center(
                              child: Image.file(
                                File(referenceImagePath),
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                                gaplessPlayback: true,
                                errorBuilder: (context, error, stackTrace) {
                                  return const SizedBox();
                                },
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),

            // Navigation arrows (only show when controls are visible)
            if (_showControls) ...[
              // Left arrow
              if (hasPrevious)
                Positioned(
                  left: 16,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.chevron_left, size: 32),
                        color: Colors.white,
                        onPressed: () {
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                      ),
                    ),
                  ),
                ),

              // Right arrow
              if (hasNext)
                Positioned(
                  right: 16,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.chevron_right, size: 32),
                        color: Colors.white,
                        onPressed: () {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                      ),
                    ),
                  ),
                ),

              // Overlay toggle button (top-right)
              Positioned(
                top: MediaQuery.of(context).padding.top + 60,
                right: 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      appState.viewerOverlayEnabled
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: appState.viewerOverlayEnabled
                          ? Colors.green
                          : Colors.white,
                    ),
                    onPressed: () {
                      if (appState.referenceImagePath == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No reference image set. Select one from camera page.'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      } else {
                        appState.toggleViewerOverlay(!appState.viewerOverlayEnabled);
                      }
                    },
                  ),
                ),
              ),

              // Opacity slider (bottom, appears only if overlay enabled)
              if (appState.viewerOverlayEnabled && appState.referenceImagePath != null)
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 200,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: CustomSlider(
                        value: _overlayOpacity,
                        min: 0.05,
                        max: 0.95,
                        divisions: 18,
                        label: 'Overlay: ${(_overlayOpacity * 100).round()}%',
                        onChanged: (value) {
                          setState(() {
                            _overlayOpacity = value;
                          });
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _deletePhoto(BuildContext context, AppState appState) async {
    final currentDate = _photoDates[_currentIndex];
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Photo?'),
        content: const Text(
          'Are you sure you want to delete this photo? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Store the count before deletion
      final photosBeforeDeletion = _photoDates.length;

      await appState.deletePhotoForDate(currentDate);

      if (mounted) {
        // Check if this was the last photo
        if (photosBeforeDeletion <= 1) {
          // No more photos: the rebuild triggered by the delete already pops
          // back to the calendar (see build), so popping here too would close
          // the home screen as well.
          if (!_closing) {
            _closing = true;
            Navigator.pop(context);
          }
          messenger.showSnackBar(
            const SnackBar(content: Text('Photo deleted')),
          );
        } else {
          // There are still photos remaining
          // Adjust current index if needed (if we deleted the last photo)
          if (_currentIndex >= photosBeforeDeletion - 1) {
            _currentIndex = photosBeforeDeletion - 2;
          }

          // Refresh the list and jump to adjusted index
          setState(() {
            _photoDates = _getAllPhotoDates(appState);
            if (_currentIndex >= _photoDates.length) {
              _currentIndex = _photoDates.length - 1;
            }
          });

          // Jump to the new current page
          if (_pageController.hasClients) {
            _pageController.jumpToPage(_currentIndex);
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Photo deleted')),
            );
          }
        }
      }
    }
  }

  String _formatDate(DateTime date) => AppDateUtils.formatLong(date);
}
