import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const String darvasTaskKey = "com.darvaspro.backgroundScanTask";

final List<String> advancedWatchlist = [
  "HAL", "BEL", "TRENT", "DIXON", "ZOMATO", "POLYCAB", "PERSISTENT",
  "COFORGE", "RELIANCE", "SBIN", "BHARTIARTL", "LT", "BAJFINANCE",
  "M&M", "SUNPHARMA", "TITAN", "TATAMOTORS", "ADANIENT", "DLF", "SIEMENS",
  "ABB", "CUMMINSIND", "CHOLAFIN", "MUTHOOTFIN", "SHRIRAMFIN", "VEDL"
];

bool checkIsMarketOpenNow() {
  final now = DateTime.now();
  if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
    return false;
  }
  final currentMinutes = now.hour * 60 + now.minute;
  return currentMinutes >= (9 * 60) && currentMinutes <= (15 * 60 + 30);
}

Future<void> triggerNotification(String title, String body) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'darvas_channel_id',
    'Darvas Alerts',
    channelDescription: 'Real-time High Accuracy Darvas Signals',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );
  const NotificationDetails notificationDetails =
      NotificationDetails(android: androidDetails);
  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    notificationDetails,
  );
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    const AndroidInitializationSettings initAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: initAndroid);
    await flutterLocalNotificationsPlugin.initialize(initSettings);

    if (!checkIsMarketOpenNow()) {
      return Future.value(true);
    }

    for (String symbol in advancedWatchlist) {
      try {
        final url = Uri.parse(
            'https://query1.finance.yahoo.com/v8/finance/chart/$symbol.NS?interval=1d&range=1y');
        final response = await http.get(url, headers: {
          'User-Agent':
              'Mozilla/5.0 (Android; Mobile; rv:109.0) Gecko/109.0 Firefox/119.0'
        }).timeout(const Duration(seconds: 7));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final quote = data['chart']['result'][0]['indicators']['quote'][0];

          List<double> closes = [];
          List<double> highs = [];
          List<double> lows = [];
          List<double> volumes = [];

          for (int i = 0; i < quote['close'].length; i++) {
            if (quote['close'][i] != null &&
                quote['high'][i] != null &&
                quote['low'][i] != null &&
                quote['volume'][i] != null) {
              closes.add(quote['close'][i].toDouble());
              highs.add(quote['high'][i].toDouble());
              lows.add(quote['low'][i].toDouble());
              volumes.add(quote['volume'][i].toDouble());
            }
          }

          if (closes.length >= 60) {
            double currentPrice = closes.last;
            double currentHigh = highs.last;
            double currentLow = lows.last;
            double currentVol = volumes.last;

            double high52w = highs.reduce((a, b) => a > b ? a : b);
            bool isNear52wHigh = currentPrice >= (high52w * 0.85);

            double avgVol20 = volumes
                    .sublist(volumes.length - 21, volumes.length - 1)
                    .reduce((a, b) => a + b) /
                20;
            double ema50 =
                closes.sublist(closes.length - 35).reduce((a, b) => a + b) / 35;

            double boxTop = highs
                .sublist(highs.length - 20, highs.length - 2)
                .reduce((a, b) => a > b ? a : b);
            double boxBottom = lows
                .sublist(lows.length - 20, lows.length - 2)
                .reduce((a, b) => a < b ? a : b);

            double candleRange = currentHigh - currentLow;
            double upperWick = currentHigh - currentPrice;
            bool isCleanBody =
                candleRange > 0 ? (upperWick / candleRange) <= 0.35 : true;

            double riskPerShare = (currentPrice - boxBottom).abs();
            if (riskPerShare < 1.0) riskPerShare = currentPrice * 0.02;
            int qty = (1000 / riskPerShare).floor().clamp(1, 10000);

            // सटीक फ़िल्टर्ड ब्रेकआउट शर्त
            if (currentPrice > boxTop &&
                isNear52wHigh &&
                currentPrice > ema50 &&
                currentVol >= (avgVol20 * 1.30) &&
                isCleanBody) {
              await triggerNotification(
                "🟢 HIGH-ACCURACY BUY: $symbol @ ₹${currentPrice.toStringAsFixed(1)}",
                "डार्वस ब्रेकआउट + 52W हाई मोमेंटम! Entry: ₹$boxTop | SL: ₹$boxBottom | Qty: $qty",
              );
            } else if (currentPrice < boxBottom) {
              await triggerNotification(
                "🔴 EXIT ALERT: $symbol @ ₹${currentPrice.toStringAsFixed(1)}",
                "बॉक्स बॉटम टूटा! तुरंत बाहर निकलें।",
              );
            }
          }
        }
      } catch (_) {}
    }

    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const AndroidInitializationSettings initAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings =
      InitializationSettings(android: initAndroid);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  final androidImpl = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.requestNotificationsPermission();

  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );

  await Workmanager().registerPeriodicTask(
    "darvas_bg_periodic_task",
    darvasTaskKey,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
  );

  runApp(const DarvasProApp());
}

