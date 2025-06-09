class ReportHistory {
  final String filePath;
  final String fileName;
  final DateTime generatedAt;
  final String fileType; // 'pdf' or 'xlsx'
  final int totalFiles;

  ReportHistory({
    required this.filePath,
    required this.fileName,
    required this.generatedAt,
    required this.fileType,
    required this.totalFiles,
  });

  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'fileName': fileName,
      'generatedAt': generatedAt.toIso8601String(),
      'fileType': fileType,
      'totalFiles': totalFiles,
    };
  }

  factory ReportHistory.fromJson(Map<String, dynamic> json) {
    return ReportHistory(
      filePath: json['filePath'],
      fileName: json['fileName'],
      generatedAt: DateTime.parse(json['generatedAt']),
      fileType: json['fileType'],
      totalFiles: json['totalFiles'],
    );
  }
}
