import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'api_config.dart';
import '../widgets/error_dialog.dart';

class ContentClassificationResult {
  final String contentType;
  final Map<String, double> confidenceScores;
  final List<String> detectedKeywords;
  final String? transcribedText; // For audio files
  final String? category; // For audio files
  final List<dynamic>? chatAnalysis; // For WhatsApp chat files

  ContentClassificationResult({
    required this.contentType,
    required this.confidenceScores,
    required this.detectedKeywords,
    this.transcribedText,
    this.category,
    this.chatAnalysis,
  });
}

class FileContentClassifierService {
  final TextRecognizer _textRecognizer = TextRecognizer();
  String? _lastChatError;
  String? _lastAudioError;

  String? get lastChatError => _lastChatError;
  String? get lastAudioError => _lastAudioError;

  /// Initialize the service
  Future<void> initialize() async {
    // No initialization needed for ML Kit
  }

  /// Classify file content into predefined categories
  bool _isChatFile(String path) {
    final lowercasePath = path.toLowerCase();
    return lowercasePath.contains('chat') && lowercasePath.endsWith('.txt');
  }

  Future<List<dynamic>?> _analyzeChatFile(
      File file, BuildContext context) async {
    String url = '';
    try {
      print('Analyzing chat file: ${file.path}');
      final host = ApiConfig().getEffectiveHost();
      url = 'http://$host:8001/analyze';
      print('Attempting chat analysis request to: $url');
      var request = http.MultipartRequest('POST', Uri.parse(url));
      print('Using host for chat analysis: $host');

      // Add headers to match FastAPI server expectations
      request.headers['accept'] = 'application/json';
      request.headers['Content-Type'] = 'multipart/form-data';

      // Add file with proper content type
      final filename = file.path.split('/').last;
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          contentType: MediaType('text', 'plain'),
          filename: filename,
        ),
      );

