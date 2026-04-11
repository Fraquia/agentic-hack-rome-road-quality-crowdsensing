import 'dart:async';
import 'package:flutter/material.dart';

import 'anomaly.dart';
import 'sensor_collector.dart';
import 'inference.dart';
import 'windowing.dart';
import 'gps_tagger.dart';

class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  final _store  = AnomalyStore();
  final _sensor = SensorCollector();
  final _voter  = WindowingVoter();
  final _tagger = GpsTagger();

  RoadInference? _inference;
  StreamSubscription<List<double>>? _windowSub;

  bool   _running   = false;
  String _lastLabel = '—';
  double _lastConf  = 0.0;

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
      await _tagger.start();

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
            }
          }
        } catch (e) {
          _showError('Errore inferenza: $e');
        }
      }, onError: (e) => _showError('Errore sensore: $e'));

      _sensor.start();
      if (mounted) setState(() => _running = true);
    } catch (e) {
      _showError('Errore avvio: $e');
    }
  }

  Future<void> _stop() async {
    _sensor.stop();
    _windowSub?.cancel();
    await _tagger.flush(_store.anomalies);
    _tagger.stop();
    _voter.reset();
    if (mounted) {
      setState(() {
        _running   = false;
        _lastLabel = '—';
        _lastConf  = 0.0;
      });
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

              // Contatore anomalie sessione
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
              const SizedBox(height: 48),

              // Bottone START / STOP
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
            ],
          ],
        ),
      ),
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
      color: _color.withOpacity(0.12),
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
                style: TextStyle(color: _color.withOpacity(0.7), fontSize: 16),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
