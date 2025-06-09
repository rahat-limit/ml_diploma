import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class DuplicateDetectionResult {
  final bool isDuplicate;
  final double similarityScore;
  final String matchType;
  final String? matchedWith;

  DuplicateDetectionResult({
    required this.isDuplicate,
    required this.similarityScore,
    required this.matchType,
    this.matchedWith,
  });
}

class DuplicateDetectionService {
  final TextRecognizer _textRecognizer = TextRecognizer();
  final Map<String, String> _fileHashes = {};
  final Map<String, String> _fileContents = {};

  /// Initialize the service
  Future<void> initialize() async {
    // No initialization needed
  }

  /// Check if a file is a duplicate
  Future<DuplicateDetectionResult> checkForDuplicate(File file) async {
    try {
      // Calculate file hash
      String fileHash = await _calculateFileHash(file);

      // Check for exact binary match
      if (_fileHashes.containsValue(fileHash)) {
        String matchedFile = _fileHashes.entries
            .firstWhere((entry) => entry.value == fileHash)
            .key;

        return DuplicateDetectionResult(
          isDuplicate: true,
          similarityScore: 1.0,
          matchType: 'exact_binary_match',
          matchedWith: matchedFile,
        );
      }

      // For text-based files, check content similarity
      if (_isTextFile(file.path)) {
        String content = await _extractTextContent(file);
        double highestSimilarity = 0.0;
        String? mostSimilarFile;

        for (var entry in _fileContents.entries) {
          double similarity = _calculateContentSimilarity(content, entry.value);
          if (similarity > highestSimilarity) {
            highestSimilarity = similarity;
            mostSimilarFile = entry.key;
          }
        }

        if (highestSimilarity > 0.8) {
          // Threshold for similarity
          return DuplicateDetectionResult(
            isDuplicate: true,
            similarityScore: highestSimilarity,
            matchType: 'content_similarity',
            matchedWith: mostSimilarFile,
          );
        }

        // Store the new file's content for future comparisons
        _fileContents[file.path] = content;
      }

      // Store the new file's hash for future comparisons
      _fileHashes[file.path] = fileHash;

      return DuplicateDetectionResult(
        isDuplicate: false,
        similarityScore: 0.0,
        matchType: 'no_match',
      );
    } catch (e) {
      print('Error checking for duplicate: $e');
      return DuplicateDetectionResult(
        isDuplicate: false,
        similarityScore: 0.0,
        matchType: 'error',
      );
    }
  }

  /// Calculate SHA-256 hash of file
  Future<String> _calculateFileHash(File file) async {
    try {
      Uint8List fileBytes = await file.readAsBytes();
      Digest digest = sha256.convert(fileBytes);
      return digest.toString();
    } catch (e) {
      print('Error calculating file hash: $e');
      throw Exception('Failed to calculate file hash');
    }
  }

  /// Extract text content from file
  Future<String> _extractTextContent(File file) async {
    try {
      if (_isImageFile(file.path)) {
        // For image files, use ML Kit text recognition
        final inputImage = InputImage.fromFile(file);
        final RecognizedText recognizedText =
            await _textRecognizer.processImage(inputImage);
        return recognizedText.text.toLowerCase();
      } else {
        // For text files, read directly
        String content = await file.readAsString();
        return content.toLowerCase();
      }
    } catch (e) {
      print('Error extracting text content: $e');
      throw Exception('Failed to extract text content');
    }
  }

  /// Calculate similarity between two text contents using Levenshtein distance
  double _calculateContentSimilarity(String text1, String text2) {
    if (text1.isEmpty || text2.isEmpty) return 0.0;

    int maxLength = text1.length > text2.length ? text1.length : text2.length;
    int distance = _levenshteinDistance(text1, text2);

    return 1 - (distance / maxLength);
  }

  /// Calculate Levenshtein distance between two strings
  int _levenshteinDistance(String text1, String text2) {
    List<List<int>> dp = List.generate(
      text1.length + 1,
      (i) => List.generate(text2.length + 1, (j) => 0),
    );

    for (int i = 0; i <= text1.length; i++) {
      for (int j = 0; j <= text2.length; j++) {
        if (i == 0) {
          dp[i][j] = j;
        } else if (j == 0) {
          dp[i][j] = i;
        } else if (text1[i - 1] == text2[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1];
        } else {
          dp[i][j] = 1 +
              [
                dp[i - 1][j], // deletion
                dp[i][j - 1], // insertion
                dp[i - 1][j - 1] // substitution
              ].reduce((a, b) => a < b ? a : b);
        }
      }
    }

    return dp[text1.length][text2.length];
  }

  /// Check if file is likely to be text-based
  bool _isTextFile(String filePath) {
    final textExtensions = [
      '.txt',
      '.md',
      '.json',
      '.xml',
      '.csv',
      '.yaml',
      '.yml',
      '.dart',
      '.java',
      '.kt',
      '.py',
      '.js',
      '.ts',
      '.html',
      '.css',
      '.c',
      '.cpp',
      '.h',
      '.hpp',
      '.rs',
      '.go',
      '.rb',
      '.php',
      '.properties',
      '.conf',
      '.config',
      '.ini',
      '.log'
    ];

    return textExtensions.any((ext) => filePath.toLowerCase().endsWith(ext));
  }

  /// Check if file is an image
  bool _isImageFile(String filePath) {
    final imageExtensions = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.bmp',
      '.webp',
      '.heic',
      '.heif'
    ];

    return imageExtensions.any((ext) => filePath.toLowerCase().endsWith(ext));
  }

  /// Clear stored hashes and contents
  void clearCache() {
    _fileHashes.clear();
    _fileContents.clear();
  }

  /// Dispose of resources
  Future<void> dispose() async {
    _textRecognizer.close();
    clearCache();
  }
}
