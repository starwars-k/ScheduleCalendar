class TodoItem {
  final int? id;
  final String title;
  final String description;
  final String category;
  final String priority; // 'HIGH', 'MEDIUM', 'LOW'
  final bool isFavorite;
  final bool isComplete;
  final bool dueTimeOn;
  final DateTime dueDate;
  final String? dueTime; // 'HH:mm' when dueTimeOn == true
  final DateTime? reminder;
  final String timezone;
  final int? linkedEventId;

  TodoItem({
    this.id,
    required this.title,
    this.description = '',
    this.category = 'Task',
    this.priority = 'MEDIUM',
    this.isFavorite = false,
    this.isComplete = false,
    this.dueTimeOn = false,
    required this.dueDate,
    this.dueTime,
    this.reminder,
    this.timezone = 'UTC',
    this.linkedEventId,
  });

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    DateTime parsedDueDate = DateTime.now();
    if (json['dueDate'] != null && json['dueDate'].toString().isNotEmpty) {
      parsedDueDate = DateTime.tryParse(json['dueDate'].toString()) ?? DateTime.now();
    } else if (json['dueDateTimeUtc'] != null) {
      parsedDueDate = DateTime.tryParse(json['dueDateTimeUtc'].toString()) ?? DateTime.now();
    }

    return TodoItem(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? ''),
      title: json['title']?.toString() ?? 'Untitled Task',
      description: json['description']?.toString() ?? '',
      category: json['category']?.toString() ?? 'Task',
      priority: json['priority']?.toString().toUpperCase() ?? 'MEDIUM',
      isFavorite: json['isFavorite'] == true,
      isComplete: (json['isComplete'] ?? json['complete']) == true,
      dueTimeOn: json['dueTimeOn'] == true,
      dueDate: DateTime(parsedDueDate.year, parsedDueDate.month, parsedDueDate.day),
      dueTime: json['dueTime']?.toString(),
      reminder: json['reminder'] != null && json['reminder'].toString().isNotEmpty
          ? DateTime.tryParse(json['reminder'].toString())
          : null,
      timezone: json['timezone']?.toString() ?? 'UTC',
      linkedEventId: json['linkedEventId'] is int
          ? json['linkedEventId']
          : int.tryParse(json['linkedEventId']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String formatIso(DateTime dt) {
      final base = dt.toIso8601String().split('.')[0];
      final ms = dt.millisecond.toString().padLeft(3, '0');
      return '$base.$ms';
    }

    return {
      'title': title,
      'description': description,
      'category': category,
      'priority': priority,
      'isFavorite': isFavorite,
      'isComplete': isComplete,
      'dueTimeOn': dueTimeOn,
      'dueDate': '${dueDate.year}-${twoDigits(dueDate.month)}-${twoDigits(dueDate.day)}',
      'dueTime': dueTimeOn ? dueTime : null,
      'reminder': reminder != null ? formatIso(reminder!) : null,
    };
  }
}