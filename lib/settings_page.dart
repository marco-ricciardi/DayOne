import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'notification_service.dart';
import 'utils/date_utils.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, dynamic>? _notificationDebugInfo;
  bool _loadingDebugInfo = false;

  Future<void> _refreshDebugInfo() async {
    setState(() {
      _loadingDebugInfo = true;
    });

    final info = await NotificationService().getNotificationDebugInfo();

    if (mounted) {
      setState(() {
        _notificationDebugInfo = info;
        _loadingDebugInfo = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // Delay to ensure method channel is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshDebugInfo();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const ListTile(
            title: Text('Appearance'),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('System'),
            value: ThemeMode.system,
            groupValue: appState.themeMode,
            onChanged: appState.setThemeMode,
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Light'),
            value: ThemeMode.light,
            groupValue: appState.themeMode,
            onChanged: appState.setThemeMode,
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Dark'),
            value: ThemeMode.dark,
            groupValue: appState.themeMode,
            onChanged: appState.setThemeMode,
          ),
          const Divider(),
          const ListTile(
            title: Text('Notifications'),
          ),
          SwitchListTile(
            title: const Text('Daily Photo Reminder'),
            subtitle: Text(
              appState.notificationsEnabled
                  ? 'Enabled at ${_formatTime(appState.notificationTime)}'
                  : 'Disabled',
            ),
            value: appState.notificationsEnabled,
            onChanged: (value) async {
              if (value) {
                // Show time picker when enabling notifications
                final TimeOfDay? picked = await showTimePicker(
                  context: context,
                  initialTime: appState.notificationTime,
                );

                if (picked != null) {
                  await appState.setNotificationTime(picked, true);
                  await NotificationService().scheduleNativeDailyNotification(picked);
                  _refreshDebugInfo();

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Daily reminder set for ${_formatTime(picked)}',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              } else {
                // Disable notifications
                await appState.toggleNotifications(false);
                await NotificationService().cancelNativeDailyNotification();
                _refreshDebugInfo();

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Daily reminder disabled'),
                    ),
                  );
                }
              }
            },
          ),
          if (appState.notificationsEnabled)
            ListTile(
              leading: const Icon(Icons.access_time),
              title: const Text('Change Reminder Time'),
              subtitle: Text(_formatTime(appState.notificationTime)),
              onTap: () async {
                final TimeOfDay? picked = await showTimePicker(
                  context: context,
                  initialTime: appState.notificationTime,
                );

                if (picked != null) {
                  await appState.setNotificationTime(picked, true);
                  await NotificationService().scheduleNativeDailyNotification(picked);
                  _refreshDebugInfo();

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Reminder time updated to ${_formatTime(picked)}',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              },
            ),
          if (appState.notificationsEnabled)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'You can snooze notifications by expanding the notification and selecting a snooze duration (15 min, 30 min, or 1 hour).',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ),
          const Divider(),
          ExpansionTile(
            leading: const Icon(Icons.developer_mode),
            title: const Text('Developer Options'),
            children: [
              ListTile(
                leading: const Icon(Icons.notifications_active),
                title: const Text('Send Test Notification'),
                subtitle: const Text('Trigger notification immediately'),
                onTap: () async {
                  await NotificationService().sendTestNotification();

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Test notification sent!'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
              const Divider(indent: 16, endIndent: 16),
              ListTile(
                title: const Text('Notification Debug Info'),
                trailing: _loadingDebugInfo
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _refreshDebugInfo,
                      ),
              ),
              if (_notificationDebugInfo != null) ...[
                _buildDebugInfoTile(
                  'Status',
                  _notificationDebugInfo!['enabled'] == true
                      ? 'Enabled'
                      : 'Disabled',
                  _notificationDebugInfo!['enabled'] == true
                      ? Colors.green
                      : Colors.red,
                ),
                if (_notificationDebugInfo!['enabled'] == true) ...[
                  _buildDebugInfoTile(
                    'Scheduled Time',
                    '${_notificationDebugInfo!['hour']}:${_notificationDebugInfo!['minute'].toString().padLeft(2, '0')}',
                    null,
                  ),
                  _buildDebugInfoTile(
                    'Alarm Registered',
                    _notificationDebugInfo!['alarmScheduled'] == true
                        ? 'Yes'
                        : 'No',
                    _notificationDebugInfo!['alarmScheduled'] == true
                        ? Colors.green
                        : Colors.red,
                  ),
                  _buildDebugInfoTile(
                    'Next Trigger',
                    _notificationDebugInfo!['nextTriggerTime'] ?? 'Unknown',
                    null,
                  ),
                  _buildDebugInfoTile(
                    'Exact Alarms Allowed',
                    _notificationDebugInfo!['canScheduleExactAlarms'] == true
                        ? 'Yes'
                        : 'No',
                    _notificationDebugInfo!['canScheduleExactAlarms'] == true
                        ? Colors.green
                        : Colors.orange,
                  ),
                ],
                _buildDebugInfoTile(
                  'Current Time',
                  _notificationDebugInfo!['currentTime'] ?? 'Unknown',
                  null,
                ),
                if (_notificationDebugInfo!['error'] != null)
                  _buildDebugInfoTile(
                    'Error',
                    _notificationDebugInfo!['error'],
                    Colors.red,
                  ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(TimeOfDay time) => AppDateUtils.formatTime(time);

  Widget _buildDebugInfoTile(String label, String value, Color? valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: valueColor,
              ),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
