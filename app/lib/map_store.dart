import 'package:flutter/foundation.dart';
import 'road_map_service.dart';

class GeneratedMap {
  final DateTime timestamp;
  final int      anomalyCount;
  final RoadMapData data;

  const GeneratedMap({
    required this.timestamp,
    required this.anomalyCount,
    required this.data,
  });

  String get title {
    final d = timestamp;
    final date = '${d.day.toString().padLeft(2, '0')}/'
                 '${d.month.toString().padLeft(2, '0')}/'
                 '${d.year}';
    final time = '${d.hour.toString().padLeft(2, '0')}:'
                 '${d.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  String get subtitle =>
      '$anomalyCount anomali${anomalyCount == 1 ? 'a' : 'e'} rilevat${anomalyCount == 1 ? 'a' : 'e'}';
}

class MapStore extends ChangeNotifier {
  static final MapStore _instance = MapStore._();
  factory MapStore() => _instance;
  MapStore._();

  final List<GeneratedMap> _maps = [];

  List<GeneratedMap> get maps  => List.unmodifiable(_maps);
  int                get count => _maps.length;

  /// Inserisce in testa (più recente prima) e notifica i listener.
  void add(GeneratedMap m) {
    _maps.insert(0, m);
    notifyListeners();
  }
}
