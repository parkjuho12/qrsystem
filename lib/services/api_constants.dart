class ApiConstants {
  // 개발 환경에서는 실제 네트워크 IP 사용
  // localhost나 127.0.0.1 대신 실제 IP 주소 사용
  static const String baseUrl = "https://qr.pjhpjh.kr/seahawk1  ";
  

  // 인증 관련
  static const String login = "$baseUrl/auth/login";
  static const String logout = "$baseUrl/auth/logout";
  static const String me = "$baseUrl/auth/me";

  // QR 발급
  static const String qrIssue = "$baseUrl/qr/issue";

  // 사용자 프로필
  static const String userProfile = "$baseUrl/user/profile";

  // 결제 관련
  static const String verifyQr = "$baseUrl/payment/verify-qr";
  static const String recordPayment = "$baseUrl/payment/record";
  static const String myPayments = "$baseUrl/payment/my-payments"; // 개인 결제 내역 조회 (JWT 필수)
  static const String paymentsByEmployee = "$baseUrl/payment/payments";
  static const String cancelPayment = "$baseUrl/payment/cancel";
  static const String refundPayment = "$baseUrl/payment/refund";
  
  /// 이미지 URL 생성 헬퍼 함수
  ///
  /// 서버에서 반환된 파일명으로 이미지 URL을 생성합니다.
  /// [filename]이 null이거나 비어있으면 기본 이미지를 반환합니다.
  ///
  /// 예시: getImageUrl('1.jpeg') -> 'http://192.168.1.203:8080/images/1.jpeg'
  static String getImageUrl(String? filename) {
    if (filename == null || filename.isEmpty) {
      filename = '1.jpeg'; // 기본 이미지
    }

    // 개발 환경에서 로컬 이미지 사용 (서버 이미지 문제 시)
    // return 'assets/images/$filename'; // 로컬 에셋 사용 시

    return '$baseUrl/images/$filename';
  }
}
  