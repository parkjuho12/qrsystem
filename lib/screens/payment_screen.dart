// 이 파일은 사용자의 QR 코드 결제를 처리하는 메인 화면입니다.
// 서버로부터 사용자별 고유 QR 데이터를 받아와 60초의 유효기간을 가진 QR코드를 화면에 표시합니다.
// 사용자의 현재 보유 포인트를 함께 보여주며, QR 코드 유효시간이 만료되면 재발급을 유도합니다.
// UI는 티켓 형태의 디자인으로 구성되어 있으며, 포인트 거래 내역 화면으로 이동하는 기능을 포함합니다.

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_constants.dart';
import '../services/auth_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:convert';
import 'dart:async';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'private_screen.dart'; // 개인 결제 내역 화면

class PaymentScreen extends StatefulWidget {
  final String userId;
  const PaymentScreen({super.key, required this.userId});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> with WidgetsBindingObserver {
  int _userPoints = 0;
  String _qrImageUrl = '';
  bool _isLoading = false;
  DateTime? _qrGeneratedAt;
  int _qrRemainingSeconds = 0;
  Timer? _qrTimer;
  bool _showExpiredMessage = false;

  @override
  void initState() {
    super.initState();
    _initializeScreen(); // 초기화
    
    // 앱이 백그라운드로 갈 때와 포그라운드로 돌아올 때 감지
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _initializeScreen() async {
    // 1. 먼저 저장된 QR 데이터 로드 (있으면 표시)
    await _loadSavedQrData();
    
    // 2. 사용자 데이터 로드
    await _fetchUserData();
    
    // 3. 저장된 QR이 없으면 자동으로 발급 시도 (서버가 기존 QR을 반환할 수 있음)
    if (_qrImageUrl.isEmpty) {
      await _fetchQrData();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      // 앱이 포그라운드로 돌아올 때 저장된 시간을 확인하고 타이머 업데이트
      _updateTimerFromSavedData();
    }
  }

  Future<void> _updateTimerFromSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedQrGeneratedAt = prefs.getInt('qr_generated_at_${widget.userId}');
    final savedQrImageUrl = prefs.getString('qr_image_url_${widget.userId}');
    
    if (savedQrGeneratedAt != null && savedQrImageUrl != null) {
      final generatedAt = DateTime.fromMillisecondsSinceEpoch(savedQrGeneratedAt);
      final now = DateTime.now();
      final elapsedSeconds = now.difference(generatedAt).inSeconds;
      
      if (elapsedSeconds < 300) { // 5분 = 300초
        setState(() {
          _qrImageUrl = savedQrImageUrl;
          _qrGeneratedAt = generatedAt;
          _qrRemainingSeconds = (300 - elapsedSeconds).toInt();
          _showExpiredMessage = false;
        });
        _qrTimer?.cancel();
        _startQrTimer();
      } else {
        setState(() {
          _qrImageUrl = '';
          _qrGeneratedAt = null;
          _qrRemainingSeconds = 0;
          _showExpiredMessage = true;
        });
        _qrTimer?.cancel();
        // 만료된 QR 데이터 삭제
        await prefs.remove('qr_generated_at_${widget.userId}');
        await prefs.remove('qr_image_url_${widget.userId}');
      }
    }
  }

  Future<void> _loadSavedQrData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedQrGeneratedAt = prefs.getInt('qr_generated_at_${widget.userId}');
    final savedQrImageUrl = prefs.getString('qr_image_url_${widget.userId}');
    
    if (savedQrGeneratedAt != null && savedQrImageUrl != null) {
      final generatedAt = DateTime.fromMillisecondsSinceEpoch(savedQrGeneratedAt);
      final now = DateTime.now();
      final elapsedSeconds = now.difference(generatedAt).inSeconds;
      
      if (elapsedSeconds < 300) { // 5분 = 300초
        setState(() {
          _qrImageUrl = savedQrImageUrl;
          _qrGeneratedAt = generatedAt;
          _qrRemainingSeconds = (300 - elapsedSeconds).toInt();
          _showExpiredMessage = false;
        });
        _startQrTimer();
      } else {
        // 만료된 QR 데이터 삭제
        await prefs.remove('qr_generated_at_${widget.userId}');
        await prefs.remove('qr_image_url_${widget.userId}');
        setState(() {
          _qrImageUrl = '';
          _qrGeneratedAt = null;
          _qrRemainingSeconds = 0;
          _showExpiredMessage = false;
        });
      }
    }
  }

