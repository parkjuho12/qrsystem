import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/api_constants.dart';
import '../services/auth_service.dart';
import 'payment_screen.dart';
import 'menu_screen.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

class QRScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String affiliation;
  final String profileImage;

  const QRScreen({
    Key? key,
    required this.userId,
    required this.userName,
    required this.affiliation,
    required this.profileImage,
  }) : super(key: key);

  @override
  State<QRScreen> createState() => _QRScreenState();
}

class _QRScreenState extends State<QRScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _qrData = '';
  bool _isLoading = false;
  String _errorMessage = '';
  int _remainingSeconds = 0;
  bool _isExpired = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    // 사용자 정보가 없으면 세션 복원 시도
    if (AuthService.user == null) {
      await AuthService.restoreSession();

      // 복원 후에도 없으면 토큰 검증
      if (AuthService.user == null && AuthService.token != null) {
        await AuthService.validateToken();
      }

      if (AuthService.user != null) {
        setState(() {}); // UI 업데이트
      }
    }

    _fetchQRData();
  }

  void _fetchQRData() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // 사용자 정보 가져오기
      final user = AuthService.user;
      if (user == null) {
        setState(() {
          _errorMessage = '사용자 정보를 찾을 수 없습니다.';
          _isLoading = false;
        });
        return;
      }

      // 학생은 1+학번, 교직원은 2+사번 형식으로 QR 데이터 생성
      String qrData;
      final employeeNumber = user['employee_number'].toString();
      final role = user['role'];

      if (role == 'student') {
        qrData = '1$employeeNumber';
      } else if (role == 'employee') {
        qrData = '2$employeeNumber';
      } else {
        setState(() {
          _errorMessage = '학생 또는 교직원만 QR 발급 가능합니다.';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _qrData = qrData;
        _isExpired = false;
        _remainingSeconds = 0;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'QR 생성 중 오류가 발생했습니다.';
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    ScreenUtil.init(context, designSize: const Size(390, 844));

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: const Color.fromARGB(250, 255, 255, 255),
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(82.h),
          child: Material(
            elevation: 0.15,
            shadowColor: Colors.grey,
            child: AppBar(
              backgroundColor: Colors.white,
              toolbarHeight: 82.h,
              leading: SizedBox.shrink(),
              title: Image.asset(
                'images/kbu_logo.png',
                height: 55.h,
                fit: BoxFit.contain,
              ),
              iconTheme: const IconThemeData(color: Colors.black),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () async {
                    await AuthService.logout();
                    if (!mounted) return;
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/login',
                      (route) => false,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: TabBarView(
                // ▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼
                // 이 부분을 추가하여 스와이프(드래그) 기능을 비활성화했습니다.
                physics: const NeverScrollableScrollPhysics(),
                // ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲
                controller: _tabController,
                children: [
                  SingleChildScrollView(
                    padding: EdgeInsets.only(top: 100.h, bottom: 80.h),
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.topCenter,
                      children: [
                        Positioned(
                          top: -80.h,
                          child: Image.asset(
                            'images/bbogi_logo.png',
                            width: 260.w,
                            height: 160.h,
                            fit: BoxFit.contain,
                          ),
                        ),
                        Align(
                          alignment: Alignment.center,
                          child: Container(
                            width: 312.w,
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(255, 10, 80, 180),
                              borderRadius: BorderRadius.circular(14.r),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.5),
                                  spreadRadius: 4,
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                SizedBox(height: 12.h),
                                Center(
                                  child: Text(
                                    '출입증',
                                    style: TextStyle(
                                      fontSize: 24.sp,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                SizedBox(height: 10.h),
                                Container(
                                  width: 351.w,
                                  padding: EdgeInsets.symmetric(
                                    vertical: 6.h,
                                    horizontal: 24.w,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 220.w,
                                        height: 220.w,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            6.r,
                                          ),
                                        ),
                                        child:
                                            _isLoading
                                                ? Center(
                                                  child:
                                                      CircularProgressIndicator(
                                                        color: Colors.black,
                                                      ),
                                                )
                                                : _errorMessage.isNotEmpty
                                                ? Center(
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(
                                                        Icons.error_outline,
                                                        color: Colors.red,
                                                        size: 40.sp,
                                                      ),
                                                      SizedBox(height: 8.h),
                                                      Text(
                                                        _errorMessage,
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: TextStyle(
                                                          color: Colors.red,
                                                          fontSize: 12.sp,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                                : _qrData.isNotEmpty
                                                ? QrImageView(
                                                  data: _qrData,
                                                  version: QrVersions.auto,
                                                  size: 200.0,
                                                  backgroundColor: Colors.white,
                                                )
                                                : Center(
                                                  child: Text(
                                                    'QR 코드를 발급해주세요',
                                                    style: TextStyle(
                                                      color: Colors.grey,
                                                      fontSize: 14.sp,
                                                    ),
                                                  ),
                                                ),
                                      ),
                                      SizedBox(height: 12.h),
                                      // QR 재발급 버튼
                                      if (_errorMessage.isNotEmpty ||
                                          _isExpired ||
                                          _qrData.isEmpty)
                                        Padding(
                                          padding: EdgeInsets.only(
                                            bottom: 12.h,
                                          ),
                                          child: ElevatedButton(
                                            onPressed:
                                                _isLoading
                                                    ? null
                                                    : _fetchQRData,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color.fromARGB(
                                                    230,
                                                    2,
                                                    47,
                                                    123,
                                                  ),
                                              minimumSize: Size(120.w, 36.h),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(18.r),
                                              ),
                                            ),
                                            child: Text(
                                              _isLoading ? '발급 중...' : 'QR 재발급',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12.sp,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              2.r,
                                            ),
                                            child: Builder(
                                              builder: (context) {
                                                final profileImageName =
                                                    AuthService
                                                        .user?['profile_image'] ??
                                                    widget.profileImage;
                                                final imageUrl =
                                                    ApiConstants.getImageUrl(
                                                      profileImageName,
                                                    );

                                                return CachedNetworkImage(
                                                  imageUrl: imageUrl,
                                                  width: 95.w,
                                                  height: 95.w,
                                                  fit: BoxFit.cover,
                                                  placeholder:
                                                      (
                                                        context,
                                                        url,
                                                      ) => Container(
                                                        width: 95.w,
                                                        height: 95.w,
                                                        color: Colors.grey[300],
                                                        child: Center(
                                                          child: CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            valueColor:
                                                                AlwaysStoppedAnimation<
                                                                  Color
                                                                >(
                                                                  const Color.fromARGB(
                                                                    230,
                                                                    2,
                                                                    47,
                                                                    123,
                                                                  ),
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                  errorWidget: (
                                                    context,
                                                    url,
                                                    error,
                                                  ) {
                                                    return Container(
                                                      width: 95.w,
                                                      height: 95.w,
                                                      color: Colors.grey[300],
                                                      child: Icon(
                                                        Icons.person,
                                                        size: 40.sp,
                                                        color: Colors.grey[600],
                                                      ),
                                                    );
                                                  },
                                                );
                                              },
                                            ),
                                          ),
                                          SizedBox(width: 16.w),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                AuthService.user?['name'] ??
                                                    widget.userName,
                                                style: TextStyle(
                                                  fontSize: 20.sp,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              SizedBox(height: 4.h),
                                              Text(
                                                AuthService
                                                        .user?['employee_number']
                                                        ?.toString() ??
                                                    widget.userId,
                                                style: TextStyle(
                                                  fontSize: 16.sp,
                                                  color: Colors.black,
                                                ),
                                              ),
                                              SizedBox(height: 4.h),
                                              Text(
                                                AuthService
                                                        .user?['affiliation'] ??
                                                    widget.affiliation,
                                                style: TextStyle(
                                                  fontSize: 16.sp,
                                                  color: Colors.black,
                                                ),
                                              ),
                                              SizedBox(height: 44.h),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: 16.h),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _KeepAlivePaymentScreen(userId: widget.userId),
                  WeeklyMenuScreen(),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24.r),
                    topRight: Radius.circular(24.r),
                  ),
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade300, width: 0.8),
                  ),
                ),
                child: ClipRRect(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(24.r),
                        topRight: Radius.circular(24.r),
                      ),
                    ),
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        splashFactory: NoSplash.splashFactory,
                        splashColor: Colors.transparent,
                        tabBarTheme: const TabBarThemeData(
                          overlayColor: WidgetStatePropertyAll(
                            Colors.transparent,
                          ),
                        ),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicator: const BoxDecoration(),
                        labelColor: const Color.fromARGB(230, 2, 47, 123),
                        unselectedLabelColor: Colors.black54,
                        labelPadding: EdgeInsets.symmetric(vertical: 12.h),
                        tabs: List.generate(3, (index) {
                          bool selected = _tabController.index == index;
                          IconData iconData;
                          String text;
                          switch (index) {
                            case 0:
                              iconData = Icons.qr_code;
                              text = '출입증';
                              break;
                            case 1:
                              iconData = Icons.payment;
                              text = '식권 구매';
                              break;
                            case 2:
                              iconData = Icons.restaurant_menu;
                              text = '식단표';
                              break;
                            default:
                              iconData = Icons.help;
                              text = '알 수 없음';
                          }

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Transform.translate(
                                offset: Offset(0, -2.h),
                                child: Icon(
                                  iconData,
                                  size:
                                      index == 1
                                          ? 30.sp
                                          : (selected ? 31.sp : 28.sp),
                                ),
                              ),
                              Text(
                                text,
                                style: TextStyle(
                                  fontSize: selected ? 17.sp : 13.sp,
                                  fontWeight:
                                      selected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeepAlivePaymentScreen extends StatefulWidget {
  final String userId;
  const _KeepAlivePaymentScreen({Key? key, required this.userId})
    : super(key: key);

  @override
  State<_KeepAlivePaymentScreen> createState() =>
      _KeepAlivePaymentScreenState();
}

class _KeepAlivePaymentScreenState extends State<_KeepAlivePaymentScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    FocusScope.of(context).unfocus();
    return PaymentScreen(userId: widget.userId);
  }
}
