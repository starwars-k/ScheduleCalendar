import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:calendar_frontend/event_model.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';

final ValueNotifier<bool> globalLoading = ValueNotifier<bool>(false);

class EventDetailPage extends StatefulWidget {
  final DailyEvent event;
  final String authToken;
  final Function() onUpdate;
  final Function(int) onDelete;
  final Function(String) onEdit;
  final List<String> allEventTypes;
  final Function(String) onEventTypeChanged;
  final bool isJapanese;

  const EventDetailPage({
    super.key,
    required this.event,
    required this.authToken,
    required this.onDelete,
    required this.onUpdate,
    required this.onEdit,
    required this.allEventTypes,
    required this.onEventTypeChanged,
    this.isJapanese = false,
  });

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  late String _eventType;
  static const String _baseUrl = 'https://calendar-backend-qhny.onrender.com';
  //static const String _baseUrl = 'http://localhost:8080';

  static const Color _appleRed = Color(0xFFFF3B30);
  static const Color _appleGroupedBg = Color(0xFFF2F2F7);
  static const Color _appleHairline = Color(0xFFE5E5EA);
  static const Color _appleSecondaryLabel = Color(0xFF8E8E93);

  Map<String, String> _headers({bool json = false}) {
    final headers = <String, String>{
      'Authorization': 'Bearer ${widget.authToken}',
    };
    if (json) {
      headers['Content-Type'] = 'application/json';
    }
    return headers;
  }

  Color _getEventColor(String type) {
    switch (type) {
      case 'Task':
        return Colors.blueAccent;
      case 'Job':
        return Colors.greenAccent;
      case 'Class':
        return Colors.orangeAccent;
      case 'Birthday':
        return Colors.pinkAccent;
      case 'Personal':
        return Colors.purpleAccent;
      default:
        return Colors.grey;
    }
  }

  @override
  void initState() {
    super.initState();
    _eventType = widget.event.eventType;
  }

