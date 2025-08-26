import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_detection_new/main.dart';
import 'package:image_detection_new/widgets/border_glow.dart';
import 'package:image_detection_new/widgets/custom_appbar.dart';
import 'package:image_detection_new/widgets/custom_gredient_button.dart';
import 'package:image_detection_new/widgets/detection_box.dart';
import 'package:image_detection_new/widgets/empty_card.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:ui' as ui; // for ImageFilter.blur


class QuickCaptureScreen extends StatefulWidget {
  const QuickCaptureScreen({Key? key}) : super(key: key);

  @override
  State<QuickCaptureScreen> createState() => _QuickCaptureScreenState();
}

class _QuickCaptureScreenState extends State<QuickCaptureScreen> {
  Interpreter? _interpreter;
  List<String> _labels = [];
  final int inputSize = 640;

  File? _imageFile;
  List<Detection> _detections = [];
  int _origImageW = 0;
  int _origImageH = 0;


  @override
  void initState() {
    super.initState();
    loadData();
  }

  loadData()async{
    await  loadModelAndLabels();
    pickImageFromCamera();
  }

  @override
  void dispose() {
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


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(preferredSize: Size.fromHeight(60), child: CustomAppbar(title: 'Quick Capture',)),

      body: Container(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            SizedBox(height: 20,),
            Row(
              children: [
                Expanded(
                  child: CustomGradientButton(
                    colors: const [Color(0xFF10B981), Color(0xFF059669)], // Gallery
                    icon: Icons.collections_outlined,
                    label: 'Capture',
                    onTap: pickImageFromCamera,
                  ),
                ),
                SizedBox(width: 15,),
                Expanded(
                  child: CustomGradientButton(
                    colors: const [Color(0xFFF43F5E), Color(0xFFE11D48)], // Clear
                    icon: Icons.delete_outline_rounded,
                    label: 'Clear',
                    onTap: clearImage,
                  ),
                ),
              ],
            ),
            SizedBox(height: 20,),
            _preview()

          ],
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
                    ? EmptyPreviewCard()
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
                            child: BorderGlow(
                              child: DetectionBox(
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

}
