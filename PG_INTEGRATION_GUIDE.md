# 💳 PG 결제 연동 구현 가이드

> **프로젝트**: KBU QR 시스템 포인트 충전 기능  
> **현재 상태**: 가상 충전 (실제 결제 없이 포인트만 추가)  
> **목표**: 실제 PG 결제 시스템 연동 (토스페이먼츠 권장)

---

## 📋 목차
1. [현재 시스템 분석](#1-현재-시스템-분석)
2. [준비사항](#2-준비사항)
3. [구현 단계](#3-구현-단계)
4. [테스트 방법](#4-테스트-방법)
5. [운영 배포](#5-운영-배포)
6. [트러블슈팅](#6-트러블슈팅)

---

## 1. 현재 시스템 분석

### 1.1 이미 구현된 기능
✅ **Flutter 앱** (`lib/screens/charge_screen.dart`)
- 충전 금액 입력 UI
- 결제 확인 다이얼로그
- 로딩 상태 관리
- 성공/실패 오버레이

✅ **서버 API** (`jsp/add_points.jsp`)
- 포인트 추가 로직
- 사용자 검증

✅ **설치된 패키지** (`pubspec.yaml`)
```yaml
tosspayments_widget_sdk_flutter: ^2.1.1
toss_payment: ^0.2.7
webview_flutter: ^4.2.2
```

### 1.2 현재 결제 플로우

```
[사용자] 금액 입력
    ↓
[앱] 확인 다이얼로그
    ↓
[앱] add_points.jsp 호출 ← ⚠️ 검증 없이 바로 포인트 추가 (문제)
    ↓
[서버] DB에 포인트 추가
```

### 1.3 수정이 필요한 파일

| 파일 | 위치 | 수정 내용 |
|------|------|----------|
| `charge_screen.dart` | `lib/screens/` | 결제창 호출 로직 추가 |
| `add_points.jsp` | `jsp/` | PG 결제 검증 추가 |
| `api_constants.dart` | `lib/services/` | 결제 관련 엔드포인트 추가 |

---

## 2. 준비사항

### 2.1 PG사 선택 및 계약

#### 옵션 A: 토스페이먼츠 (권장 ⭐)
- ✅ Flutter SDK 공식 지원
- ✅ 이미 패키지 설치됨
- ✅ 낮은 수수료 (2.5~3.0%)
- ✅ 빠른 정산 (D+1)
- ⚠️ 사업자등록증 필요

**신청 방법**:
1. https://www.tosspayments.com 접속
2. "가맹점 신청" 클릭
3. 서류 제출 (사업자등록증, 통신판매업 신고증)
4. 심사 대기 (1~2주)

#### 옵션 B: KG 이니시스
- ⚠️ Flutter 공식 SDK 없음 (WebView 구현 필요)
- 수수료: 2.8~3.5%
- 정산: D+2

### 2.2 필요한 정보 (PG사로부터 발급받음)

#### 테스트 환경 (개발/테스트용)
```
Client Key: test_ck_xxxxxxxxxxxxxxxxxxxx
Secret Key: test_sk_xxxxxxxxxxxxxxxxxxxx
Merchant ID: test_merchant_12345
```

#### 운영 환경 (실서비스용)
```
Client Key: live_ck_xxxxxxxxxxxxxxxxxxxx
Secret Key: live_sk_xxxxxxxxxxxxxxxxxxxx
Merchant ID: live_merchant_12345
```

⚠️ **Secret Key는 절대 앱 코드에 포함하지 말 것** (서버에서만 사용)

### 2.3 서버 환경 설정

**필요한 라이브러리 (Java/JSP 서버)**
```xml
<!-- pom.xml 또는 수동 다운로드 -->
<dependency>
    <groupId>com.google.code.gson</groupId>
    <artifactId>gson</artifactId>
    <version>2.10.1</version>
</dependency>

<dependency>
    <groupId>org.apache.httpcomponents</groupId>
    <artifactId>httpclient</artifactId>
    <version>4.5.14</version>
</dependency>
```

---

## 3. 구현 단계

### STEP 1: Flutter 앱 수정 (30분)

#### 📄 `lib/services/api_constants.dart` 수정

**기존 코드 (33번째 줄 근처)**:
```dart
static const String addPoints = "$baseUrl/add_points.jsp";
```

**추가할 코드**:
```dart
// 결제 관련 API 추가
static const String addPoints = "$baseUrl/add_points.jsp";
static const String verifyPayment = "$baseUrl/verify_payment.jsp"; // 새로 추가
static const String paymentSuccess = "$baseUrl/payment_success.jsp"; // 새로 추가
static const String paymentFail = "$baseUrl/payment_fail.jsp"; // 새로 추가

// 토스페이먼츠 설정
static const String tossClientKey = "test_ck_테스트키여기에입력"; // PG사에서 발급받은 키
```

#### 📄 `lib/screens/charge_screen.dart` 수정

**1) 패키지 import 추가 (6번째 줄 근처)**

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_constants.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

// ✅ 아래 3줄 추가
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
```

**2) `_charge()` 함수 전체 교체 (86~138번째 줄)**

기존 코드를 삭제하고 아래 코드로 교체:

```dart
Future<void> _charge() async {
  final amountText = _amountController.text.trim();
  final amount = int.tryParse(amountText);

  if (amount == null || amount <= 0) {
    setState(() {
      _errorMessage = '올바른 금액을 입력하세요.';
      _showErrorOverlay = true;
    });
    return;
  }

  setState(() => _loading = true);

  try {
    // 주문 ID 생성 (고유해야 함)
    final orderId = 'ORDER_${widget.userId}_${DateTime.now().millisecondsSinceEpoch}';
    final orderName = '포인트 충전';

    // 토스페이먼츠 결제 요청 URL 생성
    final paymentUrl = _generateTossPaymentUrl(
      orderId: orderId,
      orderName: orderName,
      amount: amount,
    );

    // WebView로 결제창 열기
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentWebView(
          url: paymentUrl,
          userId: widget.userId,
          orderId: orderId,
          amount: amount,
        ),
      ),
    );

    setState(() => _loading = false);

    // 결제 결과 처리
    if (result == true) {
      setState(() {
        _errorMessage = '충전이 완료되었습니다.';
        _showErrorOverlay = true;
      });
    } else if (result == false) {
      setState(() {
        _errorMessage = '충전에 실패했습니다.';
        _showErrorOverlay = true;
      });
    }
  } catch (e) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _errorMessage = '오류 발생: $e';
      _showErrorOverlay = true;
    });
  }
}