  Future<void> _deleteSingleEvent() async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/api/events/${widget.event.id}'),
        headers: _headers(),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        widget.onDelete(widget.event.id!);
        if (mounted) Navigator.pop(context);
      } else {
        debugPrint("Failed to delete event: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Connection Error: $e");
    }
  }

  Future<void> _deleteFutureEvents() async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/api/events/future/${widget.event.id}'),
        headers: _headers(),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        widget.onDelete(widget.event.id!);
        if (mounted) Navigator.pop(context);
      } else {
        debugPrint("Failed to delete future events: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Connection Error: $e");
    }
  }

  void _onDeleteButtonPressed() {
    final bool isSeriesEvent =
        widget.event.isRepeating == true && widget.event.seriesId != null;
    if (isSeriesEvent) {
      showCupertinoModalPopup<void>(
        context: context,
        builder: (BuildContext sheetContext) => CupertinoActionSheet(
          title: Text(widget.isJapanese ? '予定を削除' : 'Delete Event'),
          message: Text(
            widget.isJapanese
                ? 'これは繰り返しの予定です。'
                : 'This is a repeating event.',
          ),
          actions: [
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(sheetContext);
                _deleteSingleEvent();
              },
              child: Text(
                widget.isJapanese ? 'この予定のみ削除' : 'Delete This Event Only',
              ),
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(sheetContext);
                _deleteFutureEvents();
              },
              child: Text(
                widget.isJapanese ? 'これ以降の予定をすべて削除' : 'Delete All Future Events',
              ),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(sheetContext),
            child: Text(widget.isJapanese ? 'キャンセル' : 'Cancel'),
          ),
        ),
      );
    } else {
      showCupertinoModalPopup<void>(
        context: context,
        builder: (BuildContext sheetContext) => CupertinoActionSheet(
          title: Text(widget.isJapanese ? '予定を削除' : 'Delete Event'),
          actions: [
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(sheetContext);
                _deleteSingleEvent();
              },
              child: Text(widget.isJapanese ? '予定を削除' : 'Delete Event'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(sheetContext),
            child: Text(widget.isJapanese ? 'キャンセル' : 'Cancel'),
          ),
        ),
      );
    }
  }

  Future<void> _updateEventTypeOnServer(String newType) async {
    await showLoadingIfNeeded(() async {
      try {
        final Map<String, dynamic> eventData = {
          'title': widget.event.title,
          'description': widget.event.description,
          'eventType': newType,
          'startTime': widget.event.isTodo
              ? null
              : widget.event.displayStartTime?.toIso8601String(),
          'endTime': widget.event.displayEndTime.toIso8601String(),
          'timezone': widget.event.timezone,
          'startTimezone': widget.event.startTimezone,
          'endTimezone': widget.event.endTimezone,
          'isAllDay': widget.event.isAllDay,
          'isRepeating': widget.event.isRepeating,
          'repeatType': widget.event.repeatType ?? 'None',
          'endOn': widget.event.endOn ?? (widget.event.repeatEndOn != null),
          'repeatEndOn': widget.event.repeatEndOn != null
              ? DailyEvent.convertUtcToTimezone(
                  widget.event.repeatEndOn!,
                  widget.event.startTimezone,
                ).toIso8601String()
              : null,
          'isTodo': widget.event.isTodo,
          'isComplete': widget.event.isComplete,
        };
        final response = await http.put(
          Uri.parse('$_baseUrl/api/events/${widget.event.id}'),
          headers: _headers(json: true),
          body: jsonEncode(eventData),
        );
        if (response.statusCode == 200 || response.statusCode == 204) {
          widget.onUpdate();
        }
      } catch (e) {
        debugPrint("Error updating eventType: $e");
      }
    });
  }

  Future<T> showLoadingIfNeeded<T>(Future<T> Function() task) async {
    bool isShown = false;
    Timer timer = Timer(const Duration(milliseconds: 100), () {
      isShown = true;
      globalLoading.value = true;
    });

    try {
      return await task();
    } finally {
      timer.cancel();
      if (isShown) {
        globalLoading.value = false;
      }
    }
  }

  Future<void> _saveOnExit() async {
    widget.onUpdate();
  }

  List<String> _buildAppleTimeLines() {
    final end = widget.event.displayEndTime;
    final String dateFmt = widget.isJapanese ? 'yyyy年M月d日 (E)' : 'EEEE, MMM d, yyyy';
    if (widget.event.isTodo) {
      final String dueText = widget.event.isAllDay
          ? (widget.isJapanese
              ? '期限: ${DateFormat(dateFmt).format(end)} (終日)'
              : 'Due: ${DateFormat(dateFmt).format(end)} (All-day)')
          : (widget.isJapanese
              ? '期限: ${DateFormat(dateFmt).format(end)} ${DateFormat('HH:mm').format(end)} (${widget.event.timezone.split('/').last})'
              : 'Due: ${DateFormat(dateFmt).format(end)} at ${DateFormat('HH:mm').format(end)} (${widget.event.timezone.split('/').last})');
      return [dueText];
    }

    final start = widget.event.displayStartTime ?? end;
    final bool isSameDay =
        start.year == end.year && start.month == end.month && start.day == end.day;

    if (widget.event.isAllDay && isSameDay) {
      return [
        DateFormat(dateFmt).format(start),
        widget.isJapanese ? '終日' : 'All-day',
      ];
    } else if (widget.event.isAllDay) {
      return [
        '${DateFormat(dateFmt).format(start)} – ${DateFormat(dateFmt).format(end)}',
        widget.isJapanese ? '終日' : 'All-day',
      ];
    } else if (isSameDay) {
      return [
        DateFormat(dateFmt).format(start),
        '${DateFormat('HH:mm').format(start)} (${widget.event.startTimezone.split('/').last}) – ${DateFormat('HH:mm').format(end)} (${widget.event.endTimezone.split('/').last})',
      ];
    } else {
      return [
        '${widget.isJapanese ? '開始' : 'Starts'}: ${DateFormat(dateFmt).format(start)} ${DateFormat('HH:mm').format(start)} (${widget.event.startTimezone.split('/').last})',
        '${widget.isJapanese ? '終了' : 'Ends'}: ${DateFormat(dateFmt).format(end)} ${DateFormat('HH:mm').format(end)} (${widget.event.endTimezone.split('/').last})',
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color eventColor = _getEventColor(_eventType);
    final List<String> timeLines = _buildAppleTimeLines();
    final bool hasRepeat = widget.event.isRepeating == true &&
        widget.event.repeatType != null &&
        widget.event.repeatType != 'None';

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) {
          _saveOnExit();
        }
      },
      child: Scaffold(
        backgroundColor: _appleGroupedBg,
        body: Column(
          children: [
            // Apple Calendar Navigation Header
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF9F9FB),
                border: Border(bottom: BorderSide(color: _appleHairline, width: 0.5)),
              ),
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: 48,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        onPressed: () => Navigator.pop(context),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              CupertinoIcons.chevron_left,
                              size: 20,
                              color: _appleRed,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              widget.isJapanese ? 'カレンダー' : 'Calendar',
                              style: const TextStyle(
                                color: _appleRed,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        widget.isJapanese ? '予定の詳細' : 'Event Details',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        onPressed: () => widget.onEdit(_eventType),
                        child: Text(
                          widget.isJapanese ? '編集' : 'Edit',
                          style: const TextStyle(
                            color: _appleRed,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Grouped Content Cards
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
                    children: [
                      // Card 1: Title & Date/Time Summary
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 4,
                                  height: 24,
                                  margin: const EdgeInsets.only(top: 2, right: 10),
                                  decoration: BoxDecoration(
                                    color: eventColor,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    widget.event.title,
                                    style: const TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.4,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            for (int i = 0; i < timeLines.length; i++) ...[
                              Text(
                                timeLines[i],
                                style: TextStyle(
                                  fontSize: 15,
                                  color: i == 0 ? Colors.black87 : _appleSecondaryLabel,
                                ),
                              ),
                              if (i < timeLines.length - 1) const SizedBox(height: 3),
                            ],
                            if (hasRepeat) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(
                                    CupertinoIcons.repeat,
                                    size: 14,
                                    color: _appleRed,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    widget.isJapanese
                                        ? '繰り返し: ${widget.event.repeatType}'
                                        : 'Repeats ${widget.event.repeatType}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: _appleRed,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Card 2: Calendar / Event Type Picker
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              widget.isJapanese ? 'カレンダー' : 'Calendar',
                              style: const TextStyle(fontSize: 15, color: Colors.black),
                            ),
                            DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _eventType.isNotEmpty
                                    ? _eventType
                                    : widget.allEventTypes.first,
                                icon: const Icon(
                                  CupertinoIcons.chevron_up_chevron_down,
                                  size: 16,
                                  color: _appleSecondaryLabel,
                                ),
                                items: widget.allEventTypes.map((String type) {
                                  return DropdownMenuItem<String>(
                                    value: type,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: _getEventColor(type),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          type,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (String? newValue) async {
                                  if (newValue != null && newValue != _eventType) {
                                    setState(() {
                                      _eventType = newValue;
                                    });
                                    widget.onEventTypeChanged(newValue);
                                    await _updateEventTypeOnServer(newValue);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Card 3: Notes / Memo
                      if (widget.event.description.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.isJapanese ? 'メモ' : 'Notes',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _appleSecondaryLabel,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.event.description,
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: Colors.black87,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Card 4: Apple Calendar Full-Width Red Delete Row
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _onDeleteButtonPressed,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Center(
                              child: Text(
                                widget.isJapanese ? '予定を削除' : 'Delete Event',
                                style: const TextStyle(
                                  color: _appleRed,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}