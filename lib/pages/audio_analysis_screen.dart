import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:ml_practice/services/file_content_classifier_service.dart';

class AudioAnalysisScreen extends StatefulWidget {
  const AudioAnalysisScreen({super.key});

  @override
  State<AudioAnalysisScreen> createState() => _AudioAnalysisScreenState();
}

class _AudioAnalysisScreenState extends State<AudioAnalysisScreen> {
  bool _isLoading = false;
  List<ContentClassificationResult> _results = [];
  List<String> _filePaths = [];
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FileContentClassifierService _classifierService =
      FileContentClassifierService();

  @override
  void initState() {
    super.initState();
    _classifierService.initialize();
  }

  Future<void> _pickAndAnalyzeFiles() async {
    setState(() => _isLoading = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.audio,
      );

      if (result == null) {
        setState(() => _isLoading = false);
        return;
      }

      final newResults = <ContentClassificationResult>[];
      final localPaths = <String>[];

      for (var file in result.files) {
        if (file.path != null) {
          final analysisResult = await _classifierService.classifyContent(
              File(file.path!), context);
          newResults.add(analysisResult);
          localPaths.add(file.path!);
        }
      }

      setState(() {
        _results = newResults;
        _filePaths = localPaths;
        _isLoading = false;
      });
    } catch (e) {
      print('Error analyzing files: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error analyzing files: $e')),
        );
      }
    }
  }

  Future<void> _playAudio(String path) async {
    try {
      await _audioPlayer.stop(); // stop previous playback
      await _audioPlayer.play(DeviceFileSource(path));
    } catch (e) {
      debugPrint("Error playing audio: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error playing audio: $e')),
        );
      }
    }
  }

  Widget _buildTranscriptText(String transcript) {
    return Text(
      transcript,
      style: const TextStyle(fontSize: 16, color: Colors.black87),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _classifierService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Analysis'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _results.isEmpty
                ? const Center(child: Text("No audio files analyzed"))
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final result = _results[index];
                      final transcript = result.transcribedText ?? '';
                      final category = result.category ?? 'unknown';
                      final filename = _filePaths[index].split('/').last;
                      final path = _filePaths[index];
                      final isDangerous =
                          category == 'manipulation' || category == 'threat';
                      final categoryColor =
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
                                    tooltip: 'Play audio',
                                    onPressed: () => _playAudio(path),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "Category: $category",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: categoryColor,
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
      floatingActionButton: FloatingActionButton(
        onPressed: _pickAndAnalyzeFiles,
        child: const Icon(Icons.upload_file),
        tooltip: 'Upload audio',
      ),
    );
  }
}
