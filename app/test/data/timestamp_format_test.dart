import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/data/timestamp_format.dart';

void main() {
  test('formats an English source with hours-ago relative time', () {
    final publishedAt = DateTime(2026, 8, 23, 10, 0);
    final now = DateTime(2026, 8, 23, 13, 0);
    expect(formatPublishedAt(publishedAt, 'en', now: now), 'Sun, Aug 23 · 3h ago');
  });

  test('formats a Bengali source with hours-ago relative time in Bengali', () {
    final publishedAt = DateTime(2026, 8, 23, 10, 0);
    final now = DateTime(2026, 8, 23, 13, 0);
    expect(formatPublishedAt(publishedAt, 'bn', now: now), 'রবি, ২৩ আগস্ট · ৩ ঘণ্টা আগে');
  });

  test('formats minutes-ago relative time', () {
    final publishedAt = DateTime(2026, 8, 23, 12, 15);
    final now = DateTime(2026, 8, 23, 13, 0);
    expect(formatPublishedAt(publishedAt, 'en', now: now), 'Sun, Aug 23 · 45m ago');
  });

  test('formats days-ago relative time', () {
    final publishedAt = DateTime(2026, 8, 21, 10, 0);
    final now = DateTime(2026, 8, 23, 13, 0);
    expect(formatPublishedAt(publishedAt, 'en', now: now), 'Fri, Aug 21 · 2d ago');
  });

  test('clamps a future timestamp (clock skew) to just now in English', () {
    final publishedAt = DateTime(2026, 8, 23, 13, 5);
    final now = DateTime(2026, 8, 23, 13, 0);
    expect(formatPublishedAt(publishedAt, 'en', now: now), 'Sun, Aug 23 · just now');
  });

  test('clamps a future timestamp (clock skew) to just now in Bengali', () {
    final publishedAt = DateTime(2026, 8, 23, 13, 5);
    final now = DateTime(2026, 8, 23, 13, 0);
    expect(formatPublishedAt(publishedAt, 'bn', now: now), 'রবি, ২৩ আগস্ট · এইমাত্র');
  });

  test('defaults now to the current clock when not provided', () {
    final publishedAt = DateTime.now().subtract(const Duration(minutes: 5));
    expect(formatPublishedAt(publishedAt, 'en'), contains('ago'));
  });

  test('formats weeks-ago relative time', () {
    final publishedAt = DateTime(2026, 8, 10, 10, 0);
    final now = DateTime(2026, 8, 23, 13, 0);
    expect(formatPublishedAt(publishedAt, 'en', now: now), 'Mon, Aug 10 · 1w ago');
  });

  test('formats months-ago relative time', () {
    final publishedAt = DateTime(2026, 6, 1, 10, 0);
    final now = DateTime(2026, 8, 23, 13, 0);
    expect(formatPublishedAt(publishedAt, 'en', now: now), 'Mon, Jun 1 · 2mo ago');
  });

  test('formats years-ago relative time', () {
    final publishedAt = DateTime(2024, 8, 1, 10, 0);
    final now = DateTime(2026, 8, 23, 13, 0);
    expect(formatPublishedAt(publishedAt, 'en', now: now), 'Thu, Aug 1 · 2y ago');
  });
}
