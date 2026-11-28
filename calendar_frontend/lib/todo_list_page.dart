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
  final bool isJapanese;

  const TodoListPage({
    super.key,
    required this.backendBaseUrl,
    required this.authToken,
    required this.defaultTimezone,
    required this.onTodoChanged,
    this.isJapanese = false,
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
    final bool nextComplete = !todo.isComplete;
    final int idx = _todos.indexWhere((t) => t.id == todo.id);
    if (idx != -1) {
      setState(() {
        _todos[idx] = TodoItem(
          id: todo.id,
          title: todo.title,
          description: todo.description,
          category: todo.category,
          priority: todo.priority,
          isFavorite: todo.isFavorite,
          isComplete: nextComplete,
          dueTimeOn: todo.dueTimeOn,
          dueDate: todo.dueDate,
          dueTime: todo.dueTime,
          reminder: todo.reminder,
          timezone: todo.timezone,
          linkedEventId: todo.linkedEventId,
        );
      });
    }
    try {
      http.Response response = await http.put(
        Uri.parse('${widget.backendBaseUrl}/api/todos/${todo.id}/toggle'),
        headers: _headers(),
      );
      if (response.statusCode != 200) {
        final fallbackPayload = TodoItem(
          id: todo.id,
          title: todo.title,
          description: todo.description,
          category: todo.category,
          priority: todo.priority,
          isFavorite: todo.isFavorite,
          isComplete: nextComplete,
          dueTimeOn: todo.dueTimeOn,
          dueDate: todo.dueDate,
          dueTime: todo.dueTime,
          reminder: todo.reminder,
        ).toJson();
        response = await http.put(
          Uri.parse('${widget.backendBaseUrl}/api/todos/${todo.id}'),
          headers: _headers(json: true),
          body: jsonEncode(fallbackPayload),
        );
      }
      if (response.statusCode == 200) {
        if(response.body.isNotEmpty && mounted){
          final updatedTodo = TodoItem.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>,
          );
          final currentIdx = _todos.indexWhere((t) => t.id == todo.id);
          if (currentIdx != -1) {
            setState(() => _todos[currentIdx] = updatedTodo);
          }
        }
        await widget.onTodoChanged();
      }else{
        await _fetchTodos();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              content: Text('Failed (${response.statusCode}): ${response.body}'),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error toggling todo complete: $e');
      await _fetchTodos();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              content: Text('Network error updating task: $e'),
          ),
        );
      }
    }
  }

  Future<void> _toggleFavorite(TodoItem todo) async {
    if (todo.id == null) return;
    try {
      final response = await http.put(
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
    final bool? confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(widget.isJapanese ? 'To-Doを削除' : 'Delete To-Do'),
        content: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            widget.isJapanese
                ? '「${todo.title}」を削除してもよろしいですか？\nこの操作は取り消せません。'
                : 'Are you sure you want to delete "${todo.title}"?\nThis action cannot be undone.',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(widget.isJapanese ? 'キャンセル' : 'Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(widget.isJapanese ? '削除' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final response = await http.delete(
        Uri.parse('${widget.backendBaseUrl}/api/todos/${todo.id}'),
        headers: _headers(),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        await _fetchTodos();
        await widget.onTodoChanged();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              content: Text(
                widget.isJapanese ? 'To-Doを削除しました' : 'To-Do deleted',
              ),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            content: Text(
              widget.isJapanese
                  ? '削除に失敗しました (${response.statusCode})'
                  : 'Failed to delete (${response.statusCode})',
            ),
          ),
        );
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
    String? activePicker;
    const Color appleRed = Color(0xFFFF3B30);
    const Color appleGroupedBg = Color(0xFFF2F2F7);
    const Color appleHairline = Color(0xFFE5E5EA);
    const Color appleSecondaryLabel = Color(0xFF8E8E93);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth:600),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          void togglePicker(String key) {
            setModalState(() => activePicker = (activePicker == key) ? null : key);
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
                      const Divider(height: 1, thickness: 0.5, indent: 16, color: appleHairline),
                  ],
                ],
              ),
            );
          }

          Widget buildApplePill({
            required String label,
            required bool isActive,
            required VoidCallback onTap,
          }) {
            return GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? appleRed.withOpacity(0.14) : const Color(0xFFEFEFF4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isActive ? appleRed : Colors.black87,
                  ),
                ),
              ),
            );
          }

          Future<void> saveTodo() async {
            if (titleCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(widget.isJapanese ? 'タイトルを入力してください' : 'Title cannot be empty')),
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
          }

          final bool canSubmit = titleCtrl.text.trim().isNotEmpty;
          final String dateFmt = widget.isJapanese ? 'yyyy/MM/dd' : 'MMM d, yyyy';

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: Container(
                height: MediaQuery.of(ctx).size.height * 0.9,
                color: appleGroupedBg,
                child: Column(
                  children: [
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
                                onPressed: () => Navigator.pop(ctx),
                                child: Text(
                                  widget.isJapanese ? 'キャンセル' : 'Cancel',
                                  style: const TextStyle(color: appleRed, fontSize: 16),
                                ),
                              ),
                              Text(
                                isEditing
                                    ? (widget.isJapanese ? 'To-Doを編集' : 'Edit To-Do')
                                    : (widget.isJapanese ? '新規To-Do' : 'New To-Do'),
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CupertinoButton(
                                    padding: const EdgeInsets.symmetric(horizontal: 6),
                                    onPressed: () => setModalState(() => isFavorite = !isFavorite),
                                    child: Icon(
                                      isFavorite ? CupertinoIcons.star_fill : CupertinoIcons.star,
                                      color: isFavorite ? Colors.amber : appleSecondaryLabel,
                                      size: 21,
                                    ),
                                  ),
                                  CupertinoButton(
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    onPressed: canSubmit ? saveTodo : null,
                                    child: Text(
                                      isEditing
                                          ? (widget.isJapanese ? '更新' : 'Update')
                                          : (widget.isJapanese ? '追加' : 'Add'),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: canSubmit ? appleRed : CupertinoColors.inactiveGray,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, thickness: 0.5, color: Color(0xFFD1D1D6)),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            buildGroupedCard([
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                child: TextField(
                                  controller: titleCtrl,
                                  autofocus: !isEditing,
                                  decoration: InputDecoration(
                                    hintText: widget.isJapanese ? 'タイトル' : 'Title',
                                    hintStyle: const TextStyle(color: CupertinoColors.placeholderText),
                                    border: InputBorder.none,
                                  ),
                                  onChanged: (_) => setModalState(() {}),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                child: TextField(
                                  controller: descCtrl,
                                  maxLines: 3,
                                  minLines: 1,
                                  decoration: InputDecoration(
                                    hintText: widget.isJapanese ? 'メモ' : 'Notes',
                                    hintStyle: const TextStyle(color: CupertinoColors.placeholderText),
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 16),
                            buildGroupedCard([
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      widget.isJapanese ? 'カテゴリー' : 'Category',
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                    DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: category,
                                        icon: const Icon(
                                          CupertinoIcons.chevron_up_chevron_down,
                                          size: 16,
                                          color: appleSecondaryLabel,
                                        ),
                                        items: _categories.map((c) {
                                          return DropdownMenuItem(
                                            value: c,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  width: 10,
                                                  height: 10,
                                                  decoration: BoxDecoration(
                                                    color: _categoryColor(c),
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(c, style: const TextStyle(fontSize: 15)),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (v) {
                                          if (v != null) setModalState(() => category = v);
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      widget.isJapanese ? '優先度' : 'Priority',
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                    DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: priority,
                                        icon: const Icon(
                                          CupertinoIcons.chevron_up_chevron_down,
                                          size: 16,
                                          color: appleSecondaryLabel,
                                        ),
                                        items: _priorities.map((p) {
                                          return DropdownMenuItem(
                                            value: p,
                                            child: Text(
                                              p,
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: _priorityColor(p),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (v) {
                                          if (v != null) setModalState(() => priority = v);
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ]),
                            const SizedBox(height: 16),
                            buildGroupedCard([
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      widget.isJapanese ? '期限日' : 'Due Date',
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                    buildApplePill(
                                      label: DateFormat(dateFmt).format(dueDate),
                                      isActive: activePicker == 'dueDate',
                                      onTap: () => togglePicker('dueDate'),
                                    ),
                                  ],
                                ),
                              ),
                              if (activePicker == 'dueDate')
                                SizedBox(
                                  height: 170,
                                  child: CupertinoDatePicker(
                                    mode: CupertinoDatePickerMode.date,
                                    initialDateTime: dueDate,
                                    onDateTimeChanged: (d) => setModalState(() => dueDate = d),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      widget.isJapanese ? '期限時刻を設定' : 'Due Time',
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (dueTimeOn) ...[
                                          buildApplePill(
                                            label:
                                                '${dueTime.hour.toString().padLeft(2, '0')}:${dueTime.minute.toString().padLeft(2, '0')}',
                                            isActive: activePicker == 'dueTime',
                                            onTap: () => togglePicker('dueTime'),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        CupertinoSwitch(
                                          value: dueTimeOn,
                                          activeTrackColor: appleRed,
                                          onChanged: (val) => setModalState(() {
                                            dueTimeOn = val;
                                            if (!val && activePicker == 'dueTime') activePicker = null;
                                          }),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (dueTimeOn && activePicker == 'dueTime')
                                SizedBox(
                                  height: 170,
                                  child: CupertinoDatePicker(
                                    mode: CupertinoDatePickerMode.time,
                                    use24hFormat: true,
                                    initialDateTime: DateTime(2026, 1, 1, dueTime.hour, dueTime.minute),
                                    onDateTimeChanged: (t) => setModalState(
                                      () => dueTime = TimeOfDay(hour: t.hour, minute: t.minute),
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      widget.isJapanese ? 'リマインダー' : 'Reminder',
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                    CupertinoSwitch(
                                      value: reminderOn,
                                      activeTrackColor: appleRed,
                                      onChanged: (val) => setModalState(() {
                                        reminderOn = val;
                                        if (!val &&
                                            (activePicker == 'reminderDate' || activePicker == 'reminderTime')) {
                                          activePicker = null;
                                        }
                                      }),
                                    ),
                                  ],
                                ),
                              ),
                              if (reminderOn) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      buildApplePill(
                                        label: DateFormat(dateFmt).format(reminderDateTime),
                                        isActive: activePicker == 'reminderDate',
                                        onTap: () => togglePicker('reminderDate'),
                                      ),
                                      const SizedBox(width: 8),
                                      buildApplePill(
                                        label: DateFormat('HH:mm').format(reminderDateTime),
                                        isActive: activePicker == 'reminderTime',
                                        onTap: () => togglePicker('reminderTime'),
                                      ),
                                    ],
                                  ),
                                ),
                                if (activePicker == 'reminderDate')
                                  SizedBox(
                                    height: 170,
                                    child: CupertinoDatePicker(
                                      mode: CupertinoDatePickerMode.date,
                                      initialDateTime: reminderDateTime,
                                      onDateTimeChanged: (d) => setModalState(() {
                                        reminderDateTime = DateTime(
                                          d.year,
                                          d.month,
                                          d.day,
                                          reminderDateTime.hour,
                                          reminderDateTime.minute,
                                        );
                                      }),
                                    ),
                                  ),
                                if (activePicker == 'reminderTime')
                                  SizedBox(
                                    height: 170,
                                    child: CupertinoDatePicker(
                                      mode: CupertinoDatePickerMode.time,
                                      use24hFormat: true,
                                      initialDateTime: reminderDateTime,
                                      onDateTimeChanged: (t) => setModalState(() {
                                        reminderDateTime = DateTime(
                                          reminderDateTime.year,
                                          reminderDateTime.month,
                                          reminderDateTime.day,
                                          t.hour,
                                          t.minute,
                                        );
                                      }),
                                    ),
                                  ),
                              ],
                            ]),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color appleRed = Color(0xFFFF3B30);
    const Color appleGroupedBg = Color(0xFFF2F2F7);
    const Color appleHairline = Color(0xFFE5E5EA);
    const Color appleSecondaryLabel = Color(0xFF8E8E93);
    final visibleTodos = _filteredTodos;

    String filterLabel(String key) {
      if (!widget.isJapanese) return key;
      switch (key) {
        case 'Active':
          return '未完了';
        case 'Favorites':
          return '重要';
        case 'Completed':
          return '完了';
        case 'All':
        default:
          return 'すべて';
      }
    }

    return Container(
      color: appleGroupedBg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: CupertinoSlidingSegmentedControl<String>(
                    groupValue: _filter,
                    children: {
                      for (final key in ['All', 'Active', 'Favorites', 'Completed'])
                        key: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            filterLabel(key),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ),
                    },
                    onValueChanged: (val) {
                      if (val != null) setState(() => _filter = val);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minSize: 34,
                  color: appleRed,
                  borderRadius: BorderRadius.circular(10),
                  onPressed: () => _showTodoEditor(),
                  child: const Icon(CupertinoIcons.plus, color: Colors.white, size: 18),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CupertinoActivityIndicator(radius: 14))
                : visibleTodos.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.isJapanese ? 'タスクがありません' : 'No Reminders',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
                                color: appleSecondaryLabel,
                              ),
                            ),
                            const SizedBox(height: 6),
                            CupertinoButton(
                              onPressed: () => _showTodoEditor(),
                              child: Text(
                                widget.isJapanese ? '+ タスクを追加' : '+ New To-Do',
                                style: const TextStyle(color: appleRed, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                        itemCount: 1,
                        itemBuilder: (context, _) {
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                for (int index = 0; index < visibleTodos.length; index++) ...[
                                  Builder(
                                    builder: (context) {
                                      final todo = visibleTodos[index];
                                      final dueLabel = todo.dueTimeOn && todo.dueTime != null
                                          ? '${DateFormat('MMM d').format(todo.dueDate)} • ${todo.dueTime}'
                                          : DateFormat('MMM d, yyyy').format(todo.dueDate);

                                      return InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () => _showTodoEditor(existing: todo),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 11,
                                          ),
                                          child: Row(
                                            children: [
                                              GestureDetector(
                                                onTap: () => _toggleComplete(todo),
                                                child: Icon(
                                                  todo.isComplete
                                                      ? CupertinoIcons.checkmark_circle_fill
                                                      : CupertinoIcons.circle,
                                                  size: 24,
                                                  color: todo.isComplete
                                                      ? appleRed
                                                      : const Color(0xFFC7C7CC),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      todo.title,
                                                      style: TextStyle(
                                                        fontSize: 15,
                                                        fontWeight: FontWeight.w600,
                                                        decoration: todo.isComplete
                                                            ? TextDecoration.lineThrough
                                                            : TextDecoration.none,
                                                        color: todo.isComplete
                                                            ? appleSecondaryLabel
                                                            : Colors.black,
                                                      ),
                                                    ),
                                                    if (todo.description.isNotEmpty) ...[
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        todo.description,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          color: appleSecondaryLabel,
                                                        ),
                                                      ),
                                                    ],
                                                    const SizedBox(height: 5),
                                                    Wrap(
                                                      spacing: 6,
                                                      runSpacing: 4,
                                                      crossAxisAlignment: WrapCrossAlignment.center,
                                                      children: [
                                                        Text(
                                                          dueLabel,
                                                          style: const TextStyle(
                                                            fontSize: 12,
                                                            color: appleSecondaryLabel,
                                                          ),
                                                        ),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 1.5,
                                                          ),
                                                          decoration: BoxDecoration(
                                                            color: _priorityColor(todo.priority)
                                                                .withOpacity(0.14),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Text(
                                                            todo.priority,
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.w700,
                                                              color: _priorityColor(todo.priority),
                                                            ),
                                                          ),
                                                        ),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 1.5,
                                                          ),
                                                          decoration: BoxDecoration(
                                                            color: _categoryColor(todo.category)
                                                                .withOpacity(0.14),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Text(
                                                            todo.category,
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.w600,
                                                              color: _categoryColor(todo.category),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              CupertinoButton(
                                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                                minSize: 32,
                                                onPressed: () => _toggleFavorite(todo),
                                                child: Icon(
                                                  todo.isFavorite
                                                      ? CupertinoIcons.star_fill
                                                      : CupertinoIcons.star,
                                                  size: 19,
                                                  color: todo.isFavorite
                                                      ? Colors.amber
                                                      : appleSecondaryLabel,
                                                ),
                                              ),
                                              CupertinoButton(
                                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                                minSize: 32,
                                                onPressed: () => _deleteTodo(todo),
                                                child: const Icon(
                                                  CupertinoIcons.trash,
                                                  size: 18,
                                                  color: appleRed,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  if (index < visibleTodos.length - 1)
                                    const Divider(
                                      height: 1,
                                      thickness: 0.5,
                                      indent: 50,
                                      color: appleHairline,
                                    ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}