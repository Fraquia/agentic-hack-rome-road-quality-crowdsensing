import 'dart:async';
import 'package:flutter/material.dart';

import 'anomaly.dart';
import 'sensor_collector.dart';
import 'inference.dart';
import 'windowing.dart';
import 'gps_tagger.dart';
import 'road_map_service.dart';
import 'map_store.dart';

class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  final _store      = AnomalyStore();
  final _mapStore   = MapStore();
  final _mapService = RoadMapService();
  final _sensor     = SensorCollector();
  final _voter      = WindowingVoter();
  final _tagger     = GpsTagger();

  RoadInference? _inference;
  StreamSubscription<List<double>>? _windowSub;
  StreamSubscription<GpsStatus>?    _statusSub;

  // Anomalie confermate prima che il GPS fosse pronto.
  final _pending = <({String roadClass, double confidence, DateTime timestamp})>[];

  bool      _running       = false;
  bool      _generatingMap = false;
  String    _lastLabel     = '—';
  double    _lastConf      = 0.0;
  GpsStatus _gpsStatus     = GpsStatus.unavailable;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      final inference = await RoadInference.loadFromAssets();
      setState(() => _inference = inference);
    } catch (e) {
      _showError('Impossibile caricare il modello: $e\n'
          'Assicurati che model.tflite e scaler.json siano in app/assets/');
    }
  }

  Future<void> _start() async {
    if (_inference == null) {
      _showError('Modello non ancora caricato.');
      return;
    }
    try {
      // Iscriversi allo stream GPS prima di start() per non perdere nessun evento.
      _statusSub = _tagger.statusStream.listen((status) {
        if (mounted) setState(() => _gpsStatus = status);
        if (status == GpsStatus.ready) _drainPending();
      });

      await _tagger.start();
      // Sincronizzare lo stato attuale in caso di aggiornamento sincrono.
      if (mounted) setState(() => _gpsStatus = _tagger.status);

      _windowSub = _sensor.windows.listen((window) {
        try {
          final prediction = _inference!.predict(window);
          final confirmed  = _voter.confirm(prediction.label);

          if (mounted) {
            setState(() {
              _lastLabel = prediction.label;
              _lastConf  = prediction.confidence;
            });
          }

          if (confirmed != null) {
            final pos = _tagger.lastPosition;
            if (pos != null) {
              _store.add(Anomaly(
                lat:        pos.latitude,
                lon:        pos.longitude,
                roadClass:  confirmed,
                confidence: prediction.confidence,
                timestamp:  DateTime.now(),
              ));
              if (mounted) setState(() {});
            } else {
              // GPS non ancora pronto: accoda per risoluzione appena disponibile.
              _pending.add((
                roadClass:  confirmed,
                confidence: prediction.confidence,
                timestamp:  DateTime.now(),
              ));
            }
          }
        } catch (e) {
          _showError('Errore inferenza: $e');
        }
      }, onError: (e) => _showError('Errore sensore: $e'));

      _sensor.start();
      if (mounted) setState(() => _running = true);
    } catch (e) {
      _statusSub?.cancel();
      _showError('Errore avvio: $e');
    }
  }

  /// Risolve le anomalie accumulate prima del primo fix GPS.
  void _drainPending() {
    final pos = _tagger.lastPosition;
    if (pos == null || _pending.isEmpty) return;
    for (final p in _pending) {
      _store.add(Anomaly(
        lat:        pos.latitude,
        lon:        pos.longitude,
        roadClass:  p.roadClass,
        confidence: p.confidence,
        timestamp:  p.timestamp,
      ));
    }
    _pending.clear();
    if (mounted) setState(() {});
  }

  Future<void> _stop() async {
    _sensor.stop();
    _windowSub?.cancel();
    _statusSub?.cancel();
    _pending.clear();
    await _tagger.flush(_store.anomalies);
    _tagger.stop();
    _voter.reset();
    if (mounted) {
      setState(() {
        _running   = false;
        _gpsStatus = GpsStatus.unavailable;
        _lastLabel = '—';
        _lastConf  = 0.0;
      });
    }
  }

  Future<void> _generateMap() async {
    if (_store.count == 0) {
      _showError('Nessuna anomalia raccolta. Avvia il monitoraggio prima.');
      return;
    }
    setState(() => _generatingMap = true);
    try {
      final snapshot    = List<Anomaly>.from(_store.anomalies);
      final tracePts    = _tagger.tracePoints;
      final traceTs     = _tagger.traceTimestamps;
      final data = await _mapService.build(snapshot, tracePts, traceTs);
      _mapStore.add(GeneratedMap(
        timestamp:    DateTime.now(),
        anomalyCount: snapshot.length,
        data:         data,
      ));
      if (mounted) {
        setState(() => _generatingMap = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mappa salvata! Aprila dalla tab Mappe.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _generatingMap = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore generazione mappa: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    _stop();
    _tagger.dispose();
    _sensor.dispose();
    _inference?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modelReady = _inference != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Road Quality Monitor'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!modelReady)
              const Column(children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Caricamento modello…'),
              ])
            else ...[
              _StatusCard(label: _lastLabel, confidence: _lastConf),
              const SizedBox(height: 32),

              Text(
                'Anomalie rilevate: ${_store.count}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                _running ? 'Monitoraggio attivo' : 'In attesa',
                style: TextStyle(
                  color: _running ? Colors.green : Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              _GpsStatusRow(status: _gpsStatus, pendingCount: _pending.length),
              const SizedBox(height: 48),

              FilledButton.icon(
                onPressed: _running ? _stop : _start,
                icon: Icon(_running ? Icons.stop : Icons.play_arrow),
                label: Text(
                  _running ? 'STOP' : 'AVVIO',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(200, 64),
                  backgroundColor: _running ? Colors.red : Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: (_generatingMap || _store.count == 0)
                    ? null
                    : _generateMap,
                icon: _generatingMap
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.map_outlined),
                label: Text(
                  _generatingMap ? 'Generazione…' : 'Genera Mappa',
                  style: const TextStyle(fontSize: 15),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(200, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GpsStatusRow extends StatelessWidget {
  final GpsStatus status;
  final int       pendingCount;

  const _GpsStatusRow({required this.status, required this.pendingCount});

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (status) {
      GpsStatus.unavailable => (Icons.gps_off,       Colors.grey,   'GPS non disponibile'),
      GpsStatus.acquiring   => (Icons.gps_not_fixed, Colors.orange, 'Acquisizione GPS…'),
      GpsStatus.ready       => (Icons.gps_fixed,     Colors.green,  'GPS attivo'),
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: color, fontSize: 13)),
        if (pendingCount > 0) ...[
          const SizedBox(width: 8),
          Text(
            '($pendingCount in coda)',
            style: const TextStyle(color: Colors.orange, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String label;
  final double confidence;

  const _StatusCard({required this.label, required this.confidence});

  Color get _color {
    switch (label) {
      case 'smooth':       return Colors.green;
      case 'pothole':      return Colors.red;
      case 'asphalt_bump': return Colors.orange;
      case 'metal_bump':   return Colors.deepOrange;
      case 'worn_road':    return Colors.amber;
      default:             return Colors.grey;
    }
  }

  String get _emoji {
    switch (label) {
      case 'smooth':       return '✅';
      case 'pothole':      return '🕳️';
      case 'asphalt_bump': return '⚠️';
      case 'metal_bump':   return '🔩';
      case 'worn_road':    return '🟡';
      default:             return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      color: _color.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
        child: Column(
          children: [
            Text(_emoji, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: _color,
              ),
            ),
            if (confidence > 0) ...[
              const SizedBox(height: 6),
              Text(
                '${(confidence * 100).toStringAsFixed(1)}%',
                style: TextStyle(color: _color.withValues(alpha: 0.7), fontSize: 16),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
