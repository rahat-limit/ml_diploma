import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart'; // для rootBundle
// import 'pdf_report_generator.dart';

// import 'history_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hate Speech Audio Detector',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _results = [];
  List<String> _filePaths = [];
  final AudioPlayer _audioPlayer = AudioPlayer();

  Future<void> _pickAndAnalyzeFiles() async {
    setState(() => _isLoading = true);

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.audio,
    );

    if (result == null) {
      setState(() => _isLoading = false);
      return;
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse("http://0.0.0.0:800/predict"),
    );

    final localPaths = <String>[];

    for (var file in result.files) {
      if (file.path != null) {
        request.files
            .add(await http.MultipartFile.fromPath('files', file.path!));
        localPaths.add(file.path!);
      }
    }

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();
    final data = json.decode(responseBody);

    final newResults = List<Map<String, dynamic>>.from(data['results']);

    // Добавим путь к каждому результату
    for (int i = 0; i < newResults.length; i++) {
      newResults[i]['path'] = localPaths[i];
    }

    setState(() {
      _results = newResults;
      _filePaths = localPaths;
      _isLoading = false;
    });

    // Save history to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList('analysis_history') ?? [];
    final updated = [...existing, ...newResults.map((e) => json.encode(e))];
    await prefs.setStringList('analysis_history', updated);
  }

  void _generatePdfReport() async {
    // final generator = PdfReportGenerator(results: _results);
    // await generator.generateAndPrintPdf();
  }

  Widget _buildTranscriptText(String transcript) {
    return Text(
      transcript,
      style: const TextStyle(fontSize: 16, color: Colors.black87),
    );
  }

  Future<void> _playAudio(String path) async {
    try {
      await _audioPlayer.stop(); // остановить предыдущее
      await _audioPlayer.play(DeviceFileSource(path));
    } catch (e) {
      debugPrint("Ошибка воспроизведения: $e");
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hate Speech Detector'),
        actions: [
          IconButton(icon: const Icon(Icons.history), onPressed: () {}
              // => Navigator.push(
              // context,
              // MaterialPageRoute(builder: (_) => const HistoryScreen()),
              // ),
              )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _results.isEmpty
                ? const Text("Нет данных")
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final result = _results[index];
                      final transcript = result['text'] ?? '';
                      final classification = result['category'] ?? 'неизвестно';
                      final filename = result['filename'] ?? 'Без названия';
                      final path = result['path'] ?? '';
                      final isDangerous = classification == 'manipulation' ||
                          classification == 'threat';
                      final classificationColor =
                          isDangerous ? Colors.red : Colors.black87;

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      "File: $filename",
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.blueGrey,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.play_arrow,
                                        color: Colors.deepPurple),
                                    tooltip: 'Прослушать аудио',
                                    onPressed: () => _playAudio(path),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "Classification: $classification",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: classificationColor,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _buildTranscriptText(transcript),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'upload',
            onPressed: _pickAndAnalyzeFiles,
            child: const Icon(Icons.upload_file),
            tooltip: 'Загрузить аудио',
          ),
          const SizedBox(height: 10),
          if (_results.isNotEmpty)
            FloatingActionButton(
              heroTag: 'pdf',
              onPressed: _generatePdfReport,
              backgroundColor: Colors.redAccent,
              child: const Icon(Icons.picture_as_pdf),
              tooltip: 'Создать PDF-отчёт',
            ),
        ],
      ),
    );
  }
}
