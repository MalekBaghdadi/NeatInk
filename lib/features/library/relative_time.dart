/// Short English date/time phrases for the library.
///
/// Hand-written instead of pulling in `intl`: the app is English-only for
/// now and only needs a handful of formats.
library;

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const List<String> _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
  'Sunday',
];

/// "25 Oct 2026".
String formatDate(DateTime t) {
  final l = t.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.year}';
}

/// How long ago [time] was, relative to [now]:
/// "just now", "5 min ago", "3 h ago" (same day), "yesterday",
/// "Monday" (within the last week), "12 Mar" (this year), "12 Mar 2024".
///
/// Calendar comparisons use local time. A [time] in the future (clock skew,
/// a notebook copied from another device) reads as "just now".
String formatRelative(DateTime time, DateTime now) {
  final t = time.toLocal(), n = now.toLocal();
  final diff = n.difference(t);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  final days = _calendarDaysBetween(t, n);
  if (days == 0) return '${diff.inHours} h ago';
  if (days == 1) return 'yesterday';
  if (days < 7) return _weekdays[t.weekday - 1];
  if (t.year == n.year) return '${t.day} ${_months[t.month - 1]}';
  return formatDate(t);
}

/// "Edited 5 min ago", "Edited yesterday", "Edited 12 Mar".
String formatEdited(DateTime updatedAt, DateTime now) {
  final r = formatRelative(updatedAt, now);
  // Weekday and date phrases read better with "on".
  final needsOn = r.isNotEmpty &&
      r != 'just now' &&
      r != 'yesterday' &&
      !r.endsWith(' ago');
  return needsOn ? 'Edited on $r' : 'Edited $r';
}

/// Whole calendar days from [a] to [b]. The local dates are compared as UTC
/// midnights, so a 23 h or 25 h day around a DST change still counts as one.
int _calendarDaysBetween(DateTime a, DateTime b) {
  final da = DateTime.utc(a.year, a.month, a.day);
  final db = DateTime.utc(b.year, b.month, b.day);
  return db.difference(da).inDays;
}
