import 'package:flutter/material.dart';
import 'monitor_page.dart';
import 'map_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RoadQualityApp());
}

class RoadQualityApp extends StatelessWidget {
  const RoadQualityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Road Quality Monitor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const _RootPage(),
    );
  }
}

class _RootPage extends StatefulWidget {
  const _RootPage();

  @override
  State<_RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<_RootPage> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = [
    MonitorPage(),
    MapPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.sensors),
            label: 'Monitor',
          ),
          NavigationDestination(
            icon: Icon(Icons.map),
            label: 'Mappa',
          ),
        ],
      ),
    );
  }
}
