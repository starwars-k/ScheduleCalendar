class DailyEvent {
  final int? id;
  final String title;
  final String description;
  final DateTime? startTime;
  final DateTime endTime;
  final String eventType;
  final String timezone;
  final String startTimezone;
  final String endTimezone;
  final bool isAllDay;
  final bool isRepeating;
  final String? repeatType;
  final bool? endOn;
  final DateTime? repeatEndOn;
  final String? seriesId;
  final bool isTodo;
  final int? linkedTodoId;
  final bool isComplete;

  DailyEvent({
    this.id,
    required this.title,
    required this.description,
    this.startTime,
    required this.endTime,
    required this.eventType,
    this.timezone = 'UTC',
    this.startTimezone = 'UTC',
    this.endTimezone = 'UTC',
    required this.repeatType,
    required this.isAllDay,
    required this.isRepeating,
    this.repeatEndOn,
    this.endOn,
    this.seriesId,
    this.isTodo = false,
    this.linkedTodoId,
    this.isComplete = false,
  });

  factory DailyEvent.fromJson(Map<String, dynamic> json) {
    final fallbackTz = json['timezone']?.toString() ?? 'UTC';
    final startTz = json['startTimezone']?.toString() ?? fallbackTz;
    final endTz = json['endTimezone']?.toString() ?? startTz;
    final bool isTodoFlag = json['isTodo'] == true;

    return DailyEvent(
      id: json['id'] is int ? json['id'] : (int.tryParse(json['id']?.toString() ?? '0') ?? 0),
      title: json['title'] ?? 'No Title',
      description: json['description']?.toString() ?? '',
      startTime: json['startTime'] != null
          ? DateTime.parse(json['startTime'].toString())
          : (isTodoFlag ? null : DateTime.now()),
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'].toString())
          : DateTime.now(),
      eventType: json['eventType']?.toString() ?? 'Unknown',
      timezone: fallbackTz,
      startTimezone: startTz,
      endTimezone: endTz,
      isAllDay: json['isAllDay'] ?? false,
      isRepeating: json['isRepeating'] ?? false,
      repeatType: json['repeatType']?.toString(),
      repeatEndOn: json['repeatEndOn'] != null
          ? DateTime.parse(json['repeatEndOn'].toString())
          : null,
      endOn: json['endOn'] ?? false,
      seriesId: json['seriesId']?.toString(),
      isTodo: isTodoFlag,
      linkedTodoId: json['linkedTodoId'] is int
          ? json['linkedTodoId']
          : int.tryParse(json['linkedTodoId']?.toString() ?? ''),
      isComplete: json['isComplete'] == true,
    );
  }

  static int _fixedOffsetMinutes(String tzName) {
    switch (tzName) {
      case 'Asia/Tokyo':
        return 9 * 60;
      case 'Europe/London':
        return 0;
      case 'Europe/Paris':
        return 1 * 60;
      case 'America/New_York':
        return -5 * 60;
      case 'America/Chicago':
        return -6 * 60;
      case 'America/Denver':
        return -7 * 60;
      case 'America/Los_Angeles':
        return -8 * 60;
      case 'UTC':
      default:
        return 0;
    }
  }

  static DateTime convertUtcToTimezone(DateTime utcOrParsed, String tzName) {
    final utc = DateTime.utc(
      utcOrParsed.year,
      utcOrParsed.month,
      utcOrParsed.day,
      utcOrParsed.hour,
      utcOrParsed.minute,
      utcOrParsed.second,
      utcOrParsed.millisecond,
    );
    final shifted = utc.add(Duration(minutes: _fixedOffsetMinutes(tzName)));
    return DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
      shifted.second,
      shifted.millisecond,
    );
  }

  DateTime? get displayStartTime =>
      startTime != null ? convertUtcToTimezone(startTime!, startTimezone) : null;
  DateTime get displayEndTime => convertUtcToTimezone(endTime, endTimezone);
  DateTime get displayEffectiveTime => isTodo ? displayEndTime : (displayStartTime ?? displayEndTime);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'startTime': startTime?.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'eventType': eventType,
    'timezone': timezone,
    'startTimezone': startTimezone,
    'endTimezone': endTimezone,
    'isAllDay': isAllDay,
    'isRepeating': isRepeating,
    'repeatType': repeatType,
    'repeatEndOn': repeatEndOn?.toIso8601String(),
    'endOn': endOn,
    'seriesId': seriesId,
    'isTodo': isTodo,
    'linkedTodoId': linkedTodoId,
    'isComplete': isComplete,
  };
}