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

  const EventDetailPage({
    super.key, 
    required this.event, 
    required this.authToken,
    required this.onDelete,
    required this.onUpdate,
    required this.onEdit,
    required this.allEventTypes,
    required this.onEventTypeChanged,
  });

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  late String _eventType;
  bool _isUpdatedFromOutSide = false;
  static const String _baseUrl = 'https://calendar-backend-qhny.onrender.com';
  //static const String _baseUrl = 'http://localhost:8080';
  Map<String, String> _headers({bool json = false}) {
    final headers = <String, String>{
      'Authorization': 'Bearer ${widget.authToken}',
    };
    if (json) {
      headers['Content-Type'] = 'application/json';
    }
    return headers;
  }

  //final List<String> _eventTypes = ["Task", "Job", "Class", "Birthday", "Personal"];
  @override
  void initState() {
    super.initState();
    _eventType = widget.event.eventType;
  }

  Future<void> _deleteSingleEvent() async {
    try{
      final response = await http.delete(
        //Uri.parse('http://localhost:8080/api/events/${widget.event.id}'),
        Uri.parse('$_baseUrl/api/events/${widget.event.id}'), // Use the deployed backend URL
        headers: _headers(),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        widget.onDelete(widget.event.id!);
        Navigator.pop(context);
      } else {
        print("Failed to delete event: ${response.statusCode}");
      }
    } catch (e) {
      print("Connection Error: $e");
    }
  }

  Future<void> _deleteFutureEvents() async {
    try{
      final response = await http.delete(
        Uri.parse('$_baseUrl/api/events/future/${widget.event.id}'), // Use the deployed backend URL
        headers: _headers(),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        widget.onDelete(widget.event.id!);
        Navigator.pop(context);
      } else {
        print("Failed to delete future events: ${response.statusCode}");
      }
    }catch (e) {
      print("Connection Error: $e");
    }
  }

  void _onDeleteButtonPressed(){
    bool isSeriesEvent = widget.event.isRepeating == true && widget.event.seriesId != null;
    if(isSeriesEvent){
      showDialog(
        context: context,
        builder: (BuildContext context){
          return AlertDialog(
            title: const Text("Delete Event"),
            actions: [
              TextButton(
                onPressed: (){
                  Navigator.pop(context);
                  _deleteSingleEvent();
                },
                child: const Text("Delete this event only", style: TextStyle(color: Colors.red)),
              ),
              TextButton(
                onPressed: (){
                  Navigator.pop(context);
                  _deleteFutureEvents();
                },
                child: const Text("Delete all after this event", style: TextStyle(color: Colors.red)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
            ],
          );
        },
      );
    } else {
      showDialog(
        context: context,
        builder: (BuildContext context){
          return AlertDialog(
            title: const Text("Delete Event"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: (){
                  Navigator.pop(context);
                  _deleteSingleEvent();
                },
                child: const Text("Delete", style: TextStyle(color: Colors.red)),
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> _updateEventTypeOnServer(String newType) async{
    await showLoadingIfNeeded(() async{
      try{
        final Map<String, dynamic> eventData = {
          'title': widget.event.title,
          'description': widget.event.description,
          'eventType': newType,
          'startTime': widget.event.isTodo ? null : widget.event.displayStartTime?.toIso8601String(),
          'endTime': widget.event.displayEndTime.toIso8601String(),
          'timezone': widget.event.timezone,
          'startTimezone':widget.event.startTimezone,
          'endTimezone':widget.event.endTimezone,
          'isAllDay': widget.event.isAllDay,
          'isRepeating': widget.event.isRepeating,
          'repeatType': widget.event.repeatType ?? 'None',
          'endOn': widget.event.endOn ?? (widget.event.repeatEndOn != null),
          'repeatEndOn': widget.event.repeatEndOn != null
            ? DailyEvent.convertUtcToTimezone(widget.event.repeatEndOn!, widget.event.startTimezone).toIso8601String()
            : null,
          'isTodo':widget.event.isTodo,
          'isComplete': widget.event.isComplete,
        };
        final response = await http.put(
          Uri.parse('$_baseUrl/api/events/${widget.event.id}'),
          headers: _headers(json: true),
          body: jsonEncode(eventData),
        );
        if(response.statusCode == 200 || response.statusCode == 204){
          widget.onUpdate();
          print("EventType updated Successfully");
        }
      }catch(e){
        print("Error updating eventType: $e");
      }
    });
  }

  Future<T> showLoadingIfNeeded<T>(Future<T> Function() task) async{
    bool isShown = false;
    Timer timer = Timer(const Duration(milliseconds: 100), (){
      isShown = true;
      globalLoading.value = true;
    });
    
    try{
      return await task();
    }finally{
      timer.cancel();
      if(isShown){
        globalLoading.value = false;
      }
    }
  }

  Future<void> _saveOnExit() async {
    widget.onUpdate();
  }

  Widget _buildTimeWidget(){
    final end = widget.event.displayEndTime;
    if(widget.event.isTodo) {
      final String dueText = widget.event.isAllDay
        ? 'Due Date: ${DateFormat('EEEE, MMMM dd, yyyy').format(end)} (All-Day)'
        : 'Due Time: ${DateFormat('EEEE, MMMM dd, yyyy HH:mm').format(end)} (${widget.event.timezone.split('/').last})';
      return Text(
        dueText,
        style: const TextStyle(fontSize: 15),
      );
    }
    final start = widget.event.displayStartTime ?? end;
    bool isSameDay = start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
    Widget timeTextWidget;
    if(widget.event.isAllDay&&isSameDay){
      timeTextWidget = Text(
        style: TextStyle(
          fontSize: 15,
        ),
        '${DateFormat('EEEE, MMMM dd, yyyy').format(start)}\nAll-Day'
      );
    }else if(widget.event.isAllDay){
      timeTextWidget = Text(
        style: TextStyle(
          fontSize: 15,
        ),
        '${DateFormat('EEEE, MMMM dd, yyyy').format(start)} - ${DateFormat('EEEE, MMMM dd, yyyy').format(end)}\nAll-Day'
      );
    }else if(isSameDay){
      timeTextWidget = Text(
        style: TextStyle(
          fontSize: 15,
        ),
        'Start: ${DateFormat('EEEE, MMMM dd, yyyy HH:mm').format(start)} (${widget.event.startTimezone.split('/').last})\nEnd: ${DateFormat('EEEE, MMMM dd, yyyy HH:mm').format(end)} (${widget.event.endTimezone.split('/').last})'
      );
    }else{
      timeTextWidget = Text(
        style: TextStyle(
          fontSize: 15,
        ),
        'Start: ${DateFormat('EEEE, MMMM dd, yyyy').format(start)}(${widget.event.startTimezone.split('/').last})\nEnd: ${DateFormat('EEEE, MMMM dd, yyyy HH:mm').format(end)} (${widget.event.endTimezone.split('/').last})'
      );
    }
    List<Widget> children = [timeTextWidget];
    if(widget.event.isRepeating == true && widget.event.repeatType != null && widget.event.repeatType != 'None'){
      String repeatInfo = 'Repeats: ${widget.event.repeatType}';
      children.addAll([
        const SizedBox(height:6),
        Text(
          repeatInfo,
          style: TextStyle(
            fontSize: 15,
            color: Colors.red,
          ),
        ),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result){
        if(didPop){
          _saveOnExit();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Event Details"),
          backgroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.edit, size: 28, color: Colors.green),
              onPressed: ()async{
                widget.onEdit(_eventType);
                setState(() {
                  _isUpdatedFromOutSide = true;
                });
              },
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Title
              Text(
                widget.event.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              // 2. Time
              _buildTimeWidget(),
              const SizedBox(height: 30),
              // 3. Event Type Dropdown
              DropdownButtonFormField<String>(
                value: _eventType.isNotEmpty ? _eventType : widget.allEventTypes.first,
                decoration: const InputDecoration(
                  labelText: "Event Type",
                  border: OutlineInputBorder(),
                ),
                items: widget.allEventTypes.map((String type) {
                  return DropdownMenuItem<String>(
                    value: type,
                    child: Text(
                      type,
                      selectionColor: Colors.grey,
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
              const SizedBox(height: 24),
              if (widget.event.description.isNotEmpty) ...[
                // 4. Memo
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Memo',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.event.description,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _onDeleteButtonPressed,
                  label: const Text(
                    "Delete Event",
                    style: TextStyle(color: Colors.red, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  } 
}