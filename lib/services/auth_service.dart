import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_constants.dart';

class AuthService {
  static String? _token;
  static Map<String, dynamic>? _user;
  static const _storage = FlutterSecureStorage();

  // JWT 토큰 가져오기
  static String? get token => _token;

  // 현재 사용자 정보 가져오기
  static Map<String, dynamic>? get user => _user;

  // 로그인
  static Future<Map<String, dynamic>> login(String employeeNumber, String password) async {
    // 로그인 전에 기존 토큰 제거 (혹시 모를 충돌 방지)
    _token = null;
    _user = null;

    try {
      final response = await http.post(
        Uri.parse(ApiConstants.login),
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          'employee_number': employeeNumber,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        try {
          final Map<String, dynamic> responseData = jsonDecode(response.body.trim());
          
          if (responseData['status'] == 'success') {
            // 토큰과 사용자 정보 저장
            _token = responseData['token'];
            
            // 'data' 또는 'user' 중 존재하는 것을 사용
            _user = responseData['data'] ?? responseData['user'];
            
            if (_user == null) {
              return {"status": "fail", "message": "사용자 정보를 찾을 수 없습니다"};
            }
            
            // FlutterSecureStorage에 토큰 저장 (보안 강화)
            await _storage.write(key: 'jwt_token', value: _token!);
            await _storage.write(key: 'user_data', value: jsonEncode(_user));
          }
          
          return responseData;
        } catch (e) {
          return {"status": "fail", "message": "서버 응답 처리 실패"};
        }
      } else {
        return {"status": "fail", "message": "서버 연결 실패 (HTTP ${response.statusCode})"};
      }
    } catch (e) {
      if (e.toString().contains('Connection refused')) {
        return {"status": "fail", "message": "서버에 연결할 수 없습니다. 서버가 실행 중인지 확인해주세요."};
      } else if (e.toString().contains('Network is unreachable')) {
        return {"status": "fail", "message": "네트워크에 연결할 수 없습니다."};
      }
      return {"status": "fail", "message": "네트워크 오류가 발생했습니다: $e"};
    }
  }

  // 로그아웃
  static Future<Map<String, dynamic>> logout() async {
    if (_token == null) {
      return {"status": "fail", "message": "로그인되지 않음"};
    }

    final response = await http.post(
      Uri.parse(ApiConstants.logout),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $_token",
      },
    );

    // 로컬 데이터 정리
    _token = null;
    _user = null;
    
    // FlutterSecureStorage에서 토큰 삭제
    await _storage.delete(key: 'jwt_token');
    await _storage.delete(key: 'user_data');

    if (response.statusCode == 200) {
      try {
        final Map<String, dynamic> responseData = jsonDecode(response.body.trim());
        return responseData;
      } catch (e) {
        return {"status": "success", "message": "로그아웃 완료"};
      }
    }
    return {"status": "success", "message": "로그아웃 완료"};
  }

  // 현재 사용자 정보 조회
  static Future<Map<String, dynamic>> getCurrentUser() async {
    if (_token == null) {
      return {"status": "fail", "message": "로그인되지 않음"};
    }

    final response = await http.get(
      Uri.parse(ApiConstants.me),
      headers: {
        "Authorization": "Bearer $_token",
      },
    );

    if (response.statusCode == 200) {
      try {
        final Map<String, dynamic> responseData = jsonDecode(response.body.trim());
        if (responseData['status'] == 'success') {
          _user = responseData['user'];
        }
        return responseData;
      } catch (e) {
        return {"status": "fail", "message": "사용자 정보 조회 실패"};
      }
    }
    return {"status": "fail", "message": "인증 실패"};
  }

  // 앱 시작 시 저장된 토큰 복원
  static Future<void> restoreSession() async {
    final token = await _storage.read(key: 'jwt_token');
    final userData = await _storage.read(key: 'user_data');

    if (token != null && userData != null) {
      _token = token;
      try {
        _user = jsonDecode(userData);
      } catch (e) {
        _token = null;
        _user = null;
        await _storage.delete(key: 'jwt_token');
        await _storage.delete(key: 'user_data');
      }
    }
  }

  // 토큰 가져오기 (비동기)
  static Future<String?> getToken() async {
    if (_token != null) return _token;
    return await _storage.read(key: 'jwt_token');
  }

  // 로그인 상태 확인
  static bool get isLoggedIn => _token != null && _user != null;
  
  // 토큰 만료 체크 및 자동 로그아웃
  static Future<bool> checkTokenExpired(int statusCode) async {
    if (statusCode == 401 || statusCode == 403) {
      await logout();
      return true; // 토큰 만료됨
    }
    return false;
  }

  // 토큰 유효성 검증 (서버에 확인)
  static Future<bool> validateToken() async {
    if (_token == null) return false;
    
    try {
      final response = await http.get(
        Uri.parse(ApiConstants.me),
        headers: {
          "Authorization": "Bearer $_token",
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['status'] == 'success') {
          // 토큰이 유효하면 사용자 정보 업데이트
          _user = data['data'] ?? data['user'];
          
          // FlutterSecureStorage에도 저장해야 다음 로드 시 유지됨
          if (_user != null) {
            await _storage.write(key: 'user_data', value: jsonEncode(_user));
          }
          
          return true;
        }
      }
      
      // 401/403이면 토큰 만료
      if (response.statusCode == 401 || response.statusCode == 403) {
        return false;
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }
}
