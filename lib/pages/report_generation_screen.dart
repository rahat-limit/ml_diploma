// import 'package:diploma/models/app_colors.dart';
// import 'package:diploma/models/file_info.dart';
// import 'package:diploma/screens/expanded_button.dart';
// import 'package:diploma/services/analysis_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:ml_practice/models/app_colors.dart';
import 'package:ml_practice/widgets/expanded_button.dart';
import 'package:ml_practice/models/report_history.dart';
import 'package:ml_practice/services/report_history_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:path/path.dart' as path;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' as excel;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'dart:convert';

class ReportGenerationScreen extends StatefulWidget {
  final Map<String, dynamic> reportData;

  const ReportGenerationScreen({
    super.key,
    required this.reportData,
  });

  @override
  State<ReportGenerationScreen> createState() => _ReportGenerationScreenState();
}

class _ReportGenerationScreenState extends State<ReportGenerationScreen> {
  int selectedIndex = 0;
  bool isLoading = false;
  Map<String, dynamic>? _reportData;
  final ReportHistoryService _historyService = ReportHistoryService();

  @override
  void initState() {
    super.initState();
    _reportData = widget.reportData;
  }

  Future<void> _generateReport() async {
    if (_reportData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No report data available')),
      );
      return;
    }

    // Request storage permissions for Android
    if (Platform.isAndroid) {
      // Check if we already have the permissions
      final manageStorageStatus = await Permission.manageExternalStorage.status;
      final storageStatus = await Permission.storage.status;

      if (manageStorageStatus.isGranted || storageStatus.isGranted) {
        // We have the necessary permissions, proceed
      } else {
        final result = await Permission.manageExternalStorage.request();
        if (!result.isGranted) {
          // Try regular storage permission as fallback
          final storageResult = await Permission.storage.request();
          if (!storageResult.isGranted) {
            // Both permission requests failed, show settings dialog
            if (!mounted) return;
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Permission Required'),
                content: const Text(
                    'Storage permission is required to save reports. Please enable storage permissions in settings.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await openAppSettings();
                    },
                    child: const Text('Open Settings'),
                  ),
                ],
              ),
            );
            return;
          }
        }
      }
    }

    setState(() {
      isLoading = true;
    });

    try {
      final now = DateTime.now();
      final timestamp =
          "${now.year}${now.month}${now.day}_${now.hour}${now.minute}";
      final fileType = selectedIndex == 0
          ? "xlsx"
          : selectedIndex == 1
              ? "pdf"
              : "json";
      final filename = 'cyber_threat_report_$timestamp.$fileType';

      // Get the downloads directory
      Directory? directory;
      if (Platform.isAndroid) {
        // Try to get the Downloads directory
        try {
          directory = await getExternalStorageDirectory();
          // Navigate up to get to the root of external storage
          String newPath = "";
          List<String> paths = directory!.path.split("/");
          for (int x = 1; x < paths.length; x++) {
            String folder = paths[x];
            if (folder != "Android") {
              newPath += "/" + folder;
            } else {
              break;
            }
          }
          newPath = newPath + "/Download";
          directory = Directory(newPath);
        } catch (e) {
          // Fallback to app's documents directory if external storage is not accessible
          directory = await getApplicationDocumentsDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory == null) {
        throw Exception('Could not access storage directory');
      }

      // Create directory if it doesn't exist
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final filePath = path.join(directory.path, filename);

      if (selectedIndex == 0) {
        // Excel
        await _generateExcelReport(directory.path, filename);
      } else if (selectedIndex == 1) {
        // PDF
        await _generatePdfReport(directory.path, filename);
      } else {
        // JSON
        await _generateJsonReport(directory.path, filename);
      }

      // Save to report history
      await _historyService.addReport(
        ReportHistory(
          filePath: filePath,
          fileName: filename,
          generatedAt: DateTime.now(),
          fileType: selectedIndex == 0
              ? 'xlsx'
              : selectedIndex == 1
                  ? 'pdf'
                  : 'json',
          totalFiles: _reportData!['totalFiles'],
        ),
      );

      // Show success dialog with options
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Report Generated'),
          content: Text('Report saved to:\n$filePath'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
            TextButton(
              onPressed: () async {
                await Share.shareXFiles([XFile(filePath)],
                    text: 'Cyber Threat Report');
                if (!mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Share'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating report: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  String _getThreatLevel() {
    final suspiciousFiles = _reportData!['suspiciousFiles'] as List;
    final securitySummary =
        _reportData!['securitySummary'] as Map<String, dynamic>;

    // Determine threat level based on analysis
    if (suspiciousFiles.isNotEmpty ||
        (securitySummary['filesWithSensitiveData'] as Map).isNotEmpty) {
      return '🚨 High';
    } else if (_reportData!['totalFiles'] > 0) {
      return '⚠️ Medium';
    } else {
      return '✅ Low';
    }
  }

  Future<void> _generatePdfReport(String directory, String filename) async {
    // Use minimal page format
    final pageFormat = PdfPageFormat.a5.copyWith(
      marginLeft: 10,
      marginRight: 10,
      marginTop: 10,
      marginBottom: 10,
    );

    // Use minimal PDF settings
    final pdf = pw.Document(
      compress: true,
      version: PdfVersion.pdf_1_4,
      pageMode: PdfPageMode.none,
    );

    // Enable garbage collection
    await Future.delayed(const Duration(milliseconds: 100));
    await Future.microtask(() => null);

    final theme = pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
    );

    // Constants for minimal data processing
    const int itemsPerPage = 2; // Process minimal items per page

    // Generate header and summary first
    pdf.addPage(await _generateHeaderAndSummaryPage(theme, pageFormat));

    // Process photo classifications with optimized data
    final photoClassifications = _reportData!['photoClassifications'] as Map;
    final optimizedPhotoData = Map.fromEntries(
      photoClassifications.entries.map((entry) {
        final data = entry.value as Map<String, dynamic>;
        // Take only first 3 ML labels and confidences to reduce data size
        final mlLabels = (data['mlLabels'] as List).take(3).toList();
        final confidences = (data['confidences'] as List).take(3).toList();
        return MapEntry(
          entry.key.split('/').last, // Use only filename
          {
            'category': data['category'],
            'mlLabels': mlLabels,
            'confidences': confidences,
          },
        );
      }),
    );

    await _processDataInChunks(
      pdf: pdf,
      theme: theme,
      data: optimizedPhotoData,
      sectionTitle: '3. Photo Classifications',
      sectionSubtitle: 'Photo Analysis Results',
      backgroundColor: PdfColors.green50,
      textColor: PdfColors.green900,
      itemsPerPage: itemsPerPage,
      processItem: (entry) => [
        _buildInfoRow('File', entry.key),
        _buildInfoRow('Category', (entry.value as Map)['category']),
        _buildInfoRow(
            'ML Labels', ((entry.value as Map)['mlLabels'] as List).join(', ')),
        _buildInfoRow(
          'Confidences',
          ((entry.value as Map)['confidences'] as List)
              .map((c) => (c * 100).toStringAsFixed(1) + '%')
              .join(', '),
        ),
        pw.SizedBox(height: 8),
      ],
    );

    // Clear memory
    optimizedPhotoData.clear();
    await Future.delayed(const Duration(milliseconds: 200));

    // Process content classifications with optimized data
    final contentClassifications =
        _reportData!['contentClassifications'] as Map;
    final optimizedContentData = Map.fromEntries(
      contentClassifications.entries.map((entry) {
        final data = entry.value as Map<String, dynamic>;
        // Take only first 5 keywords to reduce data size
        final keywords = (data['detectedKeywords'] as List).take(5).toList();
        return MapEntry(
          entry.key.split('/').last, // Use only filename
          {
            'contentType': data['contentType'],
            'detectedKeywords': keywords,
          },
        );
      }),
    );

    await _processDataInChunks(
      pdf: pdf,
      theme: theme,
      data: optimizedContentData,
      sectionTitle: '4. Content Classifications',
      sectionSubtitle: 'Content Analysis Results',
      backgroundColor: PdfColors.blue50,
      textColor: PdfColors.blue900,
      itemsPerPage: itemsPerPage,
      processItem: (entry) => [
        _buildInfoRow('File', entry.key),
        _buildInfoRow('Content Type', (entry.value as Map)['contentType']),
        _buildInfoRow('Keywords',
            ((entry.value as Map)['detectedKeywords'] as List).join(', ')),
        pw.SizedBox(height: 8),
      ],
    );

    // Clear memory
    optimizedContentData.clear();
    await Future.delayed(const Duration(milliseconds: 200));

    // Process duplicate detections with optimized data
    final duplicateDetections = _reportData!['duplicateDetections'] as Map;
    final optimizedDuplicateData = Map.fromEntries(
      duplicateDetections.entries.map((entry) {
        final data = entry.value as Map<String, dynamic>;
        return MapEntry(
          entry.key.split('/').last, // Use only filename
          {
            'isDuplicate': data['isDuplicate'],
            'matchedWith':
                data['isDuplicate'] ? (data['matchedWith'] ?? 'N/A') : 'N/A',
            'similarityScore': data['similarityScore'],
            'matchType': data['matchType'],
          },
        );
      }),
    );
    await _processDataInChunks(
      pdf: pdf,
      theme: theme,
      data: duplicateDetections,
      sectionTitle: '5. Duplicate Detections',
      sectionSubtitle: 'Duplicate Analysis Results',
      backgroundColor: PdfColors.orange50,
      textColor: PdfColors.orange900,
      itemsPerPage: itemsPerPage,
      processItem: (entry) {
        final data = entry.value as Map<String, dynamic>;
        return [
          _buildInfoRow('File', entry.key),
          _buildInfoRow('Is Duplicate', data['isDuplicate'].toString()),
          if (data['isDuplicate'])
            _buildInfoRow('Matched With', data['matchedWith'] ?? 'N/A'),
          _buildInfoRow('Similarity Score',
              '${(data['similarityScore'] * 100).toStringAsFixed(1)}%'),
          _buildInfoRow('Match Type', data['matchType']),
          pw.SizedBox(height: 8),
        ];
      },
    );

    // Process auto tags in chunks
    final autoTags = _reportData!['autoTags'] as Map;
    await _processDataInChunks(
      pdf: pdf,
      theme: theme,
      data: autoTags,
      sectionTitle: '6. Auto Tags',
      sectionSubtitle: 'Auto Tagging Results',
      backgroundColor: PdfColors.purple50,
      textColor: PdfColors.purple900,
      itemsPerPage: itemsPerPage,
      processItem: (entry) {
        final data = entry.value as Map<String, dynamic>;
        return [
          _buildInfoRow('File', entry.key),
          _buildInfoRow('Tags', (data['tags'] as List).join(', ')),
          _buildInfoRow(
            'Confidences',
            (data['confidences'] as List)
                .map((c) => (c * 100).toStringAsFixed(1) + '%')
                .join(', '),
          ),
          pw.SizedBox(height: 8),
        ];
      },
    );

    // Add performance metrics page
    pdf.addPage(await _generatePerformanceMetricsPage(theme, pageFormat));

    try {
      // Save with optimized memory usage
      final file = File('$directory/$filename');
      final bytes = await pdf.save();

      // Use buffered write with smaller chunks
      final stream = file.openWrite(mode: FileMode.write);
      const chunkSize = 512 * 1024; // 512KB chunks for better memory management

      for (var i = 0; i < bytes.length; i += chunkSize) {
        final end =
            (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        stream.add(bytes.sublist(i, end));
        // More frequent GC opportunities
        await Future.delayed(const Duration(milliseconds: 100));
        await Future.microtask(() => null);
      }

      await stream.flush();
      await stream.close();
    } catch (e) {
      print('Error saving PDF: $e');
      rethrow;
    }
  }

  Future<pw.Page> _generateHeaderAndSummaryPage(
      pw.ThemeData theme, PdfPageFormat pageFormat) async {
    return pw.MultiPage(
      theme: theme,
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.all(10),
      build: (context) => [
        _buildPdfHeader(),
        pw.SizedBox(height: 10),
        _buildPdfSection('1. Report Header', [
          _buildInfoRow('Incident Name', 'File Analysis Report'),
          _buildInfoRow('Date & Time', DateTime.now().toUtc().toString()),
          _buildInfoRow('Analyst Name', 'System Generated'),
          _buildInfoRow('Threat Level', _getThreatLevel(), isHighlight: true),
        ]),
        pw.SizedBox(height: 10),
        _buildPdfSection('2. Summary of Findings', [_buildPdfSummarySection()]),
      ],
    );
  }

  Future<pw.Page> _generatePerformanceMetricsPage(
      pw.ThemeData theme, PdfPageFormat pageFormat) async {
    return pw.MultiPage(
      theme: theme,
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.all(10),
      build: (context) => [
        _buildPdfSection('7. ML Model Performance', [
          _buildPdfNetworkAnalysisSection(),
        ]),
      ],
    );
  }

  Future<void> _processDataInChunks({
    required pw.Document pdf,
    required pw.ThemeData theme,
    required Map data,
    required String sectionTitle,
    required String sectionSubtitle,
    required PdfColor backgroundColor,
    required PdfColor textColor,
    required int itemsPerPage,
    required List<pw.Widget> Function(MapEntry) processItem,
  }) async {
    final entries = data.entries.toList();

    // Process in smaller chunks with memory cleanup
    for (var i = 0; i < entries.length; i += itemsPerPage) {
      // More aggressive memory cleanup
      await Future.delayed(const Duration(milliseconds: 200));
      // Force garbage collection
      await Future.microtask(() => null);

      final chunk = entries.skip(i).take(itemsPerPage).toList();
      final widgets = chunk.expand(processItem).toList();

      // Use minimal page format
      final pageFormat = PdfPageFormat.a5.copyWith(
        marginLeft: 10,
        marginRight: 10,
        marginTop: 10,
        marginBottom: 10,
      );

      pdf.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(10),
          maxPages: 1, // Limit pages per chunk
          build: (context) => [
            _buildPdfSection(sectionTitle, [
              _buildModelResultSection(
                sectionSubtitle,
                backgroundColor,
                textColor,
                widgets,
              ),
            ]),
          ],
        ),
      );

      // Add a small delay to allow memory cleanup
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  pw.Widget _buildPdfHeader() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue700,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
      ),
      child: pw.Center(
        child: pw.Text(
          'Cyber Threat Report',
          style: pw.TextStyle(
            color: PdfColors.white,
            fontSize: 20, // Reduced from 28
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    );
  }

  pw.Widget _buildPdfSection(String title, List<pw.Widget> children) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey300),
              ),
            ),
            child: pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 14, // Reduced from 18
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue700,
              ),
            ),
          ),
          pw.SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  pw.Widget _buildInfoRow(String label, String value,
      {bool isHighlight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 120,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                color: isHighlight ? PdfColors.red : PdfColors.black,
                fontWeight: isHighlight ? pw.FontWeight.bold : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfSummarySection() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildInfoRow(
            'Total Files Analyzed', '${_reportData!['totalFiles']} files'),
        _buildInfoRow('Processing Date', DateTime.now().toString()),
        pw.SizedBox(height: 20),

        // ML Model Results Summary
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.blue50,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'ML Model Analysis Summary',
                style: pw.TextStyle(
                  fontSize: 12, // Reduced from 16
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue900,
                ),
              ),
              pw.SizedBox(height: 8),
              _buildInfoRow('Photo Classifications',
                  '${(_reportData!['photoClassifications'] as Map).length} images processed'),
              _buildInfoRow('Content Classifications',
                  '${(_reportData!['contentClassifications'] as Map).length} files analyzed'),
              _buildInfoRow('Duplicate Detections',
                  '${(_reportData!['duplicateDetections'] as Map).length} comparisons made'),
              _buildInfoRow('Auto-Tagged Files',
                  '${(_reportData!['autoTags'] as Map).length} files tagged'),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _buildPdfFileAnalysisSection() {
    final photoClassifications = _reportData!['photoClassifications'] as Map;
    final contentClassifications =
        _reportData!['contentClassifications'] as Map;
    final duplicateDetections = _reportData!['duplicateDetections'] as Map;
    final autoTags = _reportData!['autoTags'] as Map;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Photo Classifications
        _buildModelResultSection(
          'Photo Classifications',
          PdfColors.green50,
          PdfColors.green900,
          photoClassifications.entries
              .map((e) {
                final data = e.value as Map<String, dynamic>;
                return [
                  _buildInfoRow('File', e.key),
                  _buildInfoRow('Category', data['category']),
                  _buildInfoRow(
                      'ML Labels', (data['mlLabels'] as List).join(', ')),
                  _buildInfoRow(
                      'Confidences',
                      (data['confidences'] as List)
                          .map((c) => (c * 100).toStringAsFixed(1) + '%')
                          .join(', ')),
                  pw.SizedBox(height: 8),
                ];
              })
              .expand((x) => x)
              .toList(),
        ),
        pw.SizedBox(height: 20),

        // Content Classifications
        _buildModelResultSection(
          'Content Classifications',
          PdfColors.blue50,
          PdfColors.blue900,
          contentClassifications.entries
              .map((e) {
                final data = e.value as Map<String, dynamic>;
                return [
                  _buildInfoRow('File', e.key),
                  _buildInfoRow('Content Type', data['contentType']),
                  _buildInfoRow('Keywords',
                      (data['detectedKeywords'] as List).join(', ')),
                  pw.SizedBox(height: 8),
                ];
              })
              .expand((x) => x)
              .toList(),
        ),
        pw.SizedBox(height: 20),

        // Duplicate Detections
        _buildModelResultSection(
          'Duplicate Detections',
          PdfColors.orange50,
          PdfColors.orange900,
          duplicateDetections.entries
              .map((e) {
                final data = e.value as Map<String, dynamic>;
                return [
                  _buildInfoRow('File', e.key),
                  _buildInfoRow('Is Duplicate', data['isDuplicate'].toString()),
                  if (data['isDuplicate'])
                    _buildInfoRow('Matched With', data['matchedWith'] ?? 'N/A'),
                  _buildInfoRow('Similarity Score',
                      '${(data['similarityScore'] * 100).toStringAsFixed(1)}%'),
                  _buildInfoRow('Match Type', data['matchType']),
                  pw.SizedBox(height: 8),
                ];
              })
              .expand((x) => x)
              .toList(),
        ),
        pw.SizedBox(height: 20),

        // Auto Tags
        _buildModelResultSection(
          'Auto Tags',
          PdfColors.purple50,
          PdfColors.purple900,
          autoTags.entries
              .map((e) {
                final data = e.value as Map<String, dynamic>;
                return [
                  _buildInfoRow('File', e.key),
                  _buildInfoRow('Tags', (data['tags'] as List).join(', ')),
                  _buildInfoRow(
                      'Confidences',
                      (data['confidences'] as List)
                          .map((c) => (c * 100).toStringAsFixed(1) + '%')
                          .join(', ')),
                  pw.SizedBox(height: 8),
                ];
              })
              .expand((x) => x)
              .toList(),
        ),
      ],
    );
  }

  pw.Widget _buildStatRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label),
          pw.Text(
            value,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfNetworkAnalysisSection() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'ML Model Performance',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey800,
            ),
          ),
          pw.SizedBox(height: 12),
          _buildInfoRow('Average Confidence (Photo Classification)',
              '${_calculateAverageConfidence(_reportData!['photoClassifications'])}%'),
          _buildInfoRow('Average Confidence (Auto Tagging)',
              '${_calculateAverageConfidence(_reportData!['autoTags'])}%'),
          _buildInfoRow('Duplicate Detection Accuracy',
              '${_calculateDuplicateDetectionAccuracy()}%'),
        ],
      ),
    );
  }

  String _calculateAverageConfidence(Map data) {
    if (data.isEmpty) return '0.0';
    double totalConfidence = 0.0;
    int count = 0;

    data.forEach((_, value) {
      final confidences =
          (value as Map<String, dynamic>)['confidences'] as List;
      totalConfidence +=
          confidences.fold(0.0, (sum, conf) => sum + (conf as num));
      count += confidences.length;
    });

    return count > 0
        ? (totalConfidence / count * 100).toStringAsFixed(1)
        : '0.0';
  }

  String _calculateDuplicateDetectionAccuracy() {
    final duplicates = _reportData!['duplicateDetections'] as Map;
    if (duplicates.isEmpty) return '0.0';

    int correctDetections = 0;
    duplicates.forEach((_, value) {
      final data = value as Map<String, dynamic>;
      if (data['isDuplicate'] && data['similarityScore'] > 0.8) {
        correctDetections++;
      }
    });

    return (correctDetections / duplicates.length * 100).toStringAsFixed(1);
  }

  pw.Widget _buildModelResultSection(
    String title,
    PdfColor backgroundColor,
    PdfColor textColor,
    List<pw.Widget> content,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: backgroundColor,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: textColor,
            ),
          ),
          pw.SizedBox(height: 12),
          ...content,
        ],
      ),
    );
  }

  Future<void> _generateJsonReport(String directory, String filename) async {
    final file = File('$directory/$filename');
    final jsonData = {
      'reportInfo': {
        'generatedAt': DateTime.now().toIso8601String(),
        'totalFiles': _reportData!['totalFiles'],
        'threatLevel': _getThreatLevel(),
      },
      'photoClassifications': _reportData!['photoClassifications'],
      'contentClassifications': _reportData!['contentClassifications'],
      'duplicateDetections': _reportData!['duplicateDetections'],
      'autoTags': _reportData!['autoTags'],
      'performance': {
        'photoClassificationConfidence':
            _calculateAverageConfidence(_reportData!['photoClassifications']),
        'autoTaggingConfidence':
            _calculateAverageConfidence(_reportData!['autoTags']),
        'duplicateDetectionAccuracy': _calculateDuplicateDetectionAccuracy(),
      }
    };

    await file.writeAsString(JsonEncoder.withIndent('  ').convert(jsonData));
  }

  Future<void> _generateExcelReport(String directory, String filename) async {
    final workbook = excel.Excel.createExcel();

    // Summary Sheet
    final summarySheet = workbook['Summary'];
    _addExcelHeader(summarySheet);
    _addExcelSummary(summarySheet);

    // File Analysis Sheet
    final analysisSheet = workbook['File Analysis'];
    _addFileAnalysis(analysisSheet);

    // Network Analysis Sheet
    final networkSheet = workbook['Network Analysis'];
    _addNetworkAnalysis(networkSheet);

    final file = File('$directory/$filename');
    await file.writeAsBytes(workbook.encode()!);
  }

  void _addExcelHeader(excel.Sheet sheet) {
    // Title
    final titleCell = sheet.cell(excel.CellIndex.indexByString("A1"));
    titleCell.value = excel.TextCellValue("Cyber Threat Report");
    titleCell.cellStyle = excel.CellStyle(
      bold: true,
      fontSize: 16,
    );
    sheet.merge(excel.CellIndex.indexByString("A1"),
        excel.CellIndex.indexByString("C1"));

    // Header info with styling
    final headers = [
      ["Incident Name", "Suspicious Email Phishing Attempt"],
      ["Date & Time", DateTime.now().toUtc().toString()],
      ["Analyst Name", "System Generated"],
      ["Threat Level", _getThreatLevel()],
    ];

    int row = 3;
    for (var header in headers) {
      final labelCell = sheet.cell(excel.CellIndex.indexByString("A$row"));
      final valueCell = sheet.cell(excel.CellIndex.indexByString("B$row"));

      labelCell.value = excel.TextCellValue(header[0]);
      valueCell.value = excel.TextCellValue(header[1]);

      labelCell.cellStyle = excel.CellStyle(
        bold: true,
      );

      if (header[0] == "Threat Level") {
        valueCell.cellStyle = excel.CellStyle(
          bold: true,
        );
      }

      row++;
    }
  }

  void _addExcelSummary(excel.Sheet sheet) {
    int row = 7;

    // Section header
    final headerCell = sheet.cell(excel.CellIndex.indexByString("A$row"));
    headerCell.value = excel.TextCellValue("ML Analysis Summary");
    headerCell.cellStyle = excel.CellStyle(
      bold: true,
      fontSize: 14,
    );
    sheet.merge(excel.CellIndex.indexByString("A$row"),
        excel.CellIndex.indexByString("C$row"));
    row += 2;

    // Summary data
    final summaryData = [
      ["Total Files Analyzed", _reportData!['totalFiles'].toString()],
      [
        "Photo Classifications",
        "${(_reportData!['photoClassifications'] as Map).length} images"
      ],
      [
        "Content Classifications",
        "${(_reportData!['contentClassifications'] as Map).length} files"
      ],
      [
        "Duplicate Detections",
        "${(_reportData!['duplicateDetections'] as Map).length} comparisons"
      ],
      [
        "Auto-Tagged Files",
        "${(_reportData!['autoTags'] as Map).length} files"
      ],
    ];

    for (var data in summaryData) {
      final labelCell = sheet.cell(excel.CellIndex.indexByString("A$row"));
      final valueCell = sheet.cell(excel.CellIndex.indexByString("B$row"));

      labelCell.value = excel.TextCellValue(data[0]);
      valueCell.value = excel.TextCellValue(data[1]);

      labelCell.cellStyle = excel.CellStyle(
        bold: true,
      );

      row++;
    }
  }

  void _addNetworkAnalysis(excel.Sheet sheet) {
    int row = 1;

    // Section header
    final headerCell = sheet.cell(excel.CellIndex.indexByString("A$row"));
    headerCell.value = excel.TextCellValue("ML Model Performance");
    headerCell.cellStyle = excel.CellStyle(
      bold: true,
      fontSize: 14,
    );
    sheet.merge(excel.CellIndex.indexByString("A$row"),
        excel.CellIndex.indexByString("C$row"));
    row += 2;

    // Performance metrics
    final metrics = [
      [
        "Average Confidence (Photo Classification)",
        "${_calculateAverageConfidence(_reportData!['photoClassifications'])}%"
      ],
      [
        "Average Confidence (Auto Tagging)",
        "${_calculateAverageConfidence(_reportData!['autoTags'])}%"
      ],
      [
        "Duplicate Detection Accuracy",
        "${_calculateDuplicateDetectionAccuracy()}%"
      ],
    ];

    for (var metric in metrics) {
      final labelCell = sheet.cell(excel.CellIndex.indexByString("A$row"));
      final valueCell = sheet.cell(excel.CellIndex.indexByString("B$row"));

      labelCell.value = excel.TextCellValue(metric[0]);
      valueCell.value = excel.TextCellValue(metric[1]);

      labelCell.cellStyle = excel.CellStyle(
        bold: true,
      );

      row++;
    }
  }

  void _addFileAnalysis(excel.Sheet sheet) {
    int row = 1;
    final photoClassifications = _reportData!['photoClassifications'] as Map;
    final contentClassifications =
        _reportData!['contentClassifications'] as Map;
    final duplicateDetections = _reportData!['duplicateDetections'] as Map;
    final autoTags = _reportData!['autoTags'] as Map;

    // Photo Classifications
    row = _addExcelSection(sheet, row, "Photo Classifications", [
      ["File", "Category", "ML Labels", "Confidences"],
      ...photoClassifications.entries.map((e) {
        final data = e.value as Map<String, dynamic>;
        return [
          e.key,
          data['category'],
          (data['mlLabels'] as List).join(', '),
          (data['confidences'] as List)
              .map((c) => (c * 100).toStringAsFixed(1) + '%')
              .join(', '),
        ];
      }),
    ]);

    row += 2;

    // Content Classifications
    row = _addExcelSection(sheet, row, "Content Classifications", [
      ["File", "Content Type", "Keywords"],
      ...contentClassifications.entries.map((e) {
        final data = e.value as Map<String, dynamic>;
        return [
          e.key,
          data['contentType'],
          (data['detectedKeywords'] as List).join(', '),
        ];
      }),
    ]);

    row += 2;

    // Duplicate Detections
    row = _addExcelSection(sheet, row, "Duplicate Detections", [
      [
        "File",
        "Is Duplicate",
        "Matched With",
        "Similarity Score",
        "Match Type"
      ],
      ...duplicateDetections.entries.map((e) {
        final data = e.value as Map<String, dynamic>;
        return [
          e.key,
          data['isDuplicate'].toString(),
          data['isDuplicate'] ? (data['matchedWith'] ?? 'N/A') : 'N/A',
          '${(data['similarityScore'] * 100).toStringAsFixed(1)}%',
          data['matchType'],
        ];
      }),
    ]);

    row += 2;

    // Auto Tags
    row = _addExcelSection(sheet, row, "Auto Tags", [
      ["File", "Tags", "Confidences"],
      ...autoTags.entries.map((e) {
        final data = e.value as Map<String, dynamic>;
        return [
          e.key,
          (data['tags'] as List).join(', '),
          (data['confidences'] as List)
              .map((c) => (c * 100).toStringAsFixed(1) + '%')
              .join(', '),
        ];
      }),
    ]);
  }

  int _addExcelSection(
      excel.Sheet sheet, int startRow, String title, List<List<String>> data) {
    // Add section title
    final titleCell = sheet.cell(excel.CellIndex.indexByString("A$startRow"));
    titleCell.value = excel.TextCellValue(title);
    titleCell.cellStyle = excel.CellStyle(
      bold: true,
      fontSize: 12,
    );
    sheet.merge(excel.CellIndex.indexByString("A$startRow"),
        excel.CellIndex.indexByString("E$startRow"));

    int currentRow = startRow + 2;

    // Add data rows
    for (var row in data) {
      for (var i = 0; i < row.length; i++) {
        final cell = sheet.cell(
          excel.CellIndex.indexByString(
              "${String.fromCharCode(65 + i)}$currentRow"),
        );
        cell.value = excel.TextCellValue(row[i]);

        // Style header row
        if (currentRow == startRow + 2) {
          cell.cellStyle = excel.CellStyle(
            bold: true,
            backgroundColorHex: excel.ExcelColor.fromHexString("#E3E3E3"),
          );
        }
      }
      currentRow++;
    }

    return currentRow;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text('Report Generation')),
        body: SafeArea(
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(children: [
                  Expanded(
                    child: Column(
                      children: [
                        SizedBox(height: 20),
                        Row(
                          children: [
                            box(
                                index: 0,
                                text: 'Sheet',
                                path: 'assets/svgs/excel_logo.png',
                                isActive: selectedIndex == 0),
                            SizedBox(width: 15),
                            box(
                                index: 1,
                                text: 'PDF',
                                path: 'assets/svgs/pdf_logo.png',
                                isActive: selectedIndex == 1),
                            SizedBox(width: 15),
                            box(
                                index: 2,
                                text: 'JSON',
                                path: 'assets/svgs/icons8-json-80.png',
                                isActive: selectedIndex == 2)
                          ],
                        ),
                        SizedBox(height: 20),
                        if (isLoading)
                          const CircularProgressIndicator()
                        else
                          ExpandedButton(
                              action: _generateReport,
                              text:
                                  'Export ${selectedIndex == 0 ? 'Excel' : selectedIndex == 1 ? 'PDF' : 'JSON'} Report'),
                        SizedBox(height: 20)
                      ],
                    ),
                  )
                ]))));
  }

  Widget box({
    required int index,
    required String text,
    required String path,
    required bool isActive,
  }) {
    return Expanded(
        child: Material(
      color:
          // ignore: deprecated_member_use
          isActive
              ? AppColors.primary.withOpacity(0.1)
              : AppColors.inputBackground,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () {
          setState(() {
            selectedIndex = index;
          });
        },
        child: Container(
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: isActive ? Border.all(color: AppColors.primary) : null),
          height: 120,
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [Image.asset(path), Text(text)]),
        ),
      ),
    ));
  }
}
