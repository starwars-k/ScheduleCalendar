import 'package:calendar_frontend/EventDetailPage.dart';
import 'package:calendar_frontend/login_page.dart';
import 'package:calendar_frontend/initialSetupPage.dart';
import 'package:calendar_frontend/event_model.dart';
import 'package:calendar_frontend/todo_list_page.dart';
import 'package:calendar_frontend/settings_page.dart';
import 'package:calendar_frontend/notification_service.dart';

import 'package:table_calendar/table_calendar.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import 'dart:convert';
import 'dart:async';
import 'dart:ui';

const String kBackendBaseUrl = String.fromEnvironment(
  'BACKEND_BASE_URL',
  defaultValue: 'https://calendar-backend-qhny.onrender.com',
);
final ValueNotifier<bool> globalLoading = ValueNotifier<bool>(false);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(
    http
        .get(Uri.parse('$kBackendBaseUrl/api/health'))
        .timeout(const Duration(seconds: 90))
        .catchError((_) => http.Response('', 503)),
  );
  runApp(
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
  }

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
    for (final key in prefs.getKeys().where((k) => k.startsWith('cached_events_')).toList()) {
      await prefs.remove(key);
    }
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
  bool _isNotificationEnabled = false;
  int _notificationMinutesBefore = 15;
  Timer? _notificationTimer;
  final Set<String> _sentNotificationKeys = {};
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

  final List<String> _eventTypes = ['Task', 'Job', 'Class', 'Birthday', 'Personal', 'Holiday'];
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
      case 'Holiday':
        return Colors.grey;
      default:
        return Colors.black;
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
    _initLoadEvents();
    _startNotificationChecker();
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    _titleController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  void _startNotificationChecker() {
    _notificationTimer?.cancel();
    _notificationTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkDueNotifications();
    });
  }

  void _checkDueNotifications() {
    if (!mounted || !_activeSettings.enableNotifications) return;
    final now = DateTime.now();
    final bool isJa = _activeSettings.language == 'ja';

    for (final event in _events) {
      if (!event.isNotificationEnabled || event.isComplete) continue;
      final DateTime baseTime = event.isTodo
          ? (event.isAllDay
              ? DateTime(event.displayEndTime.year, event.displayEndTime.month, event.displayEndTime.day, 9, 0)
              : event.displayEndTime)
          : (event.isAllDay
              ? DateTime(event.displayEffectiveTime.year, event.displayEffectiveTime.month, event.displayEffectiveTime.day, 9, 0)
              : event.displayEffectiveTime);
      final DateTime notifyAt = baseTime.subtract(Duration(minutes: event.notificationMinutesBefore));
      final diffSeconds = now.difference(notifyAt).inSeconds;
      if (diffSeconds >= 0 && diffSeconds < 120) {
        final key = '${event.id ?? event.title}_${notifyAt.toIso8601String()}';
        if (_sentNotificationKeys.contains(key)) continue;
        _sentNotificationKeys.add(key);

        final String timeLabel = DateFormat('HH:mm').format(baseTime);
        final String body = isJa
            ? '開始/期限時刻: $timeLabel (${event.eventType})'
            : 'Starts/Due at $timeLabel (${event.eventType})';
        showBrowserNotification(event.title, body);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
            backgroundColor: const Color(0xFF1C1C1E),
            content: Row(
              children: [
                const Icon(CupertinoIcons.bell_fill, color: Color(0xFFFF3B30), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${event.title} ($timeLabel)',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
  }  

  Future<void> _initLoadEvents() async {
    final bool hasCache = await _loadCachedEvents(_focusedDay.year);
    await fetchEventsFromJava(silent: hasCache);
  }

  Future<bool> _loadCachedEvents(int year) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('cached_events_$year');
      if (raw == null || raw.isEmpty) return false;
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      final cached = decoded
          .map((item) => DailyEvent.fromJson(item as Map<String, dynamic>))
          .toList();
      if (!mounted) return false;
      setState(() => _events = cached);
      return cached.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveCachedEvents(int year, List<DailyEvent> events) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(events.map((e) => e.toJson()).toList());
      await prefs.setString('cached_events_$year', encoded);
    } catch (_) {}
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
    _isNotificationEnabled = isEditing ? eventToEdit.isNotificationEnabled : false;
    _notificationMinutesBefore = isEditing ? eventToEdit.notificationMinutesBefore : 15;
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
                                          value: (_eventType.isNotEmpty &&
                                                  (_eventTypes.contains(_eventType) ||
                                                      _eventType == 'Holiday'))
                                              ? _eventType
                                              : _eventTypes.first,
                                          icon: const Icon(
                                            CupertinoIcons.chevron_up_chevron_down,
                                            size: 16,
                                            color: Colors.grey,
                                          ),
                                          items: <String>[
                                            ..._eventTypes,
                                            if (!_eventTypes.contains('Holiday')) 'Holiday',
                                          ].map<DropdownMenuItem<String>>((String type) {
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
                                const SizedBox(height: 16),

                                // Card 6: Per-Event Notification Setting
                                buildGroupedCard([
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                isJapanese ? '通知' : 'Notification',
                                                style: const TextStyle(fontSize: 15, color: Colors.black),
                                              ),
                                              if (!_activeSettings.enableNotifications && _isNotificationEnabled)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 2),
                                                  child: Text(
                                                    isJapanese
                                                        ? '※設定画面の通知がOFFのため通知されません'
                                                        : 'Global notifications are OFF in Settings',
                                                    style: const TextStyle(fontSize: 11, color: Color(0xFFFF3B30)),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        CupertinoSwitch(
                                          value: _isNotificationEnabled,
                                          activeTrackColor: const Color(0xFFFF3B30),
                                          onChanged: (bool val) async {
                                            setDialogState(() => _isNotificationEnabled = val);
                                            if (val && _activeSettings.enableNotifications) {
                                              await requestBrowserNotificationPermission();
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_isNotificationEnabled)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(                                              isJapanese ? '通知タイミング' : 'Alert',
                                            style: const TextStyle(fontSize: 15, color: Colors.black),
                                          ),
                                          DropdownButtonHideUnderline(
                                            child: DropdownButton<int>(
                                              value: [0, 5, 10, 15, 30, 60, 1440].contains(_notificationMinutesBefore)
                                                ? _notificationMinutesBefore
                                                : 15,
                                              icon: const Icon(
                                                CupertinoIcons.chevron_up_chevron_down,
                                                size: 16,
                                                color: Colors.grey,
                                              ),
                                              style: const TextStyle(fontSize: 14, color: Colors.grey),
                                              items: [0, 5, 10, 15, 30, 60, 1440].map((mins) {
                                                String label;
                                                if (mins == 0) {
                                                  label = isJapanese ? '予定の時刻' : 'At time of event';
                                                } else if (mins < 60) {
                                                  label = isJapanese ? '$mins分前' : '$mins min before';
                                                } else if (mins == 60) {
                                                  label = isJapanese ? '1時間前' : '1 hour before';
                                                } else {
                                                  label = isJapanese ? '1日前' : '1 day before';
                                                }
                                                return DropdownMenuItem<int>(value: mins, child: Text(label));
                                              }).toList(),
                                              onChanged: (int? val) {
                                                if (val != null) {
                                                  setDialogState(() => _notificationMinutesBefore = val);
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
          final loadedEvents = body
            .map((dynamic item) => DailyEvent.fromJson(item))
            .cast<DailyEvent>()
            .toList();
          await _saveCachedEvents(yearToLoad, loadedEvents);
          setState(() {
            _events = loadedEvents;
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
      final authState = context.findAncestorStateOfType<_AuthGatePageState>();
      if (authState != null) {
        await authState._logout();
      } else {
        await widget.onLogout();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color appleRed = Color(0xFFFF3B30);
    const Color appleBg = Color(0xFFFFFFFF);
    const Color appleGroupedBg = Color(0xFFF2F2F7);
    const Color appleHairline = Color(0xFFE5E5EA);
    const Color appleSecondaryLabel = Color(0xFF8E8E93);
    const Color appleDarkCircle = Color(0xFF1C1C1E);

    String localQuery = '';
    bool isSearchByName = true;
    final TextEditingController searchController = TextEditingController();

    final List<String> tabKeys = ['calendar'];
    if (_activeSettings.enableTodoList) tabKeys.add('todo');
    if (_activeSettings.enablePayroll) tabKeys.add('payroll');
    tabKeys.add('settings');

    if (_currentTabIndex >= tabKeys.length) {
      _currentTabIndex = 0;
    }
    final String activeTab = tabKeys[_currentTabIndex];
    final bool isJapanese = _activeSettings.language == 'ja';

    Future<void> openAppleSearchMenu(BuildContext anchorContext, double screenWidth) async {
      localQuery = '';
      final RenderBox button = anchorContext.findRenderObject() as RenderBox;
      final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
      final RelativeRect position = RelativeRect.fromRect(
        Rect.fromPoints(
          button.localToGlobal(Offset.zero, ancestor: overlay),
          button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
        ),
        Offset.zero & overlay.size,
      );
      final double menuWidth = (screenWidth - 48).clamp(260.0, 410.0);
      await showMenu(
        context: context,
        position: position,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        items: [
          PopupMenuItem(
            value: 'search',
            enabled: false,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: StatefulBuilder(
              builder: (context, menuSetState) {
                final suggestions = _events.where((event) {
                  if (localQuery.isEmpty) return false;
                  if (isSearchByName) {
                    return event.title.toLowerCase().startsWith(localQuery.toLowerCase()) ||
                      event.title.toLowerCase().contains(localQuery.toLowerCase());
                  } else {
                    return event.eventType.toLowerCase().startsWith(localQuery.toLowerCase());
                  }
                }).toList();
                return SizedBox(
                  width: menuWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: isSearchByName
                                ? TextField(
                                    controller: searchController,
                                    autofocus: true,
                                    style: const TextStyle(fontSize: 14, color: Colors.black),
                                    decoration: InputDecoration(
                                      hintText: isJapanese ? 'タイトルで検索...' : 'Search by title...',
                                      hintStyle: const TextStyle(
                                        fontSize: 13,
                                        color: CupertinoColors.placeholderText,
                                      ),
                                      prefixIcon: const Icon(
                                        CupertinoIcons.search,
                                        size: 16,
                                        color: appleSecondaryLabel,
                                      ),
                                      prefixIconConstraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 34,
                                      ),
                                      suffixIcon: localQuery.isEmpty
                                          ? null
                                          : GestureDetector(
                                              onTap: () {
                                                searchController.clear();
                                                menuSetState(() => localQuery = '');
                                              },
                                              child: const Icon(
                                                CupertinoIcons.clear_thick_circled,
                                                size: 16,
                                                color: appleSecondaryLabel,
                                              ),
                                            ),
                                      suffixIconConstraints: const BoxConstraints(
                                        minWidth: 30,
                                        minHeight: 34,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 8,
                                      ),
                                      isDense: true,
                                      filled: true,
                                      fillColor: appleGroupedBg,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                    onChanged: (value) => menuSetState(() => localQuery = value),
                                  )
                                : DropdownButtonFormField<String>(
                                    value: localQuery.isEmpty ? null : localQuery,
                                    isExpanded: true,
                                    icon: const Icon(
                                      CupertinoIcons.chevron_up_chevron_down,
                                      size: 14,
                                      color: appleSecondaryLabel,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: isJapanese ? '種類を選択' : 'Select a type',
                                      hintStyle: const TextStyle(
                                        fontSize: 13,
                                        color: CupertinoColors.placeholderText,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      isDense: true,
                                      filled: true,
                                      fillColor: appleGroupedBg,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                    items: _eventTypes.map((String typeName) {
                                      return DropdownMenuItem<String>(
                                        value: typeName,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: _getEventColor(typeName),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                typeName,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 13),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (String? newValue) {
                                      if (newValue != null) {
                                        menuSetState(() => localQuery = newValue);
                                      }
                                    },
                                  ),
                          ),
                          const SizedBox(width: 6),
                          CupertinoSlidingSegmentedControl<bool>(
                            groupValue: isSearchByName,
                            padding: const EdgeInsets.all(2),
                            children: {
                              true: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                child: Text(
                                  isJapanese ? 'タイトル' : 'Title',
                                  style: const TextStyle(fontSize: 11, color: Colors.black),
                                ),
                              ),
                              false: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                child: Text(
                                  isJapanese ? '種類' : 'Type',
                                  style: const TextStyle(fontSize: 11, color: Colors.black),
                                ),
                              ),
                            },
                            onValueChanged: (value) {
                              if (value != null) {
                                menuSetState(() {
                                  isSearchByName = value;
                                  localQuery = '';
                                  searchController.clear();
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      if (localQuery.isNotEmpty && suggestions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: suggestions.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final event = suggestions[index];
                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                leading: Container(
                                  width: 4,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: _getEventColor(event.eventType),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                title: Text(
                                  event.title,
                                  style: const TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Text(
                                  DateFormat('yyyy-MM-dd').format(event.displayEffectiveTime),
                                  style: const TextStyle(fontSize: 12, color: appleSecondaryLabel),
                                ),
                                onTap: () async {
                                  Navigator.pop(context);
                                  final target = event.displayEffectiveTime;
                                  final bool yearChanged = target.year != _focusedDay.year;
                                  setState(() {
                                    _selectedDay = target;
                                    _focusedDay = target;
                                  });
                                  if (yearChanged) {
                                    await fetchEventsFromJava(targetYear: target.year);
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      ],
                      if (localQuery.isNotEmpty && suggestions.isEmpty) ...[
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        SizedBox(
                          height: 40,
                          child: Center(
                            child: Text(
                              isJapanese ? '予定が見つかりません' : 'No matching events',
                              style: const TextStyle(fontSize: 13, color: appleSecondaryLabel),
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
    }

    Widget buildAppleTopHeader(double screenWidth) {
      final bool isPhone = screenWidth < 600;
      final bool isCompact = screenWidth < 400;
      final String yearText = '${_focusedDay.year}';
      final String monthTitle = isJapanese
          ? DateFormat('M月').format(_focusedDay)
          : DateFormat('MMMM').format(_focusedDay);

      String nonCalendarTitle = isJapanese ? 'To-Do リスト' : 'To-Do List';
      if (activeTab == 'payroll') nonCalendarTitle = isJapanese ? '給与計算' : 'Payroll';
      if (activeTab == 'settings') nonCalendarTitle = isJapanese ? '設定' : 'Settings';

      return Container(
        decoration: const BoxDecoration(
          color: appleBg,
          border: Border(bottom: BorderSide(color: appleHairline, width: 0.5)),
        ),
        child: SafeArea(
          bottom: false,
          minimum: EdgeInsets.only(top: isPhone ? 16 : 0),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              isCompact ? 12 : 16,
              isPhone ? 10 : 6,
              isCompact ? 8 : 12,
              8,
            ),
            child: activeTab == 'calendar'
                ? Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Apple Calendar Year + Bold Month Title (Tap to jump date)
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            final DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: _focusedDay,
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    CupertinoIcons.chevron_left,
                                    size: 13,
                                    color: appleRed,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    isJapanese ? '$yearText年' : yearText,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: appleRed,
                                    ),
                                  ),
                                  if (widget.username.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        '• ${widget.username}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: appleSecondaryLabel,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      monthTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: isCompact ? 22 : 28,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.6,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  CupertinoButton(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    minSize: 24,
                                    onPressed: () {
                                      final prev = DateTime(_focusedDay.year, _focusedDay.month - 1, 1);
                                      setState(() => _focusedDay = prev);
                                      fetchEventsFromJava(targetYear: prev.year, silent: true);
                                    },
                                    child: const Icon(
                                      CupertinoIcons.chevron_left,
                                      size: 15,
                                      color: appleSecondaryLabel,
                                    ),
                                  ),
                                  CupertinoButton(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    minSize: 24,
                                    onPressed: () {
                                      final next = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
                                      setState(() => _focusedDay = next);
                                      fetchEventsFromJava(targetYear: next.year, silent: true);
                                    },
                                    child: const Icon(
                                      CupertinoIcons.chevron_right,
                                      size: 15,
                                      color: appleSecondaryLabel,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      //Apple Red Action Icons (Serch, Add +)
                      Builder(
                        builder: (btnCtx) => CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minSize: 32,
                          onPressed: () => openAppleSearchMenu(btnCtx, screenWidth),
                          child: const Icon(CupertinoIcons.search, color: appleRed, size: 21),
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minSize: 32,
                        onPressed: globalLoading.value
                            ? null
                            : () => _showAddEventDialog(context, _selectedDay),
                        child: const Icon(CupertinoIcons.plus, color: appleRed, size: 23),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.username.isNotEmpty)
                            Text(
                              widget.username,
                              style: const TextStyle(fontSize: 12, color: appleSecondaryLabel),
                            ),
                          Text(
                            nonCalendarTitle,
                            style: TextStyle(
                              fontSize: isCompact ? 24 : 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.6,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      );
    }

    Widget buildAppleDayCell(
      DateTime day, {
      required bool isSelected,
      required bool isToday,
      required bool isOutside,
    }) {
      Color? circleColor;
      Color textColor = isOutside ? const Color(0xFFC7C7CC) : Colors.black;
      FontWeight weight = FontWeight.w400;

      if (isSelected && isToday) {
        circleColor = appleRed;
        textColor = Colors.white;
        weight = FontWeight.w700;
      } else if (isSelected) {
        circleColor = appleDarkCircle;
        textColor = Colors.white;
        weight = FontWeight.w700;
      } else if (isToday) {
        textColor = appleRed;
        weight = FontWeight.w700;
      }

      return Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: appleHairline, width: 0.5)),
        ),
        alignment: Alignment.topCenter,
        padding: const EdgeInsets.only(top: 4),
        child: Container(
          width: 32,
          height: 32,
          decoration: circleColor != null
              ? BoxDecoration(color: circleColor, shape: BoxShape.circle)
              : null,
          alignment: Alignment.center,
          child: Text(
            '${day.day}',
            style: TextStyle(fontSize: 16, fontWeight: weight, color: textColor),
          ),
        ),
      );
    }

    Widget buildAppleMonthGrid(double availableWidth) {
      final bool isCompact = availableWidth < 400;
      const List<String> enWeekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
      const List<String> jaWeekdays = ['日', '月', '火', '水', '木', '金', '土'];

      return Container(
        color: appleBg,
        padding: const EdgeInsets.only(bottom: 4),
        child: TableCalendar<DailyEvent>(
          firstDay: DateTime(2000, 1, 1),
          lastDay: DateTime(2100, 12, 31),
          focusedDay: _focusedDay,
          calendarFormat: _calendarFormat,
          headerVisible: false,
          daysOfWeekHeight: 26,
          rowHeight: isCompact ? 46 : 52,
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
          onFormatChanged: (format) => setState(() => _calendarFormat = format),
          onPageChanged: (focusedDay) {
            setState(() => _focusedDay = focusedDay);
            fetchEventsFromJava(targetYear: focusedDay.year, silent: true);
          },
          calendarBuilders: CalendarBuilders<DailyEvent>(
            dowBuilder: (context, day) {
              final int idx = day.weekday % 7;
              final bool isWeekend = idx == 0 || idx == 6;
              return Center(
                child: Text(
                  isJapanese ? jaWeekdays[idx] : enWeekdays[idx],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isWeekend ? appleSecondaryLabel : const Color(0xFF3C3C43),
                  ),
                ),
              );
            },
            defaultBuilder: (context, day, focusedDay) =>
                buildAppleDayCell(day, isSelected: false, isToday: false, isOutside: false),
            todayBuilder: (context, day, focusedDay) =>
                buildAppleDayCell(day, isSelected: false, isToday: true, isOutside: false),
            selectedBuilder: (context, day, focusedDay) => buildAppleDayCell(
              day,
              isSelected: true,
              isToday: isSameDay(day, DateTime.now()),
              isOutside: false,
            ),
            outsideBuilder: (context, day, focusedDay) =>
                buildAppleDayCell(day, isSelected: false, isToday: false, isOutside: true),
            markerBuilder: (context, date, events) {
              if (events.isEmpty) return const SizedBox.shrink();
              return Positioned(
                bottom: 4,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: events.take(3).map((dailyEvent) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      width: 5.5,
                      height: 5.5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _getEventColor(dailyEvent.eventType),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ),
      );
    }

    Widget buildSelectedDayAgenda() {
      final bool isSelectedToday = isSameDay(_selectedDay, DateTime.now());
      final String dayHeader = isJapanese
          ? '${DateFormat('M月d日').format(_selectedDay)}${isSelectedToday ? ' ・ 今日' : ''}'
          : '${DateFormat('EEEE, MMM d').format(_selectedDay).toUpperCase()}${isSelectedToday ? ' • TODAY' : ''}';

      return Container(
        color: appleGroupedBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              decoration: const BoxDecoration(
                color: appleGroupedBg,
                border: Border(
                  top: BorderSide(color: appleHairline, width: 0.5),
                  bottom: BorderSide(color: appleHairline, width: 0.5),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dayHeader,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      color: isSelectedToday ? appleRed : appleSecondaryLabel,
                    ),
                  ),
                  if (_selectedEvents.isNotEmpty)
                    Text(
                      isJapanese
                          ? '${_selectedEvents.length}件'
                          : '${_selectedEvents.length} ${_selectedEvents.length == 1 ? 'event' : 'events'}',
                      style: const TextStyle(fontSize: 12, color: appleSecondaryLabel),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _selectedEvents.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isJapanese ? '予定なし' : 'No Events',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              color: appleSecondaryLabel,
                            ),
                          ),
                          const SizedBox(height: 6),
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            onPressed: globalLoading.value
                                ? null
                                : () => _showAddEventDialog(context, _selectedDay),
                            child: Text(
                              isJapanese ? '+ 予定を追加' : '+ New Event',
                              style: const TextStyle(fontSize: 14, color: appleRed),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 100),
                      itemCount: _selectedEvents.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final event = _selectedEvents[index];
                        final Color eventColor = _getEventColor(event.eventType);
                        final bool isHighPriorityTodo = event.isTodo &&
                            event.id != null &&
                            _highPriorityTodoEventIds.contains(event.id);

                        final String primaryTime = event.isTodo
                            ? (event.isAllDay
                                ? (isJapanese ? '期限' : 'Due')
                                : DateFormat('HH:mm').format(event.displayEndTime))
                            : (event.isAllDay
                                ? (isJapanese ? '終日' : 'All-day')
                                : DateFormat('HH:mm').format(event.displayEffectiveTime));

                        final String secondaryTime = event.isTodo
                            ? (event.isAllDay ? 'To-Do' : event.timezone.split('/').last)
                            : (event.isAllDay
                                ? event.eventType
                                : DateFormat('HH:mm').format(event.displayEndTime));

                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => EventDetailPage(
                                    event: event,
                                    authToken: widget.authToken,
                                    isJapanese: isJapanese,
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
                                      setState(() => _eventType = newType);
                                    },
                                  ),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                              child: Row(
                                children: [
                                  // Apple Calendar Left Vertical Color Bar
                                  Container(
                                    width: 4,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: eventColor,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            if (event.isTodo) ...[
                                              Icon(
                                                event.isComplete
                                                    ? CupertinoIcons.checkmark_circle_fill
                                                    : CupertinoIcons.circle,
                                                size: 16,
                                                color: eventColor,
                                              ),
                                              const SizedBox(width: 6),
                                            ],
                                            Expanded(
                                              child: Text(
                                                event.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  color: (event.isTodo && event.isComplete)
                                                      ? appleSecondaryLabel
                                                      : Colors.black,
                                                  decoration: (event.isTodo && event.isComplete)
                                                      ? TextDecoration.lineThrough
                                                      : TextDecoration.none,
                                                ),
                                              ),
                                            ),
                                            if (isHighPriorityTodo) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: appleRed.withOpacity(0.12),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Text(
                                                  'HIGH',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: appleRed,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          event.description.isNotEmpty
                                              ? event.description
                                              : event.eventType,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: appleSecondaryLabel,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        primaryTime,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        secondaryTime,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: appleSecondaryLabel,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    }

    Widget buildAppleBottomBar(double screenWidth) {
      final bool isPhone = screenWidth < 600;
      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF9F9FB).withOpacity(0.92),
              border: const Border(top: BorderSide(color: appleHairline, width: 0.5)),
            ),
            child: SafeArea(
              top: false,
              minimum: EdgeInsets.only(bottom: isPhone ? 18 : 0),
              child: Padding(
                padding: EdgeInsets.only(top: isPhone ? 4 : 0),
                child: SizedBox(
                  height: 54,
                  child: Row(
                    children: [
                      if (activeTab == 'calendar')
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minSize: 32,
                            onPressed: () async {
                              final now = DateTime.now();
                              final bool yearChanged = now.year != _focusedDay.year;
                              setState(() {
                                _focusedDay = now;
                                _selectedDay = now;
                              });
                              if (yearChanged) {
                                await fetchEventsFromJava(targetYear: now.year);
                              }
                            },
                            child: Text(
                              isJapanese ? '今日' : 'Today',
                              style: const TextStyle(
                                color: appleRed,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(tabKeys.length, (index) {
                            final key = tabKeys[index];
                            final bool selected = index == _currentTabIndex;
                            late IconData icon;
                            late String label;
                            switch (key) {
                              case 'todo':
                                icon = selected
                                    ? CupertinoIcons.checkmark_circle_fill
                                    : CupertinoIcons.checkmark_circle;
                                label = 'To-Do';
                                break;
                              case 'payroll':
                                icon = selected
                                    ? CupertinoIcons.money_dollar_circle_fill
                                    : CupertinoIcons.money_dollar_circle;
                                label = isJapanese ? '給与' : 'Payroll';
                                break;
                              case 'settings':
                                icon = selected ? CupertinoIcons.gear_solid : CupertinoIcons.gear;
                                label = isJapanese ? '設定' : 'Settings';
                                break;
                              case 'calendar':
                              default:
                                icon = selected ? CupertinoIcons.calendar_today : CupertinoIcons.calendar;
                                label = isJapanese ? 'カレンダー' : 'Calendar';
                                break;
                            }
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () async {
                                setState(() => _currentTabIndex = index);
                                if (key == 'calendar') {
                                  await fetchEventsFromJava();
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      icon,
                                      size: 22,
                                      color: selected ? appleRed : appleSecondaryLabel,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                                        color: selected ? appleRed : appleSecondaryLabel,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Scaffold(
          backgroundColor: appleGroupedBg,
          body: Column(
            children: [
              buildAppleTopHeader(constraints.maxWidth),
              Expanded(
                child: activeTab == 'settings'
                    ? SettingsPage(
                        backendBaseUrl: kBackendBaseUrl,
                        authToken: widget.authToken,
                        username: widget.username,
                        initialSettings: _activeSettings,
                        onSettingsUpdated: (updated) {
                          setState(() {
                            _activeSettings = updated;
                            if (kSupportedTimezones.contains(updated.timezone)) {
                              _startTimezone = updated.timezone;
                              _endTimezone = updated.timezone;
                            }
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
                    : activeTab == 'todo'
                        ? TodoListPage(
                            backendBaseUrl: kBackendBaseUrl,
                            authToken: widget.authToken,
                            defaultTimezone: _defaultUserTimezone(),
                            isJapanese: isJapanese,
                            onTodoChanged: () => fetchEventsFromJava(),
                          )
                        : activeTab == 'payroll'
                            ? const Center(child: Text('Payroll Page'))
                            : Column(
                                children: [
                                  buildAppleMonthGrid(constraints.maxWidth),
                                  Expanded(child: buildSelectedDayAgenda()),
                                ],
                            ),
              ),
            ],
          ),
          bottomNavigationBar: buildAppleBottomBar(constraints.maxWidth),
        );
      },
    );
  }
}