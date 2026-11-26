import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:calendar_frontend/initialSetupPage.dart';

class SettingsPage extends StatefulWidget {
  final String backendBaseUrl;
  final String authToken;
  final UserAppSettings currentSettings;
  final Future<void> Function(UserAppSettings updatedSettings) onSettingsChanged;
  final Future<void> Function() onLogout;

  const SettingsPage({
    super.key,
    required this.backendBaseUrl,
    required this.authToken,
    required this.currentSettings,
    required this.onSettingsChanged,
    required this.onLogout,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late bool _todoEnabled;
  late bool _payrollEnabled;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _todoEnabled = widget.currentSettings.enableTodoList;
    _payrollEnabled = widget.currentSettings.enablePayroll;
  }

  Future<void> _updateModuleToggle({
    required bool nextTodo,
    required bool nextPayroll,
  }) async {
    setState(() {
      _todoEnabled = nextTodo;
      _payrollEnabled = nextPayroll;
      _isSaving = true;
    });

    final updated = widget.currentSettings.copyWith(
      enableTodoList: nextTodo,
      enablePayroll: nextPayroll,
    );

    await updated.saveToCache();

    try {
      final response = await http.put(
        Uri.parse('${widget.backendBaseUrl}/api/user/settings'),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'timezone': updated.timezone,
          'language': updated.language,
          'enableTodoList': nextTodo,
          'enablePayroll': nextPayroll,
          'convertExistingEvents': false,
        }),
      );
      if(response.statusCode == 200 && response.body.isNotEmpty){
        final serverSettings = UserAppSettings.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
        await serverSettings.saveToCache();
        await widget.onSettingsChanged(serverSettings);
        if (mounted) setState(() => _isSaving = false);
        return;
      }
    } catch (e) {
      debugPrint('Settings sync warning: $e');
    }

    await widget.onSettingsChanged(updated);

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Modules',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.check_circle_outline),
                title: const Text('To-Do List'),
                subtitle: const Text('Show To-Do List tab & sync due tasks with calendar'),
                value: _todoEnabled,
                onChanged: _isSaving
                    ? null
                    : (val) => _updateModuleToggle(
                          nextTodo: val,
                          nextPayroll: _payrollEnabled,
                        ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.payments_outlined),
                title: const Text('Payroll'),
                subtitle: const Text('Show Payroll tab for shift & income tracking'),
                value: _payrollEnabled,
                onChanged: _isSaving
                    ? null
                    : (val) => _updateModuleToggle(
                          nextTodo: _todoEnabled,
                          nextPayroll: val,
                        ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Account',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Log Out'),
            onTap: () => widget.onLogout(),
          ),
        ),
      ],
    );
  }
}