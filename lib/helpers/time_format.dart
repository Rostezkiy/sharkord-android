import 'package:intl/intl.dart';

/// message list timestamps: a short clock for today, a date for anything older.
String formatMessageTime(DateTime time) {
  final now = DateTime.now();
  final isToday =
      time.year == now.year && time.month == now.month && time.day == now.day;

  if (isToday) return DateFormat.Hm().format(time);

  return DateFormat('d MMM, HH:mm').format(time);
}

/// the divider above the first message of a day.
String formatDayDivider(DateTime time) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final difference = today.difference(day).inDays;

  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  if (now.year == time.year) return DateFormat('EEEE, d MMMM').format(time);

  return DateFormat('d MMMM yyyy').format(time);
}

/// how long ago something happened, in the few words a status line needs.
String formatRelative(int millisecondsSinceEpoch) {
  final difference = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch),
  );

  if (difference.inSeconds < 60) return 'just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  if (difference.inDays < 30) return '${difference.inDays}d ago';

  return DateFormat('d MMM yyyy')
      .format(DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch));
}
