import 'dart:convert';
import 'package:ml_practice/models/report_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReportHistoryService {
  static const String _storageKey = 'report_history';

  Future<void> addReport(ReportHistory report) async {
    final prefs = await SharedPreferences.getInstance();
    final reports = await getReports();
    reports.add(report);

    // Save only the last 50 reports to prevent excessive storage usage
    if (reports.length > 50) {
      reports.removeAt(0);
    }

    await prefs.setString(
      _storageKey,
      jsonEncode(reports.map((r) => r.toJson()).toList()),
    );
  }

  Future<List<ReportHistory>> getReports() async {
    final prefs = await SharedPreferences.getInstance();
    final reportsJson = prefs.getString(_storageKey);

    if (reportsJson == null) {
      return [];
    }

    final List<dynamic> decodedList = jsonDecode(reportsJson);
    return decodedList
        .map((json) => ReportHistory.fromJson(json))
        .toList()
        .reversed // Show newest reports first
        .toList();
  }

  Future<void> deleteReport(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final reports = await getReports();

    reports.removeWhere((report) => report.filePath == filePath);

    await prefs.setString(
      _storageKey,
      jsonEncode(reports.map((r) => r.toJson()).toList()),
    );
  }
}
