import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'utils/date_utils.dart';

class TimelapseScreen extends StatefulWidget {
  const TimelapseScreen({super.key});

  @override
  State<TimelapseScreen> createState() => _TimelapseScreenState();
}

enum TimelapseInterval {
  daily,
  weekly,
  monthly,
  yearly,
}

class _TimelapseScreenState extends State<TimelapseScreen> {
  bool _isPlaying = false;
  int _currentIndex = 0;
  int _fps = 5; // Frames per second
  TimelapseInterval _interval = TimelapseInterval.daily;
  List<DateTime> _allPhotoDates = [];
  List<DateTime> _filteredPhotoDates = [];
  final Map<DateTime, ImageProvider> _imageCache = {};
  int _loadedPhotoVersion = -1;
  int _playGeneration = 0; // Lets a stale playback loop know it should stop

  @override
  void initState() {
    super.initState();
    _loadedPhotoVersion = context.read<AppState>().photoVersion;
    _loadPhotoDates();
  }

  void _loadPhotoDates() {
    final appState = context.read<AppState>();
    setState(() {
      _allPhotoDates = appState.photos.keys.toList()..sort((a, b) => a.compareTo(b));
      _applyIntervalFilter();
    });

    // Build cache first
    _buildImageCache();

    // Then schedule precaching for after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheInitialImages();
    });
  }

  bool _canUseInterval(TimelapseInterval interval) {
    if (_allPhotoDates.isEmpty) return false;

    List<DateTime> testFiltered;
    switch (interval) {
      case TimelapseInterval.daily:
        return true; // Daily always works if we have any photos
      case TimelapseInterval.weekly:
        testFiltered = _filterByInterval(_allPhotoDates, 7);
        break;
      case TimelapseInterval.monthly:
        testFiltered = _filterMonthly(_allPhotoDates);
        break;
      case TimelapseInterval.yearly:
        testFiltered = _filterYearly(_allPhotoDates);
        break;
    }

    // Need at least 2 photos after filtering to be usable
    return testFiltered.length >= 2;
  }

  void _applyIntervalFilter() {
    if (_allPhotoDates.isEmpty) {
      _filteredPhotoDates = [];
      return;
    }

    List<DateTime> filtered;
    switch (_interval) {
      case TimelapseInterval.daily:
        filtered = List.from(_allPhotoDates);
        break;
      case TimelapseInterval.weekly:
        filtered = _filterByInterval(_allPhotoDates, 7);
        break;
      case TimelapseInterval.monthly:
        filtered = _filterMonthly(_allPhotoDates);
        break;
      case TimelapseInterval.yearly:
        filtered = _filterYearly(_allPhotoDates);
        break;
    }

    // If filter resulted in too few photos, fall back to showing all photos
    if (filtered.isEmpty || (filtered.length < 2 && _allPhotoDates.length >= 2)) {
      _filteredPhotoDates = List.from(_allPhotoDates);
      // Don't change interval setting - just use all photos for this session
    } else {
      _filteredPhotoDates = filtered;
    }

    // Reset current index if out of bounds
    if (_currentIndex >= _filteredPhotoDates.length && _filteredPhotoDates.isNotEmpty) {
      _currentIndex = _filteredPhotoDates.length - 1;
    }
  }

  List<DateTime> _filterByInterval(List<DateTime> dates, int dayInterval) {
    if (dates.isEmpty) return [];

    final filtered = <DateTime>[dates.first];
    DateTime lastIncluded = dates.first;

    for (int i = 1; i < dates.length; i++) {
      final daysDiff = dates[i].difference(lastIncluded).inDays;
      if (daysDiff >= dayInterval) {
        filtered.add(dates[i]);
        lastIncluded = dates[i];
      }
    }

    return filtered;
  }

  List<DateTime> _filterMonthly(List<DateTime> dates) {
    if (dates.isEmpty) return [];

    final filtered = <DateTime>[dates.first];
    int lastMonth = dates.first.month;
    int lastYear = dates.first.year;

    for (int i = 1; i < dates.length; i++) {
      if (dates[i].year != lastYear || dates[i].month != lastMonth) {
        filtered.add(dates[i]);
        lastMonth = dates[i].month;
        lastYear = dates[i].year;
      }
    }

    return filtered;
  }

  List<DateTime> _filterYearly(List<DateTime> dates) {
    if (dates.isEmpty) return [];

    final filtered = <DateTime>[dates.first];
    int lastYear = dates.first.year;

    for (int i = 1; i < dates.length; i++) {
      if (dates[i].year != lastYear) {
        filtered.add(dates[i]);
        lastYear = dates[i].year;
      }
    }

    return filtered;
  }

  void _buildImageCache() {
    final appState = context.read<AppState>();
    _imageCache.clear();

    // Build the cache
    for (final date in _filteredPhotoDates) {
      final photo = appState.getPhotoForDate(date);
      if (photo != null) {
        _imageCache[date] = FileImage(photo);
      }
    }
  }

  Future<void> _precacheInitialImages() async {
    if (!mounted) return;

    // Precache more images upfront for smoother playback
    final imagesToPrecache = _filteredPhotoDates.take(10).toList();

    // Precache in parallel for faster loading
    final futures = <Future>[];
    for (final date in imagesToPrecache) {
      final imageProvider = _imageCache[date];
      if (imageProvider != null) {
        futures.add(
          precacheImage(imageProvider, context).catchError((_) {})
        );
      }
    }

    // Wait for all to complete (or fail)
    await Future.wait(futures);
  }

  @override
  void dispose() {
    _imageCache.clear();
    super.dispose();
  }

  void _togglePlayback() {
    setState(() {
      _isPlaying = !_isPlaying;
      // Invalidate any loop still sleeping from a previous play, so a quick
      // pause/play doesn't leave two loops advancing frames (double speed).
      _playGeneration++;
    });

    if (_isPlaying) {
      _playTimelapse(_playGeneration);
    }
  }

  Future<void> _playTimelapse(int generation) async {
    // Safety check - need at least 2 photos to play
    if (_filteredPhotoDates.length < 2) {
      setState(() {
        _isPlaying = false;
      });
      return;
    }

    while (_isPlaying && mounted && generation == _playGeneration) {
      // Wait for the current frame duration
      await Future.delayed(Duration(milliseconds: (1000 / _fps).round()));
      if (!_isPlaying || !mounted || generation != _playGeneration) break;

      // Check if we're at the last photo
      if (_currentIndex >= _filteredPhotoDates.length - 1) {
        // Finished - loop back to start
        if (mounted) {
          setState(() {
            _currentIndex = 0;
            _isPlaying = false;
          });
        }
        break;
      }

      // Precache next 3 images ahead for smoother playback
      for (int i = 1; i <= 3; i++) {
        final nextIndex = _currentIndex + i;
        if (nextIndex < _filteredPhotoDates.length) {
          final nextImageProvider = _imageCache[_filteredPhotoDates[nextIndex]];
          if (nextImageProvider != null && mounted) {
            precacheImage(nextImageProvider, context).catchError((_) {});
          }
        }
      }

      // Advance to next photo
      setState(() {
        _currentIndex++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    // Refresh photo dates if photos were added/removed/replaced. Compare
    // against the version we loaded, not the filtered list (which is
    // intentionally shorter for weekly/monthly/yearly and caused an endless
    // reload loop).
    if (appState.photoVersion != _loadedPhotoVersion ||
        appState.photos.length != _allPhotoDates.length) {
      _loadedPhotoVersion = appState.photoVersion;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadPhotoDates();
      });
    }

    if (_filteredPhotoDates.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Timelapse')),
        body: const Center(
          child: Text(
            'No photos yet!\nTake some daily photos to create a timelapse.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    // Safety checks for current index
    if (_currentIndex >= _filteredPhotoDates.length) {
      _currentIndex = _filteredPhotoDates.isEmpty ? 0 : _filteredPhotoDates.length - 1;
    }

    final currentDate = _filteredPhotoDates.isNotEmpty ? _filteredPhotoDates[_currentIndex] : DateTime.now();
    final currentImageProvider = _filteredPhotoDates.isNotEmpty ? _imageCache[currentDate] : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Timelapse'),
      ),
      body: Column(
        children: [
          // Preview Area
          Expanded(
            child: Container(
              color: Colors.black,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: currentImageProvider != null
                        ? Image(
                            key: ValueKey(_currentIndex), // Prevent rebuilds for same image
                            image: currentImageProvider,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                            gaplessPlayback: true,
                            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                              // Instant display for cached images (no fade)
                              return child;
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.error_outline, color: Colors.white, size: 48),
                                    SizedBox(height: 8),
                                    Text(
                                      'Photo not found',
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
                  );
                },
              ),
            ),
          ),

          // Info Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[900],
            child: Column(
              children: [
                Text(
                  AppDateUtils.formatLong(currentDate),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Photo ${_currentIndex + 1} of ${_filteredPhotoDates.length}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          // Progress Bar
          if (_filteredPhotoDates.length > 1)
            Slider(
              value: _currentIndex.toDouble(),
              min: 0,
              max: (_filteredPhotoDates.length - 1).toDouble(),
              divisions: _filteredPhotoDates.length - 1,
              onChanged: (value) {
                setState(() {
                  _currentIndex = value.round().clamp(0, _filteredPhotoDates.length - 1);
                });
              },
            ),

          // Controls
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Interval selector
                Row(
                  children: [
                    const Text('Interval:', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButton<TimelapseInterval>(
                        value: _interval,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(
                            value: TimelapseInterval.daily,
                            child: Text('Daily (all photos)'),
                          ),
                          DropdownMenuItem(
                            value: TimelapseInterval.weekly,
                            enabled: _canUseInterval(TimelapseInterval.weekly),
                            child: Text(
                              'Weekly',
                              style: TextStyle(
                                color: _canUseInterval(TimelapseInterval.weekly)
                                    ? null
                                    : Colors.grey,
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: TimelapseInterval.monthly,
                            enabled: _canUseInterval(TimelapseInterval.monthly),
                            child: Text(
                              'Monthly',
                              style: TextStyle(
                                color: _canUseInterval(TimelapseInterval.monthly)
                                    ? null
                                    : Colors.grey,
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: TimelapseInterval.yearly,
                            enabled: _canUseInterval(TimelapseInterval.yearly),
                            child: Text(
                              'Yearly',
                              style: TextStyle(
                                color: _canUseInterval(TimelapseInterval.yearly)
                                    ? null
                                    : Colors.grey,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _interval = value;
                              _applyIntervalFilter();
                              _buildImageCache();
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Speed Control
                Row(
                  children: [
                    const Text('Speed:', style: TextStyle(fontSize: 16)),
                    Expanded(
                      child: Slider(
                        value: _fps.toDouble(),
                        min: 1,
                        max: 15,
                        divisions: 14,
                        label: '$_fps fps',
                        onChanged: (value) {
                          setState(() {
                            _fps = value.round();
                          });
                        },
                      ),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        '$_fps fps',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Play/Pause Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _togglePlayback,
                    icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                    label: Text(
                      _isPlaying ? 'Pause' : 'Play Timelapse',
                      style: const TextStyle(fontSize: 18),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
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