class DarvasProApp extends StatelessWidget {
  const DarvasProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Darvas Pro Terminal',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B132B),
        cardColor: const Color(0xFF1C2541),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981),
          secondary: Color(0xFF3B82F6),
        ),
      ),
      home: const DarvasMainScreen(),
    );
  }
}

class DarvasSignal {
  final String symbol;
  final String status;
  final double currentPrice;
  final double entryPrice;
  final double stopLoss;
  final double target1;
  final double addLevel;
  final double nextTarget;
  final int suggestedQty;
  final String reason;
  final double near52wPercent;
  final double volumeSurgeX;
  final String riskRewardRatio;

  DarvasSignal({
    required this.symbol,
    required this.status,
    required this.currentPrice,
    required this.entryPrice,
    required this.stopLoss,
    required this.target1,
    required this.addLevel,
    required this.nextTarget,
    required this.suggestedQty,
    required this.reason,
    required this.near52wPercent,
    required this.volumeSurgeX,
    required this.riskRewardRatio,
  });
}

class VirtualPosition {
  final String id;
  final String symbol;
  final double buyPrice;
  double currentPrice;
  double currentSL;
  int qty;
  final String buyTime;

  VirtualPosition({
    required this.id,
    required this.symbol,
    required this.buyPrice,
    required this.currentPrice,
    required this.currentSL,
    required this.qty,
    required this.buyTime,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'symbol': symbol,
        'buyPrice': buyPrice,
        'currentPrice': currentPrice,
        'currentSL': currentSL,
        'qty': qty,
        'buyTime': buyTime,
      };

  factory VirtualPosition.fromMap(Map<String, dynamic> map) => VirtualPosition(
        id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        symbol: map['symbol'],
        buyPrice: (map['buyPrice'] as num).toDouble(),
        currentPrice: (map['currentPrice'] as num).toDouble(),
        currentSL: (map['currentSL'] as num).toDouble(),
        qty: map['qty'] as int,
        buyTime: map['buyTime'] ?? '',
      );
}

class TradeHistoryItem {
  final String id;
  final String symbol;
  final double buyPrice;
  final double sellPrice;
  final int qty;
  final double pnl;
  final String buyTime;
  final String sellTime;

  TradeHistoryItem({
    required this.id,
    required this.symbol,
    required this.buyPrice,
    required this.sellPrice,
    required this.qty,
    required this.pnl,
    required this.buyTime,
    required this.sellTime,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'symbol': symbol,
        'buyPrice': buyPrice,
        'sellPrice': sellPrice,
        'qty': qty,
        'pnl': pnl,
        'buyTime': buyTime,
        'sellTime': sellTime,
      };

  factory TradeHistoryItem.fromMap(Map<String, dynamic> map) => TradeHistoryItem(
        id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        symbol: map['symbol'],
        buyPrice: (map['buyPrice'] as num).toDouble(),
        sellPrice: (map['sellPrice'] as num).toDouble(),
        qty: map['qty'] as int,
        pnl: (map['pnl'] as num).toDouble(),
        buyTime: map['buyTime'] ?? '',
        sellTime: map['sellTime'] ?? '',
      );
}

class DarvasMainScreen extends StatefulWidget {
  const DarvasMainScreen({super.key});

  @override
  State<DarvasMainScreen> createState() => _DarvasMainScreenState();
}

class _DarvasMainScreenState extends State<DarvasMainScreen> {
  double virtualCash = 100000.0;
  bool isScanning = false;
  String marketStatus = "मार्केट जाँचा जा रहा है...";
  List<DarvasSignal> signalList = [];
  List<VirtualPosition> activePositions = [];
  List<TradeHistoryItem> tradeHistory = [];

  @override
  void initState() {
    super.initState();
    loadStoredUserData();
    updateMarketStatusMessage();
    runFullDarvasScan();
  }

  Future<void> loadStoredUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      virtualCash = prefs.getDouble('virtual_cash') ?? 100000.0;

