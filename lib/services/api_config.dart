import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiConfig extends ChangeNotifier {
  static final ApiConfig _instance = ApiConfig._internal();
  factory ApiConfig() => _instance;
  ApiConfig._internal();

  String _host = 'localhost';
  bool _isCustomHost = false;

  String get host => _host;
  bool get isCustomHost => _isCustomHost;

  void setHost(String newHost) {
    _host = newHost;
    _isCustomHost = true;
    notifyListeners();
  }

  void resetHost() {
    _host = 'localhost';
    _isCustomHost = false;
    notifyListeners();
  }

  // Future<bool> isHostReachable(String host) async {
  //   try {
  //     final response = await http
  //         .get(Uri.parse('http://$host:8001/health'))
  //         .timeout(const Duration(seconds: 5));
  //     return response.statusCode == 200;
  //   } catch (e) {
  //     debugPrint('Host $host not reachable: $e');
  //     return false;
  //   }
  // }

  Future<String> get defaultPlatformHost async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      // First try emulator host
      // if (await isHostReachable('10.0.2.2')) {
      //   return '10.0.2.2';
      // }
      // // Then try local network IP
      // if (await isHostReachable('192.168.3.49')) {
      //   return '192.168.3.49';
      // }
      // // Finally try localhost
      // if (await isHostReachable('localhost')) {
      //   return 'localhost';
      // }
      return '10.0.2.2'; // Default to local network IP if nothing works
    }
    return 'localhost'; // iOS or other platforms
  }

  Future<String> getEffectiveHostAsync() async {
    if (_isCustomHost) return _host;
    return await defaultPlatformHost;
  }

  String getEffectiveHost() {
    if (_isCustomHost) return _host;
    // For sync calls, try to use a more reliable default
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Try to use the Android emulator's host address first
      return '10.0.2.2';
    }
    return 'localhost';
  }

  // Helper method to get base URL with error handling
  Future<String> getBaseUrl() async {
    try {
      final host = await getEffectiveHostAsync();
      return 'http://$host:8001';
    } catch (e) {
      debugPrint('Error getting base URL: $e');
      throw Exception(
          'Failed to determine server address. Please check your network connection and server status.');
    }
  }
}
