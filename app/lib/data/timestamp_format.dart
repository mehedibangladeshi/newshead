const _enWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _enMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _bnWeekdays = ['সোম', 'মঙ্গল', 'বুধ', 'বৃহস্পতি', 'শুক্র', 'শনি', 'রবি'];
const _bnMonths = [
  'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
  'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর',
];
const _bnDigits = {
  '0': '০', '1': '১', '2': '২', '3': '৩', '4': '৪',
  '5': '৫', '6': '৬', '7': '৭', '8': '৮', '9': '৯',
};

String _toBengaliDigits(String input) =>
    input.split('').map((c) => _bnDigits[c] ?? c).join();

String _formatRelative(Duration diff, bool isBengali) {
  final seconds = diff.inSeconds < 0 ? 0 : diff.inSeconds;
  if (seconds < 60) {
    return isBengali ? 'এইমাত্র' : 'just now';
  }
  final minutes = seconds ~/ 60;
  if (minutes < 60) {
    return isBengali ? '${_toBengaliDigits('$minutes')} মিনিট আগে' : '${minutes}m ago';
  }
  final hours = minutes ~/ 60;
  if (hours < 24) {
    return isBengali ? '${_toBengaliDigits('$hours')} ঘণ্টা আগে' : '${hours}h ago';
  }
  final days = hours ~/ 24;
  return isBengali ? '${_toBengaliDigits('$days')} দিন আগে' : '${days}d ago';
}

/// The absolute day/date and a live relative offset together, e.g.
/// "Sun, Aug 23 · 3h ago" or, for a Bengali-language source, entirely in
/// Bengali with the day-before-month date order that language uses:
/// "রবি, ২৩ আগস্ট · ৩ ঘণ্টা আগে". [now] defaults to the current clock;
/// pass it explicitly in tests for a deterministic result.
String formatPublishedAt(DateTime publishedAt, String language, {DateTime? now}) {
  final effectiveNow = now ?? DateTime.now();
  final local = publishedAt.toLocal();
  final isBengali = language == 'bn';
  final weekday = (isBengali ? _bnWeekdays : _enWeekdays)[local.weekday - 1];
  final month = (isBengali ? _bnMonths : _enMonths)[local.month - 1];
  final day = isBengali ? _toBengaliDigits('${local.day}') : '${local.day}';
  final datePart = isBengali ? '$day $month' : '$month $day';
  final relative = _formatRelative(effectiveNow.difference(publishedAt), isBengali);
  return '$weekday, $datePart · $relative';
}
