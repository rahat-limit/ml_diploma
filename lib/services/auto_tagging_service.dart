import 'dart:io';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

class AutoTaggingResult {
  final List<String> tags;
  final List<double> confidences;

  AutoTaggingResult({
    required this.tags,
    required this.confidences,
  });
}

class AutoTaggingService {
  final ImageLabeler _labeler = ImageLabeler(
    options: ImageLabelerOptions(confidenceThreshold: 0.7),
  );

  /// Initialize the service
  Future<void> initialize() async {
    // No initialization needed for ML Kit
  }

  /// Generate tags for an image
  Future<AutoTaggingResult> generateTags(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final List<ImageLabel> labels = await _labeler.processImage(inputImage);

      if (labels.isEmpty) {
        return AutoTaggingResult(
          tags: [],
          confidences: [],
        );
      }

      // Get all labels and confidences
      final List<String> tags =
          labels.map((label) => _normalizeTag(label.label)).toList();
      final List<double> confidences =
          labels.map((label) => label.confidence).toList();

      return AutoTaggingResult(
        tags: tags,
        confidences: confidences, //dwad
      );
    } catch (e) {
      print('Error generating tags: $e');
      return AutoTaggingResult(
        tags: [],
        confidences: [],
      );
    }
  }

  /// Normalize tag by converting to lowercase and removing special characters
  String _normalizeTag(String tag) {
    return tag.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
  }

  /// Dispose of resources
  Future<void> dispose() async {
    _labeler.close();
  }
}
