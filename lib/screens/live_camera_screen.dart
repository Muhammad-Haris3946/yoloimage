// main.dart
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_detection_new/widgets/custom_appbar.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// --------- Tuned for smoother live preview ----------
const int kInputSize = 640;             // YOLO input side
const double kScoreThreshold = 0.30;
const double kIouThreshold = 0.45;
const int kThrottleMs = 150;            // small throttle for smoother UI
const int kProcessEveryNFrame = 3;      // skip frames to reduce load
const int kTopK = 100;                  // prune before NMS for perf

class Detection {
  /// Rect is in MODEL SPACE (640×640). Painter maps to the preview.
  final Rect rect;
  final String label;
  final double score;
  Detection({required this.rect, required this.label, required this.score});
}

class LiveCameraScreen extends StatefulWidget {
  const LiveCameraScreen({super.key});
  @override
  State<LiveCameraScreen> createState() => _LiveCameraScreenState();
}

class _LiveCameraScreenState extends State<LiveCameraScreen> {
  Interpreter? _interpreter;
  List<String> _labels = [];

  // Output layout
  bool _singleOutput = true;
  List<int> _outShape0 = [1, 8400, 85];
  int _numAnchors = 8400;
  int _outChannels = 85;

  // Camera
  CameraController? _camera;
  Size? _previewSize; // not strictly needed for drawing, but kept for info
  bool _cameraOn = false;
  bool _busy = false;
  int _lastMs = 0;
  int _frameTick = 0;

  // Model input type (robust across tflite_flutter versions)
  late String _inTypeName; // like "TfLiteType.float32" or "TfLiteType.uint8"
  bool get _isFloatInput => _inTypeName.toLowerCase().contains('float');
  bool get _isUint8Input => _inTypeName.toLowerCase().contains('uint8');

  // Linear input buffers
  late Float32List _inF32; // [0..1]
  late Uint8List _inU8;    // [0..255]

  // Reusable nested input [1][H][W][3] (num to hold either double or int)
  late List<List<List<List<num>>>> _input4D;

  // Outputs
  late Object _singleOut; // single-head models
  late List<List<List<double>>> _boxes3;
  late List<List<double>> _scores3;
  late List<List<double>> _classes3;

  // Detections (model space)
  List<Detection> _detections = [];

