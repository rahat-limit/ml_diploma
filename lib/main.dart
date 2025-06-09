import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'services/api_config.dart';
import 'package:ml_practice/pages/report_generation_screen.dart';
import 'package:ml_practice/pages/report_history_screen.dart';
import 'package:ml_practice/pages/audio_analysis_screen.dart';
import 'package:pie_chart/pie_chart.dart';
import 'dart:io';
import 'services/photo_classifier_service.dart';
import 'services/file_content_classifier_service.dart';
import 'services/duplicate_detection_service.dart';
import 'services/auto_tagging_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ApiConfig(),
      child: MaterialApp(
        title: 'File Analysis Tool',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFE94F4F),
            primary: const Color(0xFFE94F4F),
            surface: Colors.white,
            background: const Color(0xFFFFF0F0),
          ),
          useMaterial3: true,
        ),
        home: const MyHomePage(),
        // routes: {
        //   '/report_generation': (context) => const ReportGenerationScreen(),
        // },
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final PhotoClassifierService _photoClassifier = PhotoClassifierService();
  final FileContentClassifierService _contentClassifier =
      FileContentClassifierService();
  final DuplicateDetectionService _duplicateDetector =
      DuplicateDetectionService();
  final AutoTaggingService _autoTagger = AutoTaggingService();

  bool _isAnalyzing = false;
  bool _isEditingFileTypes = false;
  Map<String, bool> _expandedChatMessages = {};

  // Dynamic file type mappings
  Map<String, Set<String>> _fileTypeMappings = {
    'chats': {'txt'},
    'images': {
      'jpg',
      'jpeg',
      'png',
      'gif',
      'bmp',
      'webp',
      'svg',
      'tiff',
      'ico',
      'raw'
    },
    'documents': {
      'pdf',
      'doc',
      'docx',
      'txt',
      'rtf',
      'odt',
      // 'pages',
      'epub',
      'md',
      'tex'
    },
    'multimedia': {
      'mp3',
      'mp4',
      'wav',
      'avi',
      'mov',
      'mkv',
      'flv',
      'wmv',
      'webm',
      'm4a',
      'm4v'
    },
    'code': {
      'js',
      'py',
      'java',
      'cpp',
      'cs',
      'html',
      'css',
      'php',
      'rb',
      'swift',
      'kt',
      'dart',
      'go'
    },
    'archives': {'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'iso'},
    'spreadsheets': {'xls', 'xlsx', 'csv', 'ods', 'numbers'},
    'presentations': {'ppt', 'pptx', 'key', 'odp'},
    'databases': {'sql', 'db', 'sqlite', 'mdb', 'accdb'},
    'fonts': {'ttf', 'otf', 'woff', 'woff2', 'eot'},
    'system': {'exe', 'dll', 'sys', 'bat', 'sh', 'app', 'dmg', 'deb', 'rpm'}
  };

  
  final TextEditingController _newExtensionController = TextEditingController();
  List<FileSystemEntity> _selectedFiles = [];
  Map<String, double> _fileDistribution = {};
  int _totalFiles = 0;
  double _totalSize = 0;
  int _categories = 0;
  int _processedFiles = 0;
  int _totalFilesToProcess = 0;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Map<String, Map<String, dynamic>> _fileAnalysis = {};

  
  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    await _photoClassifier.initialize();
    await _contentClassifier.initialize();
    await _duplicateDetector.initialize();
    await _autoTagger.initialize();
  }

  
  Future<void> _analyzeDirectory() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        allowCompression: false,
      );

      if (result == null) return;

      final files = result.files.where((f) => f.path != null).toList();
      setState(() {
        _isAnalyzing = true;
        _fileAnalysis.clear();
        _selectedFiles.clear();
        _fileDistribution.clear();
        _processedFiles = 0;
        _totalFilesToProcess = files.length;
      });

      // Process files in batches of 3
      final batchSize = 3;
      Map<String, int> typeCounts = {};
      double totalSize = 0;
      Set<String> categories = {};

      for (var i = 0; i < files.length; i += batchSize) {
        final batch = files.skip(i).take(batchSize);
        await Future.wait(batch.map((file) async {
          File fileEntity = File(file.path!);
          _selectedFiles.add(fileEntity);

          String ext = file.path!.split('.').last.toLowerCase();
          String type = _getFileType(ext);

          // Analyze file
          await _analyzeFile(fileEntity, context);

          // Update counters
          typeCounts[type] = (typeCounts[type] ?? 0) + 1;
          totalSize += file.size;
          categories.add(type);

          setState(() {
            _processedFiles++;
          });
        }));

        // Update UI after each batch
        if (!mounted) return;
        setState(() {
          _fileDistribution = Map<String, double>.from(
              typeCounts.map((k, v) => MapEntry(k, v.toDouble())));
          _totalFiles = _selectedFiles.length;
          _totalSize = totalSize / (1024 * 1024); // Convert to MB
          _categories = categories.length;
        });

        // Give UI time to breathe between batches
        await Future.delayed(const Duration(milliseconds: 50));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error analyzing directory: $e')),
      );
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }
  
  Future<Map<String, dynamic>> _analyzeFile(
      File file, BuildContext context) async {
    String ext = file.path.split('.').last.toLowerCase();
    String type = _getFileType(ext);
    Map<String, dynamic> analysis = {};

    try {
      if (type == 'images') {
        final photoResult = await _photoClassifier.classifyImage(file);
        final tagResult = await _autoTagger.generateTags(file);
        analysis['photo'] = photoResult;
        analysis['tags'] = tagResult;
      } else if (type == 'multimedia' ||
          type == 'documents' ||
          type == 'chats' ||
          type == 'others') {
        final contentResult =
            await _contentClassifier.classifyContent(file, context);
        analysis['content'] = contentResult;
      }

      final duplicateResult = await _duplicateDetector.checkForDuplicate(file);
      analysis['duplicate'] = duplicateResult;

      if (mounted) {
        setState(() {
          _fileAnalysis[file.path] = analysis;
        });
      }
      return analysis;
    } catch (e) {
      print('Error analyzing file ${file.path}: $e');
      return {};
    }
  }

  
  String _getFileType(String path) {
    // Check for chat files first
    if (path.toLowerCase().contains('chat') &&
        path.toLowerCase().endsWith('.txt')) {
      return 'chats';
    }

    // Get extension and check mappings
    final extension = path.split('.').last.toLowerCase();
    for (var entry in _fileTypeMappings.entries) {
      if (entry.value.contains(extension)) {
        return entry.key;
      }
    }
    return 'others';
  }

  void _addExtension(String type, String extension) {
    setState(() {
      _fileTypeMappings[type] = {
        ..._fileTypeMappings[type]!,
        extension.toLowerCase()
      };
    });
  }

  void _removeExtension(String type, String extension) {
    setState(() {
      _fileTypeMappings[type] = _fileTypeMappings[type]!..remove(extension);
    });
  }

  void _showAddExtensionDialog(String type) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Extension to ${type.toUpperCase()}'),
        content: TextField(
          controller: _newExtensionController,
          decoration: const InputDecoration(
            hintText: 'Enter file extension (e.g., pdf)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _newExtensionController.clear();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (_newExtensionController.text.isNotEmpty) {
                _addExtension(type, _newExtensionController.text);
                Navigator.pop(context);
                _newExtensionController.clear();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }


}

