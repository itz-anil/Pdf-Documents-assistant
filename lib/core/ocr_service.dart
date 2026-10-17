import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'models.dart';

class OcrResult {
  final String text;
  final List<OcrLine> lines;
  const OcrResult(this.text, this.lines);
}

/// On-device text recognition (no network). Recognisers are reused.
class OcrService {
  OcrService._();
  static final instance = OcrService._();

  TextRecognizer? _recognizer;

  /// English (Latin script) recognition, fully on-device.
  Future<OcrResult> recognise(String imagePath, int width, int height) async {
    final recognizer = _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
    final lines = <OcrLine>[];
    if (width > 0 && height > 0) {
      for (final block in result.blocks) {
        for (final line in block.lines) {
          final r = line.boundingBox;
          lines.add(OcrLine(
            line.text,
            r.left / width,
            r.top / height,
            r.width / width,
            r.height / height,
          ));
        }
      }
    }
    final text = result.blocks.map((b) => b.text).join('\n\n').trim();
    return OcrResult(text, lines);
  }

  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
