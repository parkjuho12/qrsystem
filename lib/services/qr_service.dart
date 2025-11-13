import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_constants.dart';
import '../services/auth_service.dart';

class QRService {
  static const _storage = FlutterSecureStorage();

  /// QR 코드 발급 API
  /// 
  /// [ticketCount]: 발급할 식권 수 (기본값: 1)
  /// 
  /// 반환값:
  /// - success: 성공 여부
  /// - qr_data: QR 코드 데이터 (성공 시)
  /// - expires_at: 만료 시간 (성공 시)
  /// - remaining_seconds: 남은 시간(초) (성공 시)
  /// - message: 에러 메시지 (실패 시)
  /// - need_login: 로그인 필요 여부 (토큰 만료 시)
  /// - existing_qr: 기존 QR 정보 (이미 발급된 QR이 있을 경우)
  static Future<Map<String, dynamic>> issueQR({int ticketCount = 1}) async {
    final token = await _storage.read(key: 'jwt_token');
    
    if (token == null) {
      return {
        'success': false,
        'message': '로그인이 필요합니다',
        'need_login': true,
      };
    }
    
    try {
      final response = await http.post(
        Uri.parse(ApiConstants.qrIssue),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'ticket_count': ticketCount,
        }),
      );
      
      // 토큰 만료 처리
      if (response.statusCode == 403 || response.statusCode == 401) {
        await AuthService.logout();
        return {
          'success': false,
          'message': '세션이 만료되었습니다. 다시 로그인해주세요.',
          'need_login': true,
        };
      }
      
      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200 && data['status'] == 'success') {
        return {
          'success': true,
          'qr_data': data['qr_data'],
          'expires_at': data['expires_at'],
          'remaining_seconds': data['remaining_seconds'],
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'QR 발급 실패',
          'existing_qr': data['existing_qr'], // 기존 QR이 있는 경우
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': '네트워크 오류: $e',
      };
    }
  }

  /// 현재 유효한 QR 조회 (선택적 기능)
  /// 
  /// 서버에 이 API가 있다면 활성화
  static Future<Map<String, dynamic>> getCurrentQR() async {
    final token = await _storage.read(key: 'jwt_token');
    
    if (token == null) {
      return {
        'success': false,
        'message': '로그인이 필요합니다',
      };
    }
    
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/api/qr/current'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 403 || response.statusCode == 401) {
        await AuthService.logout();
        return {
          'success': false,
          'message': '세션이 만료되었습니다.',
          'need_login': true,
        };
      }
      
      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200 && data['status'] == 'success') {
        return {
          'success': true,
          'qr_data': data['qr_data'],
          'expires_at': data['expires_at'],
          'remaining_seconds': data['remaining_seconds'],
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? '유효한 QR이 없습니다',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': '네트워크 오류: $e',
      };
    }
  }
}

