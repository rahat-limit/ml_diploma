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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeader(),
              _buildStats(),
              if (_fileDistribution.isNotEmpty) _buildPieChart(),
              _buildFileList(),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isAnalyzing ? null : _analyzeDirectory,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.folder_open),
        label: const Text('Analyze'),
      ),
    );
  }

  
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: Icon(_isEditingFileTypes ? Icons.done : Icons.settings),
              onPressed: () {
                setState(() {
                  _isEditingFileTypes = !_isEditingFileTypes;
                });
              },
            ),
            const Text(
              'File Analysis Tool',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopupMenuButton(
                  icon: const Icon(Icons.more_vert),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      child: ListTile(
                        leading: const Icon(Icons.api),
                        title: const Text('API Host'),
                        contentPadding: EdgeInsets.zero,
                        onTap: () {
                          Navigator.pop(context);
                          _showHostConfigDialog(context);
                        },
                      ),
                    ),
                    PopupMenuItem(
                      child: ListTile(
                        leading: const Icon(Icons.history),
                        title: const Text('History'),
                        contentPadding: EdgeInsets.zero,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ReportHistoryScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                IconButton(
                    icon: const Icon(Icons.file_download_outlined),
                    onPressed: _fileAnalysis.isEmpty
                        ? null
                        : () {
                            final reportData = {
                              'totalFiles': _totalFiles,
                              'totalSize': _totalSize,
                              'suspiciousFiles': <String>[],
                              'securitySummary': {
                                'filesWithSensitiveData': <String, dynamic>{},
                              },
                              'photoClassifications': Map.fromEntries(
                                _fileAnalysis.entries
                                    .where((e) => e.value['photo'] != null)
                                    .map((e) {
                                  final photo =
                                      e.value['photo'] as ClassificationResult;
                                  return MapEntry(e.key, {
                                    'category': photo.category,
                                    'mlLabels': photo.mlLabels,
                                    'confidences': photo.confidences,
                                  });
                                }),
                              ),
                              'contentClassifications': Map.fromEntries(
                                _fileAnalysis.entries
                                    .where((e) => e.value['content'] != null)
                                    .map((e) {
                                  final content = e.value['content']
                                      as ContentClassificationResult;
                                  return MapEntry(e.key, {
                                    'contentType': content.contentType,
                                    'confidenceScores':
                                        content.confidenceScores,
                                    'detectedKeywords':
                                        content.detectedKeywords,
                                  });
                                }),
                              ),
                              'duplicateDetections': Map.fromEntries(
                                _fileAnalysis.entries
                                    .where((e) => e.value['duplicate'] != null)
                                    .map((e) {
                                  final duplicate = e.value['duplicate']
                                      as DuplicateDetectionResult;
                                  return MapEntry(e.key, {
                                    'isDuplicate': duplicate.isDuplicate,
                                    'similarityScore':
                                        duplicate.similarityScore,
                                    'matchType': duplicate.matchType,
                                    'matchedWith': duplicate.matchedWith,
                                  });
                                }),
                              ),
                              'autoTags': Map.fromEntries(
                                _fileAnalysis.entries
                                    .where((e) => e.value['tags'] != null)
                                    .map((e) {
                                  final tags =
                                      e.value['tags'] as AutoTaggingResult;
                                  return MapEntry(e.key, {
                                    'tags': tags.tags,
                                    'confidences': tags.confidences,
                                  });
                                }),
                              ),
                            };

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ReportGenerationScreen(
                                  reportData: reportData,
                                ),
                              ),
                            );
                          })
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search files...',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.white,
          ),
          onChanged: (value) {
            setState(() {
              _searchQuery = value.toLowerCase();
            });
          },
        ),
      ]),
    );
  }

  Widget _buildStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          _buildStatCard(
            icon: Icons.folder,
            value: _totalFiles.toString(),
            label: 'Total Files',
          ),
          const SizedBox(width: 8),
          _buildStatCard(
            icon: Icons.data_usage,
            value: '${_totalSize.toStringAsFixed(1)} MB',
            label: 'Total Size',
          ),
          const SizedBox(width: 8),
          _buildStatCard(
            icon: Icons.category,
            value: _categories.toString(),
            label: 'Categories',
          ),
        ],
      ),
    );
  }

  
  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChart() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: PieChart(
          dataMap: _fileDistribution,
          animationDuration: const Duration(milliseconds: 800),
          chartLegendSpacing: 32,
          chartRadius: MediaQuery.of(context).size.width / 3,
          colorList: const [
            Color(0xFFE94F4F),
            Color(0xFFFF8A8A),
            Color(0xFFFFB6B6),
            Color(0xFFFFE2E2),
          ],
          initialAngleInDegree: 0,
          chartType: ChartType.disc,
          legendOptions: const LegendOptions(
            showLegendsInRow: true,
            legendPosition: LegendPosition.bottom,
            showLegends: true,
            legendTextStyle: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          chartValuesOptions: const ChartValuesOptions(
            showChartValueBackground: true,
            showChartValues: true,
            showChartValuesInPercentage: true,
            showChartValuesOutside: false,
          ),
        ),
      ),
    );
  }

  Widget _buildFileList() {
    if (_isEditingFileTypes) {
      return _buildFileTypeEditor();
    }

    if (_isAnalyzing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Processing files: $_processedFiles / $_totalFilesToProcess',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_processedFiles > 0 && _totalFilesToProcess > 0)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: LinearProgressIndicator(
                  value: _processedFiles / _totalFilesToProcess,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      );
    }
  
    if (_selectedFiles.isEmpty) {
      return const Center(
        child: Text('No files analyzed yet'),
      );
    }

    var filteredFiles = _selectedFiles.where((file) {
      return file.path.toLowerCase().contains(_searchQuery);
    }).toList();

    // Group files by type
    Map<String, List<File>> groupedFiles = {};
    for (var file in filteredFiles) {
      String ext = file.path.split('.').last.toLowerCase();
      String type = _getFileType(ext);
      groupedFiles[type] = groupedFiles[type] ?? [];
      groupedFiles[type]!.add(file as File);
    }

    
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: groupedFiles.length,
      itemBuilder: (context, index) {
        String type = groupedFiles.keys.elementAt(index);
        List<File> files = groupedFiles[type]!;

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: _getFileTypeIcon(type),
            title: Text(
              type.toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            subtitle: Text(
              '${files.length} file${files.length == 1 ? '' : 's'}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            backgroundColor: Colors.white,
            collapsedBackgroundColor: Colors.white,
            children: [
              Column(
                children: files.map<Widget>((file) {
                  final analysis = _fileAnalysis[file.path];
                  return Card(
                    margin:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    child: ExpansionTile(
                      leading: _getFileTypeIcon(file.path),
                      title: Text(
                        file.path.split('/').last,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _getFileType(
                                file.path.split('.').last.toLowerCase()),
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          if (analysis == null)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Analyzing...',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (analysis['duplicate'] != null)
                            _buildDuplicateIndicator(analysis['duplicate']),
                        ],
                      ),
                      backgroundColor: Colors.white,
                      collapsedBackgroundColor: Colors.white,
                      children: [
                        if (analysis != null) ...[
                          if (analysis['photo'] != null)
                            _buildPhotoAnalysis(analysis['photo']),
                          if (analysis['content'] != null)
                            _buildContentAnalysis(analysis['content']),
                          if (analysis['duplicate'] != null)
                            _buildDuplicateAnalysis(analysis['duplicate']),
                          if (analysis['tags'] != null)
                            _buildTagAnalysis(analysis['tags']),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
              // )
            ],
          ),
        );
      },
      // ),
    );
  }

  
  Widget _buildPhotoAnalysis(ClassificationResult result) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Photo Classification:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...List.generate(
            result.mlLabels.length,
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${result.mlLabels[i]} (${(result.confidences[i] * 100).toStringAsFixed(1)}%)',
              ),
            ),
          ),
        ],
      ),
    );
  }

  
  Widget _buildContentAnalysis(ContentClassificationResult result) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Content Analysis:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('Type: ${result.contentType}'),
          if (result.contentType == 'chat' && result.chatAnalysis != null) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Chat Analysis:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  icon: Icon(
                    _expandedChatMessages[result.hashCode.toString()] ?? false
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                  ),
                  label: Text(
                    _expandedChatMessages[result.hashCode.toString()] ?? false
                        ? 'Show Less'
                        : 'Show All',
                  ),
                  onPressed: () {
                    setState(() {
                      _expandedChatMessages[result.hashCode.toString()] =
                          !(_expandedChatMessages[result.hashCode.toString()] ??
                              false);
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...(_expandedChatMessages[result.hashCode.toString()] ?? false
                    ? result.chatAnalysis!
                    : result.chatAnalysis!.take(3))
                .map((message) => Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Container(
                        padding: const EdgeInsets.all(8.0),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              message['message'] ?? '',
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Label: ${message['label'] ?? 'Unknown'}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ))
                .toList(),
            if (!(_expandedChatMessages[result.hashCode.toString()] ?? false) &&
                result.chatAnalysis!.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  '${result.chatAnalysis!.length - 3} more messages...',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
          if (result.transcribedText != null &&
              result.transcribedText!.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Transcribed Text:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(result.transcribedText!),
          ],
          if (result.category != null) ...[
            const SizedBox(height: 8),
            Text('Speech Category: ${result.category}',
                style: TextStyle(
                    color: result.category == 'hate_speech'
                        ? Colors.red
                        : Colors.green,
                    fontWeight: FontWeight.bold)),
          ],
          const SizedBox(height: 8),
          const Text('Keywords:',
              style: TextStyle(fontWeight: FontWeight.bold)),
          Wrap(
            spacing: 8,
            children: result.detectedKeywords
                .map((keyword) => Chip(label: Text(keyword)))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDuplicateIndicator(DuplicateDetectionResult result) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(
            result.isDuplicate ? Icons.warning : Icons.check_circle,
            color: result.isDuplicate ? Colors.red : Colors.green,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            result.isDuplicate ? 'Duplicate' : 'Unique',
            style: TextStyle(
              color: result.isDuplicate ? Colors.red : Colors.green,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildDuplicateAnalysis(DuplicateDetectionResult result) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                result.isDuplicate ? Icons.warning : Icons.check_circle,
                color: result.isDuplicate ? Colors.red : Colors.green,
              ),
              const SizedBox(width: 8),
              Text(
                result.isDuplicate
                    ? 'Duplicate Detected'
                    : 'No Duplicates Found',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (result.isDuplicate) ...[
            const SizedBox(height: 8),
            Text('Matched with: ${result.matchedWith}'),
            Text(
                'Similarity: ${(result.similarityScore * 100).toStringAsFixed(1)}%'),
          ],
        ],
      ),
    );
  }

  Widget _buildTagAnalysis(AutoTaggingResult result) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Auto-generated Tags:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              result.tags.length,
              (i) => Chip(
                label: Text(result.tags[i]),
                avatar: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(
                    '${(result.confidences[i] * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _getFileTypeIcon(String path) {
    final extension = path.split('.').last.toLowerCase();
    final type = _getFileType(extension);

    switch (type) {
      case 'chats':
        return Icon(Icons.chat, color: Theme.of(context).colorScheme.primary);
      case 'images':
        return Icon(Icons.image, color: Theme.of(context).colorScheme.primary);
      case 'documents':
        return Icon(Icons.description,
            color: Theme.of(context).colorScheme.primary);
      case 'multimedia':
        return Icon(Icons.play_circle,
            color: Theme.of(context).colorScheme.primary);
      case 'code':
        return Icon(Icons.code, color: Theme.of(context).colorScheme.primary);
      case 'archives':
        return Icon(Icons.folder_zip,
            color: Theme.of(context).colorScheme.primary);
      case 'spreadsheets':
        return Icon(Icons.table_chart,
            color: Theme.of(context).colorScheme.primary);
      case 'presentations':
        return Icon(Icons.slideshow,
            color: Theme.of(context).colorScheme.primary);
      case 'databases':
        return Icon(Icons.storage,
            color: Theme.of(context).colorScheme.primary);
      case 'fonts':
        return Icon(Icons.text_fields,
            color: Theme.of(context).colorScheme.primary);
      case 'system':
        return Icon(Icons.settings_applications,
            color: Theme.of(context).colorScheme.primary);
      default:
        return Icon(Icons.insert_drive_file,
            color: Theme.of(context).colorScheme.primary);
    }
  }

  Widget _buildFileTypeEditor() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _fileTypeMappings.length,
      itemBuilder: (context, index) {
        final type = _fileTypeMappings.keys.elementAt(index);
        final extensions = _fileTypeMappings[type]!;

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: _getFileTypeIcon(type),
            title: Text(
              type.toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            subtitle: Text(
              '${extensions.length} extension${extensions.length == 1 ? '' : 's'}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: extensions
                          .map((ext) => Chip(
                                label: Text(ext),
                                deleteIcon: const Icon(Icons.close, size: 18),
                                onDeleted: () => _removeExtension(type, ext),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _showAddExtensionDialog(type),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Extension'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showHostConfigDialog(BuildContext context) {
    final apiConfig = Provider.of<ApiConfig>(context, listen: false);
    final controller = TextEditingController(text: apiConfig.host);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configure API Host'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Host Address',
                hintText: 'e.g., 192.168.1.2',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Current host: ${apiConfig.getEffectiveHost()}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              apiConfig.resetHost();
              Navigator.pop(context);
            },
            child: const Text('Reset to Default'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                apiConfig.setHost(controller.text);
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _photoClassifier.dispose();
    _contentClassifier.dispose();
    _duplicateDetector.dispose();
    _autoTagger.dispose();
    super.dispose();
  }
}

}

