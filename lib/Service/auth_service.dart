import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  // Ganti dengan base URL API Anda
  final String baseUrl = 'http://192.168.18.18:8000/api';
  
  // Menyimpan token JWT
  String? _authToken;
  
  // Konstanta untuk key storage
  static const String TOKEN_KEY = 'auth_token';

  // Constructor dengan inisialisasi token
  AuthService() {
    _loadToken();
  }

  // Load token from storage
  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString(TOKEN_KEY);
    print('Loaded token: $_authToken'); // Debug print
  }

  // Save token to storage
  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(TOKEN_KEY, token);
    _authToken = token;
    print('Saved token: $_authToken'); // Debug print
  }

  // Clear token from storage
  Future<void> _clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(TOKEN_KEY);
    _authToken = null;
    print('Cleared token'); // Debug print
  }

  // Getter untuk token
  String? get token => _authToken;

  // Function untuk signup
  Future<Map<String, dynamic>> signup({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    try {
      // Basic validation
      if (name.isEmpty || email.isEmpty || password.isEmpty) {
        return {
          'success': false,
          'message': 'Please fill all fields'
        };
      }

      if (!email.contains('@')) {
        return {
          'success': false,
          'message': 'Invalid email format'
        };
      }

      if (password.length < 6) {
        return {
          'success': false,
          'message': 'Password must be at least 6 characters'
        };
      }

      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name.trim(),
          'email': email.trim(),
          'password': password,
          'role': role,
        }),
      );

      // First, safely get the response as a string
      final responseBody = response.body;
      
      // Try to decode the response, but handle potential format issues
      dynamic decodedResponse;
      try {
        decodedResponse = jsonDecode(responseBody);
      } catch (e) {
        return {
          'success': false,
          'message': 'Invalid response format: $responseBody'
        };
      }
      
      if (response.statusCode == 201) {
        // Check if the response contains a token, regardless of the response structure
        if (decodedResponse != null && 
            decodedResponse is Map && 
            decodedResponse['token'] != null) {
          _authToken = decodedResponse['token'].toString();
          return {
            'success': true,
            'message': 'Registration successful'
          };
        }
        return {
          'success': false,
          'message': 'Invalid response format: missing token'
        };
      } else {
        // Handle error response
        if (decodedResponse != null && 
            decodedResponse is Map && 
            decodedResponse['message'] != null) {
          return {
            'success': false,
            'message': decodedResponse['message'].toString()
          };
        }
        return {
          'success': false,
          'message': 'Registration failed: $responseBody'
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Registration error: ${e.toString()}'
      };
    }
  }

  // Function untuk login
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      if (email.isEmpty || password.isEmpty) {
        return {
          'success': false,
          'message': 'Please fill all fields'
        };
      }

      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim(),
          'password': password,
        }),
      );

      print('Login response status: ${response.statusCode}');
      print('Login response body: ${response.body}');

      final Map<String, dynamic> data = jsonDecode(response.body);
      
      if (response.statusCode == 200 && data['token'] != null) {
        await _saveToken(data['token'].toString());
        return {
          'success': true,
          'role': data['role']?.toString(),
          'message': 'Login successful'
        };
      } else {
        return {
          'success': false,
          'message': data['message']?.toString() ?? 'Login failed'
        };
      }
    } catch (e) {
      print('Login error: $e');
      return {
        'success': false,
        'message': 'Login error: ${e.toString()}'
      };
    }
  }

  // Function untuk logout
  Future<void> signOut() async {
    try {
      if (_authToken != null) {
        final response = await http.post(
          Uri.parse('$baseUrl/auth/logout'),
          headers: {
            'Authorization': 'Bearer $_authToken',
            'Content-Type': 'application/json',
          },
        );
        
        print('Logout response: ${response.statusCode}');
      }
    } catch (e) {
      print('Logout error: $e');
    } finally {
      // Selalu clear token
      await _clearToken();
    }
  }

  // Get current user info
  Future<Map<String, dynamic>?> getCurrentUser() async {
    if (_authToken == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/me'),
        headers: {
          'Authorization': 'Bearer $_authToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Error getting user info: $e');
      return null;
    }
  }

  // Update password
  Future<void> updatePassword(String oldPassword, String newPassword) async {
    // Reload token to ensure it's current
    await _loadToken();
    
    print('Current token for password update: $_authToken');

    if (_authToken == null || _authToken!.isEmpty) {
      throw Exception('Silakan login kembali');
    }

    try {
      final response = await http.put(
        Uri.parse('$baseUrl/auth/password'),
        headers: {
          'Authorization': 'Bearer $_authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'old_password': oldPassword,
          'new_password': newPassword,
        }),
      );

      print('Update password response: ${response.statusCode}');
      print('Update password body: ${response.body}');

      if (response.statusCode == 200) {
        return;
      } else if (response.statusCode == 401) {
        await _clearToken(); // Clear invalid token
        throw Exception('Silakan login kembali');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Gagal mengupdate password');
      }
    } catch (e) {
      if (e.toString().contains('401')) {
        await _clearToken(); // Clear invalid token
      }
      throw Exception('Gagal mengupdate password: ${e.toString()}');
    }
  }

  // Getter untuk mengecek status login
  Future<bool> get isLoggedIn async {
    await _loadToken();
    return _authToken != null && _authToken!.isNotEmpty;
  }
}
