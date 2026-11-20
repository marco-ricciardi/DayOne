import 'package:flutter/material.dart';

class AppDateUtils {
  static const List<String> monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];

  static const List<String> monthNamesShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  static const List<String> weekdayNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun'
  ];

  /// Format date as "Mon, Jan 12, 2026"
  static String formatLong(DateTime date) {
    final weekday = weekdayNames[date.weekday - 1];
    final month = monthNamesShort[date.month - 1];
    return '$weekday, $month ${date.day}, ${date.year}';
  }

  /// Format date as "Jan 12, 2026"
  static String formatShort(DateTime date) {
    final month = monthNamesShort[date.month - 1];
    return '$month ${date.day}, ${date.year}';
  }

  /// Format month and year as "January 2026"
  static String formatMonthYear(int year, int month) {
    return '${monthNames[month - 1]} $year';
  }

  /// Format time as "9:00 AM"
  static String formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  /// Check if two dates are the same day
  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Normalize date to midnight (remove time component)
  static DateTime normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// Hour before which a photo counts towards the previous day.
  static const int dayCutoffHour = 5;

  /// The day a photo taken at [moment] belongs to: anything before
  /// [dayCutoffHour] (e.g. 1am) counts as the previous day.
  static DateTime photoDayFor(DateTime moment) {
    final day = DateTime(moment.year, moment.month, moment.day);
    return moment.hour < dayCutoffHour
        ? DateTime(day.year, day.month, day.day - 1)
        : day;
  }
}
