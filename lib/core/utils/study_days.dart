/// Split absolute elapsed milliseconds at local calendar midnights. Calendar
/// construction (not 24-hour arithmetic) respects short/long DST days.
Map<String, int> splitStudyDays(DateTime start, DateTime end,
    {DateTime Function(DateTime)? localize,
    DateTime Function(DateTime)? nextMidnight}) {
  final result = <String, int>{};
  var cursor = start.toUtc();
  final stop = end.toUtc();
  while (cursor.isBefore(stop)) {
    final local = localize?.call(cursor) ?? cursor.toLocal();
    final boundary = (nextMidnight?.call(local) ??
            DateTime(local.year, local.month, local.day + 1))
        .toUtc();
    if (!boundary.isAfter(cursor)) {
      throw StateError('Local midnight must advance time.');
    }
    final until = boundary.isBefore(stop) ? boundary : stop;
    final key =
        '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    result.update(key, (ms) => ms + until.difference(cursor).inMilliseconds,
        ifAbsent: () => until.difference(cursor).inMilliseconds);
    cursor = until;
  }
  return result;
}
