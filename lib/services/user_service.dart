import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/api_constants.dart';

class UserService {
  /// 학번/사번으로 사용자 프로필 조회 (공개 API - 토큰 불필요)
  ///
  /// [employeeNumber]: 학번 또는 사번
  ///
  /// 반환값:
  /// - success: 성공 여부
  /// - user: 사용자 정보 (성공 시)
  ///   - employee_number: 학번/사번
  ///   - name: 이름
  ///   - role: 역할 (student/employee)
  ///   - profile_image: 프로필 이미지 파일명
  ///   - affiliation: 소속
  ///   - affiliation_code: 소속 코드
  /// - message: 에러 메시지 (실패 시)
  static Future<Map<String, dynamic>> getUserProfile(
    String employeeNumber,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.userProfile}/$employeeNumber'),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['status'] == 'success') {
        return {'success': true, 'user': data['data']};
      } else {
        return {'success': false, 'message': data['message'] ?? '프로필 조회 실패'};
      }
    } catch (e) {
      return {'success': false, 'message': '네트워크 오류: $e'};
    }
  }

  /// user_id로 사용자 프로필 조회 (공개 API - 토큰 불필요)
  ///
  /// [userId]: 사용자 ID
  ///
  /// 반환값: getUserProfile과 동일
  static Future<Map<String, dynamic>> getUserProfileById(int userId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/user/profile-by-id/$userId'),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['status'] == 'success') {
        return {'success': true, 'user': data['data']};
      } else {
        return {'success': false, 'message': data['message'] ?? '프로필 조회 실패'};
      }
    } catch (e) {
      return {'success': false, 'message': '네트워크 오류: $e'};
    }
  }

  /// 여러 사용자의 프로필을 한번에 조회 (선택적 기능)
  ///
  /// [employeeNumbers]: 학번/사번 리스트
  static Future<Map<String, dynamic>> getUserProfiles(
    List<String> employeeNumbers,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/user/profiles'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'employee_numbers': employeeNumbers}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['status'] == 'success') {
        return {'success': true, 'users': data['data']};
      } else {
        return {'success': false, 'message': data['message'] ?? '프로필 조회 실패'};
      }
    } catch (e) {
      return {'success': false, 'message': '네트워크 오류: $e'};
    }
  }
}
