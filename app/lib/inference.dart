import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Risultato di una singola inferenza.
class RoadPrediction {
  final String label;
  final double confidence;
  const RoadPrediction(this.label, this.confidence);

  @override
  String toString() => '$label (${(confidence * 100).toStringAsFixed(1)}%)';
}

/// Gestisce il caricamento del modello TFLite e l'inferenza on-device.
class RoadInference {
  // IMPORTANTE: deve coincidere con WINDOW_SIZE in training/config.py
  static const int _windowSize = 200;

  static const List<String> _classes = [
    'smooth',
    'pothole',
    'asphalt_bump',
    'metal_bump',
    'worn_road',
  ];

  final Interpreter _interpreter;
  final double _mean;
  final double _std;

  RoadInference._(this._interpreter, this._mean, this._std);

  static Future<RoadInference> loadFromAssets({
    String modelAsset  = 'assets/model.tflite',
    String scalerAsset = 'assets/scaler.json',
  }) async {
    final interpreter = await Interpreter.fromAsset(modelAsset);

    final scalerRaw  = await rootBundle.loadString(scalerAsset);
    final scalerJson = json.decode(scalerRaw) as Map<String, dynamic>;
    final mean = (scalerJson['mean'] as List).first.toDouble();
    final std  = (scalerJson['std']  as List).first.toDouble();

    return RoadInference._(interpreter, mean, std);
  }

  RoadPrediction predict(List<double> window) {
    assert(window.length == _windowSize,
        'Finestra deve avere $_windowSize campioni (trovati ${window.length})');

    final normalised = window.map((v) => (v - _mean) / _std).toList();
    final input  = [normalised.map((v) => [v]).toList()];
    final output = List.generate(1, (_) => List<double>.filled(5, 0.0));

    _interpreter.run(input, output);

    final probs  = output[0];
    final maxIdx = probs.indexOf(probs.reduce(max));
    return RoadPrediction(_classes[maxIdx], probs[maxIdx]);
  }

  void dispose() => _interpreter.close();
}
