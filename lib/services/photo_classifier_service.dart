import 'dart:io';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

class ClassificationResult {
  final String category;
  final List<String> mlLabels;
  final List<double> confidences;

  ClassificationResult({
    required this.category,
    required this.mlLabels,
    required this.confidences,
  });
}

class PhotoClassifierService {
  final ImageLabeler _labeler = ImageLabeler(
    options: ImageLabelerOptions(confidenceThreshold: 0.5),
  );

  /// Initialize the service
  Future<void> initialize() async {
    // No initialization needed for ML Kit
  }

  /// Classify image into predefined categories
  Future<ClassificationResult> classifyImage(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final List<ImageLabel> labels = await _labeler.processImage(inputImage);

      if (labels.isEmpty) {
        return ClassificationResult(
          category: 'others',
          mlLabels: [],
          confidences: [],
        );
      }

      // Get all labels and confidences
      final List<String> mlLabels = labels.map((label) => label.label).toList();
      final List<double> confidences =
          labels.map((label) => label.confidence).toList();

      // Get the top label for category classification
      final String topLabel = labels.first.label.toLowerCase();
      final String category = _determineCategory(topLabel);

      return ClassificationResult(
        category: category,
        mlLabels: mlLabels,
        confidences: confidences,
      );
    } catch (e) {
      print('Error classifying image: $e');
      return ClassificationResult(
        category: 'others',
        mlLabels: [],
        confidences: [],
      );
    }
  }

  /// Determine the category based on the label
  String _determineCategory(String label) {
    if (_isDocument(label.toLowerCase())) {
      return 'document';
    } else if (_isHumanFace(label.toLowerCase())) {
      return 'human face';
    } else if (_isNature(label.toLowerCase())) {
      return 'nature';
    }
    return 'others';
  }

  /// Check if the prediction indicates a document
  bool _isDocument(String label) {
    final List<String> documentKeywords = [
      'book',
      'paper',
      'document',
      'notebook',
      'letter',
      'envelope',
      'newspaper',
      'magazine',
      'text',
      'writing',
      'print',
      'tablet'
    ];
    return documentKeywords.any((keyword) => label.contains(keyword));
  }

  /// Check if the prediction indicates a human face
  bool _isHumanFace(String label) {
    final List<String> faceKeywords = [
      'face',
      'person',
      'people',
      'human',
      'man',
      'woman',
      'child',
      'portrait',
      'selfie',
      'head',
      'skin',
      'ear',
      'eyelash',
      'poster',
      'hat',
      'flesh',
      'hand',
      'muscle',
      'nail',
      'foot',
      'selfie',
    ];
    return faceKeywords.any((keyword) => label.contains(keyword));
  }

  /// Check if the prediction indicates nature
  bool _isNature(String label) {
    final List<String> natureKeywords = [
      'tree',
      'flower',
      'plant',
      'mountain',
      'river',
      'lake',
      'ocean',
      'forest',
      'garden',
      'landscape',
      'sky',
      'beach',
      'grass',
      'leaf',
      'animal',
      'bird',
      'insect',
      'water',
      'cloud'
    ];
    return natureKeywords.any((keyword) => label.contains(keyword));
  }

  /// Dispose of resources
  Future<void> dispose() async {
    _labeler.close();
  }
}