  Future<void> _fetchQrData() async {
    try {
      final response = await http.post(
        Uri.parse(ApiConstants.qrIssue),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${AuthService.token}",
        },
        body: jsonEncode({
          'ticket_count': 1,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body.trim());
        
        if (responseData['status'] == 'success') {
          final qrData = responseData['qr_data'];
          final generatedAt = DateTime.now();
          int remainingSeconds = (responseData['remaining_seconds'] ?? 300).toInt();
          
          // QR 데이터를 SharedPreferences에 저장
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('qr_generated_at_${widget.userId}', generatedAt.millisecondsSinceEpoch);
          await prefs.setString('qr_image_url_${widget.userId}', qrData);
          await prefs.setString('qr_user_id_${widget.userId}', widget.userId);
          
          setState(() {
            _qrImageUrl = qrData;
            _qrGeneratedAt = generatedAt;
            _qrRemainingSeconds = remainingSeconds;
            _showExpiredMessage = false;
          });
          
          _qrTimer?.cancel();
          _startQrTimer();
        } else {
          // 재발급 제한 상황 처리
          if (responseData['existing_qr'] != null) {
            final existingQr = responseData['existing_qr'];
            final remainingSeconds = (existingQr['remaining_seconds'] ?? 0).toInt();
            
            setState(() {
              _qrImageUrl = '';
              _qrGeneratedAt = null;
              _qrRemainingSeconds = remainingSeconds;
              _showExpiredMessage = remainingSeconds <= 0;
            });
            
            if (remainingSeconds > 0) {
              _startQrTimer();
            }
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('이미 유효한 QR이 있습니다. ${_formatTime(remainingSeconds)} 후 재발급 가능합니다.'),
                backgroundColor: Colors.orange,
              ),
            );
          } else {
            setState(() {
              _qrImageUrl = '';
              _qrGeneratedAt = null;
              _qrRemainingSeconds = 0;
              _showExpiredMessage = true;
            });
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(responseData['message'] ?? 'QR 발급에 실패했습니다'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        setState(() {
          _qrImageUrl = '';
          _qrGeneratedAt = null;
          _qrRemainingSeconds = 0;
          _showExpiredMessage = true;
        });
      }
    } catch (e) {
      setState(() {
        _qrImageUrl = '';
        _qrGeneratedAt = null;
        _qrRemainingSeconds = 0;
        _showExpiredMessage = true;
      });
    }
  }

  Future<void> _fetchUserData() async {
    // 임시로 포인트를 0으로 설정 (새로운 API에서는 포인트 시스템이 다를 수 있음)
    setState(() {
      _userPoints = 0;
    });
  }

  void _startQrTimer() {
    _qrTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_qrRemainingSeconds <= 0) {
        timer.cancel();
        setState(() {
          _showExpiredMessage = true;
        });
      } else {
        setState(() {
          _qrRemainingSeconds--;
        });
      }
    });
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void _handleRefreshTap() {
    if (_qrRemainingSeconds > 0) {
      // 아직 유효한 QR이 있는 경우 경고창 표시
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(
              'QR 재발급 제한',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning,
                  color: Colors.orange,
                  size: 48.sp,
                ),
                SizedBox(height: 16.h),
                Text(
                  '아직 유효한 QR 코드가 있습니다.',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  '남은 시간: ${_formatTime(_qrRemainingSeconds)}',
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'QR이 만료된 후에 재발급이 가능합니다.',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(
                  '확인',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      );
    } else {
      // QR이 만료되었거나 없는 경우 재발급 진행
      _fetchQrData();
    }
  }

  @override
  void dispose() {
    _qrTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color.fromARGB(255, 255, 223, 0);
    final double boxTop = MediaQuery.of(context).size.height * 0.15;
    final double boxWidth = 310.w;
    final double boxLeft = MediaQuery.of(context).size.width / 2 - boxWidth / 2;
    const double holeRadius = 16.0;
    final double sideMargin = 40.w;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(50.h),
        child: Material(elevation: 0, shadowColor: Colors.black),
      ),
      backgroundColor: const Color.fromARGB(0, 246, 246, 246),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator(color: gold))
              : Stack(
                children: [
                  Positioned(
                    top: boxTop,
                    left: 0,
                    right: 0,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: boxWidth,
                          height: boxWidth,
                          margin: EdgeInsets.symmetric(horizontal: sideMargin),
                          child: ClipPath(
                            clipper: HoleClipper(),
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color.fromARGB(255, 219, 219, 219),
                                borderRadius: BorderRadius.circular(16.r),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.18),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Spacer(),
                                  Text(
                                    '결제 내역',
                                    style: TextStyle(
                                      fontSize: 18.sp,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                  SizedBox(height: 8.h),
                                  Icon(
                                    Icons.receipt_long,
                                    size: 40.sp,
                                    color: Colors.black54,
                                  ),
                                  SizedBox(height: 24.h),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          child: IgnorePointer(
                            child: CustomPaint(
                              size: Size(boxWidth - 12.w, boxWidth - 12.w),
                              painter: HoleBorderPainter(
                                borderRadius: 14.r,
                                holeRadius: 12.0,
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: DottedLinePainter(
                                margin: sideMargin,
                                holeRadius: holeRadius,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: boxTop + boxWidth * 0.65,
                    left: boxLeft,
                    width: boxWidth,
                    height: boxWidth * 0.35,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        // 개인 결제 내역 화면으로 이동
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PointTransactionScreen(
                              userId: widget.userId,
                            ),
                          ),
                        );
                      },
                      child: Container(),
                    ),
                  ),
                  Positioned(
                    top: boxTop + boxWidth + 10.h,
                    left: MediaQuery.of(context).size.width / 2 - 155.w,
                    right: MediaQuery.of(context).size.width / 2 - 155.w,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16.w,
                                vertical: 14.h,
                              ),
                              decoration: BoxDecoration(
                                color: const Color.fromARGB(255, 219, 219, 219),
                                borderRadius: BorderRadius.circular(16.r),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.18),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8.r,
                                          ),
                                          child: ShaderMask(
                                            shaderCallback: (Rect bounds) {
                                              return const LinearGradient(
                                                colors: [
                                                  Color.fromARGB(
                                                    255,
                                                    196,
                                                    113,
                                                    237,
                                                  ),
                                                  Color.fromARGB(
                                                    255,
                                                    227,
                                                    0,
                                                    122,
                                                  ),
                                                ],
                                                begin: Alignment.centerLeft,
                                                end: Alignment.centerRight,
                                              ).createShader(bounds);
                                            },
                                            child: LinearProgressIndicator(
                                              value: _qrRemainingSeconds / 300, // 5분 = 300초 기준
                                              backgroundColor: Colors.black,
                                              valueColor:
                                                  const AlwaysStoppedAnimation<
                                                    Color
                                                  >(Colors.white),
                                              minHeight: 8.h,
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 14.w),
                                      GestureDetector(
                                        onTap: _handleRefreshTap,
                                        child: Icon(
                                          Icons.refresh,
                                          color: Colors.black,
                                          size: 24.sp,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_showExpiredMessage)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        top: 6.h,
                                        bottom: 4.h,
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            'QR 코드가 만료되었습니다.',
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontSize: 13.sp,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          SizedBox(height: 8.h),
                                          ElevatedButton(
                                            onPressed: _fetchQrData,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.blue,
                                              foregroundColor: Colors.white,
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 16.w,
                                                vertical: 8.h,
                                              ),
                                            ),
                                            child: Text(
                                              'QR 재발급',
                                              style: TextStyle(
                                                fontSize: 12.sp,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  Text(
                                    '남은시간 : ${_formatTime(_qrRemainingSeconds)}',
                                    style: TextStyle(
                                      fontSize: 14.sp,
                                      color: _qrRemainingSeconds <= 60 ? Colors.red : Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Container(
                                  margin: EdgeInsets.all(5.w),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14.r),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).size.height * 0.04,
                      ),
                      child: Container(
                        padding: EdgeInsets.all(18.w),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color.fromARGB(255, 180, 180, 180),
                            width: 2.w,
                          ),
                          borderRadius: BorderRadius.circular(16.r),
                          color: Colors.white,
                        ),
                        child: _qrImageUrl.isNotEmpty
                            ? QrImageView(
                              data: _qrImageUrl,
                              version: QrVersions.auto,
                              size: 200.w,
                              gapless: false,
                            )
                            : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.qr_code_2,
                                  size: 48.sp,
                                  color: Colors.grey[400],
                                ),
                                SizedBox(height: 16.h),
                                Text(
                                  'QR 코드가 없습니다',
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 8.h),
                                ElevatedButton(
                                  onPressed: _fetchQrData,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 24.w,
                                      vertical: 12.h,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8.r),
                                    ),
                                  ),
                                  child: Text(
                                    'QR 발급하기',
                                    style: TextStyle(
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                      ),
                    ),
                  ),
                ],
              ),
    );
  }
}

class HoleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path =
        Path()..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, size.width, size.height),
            Radius.circular(20.r),
          ),
        );
    const holeRadius = 12.0;
    final centerY = size.height * 0.65;
    final leftHole =
        Path()..addOval(
          Rect.fromCircle(center: Offset(0, centerY), radius: holeRadius),
        );
    final rightHole =
        Path()..addOval(
          Rect.fromCircle(
            center: Offset(size.width, centerY),
            radius: holeRadius,
          ),
        );
    final withLeftHole = Path.combine(PathOperation.difference, path, leftHole);
    return Path.combine(PathOperation.difference, withLeftHole, rightHole);
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class HoleBorderPainter extends CustomPainter {
  final double borderRadius;
  final double holeRadius;

  HoleBorderPainter({required this.borderRadius, required this.holeRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(borderRadius),
    );
    final path = Path()..addRRect(rect);
    final leftHole =
        Path()..addOval(
          Rect.fromCircle(
            center: Offset(0, size.height * 0.655),
            radius: holeRadius + 3.r,
          ),
        );
    final rightHole =
        Path()..addOval(
          Rect.fromCircle(
            center: Offset(size.width, size.height * 0.655),
            radius: holeRadius + 3.r,
          ),
        );
    final fullPath = Path.combine(PathOperation.difference, path, leftHole);
    final finalPath = Path.combine(
      PathOperation.difference,
      fullPath,
      rightHole,
    );
    canvas.drawPath(finalPath, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class DottedLinePainter extends CustomPainter {
  final double margin;
  final double holeRadius;

  DottedLinePainter({required this.margin, required this.holeRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;

    const dashWidth = 5.8;
    const dashSpace = 4.0;
    final y = size.height * 0.65;
    final startX = holeRadius + margin + 8.w;
    final endX = size.width - holeRadius - margin - 8.w;

    double x = startX;
    while (x < endX) {
      final dashEnd = (x + dashWidth < endX) ? x + dashWidth : endX;
      canvas.drawLine(Offset(x, y), Offset(dashEnd, y), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