  @override
  void initState() {
    super.initState();
    // Pre-allocate once (avoid per-frame allocations)
    _inF32 = Float32List(kInputSize * kInputSize * 3);
    _inU8 = Uint8List(kInputSize * kInputSize * 3);
    _input4D = List.generate(
      1,
          (_) => List.generate(
        kInputSize,
            (_) => List.generate(kInputSize, (_) => List<num>.filled(3, 0)),
      ),
    );
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      final opts = InterpreterOptions()
        ..threads = 4
        ..useNnApiForAndroid = true; // often faster on device

      _interpreter = await Interpreter.fromAsset(
        'assets/models/YOLOv11-Detection.tflite',
        options: opts,
      );

      // Labels
      final labelsTxt =
      await rootBundle.loadString('assets/models/yololabels.txt');
      _labels = labelsTxt
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      // Input type
      _inTypeName = _interpreter!.getInputTensors()[0].type.toString();
      debugPrint('Model input type: $_inTypeName');

      // Outputs
      final outs = _interpreter!.getOutputTensors();
      debugPrint('Output count: ${outs.length}');
      for (final t in outs) {
        debugPrint('  shape=${t.shape} type=${t.type}');
      }

      if (outs.length >= 3) {
        _singleOutput = false;
        final t0 = outs[0].shape;
        _numAnchors = (t0.length == 3) ? t0[1] : 8400;
        _boxes3 =
            List.generate(1, (_) => List.generate(_numAnchors, (_) => List.filled(4, 0.0)));
        _scores3 = List.generate(1, (_) => List.filled(_numAnchors, 0.0));
        _classes3 = List.generate(1, (_) => List.filled(_numAnchors, 0.0));
      } else {
        _singleOutput = true;
        _outShape0 = outs[0].shape;
        if (_outShape0.length == 3) {
          final d1 = _outShape0[1], d2 = _outShape0[2];
          if (d1 >= d2) {
            _numAnchors = d1;
            _outChannels = d2;
          } else {
            _numAnchors = d2;
            _outChannels = d1;
          }
        } else {
          _numAnchors = 8400;
          _outChannels = _labels.length + 5;
        }
        _singleOut = List.generate(
          1,
              (_) => List.generate(_numAnchors, (_) => List.filled(_outChannels, 0.0)),
        );
      }

      setState(() {});
    } catch (e, st) {
      debugPrint('Model load failed: $e\n$st');
    }
  }

  Future<void> _startCamera() async {
    if (_cameraOn || _interpreter == null) return;

    final cams = await availableCameras();
    if (cams.isEmpty) {
      debugPrint('No cameras on device');
      return;
    }

    final cam = cams.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cams.first,
    );

    // lower resolution => much smoother pipeline
    _camera = CameraController(
      cam,
      ResolutionPreset.low, // was medium/high
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _camera!.initialize();
    _previewSize = _camera!.value.previewSize;

    _cameraOn = true;
    setState(() {});

    await _camera!.startImageStream(_onFrame);
  }

  Future<void> _stopCamera() async {
    _cameraOn = false;
    try {
      if (_camera?.value.isStreamingImages == true) {
        await _camera?.stopImageStream();
      }
      await _camera?.dispose();
    } catch (_) {}
    _camera = null;
    _previewSize = null;
    _detections = [];
    setState(() {});
  }

  void _onFrame(CameraImage img) {
    if (!_cameraOn || _interpreter == null) return;

    // Skip frames for perf
    _frameTick = (_frameTick + 1) % kProcessEveryNFrame;
    if (_frameTick != 0) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMs < kThrottleMs || _busy) return;
    _lastMs = now;
    _busy = true;

    Future(() async {
      try {
        _letterboxYuv(img);             // fills _inF32 or _inU8
        _updateNestedInputFromLinear(); // updates _input4D in place

        if (_singleOutput) {
          _interpreter!.runForMultipleInputs([_input4D], {0: _singleOut});
          final raw = _parseSingleOutput(_singleOut);
          final kept = _nmsRaw(_topK(raw, kTopK));
          final dets = kept
              .map((r) => Detection(
            rect: r.rect,
            label: (r.cls >= 0 && r.cls < _labels.length)
                ? _labels[r.cls]
                : 'obj',
            score: r.score,
          ))
              .toList();
          if (mounted) setState(() => _detections = dets);
        } else {
          _interpreter!.runForMultipleInputs([_input4D], {
            0: _boxes3,
            1: _scores3,
            2: _classes3,
          });
          final raw = _parseThreeOutput();
          final kept = _nmsRaw(_topK(raw, kTopK));
          final dets = kept
              .map((r) => Detection(
            rect: r.rect,
            label: (r.cls >= 0 && r.cls < _labels.length)
                ? _labels[r.cls]
                : 'obj',
            score: r.score,
          ))
              .toList();
          if (mounted) setState(() => _detections = dets);
        }
      } catch (e, st) {
        debugPrint('Frame error: $e\n$st');
      } finally {
        _busy = false;
      }
    });
  }

  /// Letterbox YUV420 -> linear buffers:
  /// - if model input is float, fill _inF32 with [0..1]
  /// - if model input is uint8, fill _inU8  with [0..255]
  void _letterboxYuv(CameraImage img) {
    final srcW = img.width, srcH = img.height;
    final y = img.planes[0], u = img.planes[1], v = img.planes[2];
    final yB = y.bytes, uB = u.bytes, vB = v.bytes;
    final yS = y.bytesPerRow, uS = u.bytesPerRow, vS = v.bytesPerRow;
    final uvPix = u.bytesPerPixel ?? 1;

    final scale = min(kInputSize / srcW, kInputSize / srcH);
    final newW = srcW * scale, newH = srcH * scale;
    final padX = (kInputSize - newW) / 2.0, padY = (kInputSize - newH) / 2.0;

    if (_isFloatInput) {
      int idx = 0;
      for (int yy = 0; yy < kInputSize; yy++) {
        final fy = (yy - padY) / scale;
        if (fy < 0 || fy >= srcH) {
          for (int xx = 0; xx < kInputSize; xx++) {
            _inF32[idx++] = 0; _inF32[idx++] = 0; _inF32[idx++] = 0;
          }
          continue;
        }
        final sy = fy.toInt();
        final uvRow = sy >> 1;
        for (int xx = 0; xx < kInputSize; xx++) {
          final fx = (xx - padX) / scale;
          if (fx < 0 || fx >= srcW) {
            _inF32[idx++] = 0; _inF32[idx++] = 0; _inF32[idx++] = 0;
            continue;
          }
          final sx = fx.toInt();
          final yIndex = sy * yS + sx;
          final uvCol = (sx >> 1) * uvPix;
          final uIndex = uvRow * uS + uvCol;
          final vIndex = uvRow * vS + uvCol;

          final Y = yB[yIndex].toInt();
          final U = uB[uIndex].toInt() - 128;
          final Vv = vB[vIndex].toInt() - 128;

          double r = Y + 1.402 * Vv;
          double g = Y - 0.344136 * U - 0.714136 * Vv;
          double b = Y + 1.772 * U;

          r = r.clamp(0, 255);
          g = g.clamp(0, 255);
          b = b.clamp(0, 255);

          _inF32[idx++] = r / 255.0;
          _inF32[idx++] = g / 255.0;
          _inF32[idx++] = b / 255.0;
        }
      }
    } else if (_isUint8Input) {
      int idx = 0;
      for (int yy = 0; yy < kInputSize; yy++) {
        final fy = (yy - padY) / scale;
        if (fy < 0 || fy >= srcH) {
          for (int xx = 0; xx < kInputSize; xx++) {
            _inU8[idx++] = 0; _inU8[idx++] = 0; _inU8[idx++] = 0;
          }
          continue;
        }
        final sy = fy.toInt();
        final uvRow = sy >> 1;
        for (int xx = 0; xx < kInputSize; xx++) {
          final fx = (xx - padX) / scale;
          if (fx < 0 || fx >= srcW) {
            _inU8[idx++] = 0; _inU8[idx++] = 0; _inU8[idx++] = 0;
            continue;
          }
          final sx = fx.toInt();
          final yIndex = sy * yS + sx;
          final uvCol = (sx >> 1) * uvPix;
          final uIndex = uvRow * uS + uvCol;
          final vIndex = uvRow * vS + uvCol;

          final Y = yB[yIndex].toInt();
          final U = uB[uIndex].toInt() - 128;
          final Vv = vB[vIndex].toInt() - 128;

          double r = Y + 1.402 * Vv;
          double g = Y - 0.344136 * U - 0.714136 * Vv;
          double b = Y + 1.772 * U;

          r = r.clamp(0, 255);
          g = g.clamp(0, 255);
          b = b.clamp(0, 255);

          _inU8[idx++] = r.toInt();
          _inU8[idx++] = g.toInt();
          _inU8[idx++] = b.toInt();
        }
      }
    } else {
      // Fallback as float
      _inTypeName = 'float32';
      _letterboxYuv(img);
    }
  }

  /// Update pre-allocated nested input from linear buffer (in place).
  void _updateNestedInputFromLinear() {
    int base = 0;
    if (_isFloatInput) {
      for (int y = 0; y < kInputSize; y++) {
        final row = _input4D[0][y];
        for (int x = 0; x < kInputSize; x++) {
          final px = row[x];
          px[0] = _inF32[base++];
          px[1] = _inF32[base++];
          px[2] = _inF32[base++];
        }
      }
    } else {
      for (int y = 0; y < kInputSize; y++) {
        final row = _input4D[0][y];
        for (int x = 0; x < kInputSize; x++) {
          final px = row[x];
          px[0] = _inU8[base++];
          px[1] = _inU8[base++];
          px[2] = _inU8[base++];
        }
      }
    }
  }

  // --------- Parsing & NMS ---------

  List<_RawDet> _parseSingleOutput(Object singleOut) {
    final parsed = <_RawDet>[];
    final out0 = (singleOut as List)[0];
    if (out0.isEmpty) return parsed;

    if (out0[0] is List && out0[0].isNotEmpty && out0[0][0] is num) {
      // out0[anchor][channel]
      for (int a = 0; a < _numAnchors; a++) {
        final row = (out0[a] as List).cast<num>();
        if (row.length < 5) continue;

        final cx = row[0].toDouble();
        final cy = row[1].toDouble();
        final w = row[2].toDouble();
        final h = row[3].toDouble();

        final isNorm = (cx <= 1.05 && cy <= 1.05 && w <= 1.05 && h <= 1.05);
        final cxAbs = isNorm ? cx * kInputSize : cx;
        final cyAbs = isNorm ? cy * kInputSize : cy;
        final wAbs = isNorm ? w * kInputSize : w;
        final hAbs = isNorm ? h * kInputSize : h;

        final x1 = cxAbs - wAbs / 2.0;
        final y1 = cyAbs - hAbs / 2.0;
        final x2 = cxAbs + wAbs / 2.0;
        final y2 = cyAbs + hAbs / 2.0;

        final channels = row.length;
        final hasObj = channels >= 6;
        final classOffset = hasObj ? 5 : 4;
        final numClasses = channels - classOffset;
        if (numClasses <= 0) continue;

        int bestC = 0;
        double bestLogit = -1e9;
        for (int c = 0; c < numClasses; c++) {
          final v = row[classOffset + c].toDouble();
          if (v > bestLogit) {
            bestLogit = v;
            bestC = c;
          }
        }
        final obj = hasObj ? _sigmoid(row[4].toDouble()) : 1.0;
        final conf = obj * _sigmoid(bestLogit);
        if (conf >= kScoreThreshold) {
          parsed.add(_RawDet(
            Rect.fromLTRB(
              x1.clamp(0.0, kInputSize.toDouble()),
              y1.clamp(0.0, kInputSize.toDouble()),
              x2.clamp(0.0, kInputSize.toDouble()),
              y2.clamp(0.0, kInputSize.toDouble()),
            ),
            bestC,
            conf,
          ));
        }
      }
    } else {
      // out0[channel][anchor]
      final channels = out0.length;
      final anchors = (out0[0] as List).length;
      for (int a = 0; a < anchors; a++) {
        final row = <double>[];
        for (int c = 0; c < channels; c++) {
          row.add((out0[c][a] as num).toDouble());
        }
        if (row.length < 5) continue;

        final cx = row[0], cy = row[1], w = row[2], h = row[3];
        final isNorm = (cx <= 1.05 && cy <= 1.05 && w <= 1.05 && h <= 1.05);
        final cxAbs = isNorm ? cx * kInputSize : cx;
        final cyAbs = isNorm ? cy * kInputSize : cy;
        final wAbs = isNorm ? w * kInputSize : w;
        final hAbs = isNorm ? h * kInputSize : h;
        final x1 = cxAbs - wAbs / 2.0;
        final y1 = cyAbs - hAbs / 2.0;
        final x2 = cxAbs + wAbs / 2.0;
        final y2 = cyAbs + hAbs / 2.0;

        final hasObj = row.length >= 6;
        final classOffset = hasObj ? 5 : 4;
        final numClasses = row.length - classOffset;
        if (numClasses <= 0) continue;

        int bestC = 0;
        double bestLogit = -1e9;
        for (int c = 0; c < numClasses; c++) {
          final v = row[classOffset + c];
          if (v > bestLogit) {
            bestLogit = v;
            bestC = c;
          }
        }
        final obj = hasObj ? _sigmoid(row[4]) : 1.0;
        final conf = obj * _sigmoid(bestLogit);
        if (conf >= kScoreThreshold) {
          parsed.add(_RawDet(
            Rect.fromLTRB(
              x1.clamp(0.0, kInputSize.toDouble()),
              y1.clamp(0.0, kInputSize.toDouble()),
              x2.clamp(0.0, kInputSize.toDouble()),
              y2.clamp(0.0, kInputSize.toDouble()),
            ),
            bestC,
            conf,
          ));
        }
      }
    }
    return parsed;
  }

  List<_RawDet> _parseThreeOutput() {
    final parsed = <_RawDet>[];
    for (int i = 0; i < _numAnchors; i++) {
      final s = _scores3[0][i];
      if (s < kScoreThreshold) continue;

      final bx = _boxes3[0][i];
      final looksNorm = bx.every((v) => v >= 0.0 && v <= 1.05);
      final scale = looksNorm ? kInputSize.toDouble() : 1.0;

      final rect = Rect.fromLTRB(
        (bx[0] * scale).clamp(0.0, kInputSize.toDouble()),
        (bx[1] * scale).clamp(0.0, kInputSize.toDouble()),
        (bx[2] * scale).clamp(0.0, kInputSize.toDouble()),
        (bx[3] * scale).clamp(0.0, kInputSize.toDouble()),
      );
      final cls = _classes3[0][i].toInt().clamp(0, _labels.length - 1);
      parsed.add(_RawDet(rect, cls, s));
    }
    return parsed;
  }

  // Utilities
  List<_RawDet> _topK(List<_RawDet> list, int k) {
    if (list.length <= k) return list;
    list.sort((a, b) => b.score.compareTo(a.score));
    return list.sublist(0, k);
  }

  double _sigmoid(double x) => 1.0 / (1.0 + exp(-x));

  List<_RawDet> _nmsRaw(List<_RawDet> parsed) {
    parsed.sort((a, b) => b.score.compareTo(a.score));
    final kept = <_RawDet>[];
    final suppressed = List<bool>.filled(parsed.length, false);
    for (int i = 0; i < parsed.length; i++) {
      if (suppressed[i]) continue;
      final a = parsed[i];
      kept.add(a);
      for (int j = i + 1; j < parsed.length; j++) {
        if (suppressed[j]) continue;
        if (_iou(a.rect, parsed[j].rect) > kIouThreshold) suppressed[j] = true;
      }
    }
    return kept;
  }

  double _iou(Rect a, Rect b) {
    final x1 = max(a.left, b.left);
    final y1 = max(a.top, b.top);
    final x2 = min(a.right, b.right);
    final y2 = min(a.bottom, b.bottom);
    final w = max(0.0, x2 - x1);
    final h = max(0.0, y2 - y1);
    final inter = w * h;
    final union = a.width * a.height + b.width * b.height - inter;
    return union <= 0 ? 0 : inter / union;
  }

  @override
  void dispose() {
    _camera?.dispose();
    _interpreter?.close();
    super.dispose();
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(preferredSize: Size.fromHeight(60), child: CustomAppbar(title: 'Live Camera Detection',)),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (_cameraOn) {
            await _stopCamera();
          } else {
            await _startCamera();
          }
        },
        icon: Icon(_cameraOn ? Icons.stop : Icons.videocam),
        label: Text(_cameraOn ? 'Stop Camera' : 'Start Camera'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _cameraOn && _camera != null && _camera!.value.isInitialized
                ? _previewWithOverlay()
                : const Center(child: Text('Tap Start to open camera')),
          ),
        ],
      ),
    );
  }

  Widget _previewWithOverlay() {
    final cam = _camera!;
    return Center(
      child: AspectRatio(
        aspectRatio: cam.value.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(cam),
            LayoutBuilder(
              builder: (context, constraints) {
                final displayW = constraints.maxWidth;
                final displayH = constraints.maxHeight;
                return CustomPaint(
                  size: Size(displayW, displayH),
                  painter: _DetectionsPainter(
                    detections: _detections,
                    displaySize: Size(displayW, displayH),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RawDet {
  final Rect rect; // model space (640×640)
  final int cls;
  final double score;
  _RawDet(this.rect, this.cls, this.score);
}

class _DetectionsPainter extends CustomPainter {
  final List<Detection> detections;
  final Size displaySize;

  _DetectionsPainter({required this.detections, required this.displaySize});

  @override
  void paint(Canvas canvas, Size size) {
    // Inverse letterbox mapping (match full CameraPreview fill)
    final scale = max(displaySize.width / kInputSize,
        displaySize.height / kInputSize);
    final newW = kInputSize * scale;
    final newH = kInputSize * scale;
    final dx = (displaySize.width - newW) / 2.0;
    final dy = (displaySize.height - newH) / 2.0;

    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFFFF3B30);

    final textStyle = const TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w800,
    );

    for (final d in detections) {
      final r = Rect.fromLTRB(
        d.rect.left * scale + dx,
        d.rect.top * scale + dy,
        d.rect.right * scale + dx,
        d.rect.bottom * scale + dy,
      );

      // draw box
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(8)), boxPaint);

      // label bg + text
      final label = '${d.label} ${(d.score * 100).toStringAsFixed(1)}%';
      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);

      final bgRect = Rect.fromLTWH(
        r.left,
        max(0, r.top - tp.height - 6),
        tp.width + 8,
        tp.height + 6,
      );
      canvas.drawRRect(
          RRect.fromRectAndRadius(bgRect, const Radius.circular(6)),
          Paint()..color = const Color(0xFFFF3B30));
      tp.paint(canvas, Offset(bgRect.left + 4, bgRect.top + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionsPainter old) {
    return old.detections != detections || old.displaySize != displaySize;
  }
}