      var response = await request.send();
      print('Chat file analysis response: ${response.statusCode}, ${response}');
      if (response.statusCode == 200) {
        var body = await response.stream.bytesToString();
        var result = json.decode(body);
        print(result);
        return result['results'];
      } else {
        final error =
            'Error analyzing chat file: Status ${response.statusCode}\nURL: $url';
        print(error);
        _lastChatError = error;
        ErrorDialog.show(context, 'Chat Analysis Error', error);
        return null;
      }
    } catch (e) {
      final error = 'Error analyzing chat file: $e\nURL: $url';
      print(error);
      _lastChatError = error;
      ErrorDialog.show(context, 'Chat Analysis Error', error);
      return null;
    }
  }

  Future<ContentClassificationResult> classifyContent(
      File file, BuildContext context) async {
    try {
      final String path = file.path.toLowerCase();

      // Check for chat files first
      if (_isChatFile(path)) {
        final chatAnalysis = await _analyzeChatFile(file, context);
        final String content = await _extractTextContent(file);
        return ContentClassificationResult(
          contentType: 'chat',
          confidenceScores: {'chat': 1.0},
          detectedKeywords: _extractKeywords(content),
          chatAnalysis: chatAnalysis,
        );
      }

      print('is audio file: ${_isAudioFile(path)}');
      if (_isAudioFile(path)) {
        final audioResult = await _analyzeAudioContent(file, context);
        print('audio data: $audioResult');
        final category = audioResult['category'];
        final text = audioResult['text'] ?? '';
        final confidence = audioResult['confidence'];

        return ContentClassificationResult(
          contentType: category == 'manipulation' || category == 'threat'
              ? 'hate_speech'
              : 'normal_speech',
          confidenceScores: {'hate_speech': confidence},
          detectedKeywords: _extractKeywords(text),
          transcribedText: text,
          category: category,
        );
      }

      // For non-audio files
      final String content = await _extractTextContent(file);

      if (content.isEmpty) {
        return ContentClassificationResult(
          contentType: 'unknown',
          confidenceScores: {},
          detectedKeywords: [],
        );
      }

      // Calculate confidence scores for each content type
      Map<String, double> confidenceScores =
          await _calculateContentTypeScores(content, file);

      // Determine the primary content type based on highest confidence score
      String contentType = _determineContentType(confidenceScores);

      // Extract relevant keywords
      List<String> detectedKeywords = _extractKeywords(content);

      return ContentClassificationResult(
        contentType: contentType,
        confidenceScores: confidenceScores,
        detectedKeywords: detectedKeywords,
      );
    } catch (e) {
      print('Error classifying file content: $e');
      return ContentClassificationResult(
        contentType: 'unknown',
        confidenceScores: {},
        detectedKeywords: [],
      );
    }
  }

  /// Extract text content from file based on its type
  Future<String> _extractTextContent(File file) async {
    try {
      final String path = file.path.toLowerCase();
      if (_isPdfFile(path)) {
        // For PDF files
        try {
          final Uint8List bytes = await file.readAsBytes();
          final PdfDocument doc = PdfDocument(inputBytes: bytes);
          String text = '';

          // Extract text from all pages
          for (int i = 0; i < doc.pages.count; i++) {
            final PdfTextExtractor extractor = PdfTextExtractor(doc);
            text += await extractor.extractText(startPageIndex: i) + '\n';
          }

          doc.dispose();
          return text.toLowerCase();
        } catch (e) {
          print('Error extracting PDF text: $e');
          return '';
        }
      } else if (_isImageFile(path)) {
        // For image files, use ML Kit text recognition
        try {
          final inputImage = InputImage.fromFile(file);
          final RecognizedText recognizedText =
              await _textRecognizer.processImage(inputImage);
          return recognizedText.text.toLowerCase();
        } catch (e) {
          print('Error extracting image text: $e');
          return '';
        }
      } else if (_isTextFile(path)) {
        // For text files, read directly
        try {
          String content = await file.readAsString();
          return content.toLowerCase();
        } catch (e) {
          print('Error reading text file: $e');
          return '';
        }
      }

      return '';
    } catch (e) {
      print('Error extracting text content: $e');
      return '';
    }
  }

  /// Calculate confidence scores for different content types
  Future<Map<String, double>> _calculateContentTypeScores(
      String content, File file) async {
    Map<String, double> scores = {
      'source_code': _calculateSourceCodeScore(content),
      'documentation': _calculateDocumentationScore(content),
      'configuration': _calculateConfigurationScore(content),
      'data': _calculateDataScore(content),
    };

    // Normalize scores
    double total = scores.values.fold(0, (sum, score) => sum + score);
    if (total > 0) {
      scores.forEach((key, value) {
        scores[key] = value / total;
      });
    }

    return scores;
  }

  double _calculateSourceCodeScore(String content) {
    final List<String> codeIndicators = [
      'class ',
      'function ',
      'def ',
      'import ',
      'return ',
      'public ',
      'private ',
      'const ',
      'var ',
      'let ',
      'if ',
      'for ',
      'while ',
      '{',
      '}',
      ';',
      'package ',
      'namespace ',
      'interface ',
      'extends ',
      'implements '
    ];

    return _calculateIndicatorPresence(content, codeIndicators);
  }

  double _calculateDocumentationScore(String content) {
    final List<String> docIndicators = [
      'introduction',
      'overview',
      'description',
      'guide',
      'manual',
      'documentation',
      'instructions',
      'readme',
      'how to',
      'usage',
      'example',
      'chapter',
      'section',
      'reference',
      'appendix',
      'table of contents',
      'summary',
      'conclusion'
    ];

    return _calculateIndicatorPresence(content, docIndicators);
  }

  double _calculateConfigurationScore(String content) {
    final List<String> configIndicators = [
      'config',
      'settings',
      'environment',
      'properties',
      'api_key',
      'password',
      'username',
      'host',
      'port',
      'database',
      'url',
      'endpoint',
      'server',
      'client',
      'debug',
      'production',
      'development',
      'test'
    ];

    return _calculateIndicatorPresence(content, configIndicators);
  }

  double _calculateDataScore(String content) {
    final List<String> dataIndicators = [
      'data',
      'json',
      'xml',
      'csv',
      'array',
      'list',
      'table',
      'record',
      'field',
      'value',
      'key',
      'object',
      'schema',
      'database',
      'query',
      'select',
      'insert',
      'update'
    ];

    return _calculateIndicatorPresence(content, dataIndicators);
  }

  double _calculateIndicatorPresence(String content, List<String> indicators) {
    int matches = 0;
    int totalWeight = 0;

    for (String indicator in indicators) {
      // Count all occurrences of each indicator
      RegExp regex = RegExp(indicator, caseSensitive: false);
      int count = regex.allMatches(content).length;
      if (count > 0) {
        matches += count;
        totalWeight++;
      }
    }

    // Consider both the variety of indicators and their frequency
    if (totalWeight == 0) return 0.0;
    double varietyScore = totalWeight / indicators.length;
    double frequencyScore =
        matches / (content.length / 100); // Normalize by content length

    return (varietyScore + frequencyScore) / 2;
  }

  String _determineContentType(Map<String, double> scores) {
    if (scores.isEmpty) return 'unknown';

    var maxEntry = scores.entries.reduce((a, b) => a.value > b.value ? a : b);

    // Require a minimum confidence threshold
    return maxEntry.value > 0.15 ? maxEntry.key : 'unknown';
  }

  List<String> _extractKeywords(String content) {
    final Map<String, int> wordFrequency = {};
    final RegExp wordPattern = RegExp(r'\b\w+\b');

    // Extract words and count their frequency
    final matches = wordPattern.allMatches(content);
    for (var match in matches) {
      String word = match.group(0)!.toLowerCase();
      if (_isRelevantKeyword(word)) {
        wordFrequency[word] = (wordFrequency[word] ?? 0) + 1;
      }
    }

    // Sort by frequency and return top keywords
    final sortedWords = wordFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedWords.take(15).map((e) => e.key).toList();
  }

  bool _isRelevantKeyword(String word) {
    final List<String> commonWords = [
      'the',
      'a',
      'an',
      'and',
      'or',
      'but',
      'in',
      'on',
      'at',
      'to',
      'for',
      'of',
      'with',
      'by',
      'as',
      'is',
      'are',
      'was',
      'were',
      'be',
      'been',
      'being',
      'have',
      'has',
      'had',
      'do',
      'does',
      'did',
      'will',
      'would',
      'should',
      'could',
      'may',
      'might',
      'must',
      'shall',
      'can',
      'that',
      'this',
      'these',
      'those'
    ];

    return word.length > 2 && !commonWords.contains(word);
  }

  bool _isPdfFile(String path) {
    return path.endsWith('.pdf');
  }

  bool _isImageFile(String path) {
    final imageExtensions = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.bmp',
      '.webp',
      '.heic',
      '.heif',
      '.tiff',
      '.tif'
    ];
    return imageExtensions.any((ext) => path.endsWith(ext));
  }

  bool _isAudioFile(String path) {
    final audioExtensions = [
      '.mp3',
      '.wav',
      '.m4a',
      '.aac',
      '.wma',
      '.ogg',
      '.flac'
    ];
    return audioExtensions.any((ext) => path.endsWith(ext));
  }

  /// Analyze audio content for hate speech
  Future<Map<String, dynamic>> _analyzeAudioContent(
      File file, BuildContext context) async {
    String url = '';
    try {
      print('audio analysis response:1');
      final host = ApiConfig().getEffectiveHost();
      url = 'http://$host:800/predict';
      print('Attempting audio analysis request to: $url');
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(url),
      );
      print('audio analysis response:2');

      // Add headers to match curl request
      request.headers['accept'] = 'application/json';
      request.headers['Content-Type'] = 'multipart/form-data';

      // Add file with proper content type and name parameter
      final filename = file.path.split('/').last;
      request.files.add(
        await http.MultipartFile.fromPath(
          'files',
          file.path,
          contentType: MediaType('audio', 'mpeg'),
          filename: filename, // Add explicit filename
        ),
      );

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      print('audio analysis response:3');
      final data = json.decode(responseBody);
      print('audio analysis response:4 $data');
      if (data['results'] != null && data['results'].isNotEmpty) {
        final result = data['results'][0];
        return {
          'text': result['text'] ?? '',
          'category': result['category'] ?? 'unknown',
          'confidence': 1.0, // Server doesn't provide confidence, assuming max
        };
      }

      final error = 'Error analyzing audio content: No results\nURL: $url';
      print(error);
      _lastAudioError = error;
      ErrorDialog.show(context, 'Audio Analysis Error', error);
      return {'text': '', 'category': 'unknown', 'confidence': 0.0};
    } catch (e) {
      final error = 'Error analyzing audio content: $e\nURL: $url';
      print(error);
      _lastAudioError = error;
      ErrorDialog.show(context, 'Audio Analysis Error', error);
      return {'text': '', 'category': 'unknown', 'confidence': 0.0};
    }
  }

  bool _isTextFile(String path) {
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
    return textExtensions.any((ext) => path.endsWith(ext));
  }

  /// Dispose of resources
  Future<void> dispose() async {
    _textRecognizer.close();
  }
}
