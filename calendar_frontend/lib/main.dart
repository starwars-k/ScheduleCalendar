import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart'; // The calendar widget
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:calendar_frontend/event_model.dart'; // The event model class
import 'package:intl/intl.dart';
import 'package:calendar_frontend/EventDetailPage.dart';
import 'package:calendar_frontend/login_page.dart';
import 'package:flutter/cupertino.dart'; // For LocalDateTime
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

const String kBackendBaseUrl = 'https://calendar-backend-qhny.onrender.com'; // Replace with your backend URL
final ValueNotifier<bool> globalLoading = ValueNotifier<bool>(false);
void main() => runApp(
  MaterialApp(
    home: const AuthGatePage(),
    builder:(context, child){
      return Stack(
        children: [
          child!,
          ValueListenableBuilder<bool>(
            valueListenable: globalLoading,
            builder: (context, isLoading, child){
              if(!isLoading) return const SizedBox.shrink();
              return Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Colors.black,
                  ),
                )
              );
            }
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
  bool _checkingAuth = true;

  @override
  void initState() {
    super.initState();
    _loadSavedAuth();
  }

  Future<void> _loadSavedAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('auth_token');
    final savedUsername = prefs.getString('auth_username');
    if (!mounted) return;
    setState(() {
      _token = (savedToken != null && savedToken.isNotEmpty) ? savedToken : null;
      _username = savedUsername;
      _checkingAuth = false;
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_username');
    await prefs.remove('auth_userId');
    if (!mounted) return;
    setState(() {
      _token = null;
      _username = null;
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
        backendBaseUri: kBackendBaseUrl,
        onLoginSuccess: (token, username) {
          setState(() {
            _token = token;
            _username = username;
          });
        },
      );
    }
    return CalendarPage(
      authToken: _token!,
      username: _username ?? '',
      onLogout: _logout,
    );
  }
}

class CalendarPage extends StatefulWidget {
  final String authToken;
  final String username;
  final Future<void> Function() onLogout;

  const CalendarPage({
    super.key,
    required this.authToken,
    required this.username,
    required this.onLogout,
  });

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();
  String _eventType = 'Task';
  String _repeatType = 'Daily';
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  DateTime _startTime = DateTime.now();
  DateTime _endTime = DateTime.now().add(const Duration(hours: 1));
  bool _isAllDay = false;
  bool _isRepeating = false;
  bool _endOn = false;
  final bool _isSearching = false;
  DateTime _repeatEndDate = DateTime.now().add(const Duration(days: 1));
  CalendarFormat _calendarFormat = CalendarFormat.month;
  List<DailyEvent> _events = [];

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
      final dayStart = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day, 0, 0, 0);
      final dayEnd = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day, 23, 59, 59);
      return event.startTime.isBefore(dayEnd) && event.endTime.isAfter(dayStart);
    }).toList();
    list.sort((a, b) => a.startTime.compareTo(b.startTime));
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

  @override
  void initState() {
    super.initState();
    fetchEventsFromJava();
  }

  Future<bool?> _showAddEventDialog(BuildContext context, DateTime initialDate, {DailyEvent? eventToEdit, String? initialEventType}) async {
    final bool isEditing = eventToEdit != null;
    _titleController.text = isEditing ? eventToEdit.title : '';
    _isAllDay = isEditing ? eventToEdit.isAllDay : false;
    _startTime = isEditing ? eventToEdit.startTime : DateTime(initialDate.year, initialDate.month, initialDate.day, DateTime.now().hour);
    _endTime = isEditing ? eventToEdit.endTime : _startTime.add(const Duration(hours: 1));
    _isRepeating = isEditing ? eventToEdit.isRepeating : false;
    _repeatType = isEditing && eventToEdit.repeatType != null ? eventToEdit.repeatType! : 'None';
    _repeatOptions.contains(_repeatType) ? _repeatType : 'Daily';
    _endOn = isEditing ? (eventToEdit.repeatEndOn != null) : false;
    if (isEditing && eventToEdit.repeatEndOn != null) {
      _repeatEndDate = eventToEdit.repeatEndOn!;
    } else {
      _repeatEndDate = initialDate.add(const Duration(days: 1));
    }
    _memoController.text = isEditing ? eventToEdit.description : '';
    _eventType = initialEventType ?? (isEditing ? eventToEdit.eventType : 'Task');

    final ScrollController modalScrollController = ScrollController();
    return await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.95,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                title: Text(isEditing ? "Edit Event" : "Add New Event"),
                automaticallyImplyLeading: false,
                backgroundColor: Colors.transparent,
                elevation: 0,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
              body: Scrollbar(
                controller: modalScrollController,
                thumbVisibility: true,
                trackVisibility: true,
                child: SingleChildScrollView(
                  controller: modalScrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 40.0, left: 20.0, right: 20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: _titleController,
                        decoration: const InputDecoration(hintText: "Event Title"),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Checkbox(
                            value: _isAllDay,
                            onChanged: (bool? value) {
                              setDialogState(() {
                                _isAllDay = value ?? false;
                                _startTime = DateTime(
                                  _startTime.year,
                                  _startTime.month,
                                  _startTime.day,
                                  DateTime.now().hour,
                                  0,
                                );
                              });
                            },
                          ),
                          const Text("All-Day Event"),
                        ],
                      ),
                      if (!_isAllDay) ...[
                        ListTile(
                          title: const Text("Start Time"),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              TextButton.icon(
                                label: Text(
                                  DateFormat('yyyy-MM-dd').format(_startTime),
                                  style: const TextStyle(color: Colors.black),
                                ),
                                style: TextButton.styleFrom(
                                  backgroundColor: CupertinoColors.extraLightBackgroundGray,
                                  shape: const StadiumBorder(),
                                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                ),
                                onPressed: () async {
                                  final DateTime? pickedDate = await showDatePicker(
                                    context: context,
                                    initialDate: _startTime,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                  );
                                  if (pickedDate != null) {
                                    setDialogState(() {
                                      _startTime = DateTime(
                                        pickedDate.year,
                                        pickedDate.month,
                                        pickedDate.day,
                                        _startTime.hour,
                                        _startTime.minute,
                                      );
                                      if (_endTime.isBefore(_startTime)) {
                                        _endTime = _startTime.add(const Duration(hours: 1));
                                      }
                                    });
                                  }
                                },
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  backgroundColor: CupertinoColors.extraLightBackgroundGray,
                                  shape: const StadiumBorder(),
                                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                ),
                                onPressed: () async {
                                  final TimeOfDay? pickedTime = await _showAppleStyleTimePicker(
                                    context: context,
                                    initialTime: _startTime,
                                  );
                                  if (pickedTime != null) {
                                    setDialogState(() {
                                      _startTime = DateTime(
                                        _startTime.year,
                                        _startTime.month,
                                        _startTime.day,
                                        pickedTime.hour,
                                        pickedTime.minute,
                                      );
                                      if (_endTime.isBefore(_startTime)) {
                                        _endTime = _startTime.add(const Duration(hours: 1));
                                      }
                                    });
                                  }
                                },
                                child: Text(
                                  DateFormat('HH:mm').format(_startTime),
                                  style: const TextStyle(color: Colors.black),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          title: const Text("End Time"),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              TextButton.icon(
                                label: Text(
                                  DateFormat('yyyy-MM-dd').format(_endTime),
                                  style: const TextStyle(color: Colors.black),
                                ),
                                style: TextButton.styleFrom(
                                  backgroundColor: CupertinoColors.extraLightBackgroundGray,
                                  shape: const StadiumBorder(),
                                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                ),
                                onPressed: () async {
                                  final DateTime? pickedDate = await showDatePicker(
                                    context: context,
                                    initialDate: _endTime,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                  );
                                  if (pickedDate != null) {
                                    setDialogState(() {
                                      _endTime = DateTime(
                                        pickedDate.year,
                                        pickedDate.month,
                                        pickedDate.day,
                                        _endTime.hour,
                                        _endTime.minute,
                                      );
                                      if (_startTime.isAfter(_endTime)) {
                                        _startTime = _endTime.subtract(const Duration(hours: 1));
                                      }
                                    });
                                  }
                                },
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  backgroundColor: CupertinoColors.extraLightBackgroundGray,
                                  shape: const StadiumBorder(),
                                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                ),
                                onPressed: () async {
                                  final TimeOfDay? pickedTime = await _showAppleStyleTimePicker(
                                    context: context,
                                    initialTime: _endTime,
                                  );
                                  if (pickedTime != null) {
                                    setDialogState(() {
                                      _endTime = DateTime(
                                        _endTime.year,
                                        _endTime.month,
                                        _endTime.day,
                                        pickedTime.hour,
                                        pickedTime.minute,
                                      );
                                      if (_startTime.isAfter(_endTime)) {
                                        _startTime = _endTime.add(const Duration(hours: 1));
                                      }
                                    });
                                  }
                                },
                                child: Text(
                                  DateFormat('HH:mm').format(_endTime),
                                  style: const TextStyle(color: Colors.black),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Divider(height: 1),
                      Row(
                        children: [
                          Checkbox(
                            value: _isRepeating,
                            onChanged: (bool? value) {
                              setDialogState(() {
                                _isRepeating = value ?? false;
                                if (_isRepeating && _repeatType == 'None') {
                                  _repeatType = 'Daily';
                                } else if (!_isRepeating) {
                                  _repeatType = 'None';
                                }
                              });
                            },
                          ),
                          const Text("Repeat this event"),
                        ],
                      ),
                      if (_isRepeating) ...[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: _repeatType == 'None' ? 'Daily' : _repeatType,
                          decoration: const InputDecoration(
                            labelText: "How often?",
                            border: OutlineInputBorder(),
                          ),
                          items: _repeatOptions
                              .map((option) => DropdownMenuItem<String>(
                                    value: option,
                                    child: Text(option),
                                  ))
                              .toList(),
                          onChanged: (value) => setDialogState(() {
                            _repeatType = value!;
                          }),
                        ),
                      ],
                      if (_isRepeating) ...[
                        Row(
                          children: [
                            Checkbox(
                              value: _endOn,
                              onChanged: (bool? value) {
                                setDialogState(() {
                                  _endOn = value ?? false;
                                });
                              },
                            ),
                            const Text("Set an end date for repeating"),
                          ],
                        ),
                      ],
                      if (_isRepeating && _endOn) ...[
                        TextButton.icon(
                          icon: const Icon(Icons.calendar_today),
                          label: Text("The repeat finishes on: ${DateFormat('yyyy-MM-dd').format(_repeatEndDate)}"),
                          onPressed: () async {
                            final DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: _repeatEndDate,
                              firstDate: DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                _repeatEndDate = picked;
                              });
                            }
                          },
                        ),
                      ],
                      TextField(
                        controller: _memoController,
                        decoration: const InputDecoration(
                          labelText: "Memo/ Description",
                          prefixIcon: Icon(Icons.note),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 15),
                      DropdownButtonFormField<String>(
                        initialValue: _eventType,
                        decoration: const InputDecoration(
                          labelText: "Event Type",
                          prefixIcon: Icon(Icons.category),
                          border: OutlineInputBorder(),
                        ),
                        items: _eventTypes.map((String type) {
                          return DropdownMenuItem<String>(
                            value: type,
                            child: Text(type),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setDialogState(() {
                            _eventType = newValue!;
                          });
                        },
                      ),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text("Cancel"),
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              if (_titleController.text.isNotEmpty) {
                                if (isEditing && eventToEdit.id != null) {
                                  globalLoading.value = true;
                                  bool success = await _updateEvent(eventToEdit.id!, _startTime, _endTime);
                                  if (success && context.mounted) {
                                    Navigator.pop(context, true);
                                  }
                                } else {
                                  await _makeNewEvents(_startTime, _endTime);
                                }
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Event title cannot be empty!")),
                                );
                              }
                            },
                            child: Text(isEditing ? "Update" : "Save"),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> fetchEventsFromJava() async {
    await showLoadingIfNeeded(() async {
      try {
        final response = await http.get(
          Uri.parse('$kBackendBaseUrl/api/events'),
          headers: _authHeaders(),
        );
        if (response.statusCode == 200) {
          List<dynamic> body = jsonDecode(response.body);
          if (!mounted) return;
          setState(() {
            _events = body.map((dynamic item) => DailyEvent.fromJson(item)).cast<DailyEvent>().toList();
          });
        } else if (response.statusCode == 401) {
          await widget.onLogout();
        } else {
          debugPrint("Failed to load events: ${response.statusCode}");
        }
      } catch (e) {
        debugPrint("FLUTTER ERROR: $e");
      }
    });
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

  Future<void> _makeNewEvents(DateTime startTime, DateTime endTime) async {
    await showLoadingIfNeeded(() async {
      try {
        final Map<String, dynamic> eventData = {
          'title': _titleController.text,
          'description': _memoController.text,
          'startTime': _formatToBackendIso(startTime),
          'endTime': _formatToBackendIso(endTime),
          'eventType': _eventType,
          'isAllDay': _isAllDay,
          'isRepeating': _isRepeating,
          'repeatType': _isRepeating ? _repeatType : 'None',
          'endOn': _isRepeating ? _endOn : false,
          'repeatEndOn': (_isRepeating && _endOn)
              ? _formatToBackendIso(DateTime(_repeatEndDate.year, _repeatEndDate.month, _repeatEndDate.day, 23, 59, 59))
              : null,
        };
        final response = await http.post(
          Uri.parse('$kBackendBaseUrl/api/events/'),
          headers: _authHeaders(json: true),
          body: jsonEncode(eventData),
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
        final Map<String, dynamic> eventData = {
          'title': _titleController.text,
          'description': _memoController.text,
          'startTime': _formatToBackendIso(startTime),
          'endTime': _formatToBackendIso(endTime),
          'eventType': _eventType,
          'isAllDay': _isAllDay,
          'isRepeating': _isRepeating,
          'repeatType': _isRepeating ? _repeatType : 'None',
          'endOn': _isRepeating ? _endOn : false,
          'repeatEndOn': (_isRepeating && _endOn)
              ? _formatToBackendIso(DateTime(_repeatEndDate.year, _repeatEndDate.month, _repeatEndDate.day, 23, 59, 59))
              : null,
        };
        final response = await http.put(
          Uri.parse('$kBackendBaseUrl/api/events/$id'),
          headers: _authHeaders(json: true),
          body: jsonEncode(eventData),
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

  @override
  Widget build(BuildContext context) {
    String localQuery = '';
    bool isSearchByName = true;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.username.isNotEmpty
              ? 'Schedule Calendar (${widget.username})'
              : 'Schedule Calendar',
        ),
        actions: [
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
                                              DateFormat('yyyy-MM-dd').format(event.startTime),
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
                                            _selectedDay = event.startTime;
                                            _focusedDay = event.startTime;
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
              await widget.onLogout();
            },
          ),
        ],
      ),
      body: Stack(
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
                  return _events.where((event) => event.startTime.isBefore(dayEnd) && event.endTime.isAfter(dayStart)).toList();
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
                  }
                },
              ),
              const SizedBox(height: 8.0),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: _selectedEvents.length,
                  itemBuilder: (context, index) {
                    final event = _selectedEvents[index];
                    return ListTile(
                      leading: Icon(Icons.event, color: _getEventColor(event.eventType)),
                      title: Text(event.title),
                      subtitle: Text(
                        event.isAllDay
                            ? "All-Day"
                            : "${DateFormat('MMM d, HH:mm').format(event.startTime)} - ${DateFormat('MMM d, HH:mm').format(event.endTime)}",
                      ),
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
                                  event.startTime,
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
            bottom: 30,
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
    );
  }
}