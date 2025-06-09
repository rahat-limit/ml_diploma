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

}
