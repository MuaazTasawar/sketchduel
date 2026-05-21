import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sketchduel_app/core/constants/app_constants.dart';

class ApiDatasource {
  final String _base = AppConstants.baseUrl;

  Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final res = await http.post(
      Uri.parse('$_base$endpoint'),
      headers: _headers(token),
      body: jsonEncode(body),
    );
    if (res.statusCode >= 400) {
      throw Exception('API Error ${res.statusCode}: ${res.body}');
    }
    return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
  }

  Future<dynamic> get(String endpoint, {String? token}) async {
    final res = await http.get(
      Uri.parse('$_base$endpoint'),
      headers: _headers(token),
    );
    if (res.statusCode >= 400) {
      throw Exception('API Error ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body);
  }
}