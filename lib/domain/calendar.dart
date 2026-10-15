/// Calendar interpretation of expense dates.
///
/// An expense belongs to the calendar day on which its instant falls in the
/// device's local time zone. This one rule is used for display and for
/// monthly grouping, so an expense is always counted in the month it is
/// shown in.
///
/// * Stored date text without an offset (what SpendWise writes) already is
///   local time; it is used as is.
/// * Text with `Z` or an offset (imports, hand-made data) denotes an
///   instant; it is converted to local time first. For example
///   `2026-10-31T23:30:00.000-03:00` is 2026-11-01 for a device in UTC and
///   2026-10-31 for a device in UTC−3.
///
/// Only the interpretation is local; the stored `dateText` is never
/// rewritten to match it.
library;

/// The local calendar date of [instant], at midnight local time.
DateTime localCalendarDate(DateTime instant) {
  final local = instant.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Whether [instant] falls in the same local calendar month as [reference].
bool isInSameLocalMonth(DateTime instant, DateTime reference) {
  final a = instant.toLocal();
  final b = reference.toLocal();
  return a.year == b.year && a.month == b.month;
}