      final activeStr = prefs.getString('active_positions');
      if (activeStr != null && activeStr.isNotEmpty) {
        final List decoded = json.decode(activeStr);
        activePositions =
            decoded.map((e) => VirtualPosition.fromMap(e)).toList();
      }

      final histStr = prefs.getString('trade_history');
      if (histStr != null && histStr.isNotEmpty) {
        final List decoded = json.decode(histStr);
        tradeHistory =
            decoded.map((e) => TradeHistoryItem.fromMap(e)).toList();
      }
    });
  }

  Future<void> saveStoredUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('virtual_cash', virtualCash);
    await prefs.setString('active_positions',
        json.encode(activePositions.map((e) => e.toMap()).toList()));
    await prefs.setString('trade_history',
        json.encode(tradeHistory.map((e) => e.toMap()).toList()));
  }

  void updateMarketStatusMessage() {
    final now = DateTime.now();
    final timeStr =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    setState(() {
      if (checkIsMarketOpenNow()) {
        marketStatus = "🟢 बाजार चालू है (IST: $timeStr)";
      } else {
        marketStatus = "🔴 बाजार बंद है (IST: $timeStr)";
      }
    });
  }

  Future<void> openTradingView(String symbol) async {
    await Clipboard.setData(ClipboardData(text: symbol));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("📈 $symbol का चार्ट खोला जा रहा है (कॉपी किया गया)"),
        backgroundColor: Colors.blueAccent,
        duration: const Duration(seconds: 2),
      ),
    );

    final Uri tvAppUri = Uri.parse("tradingview://chart?symbol=NSE:$symbol");
    final Uri tvWebUri =
        Uri.parse("https://in.tradingview.com/chart/?symbol=NSE:$symbol");

    try {
      final launched =
          await launchUrl(tvAppUri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(tvWebUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrl(tvWebUri, mode: LaunchMode.externalApplication);
    }
  }

  void handleDematAction(String symbol) {
    Clipboard.setData(ClipboardData(text: symbol));

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C2541),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("🚀 $symbol ट्रेड करें",
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text("सिंबल कॉपीड",
                        style: TextStyle(
                            color: Colors.greenAccent, fontSize: 12)),
                  )
                ],
              ),
              const SizedBox(height: 6),
              const Text("अपने मोबाइल का कोई भी ट्रेडिंग ऐप चुनें:",
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 16),
              ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                tileColor: const Color(0xFF2E3856),
                leading: const Icon(Icons.share,
                    color: Colors.amberAccent, size: 28),
                title: const Text("अन्य सभी ऐप्स में खोजें (App Chooser)",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text(
                    "मोबाइल के किसी भी ऐप में सिंबल शेयर व सर्च करें"),
                onTap: () async {
                  Navigator.pop(ctx);
                  final uri = Uri.parse(
                      "intent:#Intent;action=android.intent.action.SEND;type=text/plain;S.android.intent.extra.TEXT=$symbol;end");
                  try {
                    await launchUrl(uri);
                  } catch (_) {}
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0038FF)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        launchUrl(
                                Uri.parse(
                                    "angelone://spark/search?query=$symbol"),
                                mode: LaunchMode.externalApplication)
                            .catchError((_) => launchUrl(
                                Uri.parse("https://trade.angelone.in/")));
                      },
                      child: const Text("Angel One",
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        launchUrl(Uri.parse("dhan://trade/$symbol"),
                                mode: LaunchMode.externalApplication)
                            .catchError((_) => launchUrl(Uri.parse(
                                "https://tv.dhan.co/?symbol=$symbol")));
                      },
                      child: const Text("Dhan",
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00B9F1)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        launchUrl(
                                Uri.parse(
                                    "paytmmoney://stocks/detail?symbol=$symbol"),
                                mode: LaunchMode.externalApplication)
                            .catchError((_) => launchUrl(Uri.parse(
                                "https://www.paytmmoney.com/stocks")));
                      },
                      child: const Text("Paytm",
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        launchUrl(Uri.parse("kite://"),
                                mode: LaunchMode.externalApplication)
                            .catchError((_) => launchUrl(
                                Uri.parse("https://kite.zerodha.com/")));
                      },
                      child: const Text("Zerodha Kite",
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        launchUrl(Uri.parse("groww://"),
                                mode: LaunchMode.externalApplication)
                            .catchError((_) => launchUrl(
                                Uri.parse("https://groww.in/stocks")));
                      },
                      child:
                          const Text("Groww", style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  void executeBuyOrder(DarvasSignal s) {
    int orderQty = s.suggestedQty;
    double totalCost = s.currentPrice * orderQty;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1C2541),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text("🛒 बाय ऑर्डर: ${s.symbol}",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("वर्तमान भाव: ₹${s.currentPrice.toStringAsFixed(2)}",
                    style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("क्वांटिटी (Shares):"),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle,
                              color: Colors.redAccent),
                          onPressed: orderQty > 1
                              ? () {
                                  setDialogState(() {
                                    orderQty--;
                                    totalCost = s.currentPrice * orderQty;
                                  });
                                }
                              : null,
                        ),
                        Text("$orderQty",
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.add_circle,
                              color: Color(0xFF10B981)),
                          onPressed: () {
                            setDialogState(() {
                              orderQty++;
                              totalCost = s.currentPrice * orderQty;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("कुल निवेश:"),
                    Text("₹${totalCost.toStringAsFixed(2)}",
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("उपलब्ध कैश:"),
                    Text("₹${virtualCash.toStringAsFixed(2)}",
                        style: TextStyle(
                            color: virtualCash >= totalCost
                                ? Colors.greenAccent
                                : Colors.redAccent,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("रद्द करें",
                    style: TextStyle(color: Colors.white60)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                onPressed: virtualCash >= totalCost
                    ? () async {
                        final now = DateTime.now();
                        final timeString =
                            "${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}";

                        setState(() {
                          virtualCash -= totalCost;
                          activePositions.add(VirtualPosition(
                            id: DateTime.now()
                                .millisecondsSinceEpoch
                                .toString(),
                            symbol: s.symbol,
                            buyPrice: s.currentPrice,
                            currentPrice: s.currentPrice,
                            currentSL: s.stopLoss,
                            qty: orderQty,
                            buyTime: timeString,
                          ));
                        });

                        await saveStoredUserData();
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                "✅ ${s.symbol} ($orderQty शेयर्स) स्थायी पोर्टफोलियो में सुरक्षित जुड़ गया!"),
                            backgroundColor: const Color(0xFF10B981),
                          ),
                        );
                      }
                    : null,
                child: const Text("बाय कन्फर्म करें",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> exitPositionAndRecordHistory(VirtualPosition pos) async {
    final now = DateTime.now();
    final timeString =
        "${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}";
    final double saleProceeds = pos.currentPrice * pos.qty;
    final double pnl = (pos.currentPrice - pos.buyPrice) * pos.qty;

    setState(() {
      virtualCash += saleProceeds;
      activePositions.removeWhere((item) => item.id == pos.id);

      tradeHistory.insert(
        0,
        TradeHistoryItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          symbol: pos.symbol,
          buyPrice: pos.buyPrice,
          sellPrice: pos.currentPrice,
          qty: pos.qty,
          pnl: pnl,
          buyTime: pos.buyTime,
          sellTime: timeString,
        ),
      );
    });

    await saveStoredUserData();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "🚪 ${pos.symbol} एग्जिट! P&L: ₹${pnl.toStringAsFixed(2)} (हिस्ट्री में सेव हुआ)",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: pnl >= 0 ? const Color(0xFF10B981) : Colors.redAccent,
      ),
    );
  }

  Future<void> deleteHistoryItem(String id) async {
    setState(() {
      tradeHistory.removeWhere((item) => item.id == id);
    });
    await saveStoredUserData();
  }

  void openDematPortfolioAndJournal() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DefaultTabController(
          length: 2,
          child: StatefulBuilder(
            builder: (context, setTabState) {
              double totalInvested = 0;
              double currentHoldingValue = 0;

              for (var pos in activePositions) {
                totalInvested += (pos.buyPrice * pos.qty);
                currentHoldingValue += (pos.currentPrice * pos.qty);
              }

              double totalPortfolioValue = virtualCash + currentHoldingValue;
              double totalUnrealizedPnL = currentHoldingValue - totalInvested;
              double pnlPercent = totalInvested > 0
                  ? (totalUnrealizedPnL / totalInvested) * 100
                  : 0.0;
              bool isOverallProfit = totalUnrealizedPnL >= 0;

              return Scaffold(
                appBar: AppBar(
                  title: const Text("💼 डीमैट टर्मिनल व ट्रेड जर्नल"),
                  backgroundColor: const Color(0xFF1C2541),
                  bottom: const TabBar(
                    indicatorColor: Color(0xFF10B981),
                    tabs: [
                      Tab(icon: Icon(Icons.show_chart), text: "एक्टिव ट्रेड्स"),
                      Tab(
                          icon: Icon(Icons.history_edu),
                          text: "ट्रेड हिस्ट्री (जर्नल)"),
                    ],
                  ),
                ),
                body: TabBarView(
                  children: [
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          color: const Color(0xFF111D4A),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("कुल पोर्टफोलियो मूल्य",
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 13)),
                                  Text(
                                      "₹${totalPortfolioValue.toStringAsFixed(2)}",
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text("इन्वेस्टेड राशि",
                                          style: TextStyle(
                                              color: Colors.white60,
                                              fontSize: 12)),
                                      Text("₹${totalInvested.toStringAsFixed(1)}",
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text("उपलब्ध कैश",
                                          style: TextStyle(
                                              color: Colors.white60,
                                              fontSize: 12)),
                                      Text("₹${virtualCash.toStringAsFixed(1)}",
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF10B981))),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Text("कुल अनरियलाइज्ड P&L",
                                          style: TextStyle(
                                              color: Colors.white60,
                                              fontSize: 12)),
                                      Text(
                                        "${isOverallProfit ? '+' : ''}₹${totalUnrealizedPnL.toStringAsFixed(1)} (${pnlPercent.toStringAsFixed(2)}%)",
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: isOverallProfit
                                              ? const Color(0xFF10B981)
                                              : Colors.redAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: activePositions.isEmpty
                              ? const Center(
                                  child: Text(
                                      "कोई सक्रिय पोजीशन नहीं है!\nहोम स्क्रीन पर किसी भी शेयर के 'वर्चुअल खरीदें' से ट्रेड लें।",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Colors.white60, height: 1.5)),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.all(12),
                                  itemCount: activePositions.length,
                                  itemBuilder: (context, index) {
                                    final pos = activePositions[index];
                                    final pnl =
                                        (pos.currentPrice - pos.buyPrice) *
                                            pos.qty;
                                    final itemPnlPercent = ((pos.currentPrice -
                                                pos.buyPrice) /
                                            pos.buyPrice) *
                                        100;
                                    final isProfit = pnl >= 0;

                                    return Card(
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14)),
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 8),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(pos.symbol,
                                                    style: const TextStyle(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 10,
                                                      vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: (isProfit
                                                            ? const Color(
                                                                0xFF10B981)
                                                            : Colors.redAccent)
                                                        .withOpacity(0.2),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                  child: Text(
                                                    "${isProfit ? '+' : ''}₹${pnl.toStringAsFixed(1)} (${itemPnlPercent.toStringAsFixed(2)}%)",
                                                    style: TextStyle(
                                                      color: isProfit
                                                          ? const Color(
                                                              0xFF10B981)
                                                          : Colors.redAccent,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                    "खरीद: ₹${pos.buyPrice.toStringAsFixed(1)}",
                                                    style: const TextStyle(
                                                        color: Colors.white70)),
                                                Text(
                                                    "LTP: ₹${pos.currentPrice.toStringAsFixed(1)}",
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors
                                                            .cyanAccent)),
                                                Text("मात्रा: ${pos.qty} Sh.",
                                                    style: const TextStyle(
                                                        color: Colors.white70)),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                    "🛑 ट्रेलिंग SL: ₹${pos.currentSL.toStringAsFixed(1)}",
                                                    style: const TextStyle(
                                                        color:
                                                            Colors.orangeAccent,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                                Text("समय: ${pos.buyTime}",
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        color:
                                                            Colors.white54)),
                                              ],
                                            ),
                                            const Divider(height: 18),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: OutlinedButton.icon(
                                                    onPressed: () =>
                                                        openTradingView(
                                                            pos.symbol),
                                                    icon: const Icon(
                                                        Icons.show_chart,
                                                        size: 16),
                                                    label: const Text("चार्ट"),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: ElevatedButton.icon(
                                                    onPressed: () async {
                                                      await exitPositionAndRecordHistory(
                                                          pos);
                                                      setTabState(() {});
                                                      setState(() {});
                                                    },
                                                    style:
                                                        ElevatedButton.styleFrom(
                                                            backgroundColor:
                                                                Colors
                                                                    .redAccent),
                                                    icon: const Icon(
                                                        Icons.close,
                                                        size: 16,
                                                        color: Colors.white),
                                                    label: const Text(
                                                        "Exit Position",
                                                        style: TextStyle(
                                                            color: Colors.white,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold)),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                    tradeHistory.isEmpty
                        ? const Center(
                            child: Text(
                              "अभी तक कोई ट्रेड क्लोज नहीं हुआ है।\nजब भी आप कोई पोजीशन बेचेंगे, उसका पूरा लाभ/हानि रिकॉर्ड यहाँ स्थायी रूप से दर्ज रहेगा।",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white60, height: 1.5),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: tradeHistory.length,
                            itemBuilder: (context, index) {
                              final item = tradeHistory[index];
                              final isProfit = item.pnl >= 0;

                              return Card(
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                                margin:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(item.symbol,
                                              style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold)),
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: (isProfit
                                                          ? const Color(
                                                              0xFF10B981)
                                                          : Colors.redAccent)
                                                      .withOpacity(0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  "${isProfit ? '+' : ''}₹${item.pnl.toStringAsFixed(1)}",
                                                  style: TextStyle(
                                                    color: isProfit
                                                        ? const Color(
                                                            0xFF10B981)
                                                        : Colors.redAccent,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.delete_outline,
                                                    size: 20,
                                                    color: Colors.white38),
                                                onPressed: () async {
                                                  await deleteHistoryItem(
                                                      item.id);
                                                  setTabState(() {});
                                                  setState(() {});
                                                },
                                              ),
                                            ],
                                          )
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                              "बाय: ₹${item.buyPrice.toStringAsFixed(1)}",
                                              style: const TextStyle(
                                                  color: Colors.white70)),
                                          Text(
                                              "सेल: ₹${item.sellPrice.toStringAsFixed(1)}",
                                              style: const TextStyle(
                                                  color: Colors.white70)),
                                          Text("मात्रा: ${item.qty} Sh.",
                                              style: const TextStyle(
                                                  color: Colors.white70)),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text("बाय: ${item.buyTime}",
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.white54)),
                                          Text("सेल: ${item.sellTime}",
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.white54)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // लाइव डार्वस स्कैन + 52-Week High + Volume Dry-Up + Wick Filter
  Future<void> runFullDarvasScan() async {
    if (isScanning) return;
    setState(() => isScanning = true);

    List<DarvasSignal> tempResults = [];

    for (String symbol in advancedWatchlist) {
      try {
        final url = Uri.parse(
            'https://query1.finance.yahoo.com/v8/finance/chart/$symbol.NS?interval=1d&range=1y');
        final response = await http.get(url, headers: {
          'User-Agent':
              'Mozilla/5.0 (Android; Mobile; rv:109.0) Gecko/109.0 Firefox/119.0'
        }).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final quote = data['chart']['result'][0]['indicators']['quote'][0];

          List<double> closes = [];
          List<double> highs = [];
          List<double> lows = [];
          List<double> volumes = [];

          for (int i = 0; i < quote['close'].length; i++) {
            if (quote['close'][i] != null &&
                quote['high'][i] != null &&
                quote['low'][i] != null &&
                quote['volume'][i] != null) {
              closes.add(quote['close'][i].toDouble());
              highs.add(quote['high'][i].toDouble());
              lows.add(quote['low'][i].toDouble());
              volumes.add(quote['volume'][i].toDouble());
            }
          }

          if (closes.length >= 60) {
            double currentPrice = closes.last;
            double currentHigh = highs.last;
            double currentLow = lows.last;
            double currentVol = volumes.last;

            // 1. 52-Week High प्रोक्सिमिटी फ़िल्टर
            double high52w = highs.reduce((a, b) => a > b ? a : b);
            double distFrom52w = ((high52w - currentPrice) / high52w) * 100;
            bool isNear52w = distFrom52w <= 15.0;

            // 2. 20-दिन वॉल्यूम औसत और सर्ज
            double avgVol20 = volumes
                    .sublist(volumes.length - 21, volumes.length - 1)
                    .reduce((a, b) => a + b) /
                20;
            double volumeMultiplier = currentVol / avgVol20;

            // 3. EMA 50
            double ema50 =
                closes.sublist(closes.length - 35).reduce((a, b) => a + b) / 35;

            // 4. 20-डे डार्वस कंसॉलिडेशन बॉक्स
            double boxTop = highs
                .sublist(highs.length - 20, highs.length - 2)
                .reduce((a, b) => a > b ? a : b);
            double boxBottom = lows
                .sublist(lows.length - 20, lows.length - 2)
                .reduce((a, b) => a < b ? a : b);
            double boxHeight = boxTop - boxBottom;

            // 5. फॉल्स ब्रेकआउट / सेलिंग विक रिजेक्शन फ़िल्टर
            double candleRange = currentHigh - currentLow;
            double upperWick = currentHigh - currentPrice;
            bool isUpperWickExcessive =
                candleRange > 0 && (upperWick / candleRange) > 0.35;

            // पोज़ीशन साइज़िंग और रिस्क मैनेजमेंट
            double riskPerShare = (currentPrice - boxBottom).abs();
            if (riskPerShare < 1.0) riskPerShare = currentPrice * 0.02;
            int qty = (1000 / riskPerShare).floor().clamp(1, 10000);

            double target1 = boxTop + (boxHeight * 2);
            double addLevel = boxTop + boxHeight;
            double nextTarget = addLevel + (boxHeight * 2);

            double rewardDistance = target1 - currentPrice;
            double riskRatio = rewardDistance / (riskPerShare > 0 ? riskPerShare : 1);
            String rrText = "1:${riskRatio.toStringAsFixed(1)}";

            // एक्टिव ट्रेड्स का ऑटोमैटिक ट्रेलिंग स्टॉप-लॉस
            for (var pos in activePositions) {
              if (pos.symbol == symbol) {
                pos.currentPrice = currentPrice;
                if (currentPrice > addLevel && pos.currentSL < boxTop) {
                  pos.currentSL = boxTop;
                }
              }
            }

            // सिग्नल्स का सटीक वर्गीकरण
            if (currentPrice > boxTop &&
                isNear52w &&
                currentPrice > ema50 &&
                volumeMultiplier >= 1.30 &&
                !isUpperWickExcessive) {
              tempResults.add(DarvasSignal(
                symbol: symbol,
                status: "BUY (High Accuracy)",
                currentPrice: currentPrice,
                entryPrice: boxTop,
                stopLoss: boxBottom,
                target1: target1,
                addLevel: addLevel,
                nextTarget: nextTarget,
                suggestedQty: qty,
                reason: "52W हाई के पास क्लीन ब्रेकआउट + 1.3x वॉल्यूम पुष्टि!",
                near52wPercent: distFrom52w,
                volumeSurgeX: volumeMultiplier,
                riskRewardRatio: rrText,
              ));
            } else if (currentPrice >= (boxTop * 0.985) && currentPrice <= boxTop && isNear52w) {
              // Pre-Breakout रडार (कंसॉलिडेशन के शीर्ष पर)
              tempResults.add(DarvasSignal(
                symbol: symbol,
                status: "RADAR (Pre-Breakout)",
                currentPrice: currentPrice,
                entryPrice: boxTop,
                stopLoss: boxBottom,
                target1: target1,
                addLevel: addLevel,
                nextTarget: nextTarget,
                suggestedQty: qty,
                reason: "ब्रेकआउट की कगार पर! बॉक्स टॉप के 1.5% भीतर।",
                near52wPercent: distFrom52w,
                volumeSurgeX: volumeMultiplier,
                riskRewardRatio: rrText,
              ));
            } else if (currentPrice > addLevel) {
              tempResults.add(DarvasSignal(
                symbol: symbol,
                status: "ADD (Pyramid)",
                currentPrice: currentPrice,
                entryPrice: addLevel,
                stopLoss: boxTop,
                target1: nextTarget,
                addLevel: addLevel + boxHeight,
                nextTarget: nextTarget + boxHeight,
                suggestedQty: (qty * 0.5).floor().clamp(1, 9999),
                reason: "नया बॉक्स ब्रेकआउट! पोजीशन में और शेयर जोड़ें।",
                near52wPercent: distFrom52w,
                volumeSurgeX: volumeMultiplier,
                riskRewardRatio: rrText,
              ));
            } else if (currentPrice < boxBottom) {
              tempResults.add(DarvasSignal(
                symbol: symbol,
                status: "EXIT",
                currentPrice: currentPrice,
                entryPrice: boxTop,
                stopLoss: boxBottom,
                target1: target1,
                addLevel: addLevel,
                nextTarget: nextTarget,
                suggestedQty: 0,
                reason: "बॉक्स बॉटम टूटा! एग्जिट करें।",
                near52wPercent: distFrom52w,
                volumeSurgeX: volumeMultiplier,
                riskRewardRatio: "N/A",
              ));
            } else {
              tempResults.add(DarvasSignal(
                symbol: symbol,
                status: "HOLD",
                currentPrice: currentPrice,
                entryPrice: boxTop,
                stopLoss: boxBottom,
                target1: target1,
                addLevel: addLevel,
                nextTarget: nextTarget,
                suggestedQty: qty,
                reason: "डार्वस कंसॉलिडेशन बॉक्स के अंदर चल रहा है।",
                near52wPercent: distFrom52w,
                volumeSurgeX: volumeMultiplier,
                riskRewardRatio: rrText,
              ));
            }
          }
        }
      } catch (_) {}
    }

    await saveStoredUserData();

    setState(() {
      signalList = tempResults;
      isScanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📈 Darvas Pro Terminal',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1C2541),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                tooltip: "डीमैट पोर्टफोलियो व जर्नल",
                icon: const Icon(Icons.account_balance_wallet,
                    color: Color(0xFF10B981), size: 26),
                onPressed: openDematPortfolioAndJournal,
              ),
              if (activePositions.isNotEmpty)
                Positioned(
                  right: 6,
                  top: 6,
                  child: CircleAvatar(
                    radius: 9,
                    backgroundColor: Colors.redAccent,
                    child: Text(
                      '${activePositions.length}',
                      style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                )
            ],
          ),
          IconButton(
            tooltip: "टेस्ट नोटिफिकेशन",
            icon: const Icon(Icons.notifications_active),
            onPressed: () {
              triggerNotification(
                "🔔 Darvas Pro Test Alert",
                "सटीक फ़िल्टर और नोटिफिकेशन पूरी तरह तैयार हैं!",
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF0B132B),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(marketStatus,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                ),
                Text(
                  "कैश: ₹${virtualCash.toStringAsFixed(0)}",
                  style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          if (isScanning)
            const LinearProgressIndicator(color: Color(0xFF10B981)),
          Expanded(
            child: signalList.isEmpty && !isScanning
                ? Center(
                    child: ElevatedButton.icon(
                      onPressed: runFullDarvasScan,
                      icon: const Icon(Icons.refresh),
                      label: const Text("एडवांस स्कैन शुरू करें"),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981)),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(10),
                    children: signalList
                        .map((s) => buildInteractiveStockCard(s))
                        .toList(),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isScanning ? null : runFullDarvasScan,
        backgroundColor: const Color(0xFF10B981),
        icon: const Icon(Icons.bolt),
        label: Text(isScanning ? "स्कैन हो रहा है..." : "मैन्युअल स्कैन"),
      ),
    );
  }

  Widget buildInteractiveStockCard(DarvasSignal s) {
    Color badgeColor;
    if (s.status.contains("BUY")) {
      badgeColor = const Color(0xFF10B981);
    } else if (s.status.contains("RADAR")) {
      badgeColor = Colors.purpleAccent;
    } else if (s.status.contains("ADD")) {
      badgeColor = Colors.blueAccent;
    } else if (s.status == "EXIT") {
      badgeColor = Colors.redAccent;
    } else {
      badgeColor = Colors.orange;
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(s.symbol,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        "52W: -${s.near52wPercent.toStringAsFixed(1)}%",
                        style: const TextStyle(
                            fontSize: 10, color: Colors.cyanAccent),
                      ),
                    )
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: badgeColor),
                  ),
                  child: Text(s.status,
                      style: TextStyle(
                          color: badgeColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("वर्तमान भाव: ₹${s.currentPrice.toStringAsFixed(2)}",
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                Text(
                  "वॉल्यूम: ${s.volumeSurgeX.toStringAsFixed(1)}x Avg",
                  style: TextStyle(
                    fontSize: 12,
                    color: s.volumeSurgeX >= 1.3
                        ? Colors.greenAccent
                        : Colors.white60,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 18, color: Colors.white24),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("🎯 Entry: ₹${s.entryPrice.toStringAsFixed(1)}",
                          style: const TextStyle(
                              color: Colors.greenAccent, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text("🛑 SL: ₹${s.stopLoss.toStringAsFixed(1)}",
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text("🏁 Target 1: ₹${s.target1.toStringAsFixed(1)}",
                          style: const TextStyle(
                              color: Colors.yellowAccent, fontSize: 13)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("➕ Add: ₹${s.addLevel.toStringAsFixed(1)}",
                          style: const TextStyle(
                              color: Colors.lightBlueAccent, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text("⚖️ R:R Ratio: ${s.riskRewardRatio}",
                          style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text("📦 Qty (1%): ${s.suggestedQty} Sh.",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "विवरण: ${s.reason}",
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                  fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Colors.white12),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton(
                    onPressed: () => executeBuyOrder(s),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text(
                      "वर्चुअल खरीदें",
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: () => openTradingView(s.symbol),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      side: const BorderSide(color: Colors.blueAccent),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text(
                      "चार्ट",
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.blueAccent,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: () => handleDematAction(s.symbol),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      side: const BorderSide(color: Colors.orangeAccent),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text(
                      "डीमैट ट्रेड",
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