// 토스페이먼츠 결제 URL 생성 함수
String _generateTossPaymentUrl({
  required String orderId,
  required String orderName,
  required int amount,
}) {
  final clientKey = ApiConstants.tossClientKey;
  final successUrl = '${ApiConstants.paymentSuccess}?userId=${widget.userId}';
  final failUrl = ApiConstants.paymentFail;
  
  // 토스페이먼츠 결제창 URL (실제로는 SDK 사용 권장)
  return 'https://pay.toss.im/web/checkout?'
      'clientKey=$clientKey&'
      'orderId=$orderId&'
      'orderName=${Uri.encodeComponent(orderName)}&'
      'amount=$amount&'
      'customerName=${widget.userId}&'
      'successUrl=${Uri.encodeComponent(successUrl)}&'
      'failUrl=${Uri.encodeComponent(failUrl)}';
}
```

**3) `charge_screen.dart` 파일 끝에 WebView 위젯 추가**

```dart
// ChargeScreen 클래스 밖에 추가 (파일 맨 아래)

/// 결제 WebView 화면
class PaymentWebView extends StatefulWidget {
  final String url;
  final String userId;
  final String orderId;
  final int amount;

  const PaymentWebView({
    Key? key,
    required this.url,
    required this.userId,
    required this.orderId,
    required this.amount,
  }) : super(key: key);

