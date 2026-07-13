import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.dns_outlined),
            title: Text('Server'),
            subtitle: Text('Self-hosted API connection — arrives with OPH-024'),
          ),
          ListTile(
            leading: Icon(Icons.notifications_outlined),
            title: Text('Notifications'),
            subtitle: Text(
              'Reminder & urgent alarm settings — arrives with Epic 07',
            ),
          ),
          AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationName: 'AllisWell',
            applicationVersion: '0.1.0',
            aboutBoxChildren: [
              Text(
                'Open-source, self-hosted productivity hub — '
                'tasks, projects, notes, calendar and reminders.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
