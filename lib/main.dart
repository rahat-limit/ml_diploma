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
