import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../services/api_constants.dart';
import '../services/auth_service.dart';

class PointTransactionScreen extends StatefulWidget {
  final String userId;
  const PointTransactionScreen({super.key, required this.userId});

  @override
  State<PointTransactionScreen> createState() => _PointTransactionScreenState();
}

class _PointTransactionScreenState extends State<PointTransactionScreen> {
  List<dynamic> _transactions = [];
  bool _isLoading = true;
  String _selectedFilter = '전체';
  String _selectedMonthFilter = '전체';

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
  }

  // 개인 결제 내역 조회 API 호출
  Future<void> _fetchTransactions() async {
    setState(() => _isLoading = true);

    final token = await AuthService.getToken();

    if (token == null) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('로그인이 필요합니다.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      final response = await http.get(
        Uri.parse(ApiConstants.myPayments),
        headers: {'Authorization': 'Bearer $token'},
      );

      // 토큰 만료 처리
      if (response.statusCode == 401 || response.statusCode == 403) {
        await AuthService.logout();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('세션이 만료되었습니다. 다시 로그인해주세요.'),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.pushReplacementNamed(context, '/login');
        }
        return;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'success') {
          final paymentList = data['data'] as List;

          final transactions =
              paymentList.map((payment) {
                // amount 처리
                int amount = 0;
                try {
                  if (payment['amount'] is String) {
                    amount = double.parse(payment['amount']).toInt();
                  } else if (payment['amount'] is num) {
                    amount = (payment['amount'] as num).toInt();
                  }
                } catch (e) {
                  amount = 0;
                }

                // 날짜 필드 확인
                final paymentTime =
                    payment['payment_time'] ??
                    payment['paymentTime'] ??
                    payment['created_at'] ??
                    payment['createdAt'] ??
                    payment['timestamp'] ??
                    '';

                return {
                  'id': payment['id'],
                  'employee_number': payment['employee_number'],
                  'description': payment['menu_name'] ?? '식권',
                  'amount': amount,
                  'restaurant': payment['restaurant'] ?? '',
                  'created_at': paymentTime,
                  'transaction_type': 'payment',
                  'status': payment['status'],
                  'cancelled_at': payment['cancelled_at'],
                  'refunded_at': payment['refunded_at'],
                };
              }).toList();

          setState(() {
            _transactions = transactions;
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('결제 내역을 불러올 수 없습니다'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  '내역 선택',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              ...['전체', '완료', '취소', '환불'].map((filter) {
                final isSelected = _selectedFilter == filter;
                return Material(
                  color: isSelected ? Colors.blue[100] : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedFilter = filter;
                      });
                      Navigator.pop(context);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 16,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            filter,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight:
                                  isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                            ),
                          ),
                          if (isSelected) const Icon(Icons.check),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  void _showMonthFilterSheet() {
    final now = DateTime.now();
    final months = [
      '전체',
      ...List.generate(12, (i) {
        final date = DateTime(now.year, now.month - i);
        return DateFormat('yyyy년 M월').format(date);
      }),
    ];
    final ScrollController scrollController = ScrollController();
    bool showTopGradient = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            scrollController.addListener(() {
              if (scrollController.offset > 0 && !showTopGradient) {
                setStateModal(() => showTopGradient = true);
              } else if (scrollController.offset <= 0 && showTopGradient) {
                setStateModal(() => showTopGradient = false);
              }
            });
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 0),
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 80),
                          ...months.map((month) {
                            final isSelected = _selectedMonthFilter == month;
                            return Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    isSelected
                                        ? Colors.blue[100]
                                        : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedMonthFilter = month;
                                    });
                                    Navigator.pop(context);
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                      horizontal: 16,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          month,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight:
                                                isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                            color: Colors.black,
                                          ),
                                        ),
                                        if (isSelected)
                                          const Icon(
                                            Icons.check,
                                            color: Colors.black,
                                            size: 20,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                  if (showTopGradient)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 100,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white,
                              Colors.white,
                              Color.fromARGB(150, 255, 255, 255),
                              Color.fromARGB(0, 255, 255, 255),
                            ],
                            stops: [0.0, 0.6, 0.8, 1.0],
                          ),
                        ),
                      ),
                    ),
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SizedBox(
                      height: 80,
                      child: Center(
                        child: Text(
                          '기간 선택',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<dynamic> _getFilteredTransactions() {
    return _transactions.where((tx) {
      final status = tx['status'] ?? 'completed';
      final matchesType =
          _selectedFilter == '전체' ||
          (_selectedFilter == '완료' && status == 'completed') ||
          (_selectedFilter == '취소' && status == 'cancelled') ||
          (_selectedFilter == '환불' && status == 'refunded');

      if (!matchesType) return false;
      if (_selectedMonthFilter == '전체') return true;

      final txDateStr = tx['created_at'] ?? '';
      if (txDateStr.isEmpty) return false;

      try {
        final txDate = DateTime.parse(txDateStr.replaceAll(' ', 'T'));
        final monthLabel = DateFormat('yyyy년 M월').format(txDate);
        return monthLabel == _selectedMonthFilter;
      } catch (_) {
        return false;
      }
    }).toList();
  }

  Map<String, List<dynamic>> _groupTransactionsByDate(
    List<dynamic> transactions,
  ) {
    Map<String, List<dynamic>> grouped = {};
    for (var tx in transactions) {
      final dateStr = tx['created_at'] ?? '';
      if (dateStr.isEmpty) continue;

      try {
        // "2025-11-13 10:30:15" 형식을 DateTime으로 파싱
        DateTime date;
        if (dateStr.contains('T')) {
          date = DateTime.parse(dateStr);
        } else if (dateStr.contains(' ')) {
          date = DateTime.parse(dateStr.replaceAll(' ', 'T'));
        } else {
          date = DateTime.parse(dateStr);
        }

        final dateLabel = DateFormat('yyyy-MM-dd').format(date);
        grouped.putIfAbsent(dateLabel, () => []).add(tx);
      } catch (e) {
        // 날짜 파싱 실패 시 무시
      }
    }
    return grouped;
  }

  Widget _buildTransactionItem(Map<String, dynamic> tx) {
    final status = tx['status'] ?? 'completed';
    final amount = (tx['amount'] as num?)?.toInt() ?? 0;
    final dateTimeStr = tx['created_at'] ?? '';
    final restaurant = tx['restaurant'] ?? '';
    final menuName = tx['description'] ?? '식권';

    // 식권 개수 계산 (아질리아: 4800원, 피오니: 5000원)
    int ticketCount = 0;
    if (restaurant == '아질리아' && amount > 0) {
      ticketCount = (amount / 4800).round();
    } else if (restaurant == '피오니' && amount > 0) {
      ticketCount = (amount / 5000).round();
    }

    String transactionLabel = menuName;
    if (ticketCount > 0) {
      transactionLabel = '$restaurant 식권 ${ticketCount}장';
    } else if (restaurant.isNotEmpty) {
      transactionLabel = '$restaurant';
    }

    // 아이콘과 색상 설정
    IconData iconData = Icons.confirmation_number; // 식권 아이콘
    Color iconColor;
    Color amountTextColor;
    String statusText;

    // 결제 상태에 따른 색상과 텍스트
    if (status == 'completed') {
      if (restaurant == '아질리아') {
        iconColor = const Color(0xFF4CAF50); // 초록
        statusText = '아질리아';
      } else if (restaurant == '피오니') {
        iconColor = const Color(0xFF2196F3); // 파랑
        statusText = '피오니';
      } else {
        iconColor = Colors.green;
        statusText = restaurant.isNotEmpty ? restaurant : '완료';
      }
      amountTextColor = Colors.redAccent;
    } else if (status == 'cancelled') {
      iconColor = Colors.orange;
      amountTextColor = Colors.orange;
      statusText = '취소됨';
    } else if (status == 'refunded') {
      iconColor = Colors.blue;
      amountTextColor = Colors.blue;
      statusText = '환불완료';
    } else {
      iconColor = Colors.grey;
      amountTextColor = Colors.grey;
      statusText = '알 수 없음';
    }

    String formattedDateTime = '';
    if (dateTimeStr.isNotEmpty) {
      try {
        final parsedDate = DateTime.parse(dateTimeStr.replaceAll(' ', 'T'));
        // 25.10.26 10:30 형식으로 표시
        formattedDateTime = DateFormat('yy.MM.dd HH:mm').format(parsedDate);
      } catch (_) {}
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.translate(
            offset: const Offset(0, 4),
            child: Icon(iconData, color: iconColor, size: 36),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 첫째 줄: 식당명과 금액
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      statusText, // 아질리아 또는 피오니
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: iconColor,
                      ),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '-${NumberFormat('#,###').format(amount)}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: amountTextColor,
                            ),
                          ),
                          const TextSpan(
                            text: '원',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // 둘째 줄: 식권 개수
                if (ticketCount > 0)
                  Text(
                    '식권 ${ticketCount}장',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const SizedBox(height: 4),
                // 셋째 줄: 날짜 시간
                if (formattedDateTime.isNotEmpty)
                  Text(
                    formattedDateTime,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Padding(
            padding: EdgeInsets.only(top: 8.0),
            child: Text('결제 내역'),
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final filteredTransactions = _getFilteredTransactions();
    final groupedTransactions = _groupTransactionsByDate(filteredTransactions);
    final sortedDates =
        groupedTransactions.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Padding(
          padding: EdgeInsets.only(top: 8.0),
          child: Text('결제 내역'),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchTransactions,
            tooltip: '새로고침',
          ),
        ],
      ),

      body: Column(
        children: [
          const SizedBox(height: 16),
          const Text(
            '결제 내역',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '총 ${_transactions.length}건',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          Container(
            color: const Color(0xFFF4F6F8),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.calendar_today,
                        size: 20,
                        color: Colors.black,
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _showMonthFilterSheet,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF4F6F8),
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        splashFactory: NoSplash.splashFactory,
                      ).copyWith(
                        elevation: MaterialStateProperty.all(0),
                        shadowColor: MaterialStateProperty.all(
                          Colors.transparent,
                        ),
                      ),
                      child: Text(_selectedMonthFilter),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(right: 0),
                      child: Icon(
                        Icons.attach_money,
                        size: 20,
                        color: Colors.black,
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _showFilterSheet,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF4F6F8),
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        splashFactory: NoSplash.splashFactory,
                      ).copyWith(
                        elevation: MaterialStateProperty.all(0),
                        shadowColor: MaterialStateProperty.all(
                          Colors.transparent,
                        ),
                      ),
                      child: Text(_selectedFilter),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child:
                  filteredTransactions.isEmpty
                      ? const Center(child: Text('거래 내역이 없습니다.'))
                      : ListView.builder(
                        itemCount: sortedDates.length,
                        itemBuilder: (context, index) {
                          final date = sortedDates[index];
                          final transactionsOnDate = groupedTransactions[date]!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 10),
                              Text(
                                DateFormat(
                                  'M월 d일',
                                  'ko_KR',
                                ).format(DateTime.parse(date)),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ...transactionsOnDate.asMap().entries.map((
                                entry,
                              ) {
                                final tx = entry.value;
                                transactionsOnDate.length - 1;
                                return Column(
                                  children: [_buildTransactionItem(tx)],
                                );
                              }).toList(),
                            ],
                          );
                        },
                      ),
            ),
          ),
        ],
      ),
    );
  }
}