  @override
  State<PaymentWebView> createState() => _PaymentWebViewState();
}

class _PaymentWebViewState extends State<PaymentWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            // 결제 성공 시
            if (request.url.contains('payment_success')) {
              _handlePaymentSuccess(request.url);
              return NavigationDecision.prevent;
            }
            // 결제 실패 시
            if (request.url.contains('payment_fail')) {
              Navigator.pop(context, false);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (String url) {
            print('✅ 페이지 로드 완료: $url');
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _handlePaymentSuccess(String url) async {
    // URL에서 paymentKey, orderId 추출
    final uri = Uri.parse(url);
    final paymentKey = uri.queryParameters['paymentKey'];
    final orderId = uri.queryParameters['orderId'];
    final amount = uri.queryParameters['amount'];

    if (paymentKey == null || orderId == null) {
      Navigator.pop(context, false);
      return;
    }

    // 서버에 결제 검증 요청
    try {
      final response = await http.post(
        Uri.parse(ApiConstants.verifyPayment),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'userId': widget.userId,
          'paymentKey': paymentKey,
          'orderId': orderId,
          'amount': amount ?? widget.amount.toString(),
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          Navigator.pop(context, true); // 성공
          return;
        }
      }
      Navigator.pop(context, false); // 실패
    } catch (e) {
      print('❌ 결제 검증 오류: $e');
      Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('결제하기'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
```

---

### STEP 2: 서버 구현 (1시간)

#### 📄 신규 파일 생성: `jsp/verify_payment.jsp`

```jsp
<%@ page language="java" contentType="application/json; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page import="java.io.*" %>
<%@ page import="java.net.*" %>
<%@ page import="java.util.*" %>
<%@ page import="com.google.gson.*" %>
<%@ page import="org.apache.commons.codec.binary.Base64" %>
<%@ page import="java.sql.*" %>

<%
    response.setContentType("application/json; charset=UTF-8");
    
    // 요청 파라미터 받기
    String userId = request.getParameter("userId");
    String paymentKey = request.getParameter("paymentKey");
    String orderId = request.getParameter("orderId");
    String amountStr = request.getParameter("amount");
    
    JsonObject result = new JsonObject();
    
    try {
        int amount = Integer.parseInt(amountStr);
        
        // ===== 1단계: 토스페이먼츠 서버에 결제 검증 요청 =====
        String secretKey = "test_sk_여기에_시크릿키_입력"; // ⚠️ 실제 키로 교체 필요
        String auth = "Basic " + Base64.encodeBase64String((secretKey + ":").getBytes());
        
        URL url = new URL("https://api.tosspayments.com/v1/payments/" + paymentKey);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("GET");
        conn.setRequestProperty("Authorization", auth);
        conn.setRequestProperty("Content-Type", "application/json");
        
        int responseCode = conn.getResponseCode();
        
        if (responseCode == 200) {
            // 응답 읽기
            BufferedReader br = new BufferedReader(new InputStreamReader(conn.getInputStream(), "UTF-8"));
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = br.readLine()) != null) {
                sb.append(line);
            }
            br.close();
            
            // JSON 파싱
            JsonObject paymentData = JsonParser.parseString(sb.toString()).getAsJsonObject();
            String status = paymentData.get("status").getAsString();
            int verifiedAmount = paymentData.get("totalAmount").getAsInt();
            
            // ===== 2단계: 결제 상태 및 금액 검증 =====
            if (!"DONE".equals(status)) {
                result.addProperty("success", false);
                result.addProperty("message", "결제가 완료되지 않았습니다. 상태: " + status);
            } else if (verifiedAmount != amount) {
                result.addProperty("success", false);
                result.addProperty("message", "결제 금액 불일치");
            } else {
                // ===== 3단계: DB에 포인트 추가 =====
                Class.forName("com.mysql.cj.jdbc.Driver");
                String dbUrl = "jdbc:mysql://localhost:3306/your_database?useUnicode=true&characterEncoding=utf8";
                String dbUser = "your_username";
                String dbPassword = "your_password";
                
                Connection dbConn = DriverManager.getConnection(dbUrl, dbUser, dbPassword);
                
                // 중복 결제 방지 (orderId 체크)
                String checkSql = "SELECT COUNT(*) FROM payment_logs WHERE order_id = ?";
                PreparedStatement checkStmt = dbConn.prepareStatement(checkSql);
                checkStmt.setString(1, orderId);
                ResultSet rs = checkStmt.executeQuery();
                rs.next();
                int count = rs.getInt(1);
                
                if (count > 0) {
                    result.addProperty("success", false);
                    result.addProperty("message", "이미 처리된 결제입니다.");
                } else {
                    // 포인트 추가
                    String updateSql = "UPDATE users SET points = points + ? WHERE user_id = ?";
                    PreparedStatement updateStmt = dbConn.prepareStatement(updateSql);
                    updateStmt.setInt(1, amount);
                    updateStmt.setString(2, userId);
                    updateStmt.executeUpdate();
                    
                    // 결제 로그 기록
                    String logSql = "INSERT INTO payment_logs (user_id, order_id, payment_key, amount, status, created_at) VALUES (?, ?, ?, ?, 'SUCCESS', NOW())";
                    PreparedStatement logStmt = dbConn.prepareStatement(logSql);
                    logStmt.setString(1, userId);
                    logStmt.setString(2, orderId);
                    logStmt.setString(3, paymentKey);
                    logStmt.setInt(4, amount);
                    logStmt.executeUpdate();
                    
                    result.addProperty("success", true);
                    result.addProperty("message", "충전 완료");
                    result.addProperty("newPoints", amount); // 필요시 새 포인트 조회
                }
                
                dbConn.close();
            }
        } else {
            result.addProperty("success", false);
            result.addProperty("message", "토스 결제 검증 실패: " + responseCode);
        }
        
    } catch (Exception e) {
        result.addProperty("success", false);
        result.addProperty("message", "서버 오류: " + e.getMessage());
        e.printStackTrace();
    }
    
    out.print(result.toString());
%>
```

#### 📄 신규 파일 생성: `jsp/payment_success.jsp`

```jsp
<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>결제 성공</title>
</head>
<body>
    <script>
        // URL에서 결제 정보 추출
        const urlParams = new URLSearchParams(window.location.search);
        const paymentKey = urlParams.get('paymentKey');
        const orderId = urlParams.get('orderId');
        const amount = urlParams.get('amount');
        const userId = urlParams.get('userId');
        
        // 앱으로 리다이렉트 (WebView가 감지)
        window.location.href = 'payment_success://complete?paymentKey=' + paymentKey + 
                               '&orderId=' + orderId + 
                               '&amount=' + amount +
                               '&userId=' + userId;
    </script>
</body>
</html>
```

#### 📄 신규 파일 생성: `jsp/payment_fail.jsp`

```jsp
<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>결제 실패</title>
</head>
<body>
    <script>
        window.location.href = 'payment_fail://error';
    </script>
</body>
</html>
```

#### 📄 DB 테이블 생성

```sql
-- 결제 로그 테이블 (없는 경우 생성)
CREATE TABLE IF NOT EXISTS payment_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id VARCHAR(50) NOT NULL,
    order_id VARCHAR(100) NOT NULL UNIQUE,
    payment_key VARCHAR(200),
    amount INT NOT NULL,
    status VARCHAR(20) DEFAULT 'PENDING',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_order_id (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

---

## 4. 테스트 방법

### 4.1 테스트 환경 설정

**토스페이먼츠 테스트 계정**:
```
Client Key: test_ck_D5GePWvyJnrK0W0k6q8gLzN97Eoq
Secret Key: test_sk_zXLkKEypNArWmo50nX3lmeaxYG5R

⚠️ 위 키는 예시입니다. 실제로는 https://developers.tosspayments.com 에서 발급받으세요.
```

### 4.2 테스트 카드 번호

| 카드사 | 카드번호 | 유효기간 | CVC | 결과 |
|--------|----------|----------|-----|------|
| 신한카드 | 9446-0190-9182-7001 | 25/12 | 123 | ✅ 성공 |
| KB국민카드 | 4568-2900-1234-5678 | 26/01 | 456 | ✅ 성공 |
| 실패 테스트용 | 4000-0000-0000-0002 | 25/12 | 123 | ❌ 실패 |

### 4.3 테스트 시나리오

**시나리오 1: 정상 결제**
1. 앱 실행 → 포인트 충전 화면
2. 금액 입력: 10,000원
3. "충전 요청" 버튼 클릭
4. 결제창에서 테스트 카드 정보 입력
5. 결제 완료
6. ✅ "충전이 완료되었습니다" 메시지 확인
7. DB 확인: `payment_logs` 테이블에 기록 확인

**시나리오 2: 결제 실패**
1. 금액 입력: 5,000원
2. 실패 테스트용 카드 입력
3. ❌ "충전에 실패했습니다" 메시지 확인
4. DB 확인: 포인트 추가 안 됨

**시나리오 3: 중복 결제 방지**
1. 같은 orderId로 두 번 검증 요청
2. 두 번째 요청은 "이미 처리된 결제입니다" 에러

### 4.4 디버깅 로그 확인

**Flutter 앱 로그**:
```bash
flutter run --verbose
```

**서버 로그** (Tomcat 예시):
```bash
tail -f /var/log/tomcat/catalina.out
```

---

## 5. 운영 배포

### 5.1 운영 환경 체크리스트

- [ ] 토스페이먼츠 **운영 계약** 완료
- [ ] **운영용 키** 발급 받음 (live_ck_, live_sk_)
- [ ] `api_constants.dart`의 `tossClientKey`를 **운영 키로 변경**
- [ ] `verify_payment.jsp`의 `secretKey`를 **운영 키로 변경**
- [ ] DB 백업 설정
- [ ] HTTPS 적용 (필수!)
- [ ] 에러 로깅 시스템 구축
- [ ] 결제 실패 시 고객 안내 문구 준비

### 5.2 보안 설정 (매우 중요! ⚠️)

#### 1) Secret Key 보호
```jsp
// ❌ 나쁜 예: 하드코딩
String secretKey = "test_sk_xxxxxxxxxxxx";

// ✅ 좋은 예: 환경변수 사용
String secretKey = System.getenv("TOSS_SECRET_KEY");
```

서버 환경변수 설정:
```bash
# Linux/Mac
export TOSS_SECRET_KEY="live_sk_xxxxxxxxx"

# Windows
set TOSS_SECRET_KEY=live_sk_xxxxxxxxx
```

#### 2) HTTPS 필수
- HTTP로는 결제 불가 (PG사에서 차단)
- Let's Encrypt 무료 SSL 인증서 사용 가능

#### 3) IP 화이트리스트 (선택)
```jsp
// 특정 IP에서만 결제 API 호출 허용
String clientIp = request.getRemoteAddr();
if (!Arrays.asList("123.456.789.0", "111.222.333.444").contains(clientIp)) {
    response.setStatus(403);
    return;
}
```

### 5.3 모니터링

**필수 모니터링 항목**:
1. 결제 성공률 (일일 체크)
2. 평균 결제 완료 시간
3. 에러 발생 빈도
4. 미처리 결제 건수

```sql
-- 일일 결제 통계 쿼리
SELECT 
    DATE(created_at) as date,
    COUNT(*) as total_count,
    SUM(CASE WHEN status='SUCCESS' THEN 1 ELSE 0 END) as success_count,
    SUM(amount) as total_amount
FROM payment_logs
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY DATE(created_at);
```

---

## 6. 트러블슈팅

### 문제 1: "결제창이 열리지 않습니다"

**원인**: WebView 설정 오류

**해결**:
```dart
// AndroidManifest.xml에 인터넷 권한 확인
<uses-permission android:name="android.permission.INTERNET"/>

// Info.plist (iOS)에 ATS 설정 확인
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

### 문제 2: "결제는 성공했는데 포인트가 안 들어옴"

**원인**: 서버 검증 실패 또는 DB 연결 오류

**해결**:
1. `verify_payment.jsp` 로그 확인
2. DB 연결 정보 확인
3. `payment_logs` 테이블에 기록 여부 확인

```sql
-- 미처리 결제 조회
SELECT * FROM payment_logs 
WHERE status != 'SUCCESS' 
ORDER BY created_at DESC 
LIMIT 10;
```

### 문제 3: "토스 API 호출 시 401 에러"

**원인**: Secret Key가 잘못되었거나 인증 헤더 오류

**해결**:
```java
// Base64 인코딩 확인
String auth = "Basic " + Base64.encodeBase64String((secretKey + ":").getBytes("UTF-8"));

// ⚠️ secretKey 뒤에 콜론(:) 붙이는 것 잊지 말 것!
```

### 문제 4: "앱에서 결제 성공했는데 앱으로 돌아오지 않음"

**원인**: URL Scheme 설정 오류

**해결**:
```dart
// NavigationDelegate에서 URL 패턴 확인
if (request.url.contains('payment_success')) {
    print('🎉 성공 URL 감지: ${request.url}');
    _handlePaymentSuccess(request.url);
    return NavigationDecision.prevent;
}
```

### 문제 5: "결제 금액과 실제 충전 금액이 다름"

**원인**: 금액 검증 로직 누락

**해결**:
```java
// verify_payment.jsp에서 반드시 금액 비교
if (verifiedAmount != amount) {
    result.addProperty("success", false);
    result.addProperty("message", "결제 금액 불일치");
    
    // 보안 로그 기록
    logger.warn("금액 불일치 감지 - userId: " + userId + 
                ", 요청: " + amount + ", 검증: " + verifiedAmount);
}
```

---

## 📚 참고 자료

### 공식 문서
- [토스페이먼츠 개발자센터](https://docs.tosspayments.com/)
- [토스페이먼츠 Flutter SDK](https://github.com/tosspayments/payment-sdk-flutter)
- [WebView Flutter 패키지](https://pub.dev/packages/webview_flutter)

### 테스트 도구
- [토스페이먼츠 테스트 카드](https://docs.tosspayments.com/resources/test-card)
- [Postman으로 API 테스트](https://www.postman.com/)

### 보안
- [OWASP 결제 보안 가이드](https://owasp.org/www-project-web-security-testing-guide/)
- [PCI DSS 준수 가이드](https://www.pcisecuritystandards.org/)

---

## 💬 문의 및 지원

구현 중 문제가 발생하면:
1. 위 트러블슈팅 섹션 확인
2. 토스페이먼츠 고객센터: 1544-7772
3. 개발자 커뮤니티: https://developers.tosspayments.com/community

---

## 📌 중요 체크포인트 요약

| 단계 | 체크 항목 | 중요도 |
|------|-----------|--------|
| ✅ 준비 | PG사 계약 완료 | ⭐⭐⭐ |
| ✅ 개발 | Secret Key를 **서버**에서만 사용 | ⭐⭐⭐ |
| ✅ 개발 | 금액 검증 로직 추가 | ⭐⭐⭐ |
| ✅ 개발 | 중복 결제 방지 (orderId 체크) | ⭐⭐⭐ |
| ✅ 테스트 | 테스트 카드로 충분히 테스트 | ⭐⭐ |
| ✅ 배포 | HTTPS 적용 | ⭐⭐⭐ |
| ✅ 운영 | 결제 로그 모니터링 시스템 | ⭐⭐ |

---

**작성일**: 2025년 12월 29일  
**버전**: 1.0  
**프로젝트**: KBU QR System

> 이 문서는 외주 개발팀에 전달되는 공식 가이드입니다.  
> 구현 완료 후 운영 배포 전 반드시 보안 검토를 받으시기 바랍니다.

