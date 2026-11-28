// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

Future<bool> requestBrowserNotificationPermission() async {
  if (!html.Notification.supported) return false;
  if (html.Notification.permission == 'granted') return true;
  final permission = await html.Notification.requestPermission();
  return permission == 'granted';
}

void showBrowserNotification(String title, String body) {
  if (!html.Notification.supported) return;
  if (html.Notification.permission == 'granted') {
    html.Notification(title, body: body);
  }
}