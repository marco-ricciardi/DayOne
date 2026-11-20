import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'camera_page.dart';
import 'photo_viewer_page.dart';
import 'photo_review_page.dart';
import 'utils/date_utils.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  static const int _startYear = 2020;
  // Always allow paging at least a year past the current one
  final int _endYear =
      DateTime.now().year < 2030 ? 2030 : DateTime.now().year + 1;
  late PageController _pageController;
  late int _currentPageIndex;

  // Calculate initial page to show current month
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Pages represent months from Jan 2020 to Dec 2030
    // Page 0 = Jan 2020, Page 1 = Feb 2020, etc.
    _currentPageIndex = ((now.year - _startYear) * 12) + (now.month - 1);
    _pageController = PageController(initialPage: _currentPageIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Calculate year and month from page index
    final year = _startYear + (_currentPageIndex ~/ 12);
    final month = (_currentPageIndex % 12) + 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(_getMonthYearString(year, month)),
        actions: [
          // Today button
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () {
              final now = DateTime.now();
              final todayPage = ((now.year - _startYear) * 12) + (now.month - 1);
              _pageController.animateToPage(
                todayPage,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
            tooltip: 'Go to today',
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: (_endYear - _startYear + 1) * 12,
        onPageChanged: (index) {
          setState(() {
            _currentPageIndex = index;
          });
        },
        itemBuilder: (context, index) {
          final pageYear = _startYear + (index ~/ 12);
          final pageMonth = (index % 12) + 1;

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: _MonthWidget(
                year: pageYear,
                month: pageMonth,
              ),
            ),
          );
        },
      ),
    );
  }

  String _getMonthYearString(int year, int month) {
    return AppDateUtils.formatMonthYear(year, month);
  }
}

class _MonthWidget extends StatelessWidget {
  final int year;
  final int month;

  const _MonthWidget({
    required this.year,
    required this.month,
  });

  static const List<String> _weekdayNames = AppDateUtils.weekdayNames;

  @override
  Widget build(BuildContext context) {
    final firstDayOfMonth = DateTime(year, month, 1);
    final lastDayOfMonth = DateTime(year, month + 1, 0);
    final daysInMonth = lastDayOfMonth.day;

    // Monday is 1, Sunday is 7
    final firstWeekday = firstDayOfMonth.weekday;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Weekday labels
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: _weekdayNames.map((day) {
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // Date grid
        _buildDateGrid(context, firstWeekday, daysInMonth),
      ],
    );
  }

  Widget _buildDateGrid(BuildContext context, int firstWeekday, int daysInMonth) {
    final List<Widget> cells = [];

    // Add empty cells for alignment
    for (int i = 1; i < firstWeekday; i++) {
      cells.add(const SizedBox());
    }

    // Add date cells
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      cells.add(_DateCell(
        key: ValueKey('$year-$month-$day'),
        date: date,
      ));
    }

    // Pad the last row with empty cells to make complete rows of 7
    final remainder = cells.length % 7;
    if (remainder != 0) {
      for (int i = 0; i < (7 - remainder); i++) {
        cells.add(const SizedBox());
      }
    }

    // Build grid with 7 columns
    final rows = <Widget>[];
    for (int i = 0; i < cells.length; i += 7) {
      final rowCells = cells.sublist(i, i + 7);
      rows.add(
        Row(
          children: rowCells.map((cell) => Expanded(child: cell)).toList(),
        ),
      );
    }

    return Column(children: rows);
  }
}

class _DateCell extends StatelessWidget {
  final DateTime date;

  const _DateCell({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    // Use select to only rebuild when this specific date's photo changes
    final hasPhoto = context.select<AppState, bool>(
      (state) => state.hasPhotoForDate(date),
    );
    final photo = context.select<AppState, File?>(
      (state) => state.getPhotoForDate(date),
    );
    // Changes when any photo is rewritten, so replaced/re-aligned photos reload
    final photoVersion = context.select<AppState, int>(
      (state) => state.photoVersion,
    );
    final now = DateTime.now();
    final isToday = _isSameDay(date, now);
    final isFuture = date.isAfter(DateTime(now.year, now.month, now.day));
    final isPastOrToday = !isFuture;
    final showPlusIcon = isPastOrToday && !hasPhoto;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: isFuture ? null : () => _handleTap(context, hasPhoto, photo),
        child: AspectRatio(
          aspectRatio: 0.75, // Make cells taller (3:4 ratio)
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              border: isToday
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    )
                  : null,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Photo thumbnail if exists
                if (hasPhoto && photo != null)
                  ClipRect(
                    child: Image.file(
                      photo,
                      key: ValueKey('${photo.path}_$photoVersion'),
                      fit: BoxFit.cover,
                      // Performance optimizations
                      cacheWidth: AppState.thumbnailCacheWidth, // Decode at reasonable thumbnail size (height auto-calculated)
                      filterQuality: FilterQuality.medium, // Balance quality/performance
                      gaplessPlayback: true, // Smooth loading
                      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                        // Skip fade for cached images
                        if (wasSynchronouslyLoaded) {
                          return child;
                        }
                        // Show placeholder while loading
                        return AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: const Duration(milliseconds: 100),
                          child: child,
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey.withValues(alpha: 0.3),
                          child: Icon(Icons.error_outline, color: Colors.grey[600]),
                        );
                      },
                    ),
                  )
                else
                  Container(
                    color: isFuture
                        ? Colors.grey.withValues(alpha: 0.1)
                        : Colors.transparent,
                  ),

                // Plus icon for past/today dates without photos
                if (showPlusIcon)
                  Center(
                    child: Icon(
                      Icons.add_circle_outline,
                      size: 32,
                      color: Colors.grey[400],
                    ),
                  ),

                // Day number overlay
                Positioned(
                  top: 1,
                  left: 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: hasPhoto
                          ? Colors.black.withValues(alpha: 0.6)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 10,
                        color: hasPhoto
                            ? Colors.white
                            : isFuture
                                ? Colors.grey[400]
                                : Colors.grey[700],
                        fontWeight: hasPhoto ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) => AppDateUtils.isSameDay(a, b);

  void _handleTap(BuildContext context, bool hasPhoto, File? photo) {
    if (hasPhoto && photo != null) {
      // Navigate to photo viewer
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PhotoViewerPage(
            photo: photo,
            date: date,
          ),
        ),
      );
    } else {
      // Show dialog with options
      _showAddPhotoDialog(context);
    }
  }

  Future<void> _showAddPhotoDialog(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_formatShortDate(date)),
        content: const Text('How would you like to add a photo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'gallery'),
            child: const Text('From Gallery'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'camera'),
            child: const Text('Take Photo'),
          ),
        ],
      ),
    );

    if (!context.mounted) return;

    if (result == 'gallery') {
      await _addPhotoFromGallery(context);
    } else if (result == 'camera') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (cameraContext) => CameraPage(
            forDate: date,
            // Close the camera and return to the calendar once saved
            onPhotoSaved: () => Navigator.pop(cameraContext),
          ),
        ),
      );
    }
  }

  Future<void> _addPhotoFromGallery(BuildContext context) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null && context.mounted) {
      // Navigate to review page instead of saving directly
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => PhotoReviewPage(
            photo: File(image.path),
            forDate: date,
            autoSave: false,
            fromGallery: true,
          ),
        ),
      );

      // Show success message if photo was saved
      if (result == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Photo added for ${_formatShortDate(date)}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  String _formatShortDate(DateTime date) => AppDateUtils.formatShort(date);
}
