import 'package:flutter/material.dart';

import 'map_store.dart';
import 'map_detail_page.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _store = MapStore();

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mappe'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _store.count == 0 ? _empty() : _list(),
    );
  }

  Widget _empty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map_outlined, size: 72, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'Nessuna mappa generata.',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            'Raccogli anomalie e premi "Genera Mappa".',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _list() {
    final maps = _store.maps;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: maps.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final m = maps[i];
        return ListTile(
          leading: const CircleAvatar(
            backgroundColor: Colors.deepOrangeAccent,
            child: Icon(Icons.map, color: Colors.white, size: 20),
          ),
          title: Text(m.title),
          subtitle: Text(m.subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => MapDetailPage(map: m)),
          ),
        );
      },
    );
  }
}
