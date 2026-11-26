import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:calendar_frontend/todo_model.dart';

class TodoListPage extends StatefulWidget {
  final String backendBaseUrl;
  final String authToken;
  final String defaultTimezone;
  final Future<void> Function() onTodoChanged;

  const TodoListPage({
    super.key,
    required this.backendBaseUrl,
    required this.authToken,
    required this.defaultTimezone,
    required this.onTodoChanged,
  });

  @override
  State<TodoListPage> createState() => _TodoListPageState();
}

class _TodoListPageState extends State<TodoListPage> {
  List<TodoItem> _todos = [];
  bool _isLoading = false;
  String _filter = 'All'; // 'All', 'Active', 'Favorites', 'Completed'

  final List<String> _categories = ['Task', 'Job', 'Class', 'Birthday', 'Personal'];
  final List<String> _priorities = ['HIGH', 'MEDIUM', 'LOW'];

  Map<String, String> _headers({bool json = false}) {
    final headers = <String, String>{
      'Authorization': 'Bearer ${widget.authToken}',
    };
    if (json) {
      headers['Content-Type'] = 'application/json';
    }
    return headers;
  }

  @override
  void initState() {
    super.initState();
    _fetchTodos();
  }

  Future<void> _fetchTodos() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('${widget.backendBaseUrl}/api/todos'),
        headers: _headers(),
      );
      if (response.statusCode == 200 && mounted) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _todos = data.map((item) => TodoItem.fromJson(item)).toList();
        });
      }
    } catch (e) {
      debugPrint('Error fetching todos: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleComplete(TodoItem todo) async {
    if (todo.id == null) return;
    try {
      final response = await http.patch(
        Uri.parse('${widget.backendBaseUrl}/api/todos/${todo.id}/toggle'),
        headers: _headers(),
      );
      if (response.statusCode == 200) {
        await _fetchTodos();
        await widget.onTodoChanged();
      }
    } catch (e) {
      debugPrint('Error toggling todo complete: $e');
    }
  }

  Future<void> _toggleFavorite(TodoItem todo) async {
    if (todo.id == null) return;
    try {
      final response = await http.patch(
        Uri.parse('${widget.backendBaseUrl}/api/todos/${todo.id}/favorite'),
        headers: _headers(),
      );
      if (response.statusCode == 200) {
        await _fetchTodos();
      }
    } catch (e) {
      debugPrint('Error toggling todo favorite: $e');
    }
  }

  Future<void> _deleteTodo(TodoItem todo) async {
    if (todo.id == null) return;
    try {
      final response = await http.delete(
        Uri.parse('${widget.backendBaseUrl}/api/todos/${todo.id}'),
        headers: _headers(),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        await _fetchTodos();
        await widget.onTodoChanged();
      }
    } catch (e) {
      debugPrint('Error deleting todo: $e');
    }
  }

  List<TodoItem> get _filteredTodos {
    switch (_filter) {
      case 'Active':
        return _todos.where((t) => !t.isComplete).toList();
      case 'Favorites':
        return _todos.where((t) => t.isFavorite).toList();
      case 'Completed':
        return _todos.where((t) => t.isComplete).toList();
      case 'All':
      default:
        return _todos;
    }
  }

  Color _priorityColor(String priority) {
    switch (priority.toUpperCase()) {
      case 'HIGH':
        return Colors.redAccent;
      case 'LOW':
        return Colors.teal;
      case 'MEDIUM':
      default:
        return Colors.amber.shade800;
    }
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'Task':
        return Colors.blueAccent;
      case 'Job':
        return Colors.green;
      case 'Class':
        return Colors.orange;
      case 'Birthday':
        return Colors.pinkAccent;
      case 'Personal':
        return Colors.purpleAccent;
      default:
        return Colors.grey;
    }
  }

  Future<void> _showTodoEditor({TodoItem? existing}) async {
    final isEditing = existing != null;
    final titleCtrl = TextEditingController(text: isEditing ? existing.title : '');
    final descCtrl = TextEditingController(text: isEditing ? existing.description : '');
    String category = isEditing && _categories.contains(existing.category) ? existing.category : 'Task';
    String priority = isEditing && _priorities.contains(existing.priority) ? existing.priority : 'MEDIUM';
    bool isFavorite = isEditing ? existing.isFavorite : false;
    bool isComplete = isEditing ? existing.isComplete : false;
    DateTime dueDate = isEditing ? existing.dueDate : DateTime.now();
    bool dueTimeOn = isEditing ? existing.dueTimeOn : false;
    TimeOfDay dueTime = const TimeOfDay(hour: 18, minute: 0);
    if (isEditing && existing.dueTime != null && existing.dueTime!.contains(':')) {
      final parts = existing.dueTime!.split(':');
      dueTime = TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 18,
        minute: int.tryParse(parts[1]) ?? 0,
      );
    }
    bool reminderOn = isEditing && existing.reminder != null;
    DateTime reminderDateTime = isEditing && existing.reminder != null
        ? existing.reminder!
        : DateTime(dueDate.year, dueDate.month, dueDate.day, 9, 0);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            left: 20,
            right: 20,
            top: 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isEditing ? 'Edit To-Do' : 'New To-Do',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            isFavorite ? Icons.star : Icons.star_border,
                            color: isFavorite ? Colors.amber : Colors.grey,
                          ),
                          onPressed: () => setModalState(() => isFavorite = !isFavorite),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: titleCtrl,
                  autofocus: !isEditing,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description / Memo',
                    prefixIcon: Icon(Icons.notes),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                        ),
                        items: _categories
                            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setModalState(() => category = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: priority,
                        decoration: const InputDecoration(
                          labelText: 'Priority',
                          border: OutlineInputBorder(),
                        ),
                        items: _priorities
                            .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setModalState(() => priority = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Due Date (Synced to Calendar)'),
                  subtitle: Text(
                    'Timezone: ${widget.defaultTimezone}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(DateFormat('yyyy-MM-dd').format(dueDate)),
                    style: TextButton.styleFrom(
                      backgroundColor: CupertinoColors.extraLightBackgroundGray,
                      shape: const StadiumBorder(),
                    ),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: dueDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setModalState(() => dueDate = picked);
                      }
                    },
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Due Time'),
                  subtitle: Text(
                    dueTimeOn
                        ? '${dueTime.hour.toString().padLeft(2, '0')}:${dueTime.minute.toString().padLeft(2, '0')}'
                        : 'All-Day on Due Date',
                  ),
                  value: dueTimeOn,
                  onChanged: (val) => setModalState(() => dueTimeOn = val),
                ),
                if (dueTimeOn)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.access_time, size: 16),
                      label: Text(
                        '${dueTime.hour.toString().padLeft(2, '0')}:${dueTime.minute.toString().padLeft(2, '0')}',
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: CupertinoColors.extraLightBackgroundGray,
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () async {
                        final pickedTime = await showTimePicker(
                          context: ctx,
                          initialTime: dueTime,
                        );
                        if (pickedTime != null) {
                          setModalState(() => dueTime = pickedTime);
                        }
                      },
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reminder'),
                  subtitle: Text(
                    reminderOn
                        ? DateFormat('yyyy-MM-dd HH:mm').format(reminderDateTime)
                        : 'Off',
                  ),
                  value: reminderOn,
                  onChanged: (val) => setModalState(() => reminderOn = val),
                ),
                if (reminderOn)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () async {
                          final pickedDate = await showDatePicker(
                            context: ctx,
                            initialDate: reminderDateTime,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (pickedDate != null) {
                            setModalState(() {
                              reminderDateTime = DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                reminderDateTime.hour,
                                reminderDateTime.minute,
                              );
                            });
                          }
                        },
                        child: Text(DateFormat('yyyy-MM-dd').format(reminderDateTime)),
                      ),
                      TextButton(
                        onPressed: () async {
                          final pickedTime = await showTimePicker(
                            context: ctx,
                            initialTime: TimeOfDay.fromDateTime(reminderDateTime),
                          );
                          if (pickedTime != null) {
                            setModalState(() {
                              reminderDateTime = DateTime(
                                reminderDateTime.year,
                                reminderDateTime.month,
                                reminderDateTime.day,
                                pickedTime.hour,
                                pickedTime.minute,
                              );
                            });
                          }
                        },
                        child: Text(DateFormat('HH:mm').format(reminderDateTime)),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    if (titleCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Title cannot be empty')),
                      );
                      return;
                    }
                    final formattedDueTime =
                        '${dueTime.hour.toString().padLeft(2, '0')}:${dueTime.minute.toString().padLeft(2, '0')}';
                    final payload = TodoItem(
                      id: existing?.id,
                      title: titleCtrl.text.trim(),
                      description: descCtrl.text.trim(),
                      category: category,
                      priority: priority,
                      isFavorite: isFavorite,
                      isComplete: isComplete,
                      dueTimeOn: dueTimeOn,
                      dueDate: dueDate,
                      dueTime: dueTimeOn ? formattedDueTime : null,
                      reminder: reminderOn ? reminderDateTime : null,
                    ).toJson();

                    try {
                      final response = isEditing
                          ? await http.put(
                              Uri.parse('${widget.backendBaseUrl}/api/todos/${existing.id}'),
                              headers: _headers(json: true),
                              body: jsonEncode(payload),
                            )
                          : await http.post(
                              Uri.parse('${widget.backendBaseUrl}/api/todos'),
                              headers: _headers(json: true),
                              body: jsonEncode(payload),
                            );
                      if (response.statusCode == 200 || response.statusCode == 201) {
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _fetchTodos();
                        await widget.onTodoChanged();
                      }
                    } catch (e) {
                      debugPrint('Error saving todo: $e');
                    }
                  },
                  child: Text(isEditing ? 'Update To-Do' : 'Save To-Do'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleTodos = _filteredTodos;
    return Scaffold(
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: ['All', 'Active', 'Favorites', 'Completed'].map((filterName) {
                final selected = _filter == filterName;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(filterName),
                    selected: selected,
                    onSelected: (_) => setState(() => _filter = filterName),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : visibleTodos.isEmpty
                    ? const Center(child: Text('No to-do items yet. Tap + to add one!'))
                    : ListView.separated(
                        itemCount: visibleTodos.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final todo = visibleTodos[index];
                          final dueLabel = todo.dueTimeOn && todo.dueTime != null
                              ? 'Due: ${DateFormat('MMM d, yyyy').format(todo.dueDate)} ${todo.dueTime}'
                              : 'Due: ${DateFormat('MMM d, yyyy').format(todo.dueDate)} (All-Day)';

                          return ListTile(
                            leading: Checkbox(
                              value: todo.isComplete,
                              onChanged: (_) => _toggleComplete(todo),
                            ),
                            title: Text(
                              todo.title,
                              style: TextStyle(
                                decoration: todo.isComplete
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                                color: todo.isComplete ? Colors.grey : Colors.black,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (todo.description.isNotEmpty)
                                  Text(
                                    todo.description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      dueLabel,
                                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: _priorityColor(todo.priority).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        todo.priority,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: _priorityColor(todo.priority),
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: _categoryColor(todo.category).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        todo.category,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _categoryColor(todo.category),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    todo.isFavorite ? Icons.star : Icons.star_border,
                                    color: todo.isFavorite ? Colors.amber : Colors.grey,
                                  ),
                                  onPressed: () => _toggleFavorite(todo),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () => _deleteTodo(todo),
                                ),
                              ],
                            ),
                            onTap: () => _showTodoEditor(existing: todo),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showTodoEditor(),
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }
}