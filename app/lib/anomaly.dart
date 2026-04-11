/// Modello dati per un'anomalia stradale rilevata.
class Anomaly {
  final double lat;
  final double lon;
  final String roadClass;
  final double confidence;
  final DateTime timestamp;

  const Anomaly({
    required this.lat,
    required this.lon,
    required this.roadClass,
    required this.confidence,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'lat':        lat,
    'lon':        lon,
    'class':      roadClass,
    'confidence': confidence,
    'timestamp':  timestamp.toIso8601String(),
  };
}

/// Singleton condiviso tra MonitorPage e MapPage.
class AnomalyStore {
  static final AnomalyStore _instance = AnomalyStore._();
  factory AnomalyStore() => _instance;
  AnomalyStore._();

  final List<Anomaly> _anomalies = [];

  List<Anomaly> get anomalies => List.unmodifiable(_anomalies);
  int get count => _anomalies.length;

  void add(Anomaly a) => _anomalies.add(a);
  void clear() => _anomalies.clear();
}
