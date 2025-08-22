import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui; // for ImageFilter.blur
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

void main() {
  runApp(const MyApp());
}

class Detection {
  final Rect rect;
  final String label;
  final double score;
  Detection({required this.rect, required this.label, required this.score});
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6366F1), // indigo
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'YOLOv11 Object Detection',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        fontFamily: 'Roboto',
      ),
      home: const _Home(),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home({super.key});
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> with SingleTickerProviderStateMixin {
  Interpreter? _interpreter;
  List<String> _labels = [];
  final int inputSize = 640;

  File? _imageFile;
  List<Detection> _detections = [];
  int _origImageW = 0;
  int _origImageH = 0;

  late final AnimationController _ac;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat();
    loadModelAndLabels();
  }

  @override
  void dispose() {
    _ac.dispose();
    _interpreter?.close();
    super.dispose();
  }

  Future<void> loadModelAndLabels() async {
    try {
      _interpreter =
      await Interpreter.fromAsset('assets/models/YOLOv11-Detection.tflite');
      final labelsData = await DefaultAssetBundle.of(context)
          .loadString('assets/models/yololabels.txt');
      _labels = labelsData
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      setState(() {});
    } catch (e) {
      // ignore: avoid_print
      print('Error loading model or labels: $e');
    }
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      _imageFile = File(picked.path);
      _detections = [];
    });
    await runModelOnImage(_imageFile!);
  }

  Future<void> pickImageFromCamera() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera);
    if (picked == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _imageFile = File(picked.path);
      _detections = [];
    });
    await runModelOnImage(_imageFile!);
  }

  void clearImage() {
    HapticFeedback.selectionClick();
    setState(() {
      _imageFile = null;
      _detections = [];
      _origImageW = 0;
      _origImageH = 0;
    });
  }

  List<Detection> nonMaxSuppression(List<Detection> detections,
      {double iouThreshold = 0.45}) {
    detections.sort((a, b) => b.score.compareTo(a.score));
    final result = <Detection>[];
    while (detections.isNotEmpty) {
      final best = detections.removeAt(0);
      result.add(best);
      detections.removeWhere((det) {
        final xx1 = max(best.rect.left, det.rect.left);
        final yy1 = max(best.rect.top, det.rect.top);
        final xx2 = min(best.rect.right, det.rect.right);
        final yy2 = min(best.rect.bottom, det.rect.bottom);
        final w = max(0, xx2 - xx1);
        final h = max(0, yy2 - yy1);
        final inter = w * h;
        final union =
            best.rect.width * best.rect.height + det.rect.width * det.rect.height - inter;
        return union <= 0 ? false : (inter / union > iouThreshold);
      });
    }
    return result;
  }

  Future<void> runModelOnImage(File imageFile) async {
    if (_interpreter == null) return;

    final bytes = await imageFile.readAsBytes();
    final oriImage = img.decodeImage(bytes);
    if (oriImage == null) return;

    _origImageW = oriImage.width;
    _origImageH = oriImage.height;

    final resized = img.copyResize(oriImage, width: inputSize, height: inputSize);

    final inputTensor = List.generate(
      1,
          (_) => List.generate(
        inputSize,
            (y) => List.generate(
          inputSize,
              (x) {
            final p = resized.getPixel(x, y);
            return [p.r / 255.0, p.g / 255.0, p.b / 255.0];
          },
        ),
      ),
    );

    final boxes =
    List.generate(1, (_) => List.generate(8400, (_) => List.filled(4, 0.0)));
    final scores = List.generate(1, (_) => List.filled(8400, 0.0));
    final classes = List.generate(1, (_) => List.filled(8400, 0.0));

    _interpreter!.runForMultipleInputs([inputTensor], {0: boxes, 1: scores, 2: classes});

    var dets = <Detection>[];
    for (int i = 0; i < 8400; i++) {
      final score = scores[0][i];
      final classIndex = classes[0][i].toInt();
      if (score > 0.30) {
        final x1 = boxes[0][i][0];
        final y1 = boxes[0][i][1];
        final x2 = boxes[0][i][2];
        final y2 = boxes[0][i][3];
        final scaleX = _origImageW / inputSize;
        final scaleY = _origImageH / inputSize;
        dets.add(Detection(
          rect: Rect.fromLTRB(x1 * scaleX, y1 * scaleY, x2 * scaleX, y2 * scaleY),
          score: score,
          label: classIndex < _labels.length ? _labels[classIndex] : "Unknown",
        ));
      }
    }
    dets = nonMaxSuppression(dets, iouThreshold: 0.45);

    setState(() {
      _detections = dets;
    });
  }

  // -------------------------- UI HELPERS --------------------------

  AppBar _buildAppBar() {
    return AppBar(
      elevation: 0,
      centerTitle: true,
      foregroundColor: Colors.white,
      backgroundColor: Colors.transparent,
      flexibleSpace: AnimatedBuilder(
        animation: _ac,
        builder: (_, __) {
          final t = _ac.value;
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: const [Color(0xFF0EA5E9), Color(0xFF4F46E5), Color(0xFF8B5CF6)],
                stops: [0.0, (0.35 + 0.3 * t).clamp(0.2, 0.7), 1.0],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          );
        },
      ),
      title: const Text(
        'Object Detects',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _background() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF8FAFF), Color(0xFFF1F5F9)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: const _BlobsBackground(),
    );
  }

  Widget _heroHeader() {
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) {
        final t = _ac.value;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: const [Color(0xFF22D3EE), Color(0xFF6366F1), Color(0xFF9333EA)],
              stops: [0.0, (0.4 + 0.2 * t).clamp(0.2, .8), 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x22000000), blurRadius: 16, offset: Offset(0, 8))
            ],
          ),
          child: Row(
            children: const [
              Icon(Icons.auto_awesome, color: Colors.white, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'YOLOv11 Object Detection',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: .4,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Buttons bar (colored container) — Gallery & Clear
  Widget _actionsBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFA5B4FC), Color(0xFF67E8F9)], // indigo-200 → cyan-200
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(color: Color(0x22000000), blurRadius: 14, offset: Offset(0, 8)),
          ],
          border: Border.all(color: Colors.white.withOpacity(.6), width: 1),
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            _gradientButton(
              colors: const [Color(0xFF10B981), Color(0xFF059669)], // Gallery
              icon: Icons.collections_outlined,
              label: 'Gallery',
              onTap: pickImage,
            ),
            _gradientButton(
              colors: const [Color(0xFFF43F5E), Color(0xFFE11D48)], // Clear
              icon: Icons.delete_outline_rounded,
              label: 'Clear',
              onTap: clearImage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _gradientButton({
    required List<Color> colors,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 52,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        elevation: 8,
        shadowColor: colors.last.withOpacity(.35),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          onTapDown: (_) => HapticFeedback.selectionClick(),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _glass({required Widget child, double radius = 22}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.65),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withOpacity(0.5)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _preview() {
    const double expandBoxes = 0.06;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: _glass(
          child: Container(
            color: Colors.white.withOpacity(0.35),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _imageFile == null
                    ? _EmptyPreviewCard(controller: _ac)
                    : LayoutBuilder(
                  builder: (context, constraints) {
                    final displayW = constraints.maxWidth;
                    final displayH = constraints.maxHeight;

                    final imgW = (_origImageW > 0) ? _origImageW.toDouble() : 1.0;
                    final imgH = (_origImageH > 0) ? _origImageH.toDouble() : 1.0;

                    final scale = min(displayW / imgW, displayH / imgH);
                    final offsetX = (displayW - imgW * scale) / 2;
                    final offsetY = (displayH - imgH * scale) / 2;

                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Image.file(_imageFile!, fit: BoxFit.contain),
                        ),
                        ..._detections.map((det) {
                          double left = det.rect.left * scale + offsetX;
                          double top = det.rect.top * scale + offsetY;
                          double width = det.rect.width * scale;
                          double height = det.rect.height * scale;

                          if (expandBoxes > 0) {
                            final addW = width * expandBoxes;
                            final addH = height * expandBoxes;
                            left -= addW / 2;
                            top -= addH / 2;
                            width += addW;
                            height += addH;
                          }

                          left = left.clamp(0.0, displayW);
                          top = top.clamp(0.0, displayH);
                          if (left + width > displayW) width = max(0.0, displayW - left);
                          if (top + height > displayH) height = max(0.0, displayH - top);

                          return AnimatedPositioned(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            left: left,
                            top: top,
                            width: width,
                            height: height,
                            child: _BorderGlow(
                              child: _DetectionBox(
                                label: det.label,
                                score: det.score,
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _background(),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: _buildAppBar(),
          floatingActionButton: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF22D3EE)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(100),
              boxShadow: const [
                BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 8)),
              ],
            ),
            child: FloatingActionButton.extended(
              backgroundColor: Colors.transparent,
              elevation: 0,
              onPressed: pickImageFromCamera,
              icon: const Icon(Icons.camera_rounded, color: Colors.white),
              label: const Text('Quick Capture',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ),
          body: Column(
            children: [
              _heroHeader(),
              _actionsBar(),
              _preview(),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------- Decorative background blobs ----------
class _BlobsBackground extends StatelessWidget {
  const _BlobsBackground({super.key});
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _BlobsPainter(),
        size: Size.infinite,
      ),
    );
  }
}

class _BlobsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p1 = Paint()..color = const Color(0x223B82F6); // blue-500
    final p2 = Paint()..color = const Color(0x229333EA); // violet-600
    final p3 = Paint()..color = const Color(0x2214B8A6); // teal-500

    canvas.drawCircle(Offset(size.width * .18, 120), 110, p1);
    canvas.drawCircle(Offset(size.width * .82, 90), 95, p2);
    canvas.drawCircle(Offset(size.width * .72, size.height - 120), 135, p3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------- Detection box with RED border + label chip ----------
class _DetectionBox extends StatelessWidget {
  final String label;
  final double score;
  const _DetectionBox({super.key, required this.label, required this.score});

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFFF3B30); // iOS red
    final text = '$label ${(score * 100).toStringAsFixed(1)}%';

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: red, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: Container(
          decoration: const BoxDecoration(
            color: red,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: .2,
            ),
          ),
        ),
      ),
    );
  }
}

// RED glow wrapper for the detection box
class _BorderGlow extends StatelessWidget {
  final Widget child;
  const _BorderGlow({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(boxShadow: [
        BoxShadow(
          color: Color(0x33FF3B30), // soft red glow
          blurRadius: 12,
          spreadRadius: 1,
        ),
      ]),
      child: child,
    );
  }
}

// Empty-state card with shimmer bar
class _EmptyPreviewCard extends StatelessWidget {
  final AnimationController controller;
  const _EmptyPreviewCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library_outlined, size: 48, color: Color(0xFF64748B)),
            const SizedBox(height: 10),
            const Text(
              "No image selected",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
            ),
            const SizedBox(height: 8),
            _ShimmerBar(controller: controller),
            const SizedBox(height: 6),
            const Text(
              "Pick from Gallery or use Quick Capture",
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final Widget child;
  const _GlassPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.55),
            border: Border.all(color: Colors.white.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ShimmerBar extends StatelessWidget {
  final AnimationController controller;
  const _ShimmerBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = controller.value;
        return Container(
          height: 8,
          width: 180,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              colors: const [Color(0xFFE5E7EB), Color(0xFFF3F4F6), Color(0xFFE5E7EB)],
              stops: [0.0, (0.3 + 0.4 * t).clamp(0.2, .8), 1.0],
            ),
          ),
        );
      },
    );
  }
}
