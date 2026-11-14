import '../models/transport.dart';

class ScheduleSelection {
  const ScheduleSelection(this.date, this.period);
  // Calendar date, not a Firestore timestamp or a UTC instant.
  final DateTime date;
  final TransportPeriod period;
}

/// Operating selection cutoffs, separate from route departure/arrival estimates.
class ScheduleSelectionPolicy {
  const ScheduleSelectionPolicy({
    this.afternoonFromMinute = 9 * 60 + 30,
    this.nextMorningFromMinute = 19 * 60,
  }) : assert(afternoonFromMinute >= 0),
       assert(afternoonFromMinute < nextMorningFromMinute),
       assert(nextMorningFromMinute < 24 * 60);

  static const timeZone = 'Asia/Seoul';
  // Modern Korean operating dates use UTC+09:00, without seasonal changes.
  static const seoulOffset = Duration(hours: 9);
  final int afternoonFromMinute;
  final int nextMorningFromMinute;

  DateTime seoulTime(DateTime instant) => instant.toUtc().add(seoulOffset);

  DateTime today(DateTime instant) {
    final local = seoulTime(instant);
    return DateTime(local.year, local.month, local.day);
  }

  ScheduleSelection select(DateTime instant) {
    final local = seoulTime(instant);
    final minute = local.hour * 60 + local.minute;
    final nextDay = minute >= nextMorningFromMinute;
    return ScheduleSelection(
      DateTime(local.year, local.month, local.day + (nextDay ? 1 : 0)),
      minute >= afternoonFromMinute && !nextDay
          ? TransportPeriod.afternoon
          : TransportPeriod.morning,
    );
  }

  static String weekday(DateTime date) =>
      const ['월', '화', '수', '목', '금', '토', '일'][date.weekday - 1];

  String describe(DateTime date, TransportPeriod period, DateTime instant) {
    final current = today(instant);
    final difference = DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime.utc(current.year, current.month, current.day)).inDays;
    final prefix = difference == 0
        ? '오늘 · '
        : difference == 1
        ? '내일 · '
        : '${date.year}년 ';
    return '$prefix${date.month}월 ${date.day}일 (${weekday(date)}) · ${period.label}';
  }
}
