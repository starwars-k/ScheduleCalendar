import 'dart:convert';

import 'package:flutter/cupertino.dart';
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
  static const Map<String, String> _languageOptions = {
    'en' : 'English',
    'ja' : '日本語 (Japanese)',
  };
  late bool _todoEnabled;
  late bool _payrollEnabled;
  late String _selectedLanguage;
  bool _isSaving = false;

  bool get _isJapanese => _selectedLanguage == 'ja';

  @override
  void initState() {
    super.initState();
    _todoEnabled = widget.currentSettings.enableTodoList;
    _payrollEnabled = widget.currentSettings.enablePayroll;
    _selectedLanguage = _languageOptions.containsKey(widget.currentSettings.language)
      ? widget.currentSettings.language
      : 'en';
  }

  Future<void> _updateSettings({
    bool? nextTodo,
    bool? nextPayroll,
    String? nextLanguage,
  }) async {
    final resolvedTodo = nextTodo ?? _todoEnabled;
    final resolvedPayroll = nextPayroll ?? _payrollEnabled;
    final resolvedLanguage = nextLanguage ?? _selectedLanguage;
    setState(() {
      _todoEnabled = resolvedTodo;
      _payrollEnabled = resolvedPayroll;
      _selectedLanguage = resolvedLanguage;
      _isSaving = true;
    });

    final updated = widget.currentSettings.copyWith(
      language: resolvedLanguage,
      enableTodoList: resolvedTodo,
      enablePayroll: resolvedPayroll,
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
          'language': resolvedLanguage,
          'enableTodoList': resolvedTodo,
          'enablePayroll': resolvedPayroll,
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

  Widget _buildComingSoonBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _isJapanese ? '順次追加予定' : 'Coming Soon',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.amber.shade900,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color appleRed = Color(0xFFFF3B30);
    const Color appleGroupedBg = Color(0xFFF2F2F7);
    const Color appleHairline = Color(0xFFE5E5EA);
    const Color appleSecondaryLabel = Color(0xFF8E8E93);

    Widget buildSectionHeader(String title) {
      return Padding(
        padding: const EdgeInsets.only(left: 16, bottom: 6),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: appleSecondaryLabel,
          ),
        ),
      );
    }

    return Container(
      color: appleGroupedBg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          buildSectionHeader(_isJapanese ? '言語 (LANGUAGE)' : 'LANGUAGE'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(CupertinoIcons.globe, color: appleRed, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isJapanese ? '表示言語' : 'App Language',
                    style: const TextStyle(fontSize: 15, color: Colors.black),
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedLanguage,
                    icon: const Icon(
                      CupertinoIcons.chevron_up_chevron_down,
                      size: 16,
                      color: appleSecondaryLabel,
                    ),
                    style: const TextStyle(fontSize: 15, color: appleSecondaryLabel),
                    items: _languageOptions.entries.map((entry) {
                      return DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(entry.value),
                      );
                    }).toList(),
                    onChanged: _isSaving
                        ? null
                        : (String? newValue) {
                            if (newValue != null && newValue != _selectedLanguage) {
                              _updateSettings(nextLanguage: newValue);
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          buildSectionHeader(_isJapanese ? 'モジュール' : 'MODULES'),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.checkmark_circle, color: appleRed, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isJapanese ? 'To-Do リスト' : 'To-Do List',
                              style: const TextStyle(fontSize: 15, color: Colors.black),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isJapanese
                                  ? 'To-Do タブを表示し、期限タスクをカレンダーと同期'
                                  : 'Show To-Do tab & sync due tasks with calendar',
                              style: const TextStyle(fontSize: 12, color: appleSecondaryLabel),
                            ),
                          ],
                        ),
                      ),
                      CupertinoSwitch(
                        value: _todoEnabled,
                        activeTrackColor: appleRed,
                        onChanged: _isSaving
                            ? null
                            : (val) => _updateSettings(
                                  nextTodo: val,
                                  nextPayroll: _payrollEnabled,
                                ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 0.5, indent: 50, color: appleHairline),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.money_dollar_circle,
                        color: appleSecondaryLabel,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  _isJapanese ? '給与計算 (Payroll)' : 'Payroll',
                                  style: const TextStyle(fontSize: 15, color: Colors.black),
                                ),
                                _buildComingSoonBadge(),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isJapanese
                                  ? 'シフト・収入管理用の給与タブを表示します'
                                  : 'Show Payroll tab for shift & income tracking',
                              style: const TextStyle(fontSize: 12, color: appleSecondaryLabel),
                            ),
                          ],
                        ),
                      ),
                      const CupertinoSwitch(value: false, onChanged: null),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          buildSectionHeader(_isJapanese ? 'アカウント' : 'ACCOUNT'),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => widget.onLogout(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(
                  children: [
                    const Icon(Icons.logout_rounded, color: appleRed, size: 21),
                    const SizedBox(width: 12),
                    Text(
                      _isJapanese ? 'ログアウト' : 'Log Out',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: appleRed,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}