import 'package:calendar_frontend/EventDetailPage.dart';
import 'package:calendar_frontend/login_page.dart';
import 'package:calendar_frontend/initialSetupPage.dart';
import 'package:calendar_frontend/event_model.dart';
import 'package:calendar_frontend/todo_list_page.dart';
import 'package:calendar_frontend/settings_page.dart';

import 'package:table_calendar/table_calendar.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import 'dart:convert';
import 'dart:async';
import 'dart:ui';

const String kBackendBaseUrl = 'https://calendar-backend-qhny.onrender.com';
//const String kBackendBaseUrl = 'http://localhost:8080';
final ValueNotifier<bool> globalLoading = ValueNotifier<bool>(false);

void main() => runApp(
      MaterialApp(
        home: const AuthGatePage(),
        builder: (context, child) {
          return Stack(
            children: [
              child!,
              ValueListenableBuilder<bool>(
                valueListenable: globalLoading,
                builder: (context, isLoading, child) {
                  if (!isLoading) return const SizedBox.shrink();
                  return Container(
                    color: Colors.black.withOpacity(0.3),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Colors.black,
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );

class AuthGatePage extends StatefulWidget {
  const AuthGatePage({super.key});

  @override
  State<AuthGatePage> createState() => _AuthGatePageState();
}

class _AuthGatePageState extends State<AuthGatePage> {
  String? _token;
  String? _username;
  UserAppSettings _appSettings = const UserAppSettings();
  bool _checkingAuth = true;
  bool _isNewRegistration = false;

  @override
  void initState() {
    super.initState();
    _loadSavedAuth();
  }

  Future<void> _loadSavedAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('auth_token');
    final savedUsername = prefs.getString('auth_username');
    final cachedSettings = await UserAppSettings.loadFromCache();

    if (!mounted) return;
    setState(() {
      _token = (savedToken != null && savedToken.isNotEmpty) ? savedToken : null;
      _username = savedUsername;
      _appSettings = cachedSettings;
      _checkingAuth = false;
    });

    if (savedToken != null && savedToken.isNotEmpty) {
      try {
        final response = await http.get(
          Uri.parse('$kBackendBaseUrl/api/user/settings'),
          headers: {'Authorization': 'Bearer $savedToken'},
        );
        if (response.statusCode == 200 && mounted) {
          final freshSettings = UserAppSettings.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>,
          );
          await freshSettings.saveToCache();
          setState(() {
            _appSettings = freshSettings;
          });
        }else if (response.statusCode == 401 && mounted){
          await _logout();
        }
      } catch (_) {}
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_username');
    await prefs.remove('auth_userId');
    await prefs.remove('auth_user_settings');
    if (!mounted) return;
    setState(() {
      _token = null;
      _username = null;
      _appSettings = const UserAppSettings();
      _isNewRegistration = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAuth) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_token == null) {
      return LoginPage(
        backendBaseUrl: kBackendBaseUrl,
        onLoginSuccess: (token, username, settings, isRegisterMode) {
          setState(() {
            _token = token;
            _username = username;
            _appSettings = settings;
            _isNewRegistration = isRegisterMode;
          });
        },
      );
    }
    if (_isNewRegistration && !_appSettings.setupComplete) {
      return InitialSetupPage(
        backendBaseUrl: kBackendBaseUrl,
        authToken: _token!,
        username: _username ?? '',
        initialSettings: _appSettings,
        onSetupComplete: (updatedSettings) {
          setState(() {
            _appSettings = updatedSettings;
            _isNewRegistration = false;
          });
        },
      );
    }
    return CalendarPage(
      authToken: _token!,
      username: _username ?? '',
      appSettings: _appSettings,
      onLogout: _logout,
    );
  }
}

class CalendarPage extends StatefulWidget {
  final String authToken;
  final String username;
  final UserAppSettings appSettings;
  final Future<void> Function() onLogout;

  const CalendarPage({
    super.key,
    required this.authToken,
    required this.username,
    required this.appSettings,
    required this.onLogout,
  });

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();
  String _eventType = 'Task';
  late String _startTimezone;
  late String _endTimezone;
  String _repeatType = 'Daily';
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  DateTime _startTime = DateTime.now();
  DateTime _endTime = DateTime.now().add(const Duration(hours: 1));
  bool _isAllDay = false;
  bool _isRepeating = false;
  bool _endOn = false;
  bool _isTodo = false;
  bool _setDueTime = false;
  bool _isComplete = false;
  int _currentTabIndex = 0;
  late UserAppSettings _activeSettings;
  bool _showStartTimezonePicker = false;
  bool _showEndTimezonePicker = false;
  final bool _isSearching = false;
  DateTime _repeatEndDate = DateTime.now().add(const Duration(days: 1));
  CalendarFormat _calendarFormat = CalendarFormat.month;
  List<DailyEvent> _events = [];
  Set<int> _highPriorityTodoEventIds = {};

  Map<String, String> _authHeaders({bool json = false}) {
    final headers = <String, String>{
      'Authorization': 'Bearer ${widget.authToken}',
    };
    if (json) {
      headers['Content-Type'] = 'application/json';
    }
    return headers;
  }

  List<DailyEvent> get _selectedEvents {
    final list = _events.where((event) {
      if (event.isTodo) {
        return isSameDay(event.displayEndTime, _selectedDay);
      }
      final dayStart = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day, 0, 0, 0);
      final dayEnd = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day, 23, 59, 59);
      return event.displayEffectiveTime.isBefore(dayEnd) && event.displayEndTime.isAfter(dayStart);
    }).toList();
    list.sort((a, b) => a.displayEffectiveTime.compareTo(b.displayEffectiveTime));
    return list;
  }

  final List<String> _eventTypes = ['Task', 'Job', 'Class', 'Birthday', 'Personal'];
  final List<String> _repeatOptions = ['Daily', 'Weekly', 'Biweekly', 'Monthly', 'Yearly'];

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

  String _defaultUserTimezone() {
    return kSupportedTimezones.contains(widget.appSettings.timezone)
        ? widget.appSettings.timezone
        : 'America/Chicago';
  }

  @override
  void initState() {
    super.initState();
    _activeSettings = widget.appSettings;
    _startTimezone = _defaultUserTimezone();
    _endTimezone = _defaultUserTimezone();
    fetchEventsFromJava();
  }

  Future<bool?> _showAddEventDialog(
    BuildContext context,
    DateTime initialDate, {
    DailyEvent? eventToEdit,
    String? initialEventType,
  }) async {
    final bool isEditing = eventToEdit != null;
    _titleController.text = isEditing ? eventToEdit.title : '';
    _memoController.text = isEditing ? eventToEdit.description : '';
    _isTodo = _activeSettings.enableTodoList
      ?(isEditing ? eventToEdit.isTodo : false)
      :false;
    _setDueTime = (_isTodo && isEditing) ? !eventToEdit.isAllDay : false;
    _isComplete = isEditing ? eventToEdit.isComplete : false;
    _startTime = isEditing
        ? (eventToEdit.displayStartTime ?? eventToEdit.displayEndTime.subtract(const Duration(hours: 1)))
        : DateTime(initialDate.year, initialDate.month, initialDate.day, DateTime.now().hour);
    _endTime = isEditing ? eventToEdit.displayEndTime : _startTime.add(const Duration(hours: 1));
    _eventType = initialEventType ?? (isEditing ? eventToEdit.eventType : 'Task');
    _startTimezone = (isEditing && kSupportedTimezones.contains(eventToEdit.startTimezone))
        ? eventToEdit.startTimezone
        : _defaultUserTimezone();
    _endTimezone = (isEditing && kSupportedTimezones.contains(eventToEdit.endTimezone))
        ? eventToEdit.endTimezone
        : _startTimezone;
    _isAllDay = isEditing ? eventToEdit.isAllDay : false;
    _isRepeating = isEditing ? eventToEdit.isRepeating : false;
    _showStartTimezonePicker = false;
    _showEndTimezonePicker = false;
    _repeatType = (_isRepeating &&
            isEditing &&
            eventToEdit.repeatType != null &&
            _repeatOptions.contains(eventToEdit.repeatType))
        ? eventToEdit.repeatType!
        : (_isRepeating ? 'Daily' : 'None');
    _endOn = isEditing ? (eventToEdit.endOn ?? (eventToEdit.repeatEndOn != null)) : false;

    if (isEditing && eventToEdit.repeatEndOn != null) {
      _repeatEndDate = DailyEvent.convertUtcToTimezone(eventToEdit.repeatEndOn!, eventToEdit.startTimezone);
    } else {
      _repeatEndDate = initialDate.add(const Duration(days: 1));
    }
    final bool isJapanese = _activeSettings.language == 'ja';
    String? activePicker; // 'startDate', 'startTime', 'startTz', 'endDate', 'endTime', 'endTz', 'repeatEnd'
    String repeatDisplayLabel(String value) {
      if (isJapanese) {
        switch (value) {
          case 'Daily':
            return '毎日';
          case 'Weekly':
            return '毎週';
          case 'Biweekly':
            return '2週間ごと';
          case 'Monthly':
            return '毎月';
          case 'Yearly':
            return '毎年';
          case 'None':
          default:
            return 'しない';
        }
      }
      switch (value) {
        case 'Daily':
          return 'Every Day';
        case 'Weekly':
          return 'Every Week';
        case 'Biweekly':
          return 'Every 2 Weeks';
        case 'Monthly':
          return 'Every Month';
        case 'Yearly':
          return 'Every Year';
        case 'None':
        default:
          return 'Never';
      }
    }

    return await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void togglePicker(String key) {
            setDialogState(() {
              activePicker = (activePicker == key) ? null : key;
            });
          }

          Future<void> handleSubmit() async {
            if (_titleController.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isJapanese ? 'タイトルを入力してください' : 'Event title cannot be empty!',
                  ),
                ),
              );
              return;
            }
            if (isEditing && eventToEdit.id != null) {
              globalLoading.value = true;
              final bool success = await _updateEvent(eventToEdit.id!, _startTime, _endTime);
              if (success && context.mounted) {
                Navigator.pop(context, true);
              }
            } else {
              await _makeNewEvents(_startTime, _endTime);
            }
          }

          Widget buildGroupedCard(List<Widget> children) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < children.length; i++) ...[
                    children[i],
                    if (i < children.length - 1)
                      const Divider(
                        height: 1,
                        thickness: 0.5,
                        indent: 16,
                        color: Color(0xFFE5E5EA),
                      ),
                  ],
                ],
              ),
            );
          }

          Widget buildApplePill({
            required String label,
            required bool isActive,
            required VoidCallback onTap,
            IconData? icon,
          }) {
            return GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive
                      ? CupertinoColors.activeBlue.withOpacity(0.14)
                      : const Color(0xFFEFEFF4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 13,
                        color: isActive ? CupertinoColors.activeBlue : Colors.black87,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isActive ? CupertinoColors.activeBlue : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          Widget buildResponsivePickerRow({
            required String label,
            required List<Widget> pills,
            required bool isVeryNarrow,
          }) {
            if (isVeryNarrow) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 15, color: Colors.black)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: pills),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Text(label, style: const TextStyle(fontSize: 15, color: Colors.black)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 6,
                      runSpacing: 6,
                      children: pills,
                    ),
                  ),
                ],
              ),
            );
          }

          Widget buildInlineWheelDatePicker({
            required String pickerKey,
            required DateTime currentDate,
            required void Function(DateTime picked) onDateChanged,
          }) {
            return SizedBox(
              height: 180,
              child: CupertinoDatePicker(
                key: ValueKey(pickerKey),
                mode: CupertinoDatePickerMode.date,
                initialDateTime: DateTime(currentDate.year, currentDate.month, currentDate.day),
                minimumDate: DateTime(2000, 1, 1),
                maximumDate: DateTime(2100, 12, 31),
                onDateTimeChanged: onDateChanged,
              ),
            );
          }

          Widget buildInlineWheelTimePicker({
            required String pickerKey,
            required DateTime currentTime,
            required void Function(DateTime picked) onTimeChanged,
          }) {
            return SizedBox(
              height: 180,
              child: CupertinoDatePicker(
                key: ValueKey(pickerKey),
                mode: CupertinoDatePickerMode.time,
                initialDateTime: currentTime,
                use24hFormat: true,
                onDateTimeChanged: onTimeChanged,
              ),
            );
          }

          final bool canSubmit = _titleController.text.trim().isNotEmpty;
          final String datePattern = isJapanese ? 'yyyy/MM/dd' : 'MMM d, yyyy';

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.94,
                color: const Color(0xFFF2F2F7),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final bool isVeryNarrow = constraints.maxWidth < 365;
                    final double outerPadding = isVeryNarrow ? 12.0 : 16.0;

                    return Column(
                      children: [
                        // Apple Calendar Top Drag Handle + Navigation Bar
                        Container(
                          color: const Color(0xFFF9F9FB),
                          padding: const EdgeInsets.only(top: 8, bottom: 4, left: 8, right: 8),
                          child: Column(
                            children: [
                              Container(
                                width: 36,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFC7C7CC),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  CupertinoButton(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    onPressed: () => Navigator.pop(context, false),
                                    child: Text(
                                      isJapanese ? 'キャンセル' : 'Cancel',
                                      style: const TextStyle(
                                        color: CupertinoColors.activeBlue,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    isEditing
                                        ? (isJapanese ? '予定を編集' : 'Edit Event')
                                        : (isJapanese ? '新規予定' : 'New Event'),
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black,
                                    ),
                                  ),
                                  CupertinoButton(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    onPressed: canSubmit ? handleSubmit : null,
                                    child: Text(
                                      isEditing
                                          ? (isJapanese ? '更新' : 'Update')
                                          : (isJapanese ? '追加' : 'Add'),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: canSubmit
                                            ? CupertinoColors.activeBlue
                                            : CupertinoColors.inactiveGray,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, thickness: 0.5, color: Color(0xFFD1D1D6)),

                        // Scrollable Grouped Cards
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(outerPadding, 16, outerPadding, 40),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Card 1: Title & Notes (Apple Calendar style)
                                buildGroupedCard([
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    child: TextField(
                                      controller: _titleController,
                                      style: const TextStyle(fontSize: 16, color: Colors.black),
                                      decoration: InputDecoration(
                                        hintText: isJapanese ? 'タイトル' : 'Title',
                                        hintStyle: const TextStyle(color: CupertinoColors.placeholderText),
                                        border: InputBorder.none,
                                      ),
                                      onChanged: (_) => setDialogState(() {}),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    child: TextField(
                                      controller: _memoController,
                                      maxLines: 3,
                                      minLines: 1,
                                      style: const TextStyle(fontSize: 15, color: Colors.black87),
                                      decoration: InputDecoration(
                                        hintText: isJapanese ? 'メモ' : 'Notes',
                                        hintStyle: const TextStyle(color: CupertinoColors.placeholderText),
                                        border: InputBorder.none,
                                      ),
                                    ),
                                  ),
                                ]),
                                const SizedBox(height: 16),

                                // Card 2: To-Do List Sync Toggle (if enabled)
                                if (_activeSettings.enableTodoList) ...[
                                  buildGroupedCard([
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  isJapanese ? 'To-Do リストに追加' : 'Add to To-Do List',
                                                  style: const TextStyle(fontSize: 15, color: Colors.black),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  _isTodo
                                                      ? (isJapanese
                                                          ? '期限日・時刻のみ使用し To-Do と同期'
                                                          : 'Uses Due Date / Time & syncs with To-Do')
                                                      : (isJapanese ? '通常のカレンダー予定' : 'Standard calendar event'),
                                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                                ),
                                              ],
                                            ),
                                          ),
                                          CupertinoSwitch(
                                            value: _isTodo,
                                            onChanged: (bool value) {
                                              setDialogState(() {
                                                _isTodo = value;
                                                activePicker = null;
                                                if (_isTodo) {
                                                  _isRepeating = false;
                                                  _repeatType = 'None';
                                                  _setDueTime = false;
                                                  _isAllDay = true;
                                                  _endTime = DateTime(
                                                    _endTime.year,
                                                    _endTime.month,
                                                    _endTime.day,
                                                    23,
                                                    59,
                                                    59,
                                                  );
                                                } else {
                                                  _setDueTime = false;
                                                  _isAllDay = false;
                                                }
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ]),
                                  const SizedBox(height: 16),
                                ],

                                // Card 3: All-day, Starts, Ends / Due Date & Timezone
                                buildGroupedCard([
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _isTodo
                                              ? (isJapanese ? '期限時刻を設定' : 'Set Due Time')
                                              : (isJapanese ? '終日' : 'All-day'),
                                          style: const TextStyle(fontSize: 15, color: Colors.black),
                                        ),
                                        CupertinoSwitch(
                                          value: _isTodo ? _setDueTime : _isAllDay,
                                          onChanged: (bool value) {
                                            setDialogState(() {
                                              activePicker = null;
                                              if (_isTodo) {
                                                _setDueTime = value;
                                                _isAllDay = !_setDueTime;
                                                if (!_setDueTime) {
                                                  _endTime = DateTime(
                                                    _endTime.year,
                                                    _endTime.month,
                                                    _endTime.day,
                                                    23,
                                                    59,
                                                    59,
                                                  );
                                                }
                                              } else {
                                                _isAllDay = value;
                                                if (_isAllDay) {
                                                  _startTime = DateTime(
                                                    _startTime.year,
                                                    _startTime.month,
                                                    _startTime.day,
                                                    0,
                                                    0,
                                                    0,
                                                  );
                                                  _endTime = DateTime(
                                                    _endTime.year,
                                                    _endTime.month,
                                                    _endTime.day,
                                                    23,
                                                    59,
                                                    59,
                                                  );
                                                }
                                              }
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Starts Row (Standard Event)
                                  if (!_isTodo) ...[
                                    buildResponsivePickerRow(
                                      label: isJapanese ? '開始' : 'Starts',
                                      isVeryNarrow: isVeryNarrow,
                                      pills: [
                                        buildApplePill(
                                          label: DateFormat(datePattern).format(_startTime),
                                          isActive: activePicker == 'startDate',
                                          onTap: () => togglePicker('startDate'),
                                        ),
                                        if (!_isAllDay)
                                          buildApplePill(
                                            label: DateFormat('HH:mm').format(_startTime),
                                            isActive: activePicker == 'startTime',
                                            onTap: () => togglePicker('startTime'),
                                          ),
                                        buildApplePill(
                                          icon: Icons.public,
                                          label: _startTimezone.split('/').last,
                                          isActive: activePicker == 'startTz',
                                          onTap: () => togglePicker('startTz'),
                                        ),
                                      ],
                                    ),
                                    if (activePicker == 'startDate')
                                      buildInlineWheelDatePicker(
                                        pickerKey: 'startDate',
                                        currentDate: _startTime,
                                        onDateChanged: (picked) {
                                          setDialogState(() {
                                            _startTime = DateTime(
                                              picked.year,
                                              picked.month,
                                              picked.day,
                                              _isAllDay ? 0 : _startTime.hour,
                                              _isAllDay ? 0 : _startTime.minute,
                                            );
                                            if (_endTime.isBefore(_startTime)) {
                                              _endTime = _isAllDay
                                                  ? DateTime(picked.year, picked.month, picked.day, 23, 59, 59)
                                                  : _startTime.add(const Duration(hours: 1));
                                            }
                                          });
                                        },
                                      ),
                                    if (activePicker == 'startTime' && !_isAllDay)
                                      buildInlineWheelTimePicker(
                                        pickerKey: 'startTime',
                                        currentTime: _startTime,
                                        onTimeChanged: (picked) {
                                          setDialogState(() {
                                            _startTime = DateTime(
                                              _startTime.year,
                                              _startTime.month,
                                              _startTime.day,
                                              picked.hour,
                                              picked.minute,
                                            );
                                            if (_endTime.isBefore(_startTime)) {
                                              _endTime = _startTime.add(const Duration(hours: 1));
                                            }
                                          });
                                        },
                                      ),
                                    if (activePicker == 'startTz')
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                                        child: DropdownButtonFormField<String>(
                                          initialValue: _startTimezone,
                                          decoration: InputDecoration(
                                            labelText: isJapanese ? '開始タイムゾーン' : 'Start Timezone',
                                            prefixIcon: const Icon(Icons.public),
                                            border: const OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                          items: kSupportedTimezones.map((tz) {
                                            return DropdownMenuItem(value: tz, child: Text(tz));
                                          }).toList(),
                                          onChanged: (val) {
                                            if (val != null) {
                                              setDialogState(() {
                                                _startTimezone = val;
                                                activePicker = null;
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                  ],

                                  // Ends / Due Row
                                  buildResponsivePickerRow(
                                    label: _isTodo
                                        ? (isJapanese ? '期限' : 'Due')
                                        : (isJapanese ? '終了' : 'Ends'),
                                    isVeryNarrow: isVeryNarrow,
                                    pills: [
                                      buildApplePill(
                                        label: DateFormat(datePattern).format(_endTime),
                                        isActive: activePicker == 'endDate',
                                        onTap: () => togglePicker('endDate'),
                                      ),
                                      if ((!_isTodo && !_isAllDay) || (_isTodo && _setDueTime))
                                        buildApplePill(
                                          label: DateFormat('HH:mm').format(_endTime),
                                          isActive: activePicker == 'endTime',
                                          onTap: () => togglePicker('endTime'),
                                        ),
                                      buildApplePill(
                                        icon: Icons.public,
                                        label: _endTimezone.split('/').last,
                                        isActive: activePicker == 'endTz',
                                        onTap: () => togglePicker('endTz'),
                                      ),
                                    ],
                                  ),
                                  if (activePicker == 'endDate')
                                    buildInlineWheelDatePicker(
                                      pickerKey: 'endDate',
                                      currentDate: _endTime,
                                      onDateChanged: (picked) {
                                        setDialogState(() {
                                          final bool keepAllDay = _isTodo ? !_setDueTime : _isAllDay;
                                          _endTime = DateTime(
                                            picked.year,
                                            picked.month,
                                            picked.day,
                                            keepAllDay ? 23 : _endTime.hour,
                                            keepAllDay ? 59 : _endTime.minute,
                                            keepAllDay ? 59 : 0,
                                          );
                                          if (!_isTodo && _startTime.isAfter(_endTime)) {
                                            _startTime = keepAllDay
                                                ? DateTime(picked.year, picked.month, picked.day, 0, 0, 0)
                                                : _endTime.subtract(const Duration(hours: 1));
                                          }
                                        });
                                      },
                                    ),
                                  if (activePicker == 'endTime' &&
                                      ((!_isTodo && !_isAllDay) || (_isTodo && _setDueTime)))
                                    buildInlineWheelTimePicker(
                                      pickerKey: 'endTime',
                                      currentTime: _endTime,
                                      onTimeChanged: (picked) {
                                        setDialogState(() {
                                          _endTime = DateTime(
                                            _endTime.year,
                                            _endTime.month,
                                            _endTime.day,
                                            picked.hour,
                                            picked.minute,
                                          );
                                          if (!_isTodo && _startTime.isAfter(_endTime)) {
                                            _startTime = _endTime.subtract(const Duration(hours: 1));
                                          }
                                        });
                                      },
                                    ),
                                  if (activePicker == 'endTz')
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                                      child: DropdownButtonFormField<String>(
                                        initialValue: _endTimezone,
                                        decoration: InputDecoration(
                                          labelText: _isTodo
                                              ? (isJapanese ? '期限タイムゾーン' : 'Due Timezone')
                                              : (isJapanese ? '終了タイムゾーン' : 'End Timezone'),
                                          prefixIcon: const Icon(Icons.public),
                                          border: const OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        items: kSupportedTimezones.map((tz) {
                                          return DropdownMenuItem(value: tz, child: Text(tz));
                                        }).toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setDialogState(() {
                                              _endTimezone = val;
                                              if (_isTodo) _startTimezone = val;
                                              activePicker = null;
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                ]),
                                const SizedBox(height: 16),

                                // Card 4: Repeat (Apple Calendar style)
                                if (!_isTodo) ...[
                                  buildGroupedCard([
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            isJapanese ? '繰り返し' : 'Repeat',
                                            style: const TextStyle(fontSize: 15, color: Colors.black),
                                          ),
                                          DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value: _isRepeating ? _repeatType : 'None',
                                              icon: const Icon(
                                                CupertinoIcons.chevron_up_chevron_down,
                                                size: 16,
                                                color: Colors.grey,
                                              ),
                                              style: const TextStyle(fontSize: 15, color: Colors.grey),
                                              items: ['None', ..._repeatOptions].map((opt) {
                                                return DropdownMenuItem(
                                                  value: opt,
                                                  child: Text(repeatDisplayLabel(opt)),
                                                );
                                              }).toList(),
                                              onChanged: (val) {
                                                if (val == null) return;
                                                setDialogState(() {
                                                  if (val == 'None') {
                                                    _isRepeating = false;
                                                    _repeatType = 'None';
                                                    _endOn = false;
                                                  } else {
                                                    _isRepeating = true;
                                                    _repeatType = val;
                                                    final minYearlyEnd = DateTime(
                                                      _startTime.year + 1,
                                                      _startTime.month,
                                                      _startTime.day,
                                                    );
                                                    if (_repeatType == 'Yearly' &&
                                                        _repeatEndDate.isBefore(minYearlyEnd)) {
                                                      _repeatEndDate = minYearlyEnd;
                                                    }
                                                  }
                                                });
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_isRepeating) ...[
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              isJapanese ? '繰り返し終了日' : 'End Repeat',
                                              style: const TextStyle(fontSize: 15, color: Colors.black),
                                            ),
                                            CupertinoSwitch(
                                              value: _endOn,
                                              onChanged: (val) {
                                                setDialogState(() {
                                                  _endOn = val;
                                                  if (!_endOn && activePicker == 'repeatEnd') {
                                                    activePicker = null;
                                                  }
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (_endOn) ...[
                                        buildResponsivePickerRow(
                                          label: isJapanese ? '終了日' : 'End Date',
                                          isVeryNarrow: isVeryNarrow,
                                          pills: [
                                            buildApplePill(
                                              label: DateFormat(datePattern).format(_repeatEndDate),
                                              isActive: activePicker == 'repeatEnd',
                                              onTap: () => togglePicker('repeatEnd'),
                                            ),
                                          ],
                                        ),
                                        if (activePicker == 'repeatEnd')
                                          buildInlineWheelDatePicker(
                                            pickerKey: 'repeatEnd',
                                            currentDate: _repeatEndDate,
                                            onDateChanged: (picked) {
                                              setDialogState(() {
                                                _repeatEndDate = picked;
                                              });
                                            },
                                          ),
                                      ],
                                    ],
                                  ]),
                                  const SizedBox(height: 16),
                                ],

                                // Card 5: Calendar / Event Type (Apple Calendar colored dot style)
                                buildGroupedCard([
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          isJapanese ? 'カレンダー種類' : 'Calendar',
                                          style: const TextStyle(fontSize: 15, color: Colors.black),
                                        ),
                                        DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            value: _eventTypes.contains(_eventType)
                                                ? _eventType
                                                : _eventTypes.first,
                                            icon: const Icon(
                                              CupertinoIcons.chevron_up_chevron_down,
                                              size: 16,
                                              color: Colors.grey,
                                            ),
                                            items: _eventTypes.map((String type) {
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
                                            onChanged: (String? newValue) {
                                              if (newValue != null) {
                                                setDialogState(() => _eventType = newValue);
                                              }
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ]),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> fetchEventsFromJava({int? targetYear, bool silent = false}) async {
    Future<void> loadTask() async{
      try {
        final int yearToLoad = targetYear ?? _focusedDay.year;
        final String baseUrl = kBackendBaseUrl.endsWith('/')
            ? kBackendBaseUrl.substring(0, kBackendBaseUrl.length - 1)
            : kBackendBaseUrl;
        final Uri requestUri = Uri.parse('$baseUrl/api/events?targetYear=$yearToLoad');
        final response = await http.get(
          requestUri,
          headers: _authHeaders(),
        );
        if (response.statusCode == 200) {
          List<dynamic> body = jsonDecode(response.body);
          Set<int> highPriorityIds = {};
          if (_activeSettings.enableTodoList) {
            try {
              final todoRes = await http.get(
                Uri.parse('$kBackendBaseUrl/api/todos'),
                headers: _authHeaders(),
              );
              if (todoRes.statusCode == 200) {
                final List<dynamic> todoList = jsonDecode(todoRes.body);
                for (final item in todoList) {
                  if (item is Map<String, dynamic> &&
                      item['priority']?.toString().toUpperCase() == 'HIGH') {
                    final linkedId = item['linkedEventId'] is int
                        ? item['linkedEventId'] as int
                        : int.tryParse(item['linkedEventId']?.toString() ?? '');
                    if (linkedId != null) highPriorityIds.add(linkedId);
                  }
                }
              }
            } catch (_) {}
          }
          if (!mounted) return;
          setState(() {
            _events = body.map((dynamic item) => DailyEvent.fromJson(item)).cast<DailyEvent>().toList();
            _highPriorityTodoEventIds = highPriorityIds;
          });
        } else if (response.statusCode == 401) {
          await widget.onLogout();
        } else {
          debugPrint("Failed to load events: ${response.statusCode} -> $requestUri");
        }
      } catch (e) {
        debugPrint("FLUTTER ERROR: $e");
      }
    }
    if (silent) {
      await loadTask();
    } else {
      await showLoadingIfNeeded(loadTask);
    }
  }

  Future<void> _deleteEvent(int id) async {
    await showLoadingIfNeeded(() async {
      try {
        final response = await http.delete(
          Uri.parse('$kBackendBaseUrl/api/events/$id'),
          headers: _authHeaders(),
        );
        if (response.statusCode == 200 || response.statusCode == 204) {
          await fetchEventsFromJava();
        } else {
          debugPrint("Failed to delete event. Status code: ${response.statusCode}");
        }
      } catch (e) {
        debugPrint("ERROR deleting event: $e");
      }
    });
  }

  String _formatToBackendIso(DateTime dateTime) {
    String base = dateTime.toIso8601String().split('.')[0];
    String ms = (dateTime.millisecond).toString().padLeft(3, '0');
    return '$base.$ms';
  }

  Map<String, dynamic> _buildEventPayload(DateTime startTime, DateTime endTime) {
    return {
      'title': _titleController.text,
      'description': _memoController.text,
      'startTime': _isTodo ? null : _formatToBackendIso(startTime),
      'endTime': _formatToBackendIso(endTime),
      'eventType': _eventType,
      'timezone': _isTodo ? _endTimezone : _startTimezone,
      'startTimezone': _startTimezone,
      'endTimezone': _endTimezone,
      'isAllDay': _isTodo ? !_setDueTime : _isAllDay,
      'isRepeating': _isTodo ? false : _isRepeating,
      'repeatType': (_isTodo || !_isRepeating) ? 'None' : _repeatType,
      'endOn': (!_isTodo && _isRepeating) ? _endOn : false,
      'repeatEndOn': (!_isTodo && _isRepeating && _endOn)
          ? _formatToBackendIso(DateTime(_repeatEndDate.year, _repeatEndDate.month, _repeatEndDate.day, 23, 59, 59))
          : null,
      'isTodo': _isTodo,
      'isComplete': _isTodo ? _isComplete : false,
    };
  }

  Future<void> _makeNewEvents(DateTime startTime, DateTime endTime) async {
    await showLoadingIfNeeded(() async {
      try {
        final response = await http.post(
          Uri.parse('$kBackendBaseUrl/api/events/'),
          headers: _authHeaders(json: true),
          body: jsonEncode(_buildEventPayload(startTime, endTime)),
        );
        if (response.statusCode == 200 || response.statusCode == 201) {
          await fetchEventsFromJava();
          if (mounted) Navigator.pop(context, true);
        } else {
          debugPrint("Failed to save event. Status code: ${response.statusCode}");
          debugPrint("Response body: ${response.body}");
        }
      } catch (e) {
        debugPrint("EXCEPTION caught while saving event: $e");
      }
    });
  }

  Future<bool> _updateEvent(int id, DateTime startTime, DateTime endTime) async {
    bool isSuccess = false;
    await showLoadingIfNeeded(() async {
      try {
        final response = await http.put(
          Uri.parse('$kBackendBaseUrl/api/events/$id'),
          headers: _authHeaders(json: true),
          body: jsonEncode(_buildEventPayload(startTime, endTime)),
        );
        if (response.statusCode == 200 || response.statusCode == 204) {
          if (mounted) {
            await fetchEventsFromJava();
          }
          isSuccess = true;
        } else {
          debugPrint("Failed to update event. Status code: ${response.statusCode}");
          isSuccess = false;
        }
      } catch (e) {
        debugPrint("EXCEPTION caught while updating event: $e");
        isSuccess = false;
      }
    });
    return isSuccess;
  }

  Future<TimeOfDay?> _showAppleStyleTimePicker({
    required BuildContext context,
    required DateTime initialTime,
  }) async {
    DateTime selected = initialTime;
    return await showModalBottomSheet<TimeOfDay>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(100.0)),
      ),
      builder: (BuildContext builderContext) {
        return Container(
          height: 300,
          color: CupertinoColors.systemBackground.resolveFrom(context),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    child: const Text('Cancel'),
                    onPressed: () {
                      Navigator.of(builderContext).pop();
                    },
                  ),
                  CupertinoButton(
                    child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Navigator.of(builderContext).pop(
                        TimeOfDay(hour: selected.hour, minute: selected.minute),
                      );
                    },
                  ),
                ],
              ),
              const Divider(height: 1),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: initialTime,
                  use24hFormat: true,
                  onDateTimeChanged: (DateTime newDateTime) {
                    selected = newDateTime;
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
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

  Future<void> _confirmAndLogout() async {
    final bool isJapanese = _activeSettings.language == 'ja';
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isJapanese ? 'ログアウト' : 'Log Out'),
        content: Text(
          isJapanese
              ? 'ログアウトしてもよろしいですか？'
              : 'Are you sure you want to log out?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isJapanese ? 'キャンセル' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              isJapanese ? 'ログアウト' : 'Log Out',
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.onLogout();
    }
  }

  @override
  Widget build(BuildContext context) {
    String localQuery = '';
    bool isSearchByName = true;
    
    final List<String> tabKeys = ['calendar'];
    if (_activeSettings.enableTodoList) tabKeys.add('todo');
    if (_activeSettings.enablePayroll) tabKeys.add('payroll');
    tabKeys.add('settings');

    if (_currentTabIndex >= tabKeys.length) {
      _currentTabIndex = 0;
    }
    final String activeTab = tabKeys[_currentTabIndex];
    final bool isJapanese = _activeSettings.language == 'ja';
    Widget buildAppleDockBar() {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14, left: 16, right: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.82),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.95),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.14),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(tabKeys.length, (index) {
                    final key = tabKeys[index];
                    final bool selected = index == _currentTabIndex;
                    late IconData icon;
                    late String label;
                    late Color accentColor;
                    switch (key) {
                      case 'todo':
                        icon = Icons.check_circle_rounded;
                        label = 'To-Do';
                        accentColor = Colors.green;
                        break;
                      case 'payroll':
                        icon = Icons.payments_rounded;
                        label = isJapanese ? '給与' : 'Payroll';
                        accentColor = Colors.orange;
                        break;
                      case 'settings':
                        icon = Icons.settings_rounded;
                        label = isJapanese ? '設定' : 'Settings';
                        accentColor = Colors.blueGrey;
                        break;
                      case 'calendar':
                      default:
                        icon = Icons.calendar_month_rounded;
                        label = isJapanese ? 'カレンダー' : 'Calendar';
                        accentColor = Colors.blue;
                        break;
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          setState(() => _currentTabIndex = index);
                          if (key == 'calendar') {
                            await fetchEventsFromJava();
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: selected
                                ? accentColor.withOpacity(0.14)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedScale(
                                scale: selected ? 1.12 : 1.0,
                                duration: const Duration(milliseconds: 180),
                                child: Icon(
                                  icon,
                                  size: 24,
                                  color: selected ? accentColor : Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                  color: selected ? accentColor : Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: selected ? 5 : 0,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: selected ? accentColor : Colors.transparent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      );
    }

    String appBarTitleBase = isJapanese ? 'スケジュールカレンダー' : 'Schedule Calendar';
    if (activeTab == 'todo') appBarTitleBase = isJapanese ? 'To-Do リスト' : 'To-Do List';
    if (activeTab == 'payroll') appBarTitleBase = isJapanese ? '給与計算' : 'Payroll';
    if (activeTab == 'settings') appBarTitleBase = isJapanese ? '設定' : 'Settings';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.username.isNotEmpty ? '$appBarTitleBase (${widget.username})' : appBarTitleBase,
        ),
        actions: [
          if (activeTab == 'calendar')
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: () async {
                localQuery = '';
                final RenderBox button = context.findRenderObject() as RenderBox;
                final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
                final RelativeRect position = RelativeRect.fromRect(
                  Rect.fromPoints(
                    button.localToGlobal(Offset.zero, ancestor: overlay),
                    button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
                  ),
                  Offset.zero & overlay.size,
                );
                await showMenu(
                  context: context,
                  position: position,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24.0),
                  ),
                  items: [
                    PopupMenuItem(
                      value: 'search',
                      enabled: false,
                      child: StatefulBuilder(
                        builder: (context, menuSetState) {
                          final suggestions = _events.where((event) {
                            if (localQuery.isEmpty) return false;
                            if (isSearchByName) {
                              return event.title.toLowerCase().startsWith(localQuery.toLowerCase());
                            } else {
                              return event.eventType.toLowerCase().startsWith(localQuery.toLowerCase());
                            }
                          }).toList();
                          return SizedBox(
                            width: 500,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: isSearchByName
                                          ? TextField(
                                              autofocus: true,
                                              decoration: const InputDecoration(
                                                hintText: 'Search event by title or type...',
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                              ),
                                              onChanged: (value) {
                                                menuSetState(() {
                                                  localQuery = value;
                                                });
                                              },
                                            )
                                          : DropdownButtonFormField<String>(
                                              initialValue: localQuery.isEmpty ? null : localQuery,
                                              decoration: const InputDecoration(
                                                hintText: 'Select a type',
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                              ),
                                              items: _eventTypes.map((String typeName) {
                                                return DropdownMenuItem<String>(
                                                  value: typeName,
                                                  child: Text(
                                                    typeName,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      color: _getEventColor(typeName),
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                              onChanged: (String? newValue) {
                                                if (newValue != null) {
                                                  menuSetState(() {
                                                    localQuery = newValue;
                                                  });
                                                }
                                              },
                                            ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: Radio<bool>(
                                                value: true,
                                                groupValue: isSearchByName,
                                                onChanged: (value) {
                                                  if (value != null) {
                                                    menuSetState(() {
                                                      isSearchByName = value;
                                                      localQuery = '';
                                                    });
                                                  }
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            const Text('Title', style: TextStyle(fontSize: 12, color: Colors.black)),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: Radio<bool>(
                                                value: false,
                                                groupValue: isSearchByName,
                                                onChanged: (value) {
                                                  if (value != null) {
                                                    menuSetState(() {
                                                      isSearchByName = value;
                                                      localQuery = '';
                                                    });
                                                  }
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            const Text('Type', style: TextStyle(fontSize: 12, color: Colors.black)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (localQuery.isNotEmpty && suggestions.isNotEmpty) ...[
                                  const Divider(height: 1),
                                  Container(
                                    constraints: const BoxConstraints(maxHeight: 150),
                                    child: ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: suggestions.length,
                                      itemBuilder: (context, index) {
                                        final event = suggestions[index];
                                        return ListTile(
                                          dense: true,
                                          title: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  event.title,
                                                  style: const TextStyle(fontSize: 14, color: Colors.black),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                DateFormat('yyyy-MM-dd').format(event.displayEffectiveTime),
                                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                                              ),
                                            ],
                                          ),
                                          subtitle: Text(
                                            event.eventType,
                                            style: TextStyle(fontSize: 14, color: _getEventColor(event.eventType)),
                                          ),
                                          onTap: () {
                                            Navigator.pop(context);
                                            setState(() {
                                              _selectedDay = event.displayEffectiveTime;
                                              _focusedDay = event.displayEffectiveTime;
                                            });
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ],
                                if (localQuery.isNotEmpty && suggestions.isEmpty) ...[
                                  const Divider(height: 1),
                                  const SizedBox(
                                    height: 40,
                                    child: Center(
                                      child: Text(
                                        'Cannot find event',
                                        style: TextStyle(fontSize: 12, color: Colors.black),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await _confirmAndLogout();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          if (activeTab == 'settings')
            SettingsPage(
              backendBaseUrl: kBackendBaseUrl,
              authToken: widget.authToken,
              currentSettings: _activeSettings,
              onSettingsChanged: (updated) async {
                setState(() {
                  _activeSettings = updated;
                  final updatedTabKeys = [
                    'calendar',
                    if (updated.enableTodoList) 'todo',
                    if (updated.enablePayroll) 'payroll',
                    'settings',
                  ];
                  final settingsIdx = updatedTabKeys.indexOf('settings');
                  if (settingsIdx != -1) {
                    _currentTabIndex = settingsIdx;
                  }
                });
              },
              onLogout: _confirmAndLogout,
            )
          else if (activeTab == 'todo')
            TodoListPage(
              backendBaseUrl: kBackendBaseUrl,
              authToken: widget.authToken,
              defaultTimezone: _defaultUserTimezone(),
              onTodoChanged: () => fetchEventsFromJava(),
            )
          else if (activeTab == 'payroll')
            const Center(child: Text('Payroll Page'))
          else
            Stack(
              children: [
                Column(
                  children: [
                    TableCalendar(
                      firstDay: DateTime(2000, 1, 1),
                      lastDay: DateTime(2100, 12, 31),
                      focusedDay: _focusedDay,
                      calendarFormat: _calendarFormat,
                      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                      eventLoader: (day) {
                        final dayStart = DateTime(day.year, day.month, day.day, 0, 0, 0);
                        final dayEnd = DateTime(day.year, day.month, day.day, 23, 59, 59);
                        return _events.where((event) {
                          if (event.isTodo) return isSameDay(event.displayEndTime, day);
                          return event.displayEffectiveTime.isBefore(dayEnd) &&
                          event.displayEndTime.isAfter(dayStart);
                        }).toList();
                      },
                      onDaySelected: (selectedDay, focusedDay) {
                        setState(() {
                          _selectedDay = selectedDay;
                          _focusedDay = focusedDay;
                        });
                      },
                      onFormatChanged: (format) {
                        setState(() {
                          _calendarFormat = format;
                        });
                      },
                      onPageChanged: (focusedDay){
                        _focusedDay = focusedDay;
                        fetchEventsFromJava(targetYear: focusedDay.year, silent:true);
                      },
                      calendarBuilders: CalendarBuilders(
                        markerBuilder: (context, date, events) {
                          if (events.isEmpty) return const SizedBox();
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: events.take(3).map((event) {
                              final dailyEvent = event as DailyEvent;
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 0.5),
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _getEventColor(dailyEvent.eventType),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                      headerStyle: const HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                      ),
                      onHeaderTapped: (focusedDay) async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: focusedDay,
                          firstDate: DateTime(2000, 1, 1),
                          lastDate: DateTime(2100, 12, 31),
                        );
                        if (picked != null) {
                          setState(() {
                            _focusedDay = picked;
                            _selectedDay = picked;
                          });
                          await fetchEventsFromJava(targetYear: picked.year);
                        }
                      },
                    ),

                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 160),
                        itemCount: _selectedEvents.length,
                        itemBuilder: (context, index) {
                          final event = _selectedEvents[index];
                          final bool isDueToday = event.isTodo && isSameDay(event.displayEndTime, DateTime.now());
                          final bool isHighPriorityTodo = event.isTodo &&
                              event.id != null &&
                              _highPriorityTodoEventIds.contains(event.id);
                          return ListTile(
                            leading: Icon(
                              event.isTodo
                                ? (event.isComplete ? Icons.check_circle : Icons.radio_button_unchecked)
                                : Icons.event,
                              color: _getEventColor(event.eventType),
                            ),
                            title: Text(
                              event.title,
                              style: TextStyle(
                                decoration: (event.isTodo && event.isComplete)
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                              ),
                            ),
                            subtitle: Text(
                              event.isTodo
                                ? (isDueToday
                                    ? (event.isAllDay
                                        ? "Due: TODAY"
                                        : "Due: TODAY, ${DateFormat('HH:mm').format(event.displayEndTime)} (${event.timezone.split('/').last})")
                                    : (event.isAllDay
                                        ? "Due: ${DateFormat('MMM d').format(event.displayEndTime)}"
                                        : "Due: ${DateFormat('MMM d, HH:mm').format(event.displayEndTime)} (${event.timezone.split('/').last})"))
                                : (event.isAllDay
                                    ? "All-Day"
                                    : "${DateFormat('MMM d, HH:mm').format(event.displayEffectiveTime)}(${event.startTimezone.split('/').last}) - ${DateFormat('MMM d, HH:mm').format(event.displayEndTime)}(${event.endTimezone.split('/').last})"),
                            ),
                            trailing: isHighPriorityTodo
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                                    ),
                                    child: const Text(
                                      'HIGH',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.redAccent,
                                      ),
                                    ),
                                  )
                                : null,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => EventDetailPage(
                                    event: event,
                                    authToken: widget.authToken,
                                    onDelete: (id) => _deleteEvent(id),
                                    onUpdate: () => fetchEventsFromJava(),
                                    onEdit: (currentEventType) async {
                                      final bool? isUpdated = await _showAddEventDialog(
                                        context,
                                        event.displayEffectiveTime,
                                        eventToEdit: event,
                                        initialEventType: currentEventType,
                                      );
                                      if (isUpdated == true && context.mounted) {
                                        Navigator.pop(context);
                                      }
                                    },
                                    allEventTypes: _eventTypes,
                                    onEventTypeChanged: (newType) {
                                      setState(() {
                                        _eventType = newType;
                                      });
                                    },
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 96,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      FloatingActionButton.extended(
                        onPressed: () {
                          setState(() {
                            _focusedDay = DateTime.now();
                            _selectedDay = DateTime.now();
                          });
                        },
                        label: const Text("TODAY"),
                        icon: const Icon(Icons.today),
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.blue,
                      ),
                      FloatingActionButton(
                        onPressed: globalLoading.value ? null : () => _showAddEventDialog(context, _selectedDay),
                        child: const Icon(Icons.add, color: Colors.black),
                      ),
                    ],
                  ),
                  
                ),
              ],
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: buildAppleDockBar(),
            ),
        ],
      ),
    );
  }
}