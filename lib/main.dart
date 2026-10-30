import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:url_launcher/url_launcher.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const String darvasTaskKey = "com.darvaspro.backgroundScanTask";

final List<String> backgroundStockWatchlist = [
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
    channelDescription: 'Real-time Darvas Box Buy/Sell signals',
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

    for (String symbol in backgroundStockWatchlist) {
      try {
        final url = Uri.parse(
            'https://query1.finance.yahoo.com/v8/finance/chart/$symbol.NS?interval=1d&range=6mo');
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

          if (closes.length >= 40) {
            double currentPrice = closes.last;
            double currentVol = volumes.last;
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

            double riskPerShare = (currentPrice - boxBottom).abs();
            if (riskPerShare < 1.0) riskPerShare = currentPrice * 0.02;
            int qty = (1000 / riskPerShare).floor().clamp(1, 10000);

            if (currentPrice > boxTop && currentPrice > ema50 && currentVol >= (avgVol20 * 1.15)) {
              await triggerNotification(
                "🟢 BUY ALERT: $symbol @ ₹${currentPrice.toStringAsFixed(1)}",
                "Entry: ₹$boxTop | SL: ₹$boxBottom | Qty: $qty",
              );
            } else if (currentPrice < boxBottom) {
              await triggerNotification(
                "🔴 EXIT ALERT: $symbol @ ₹${currentPrice.toStringAsFixed(1)}",
                "बॉक्स बॉटम टूट गया है! तुरंत बाहर निकलें।",
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

  // Background Periodic Task (बिना किसी conflicting policy के सुरक्षित रूप से)
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
  });
}

class VirtualPosition {
  final String symbol;
  final double buyPrice;
  double currentPrice;
  double currentSL;
  int qty;
  final DateTime buyTime;

  VirtualPosition({
    required this.symbol,
    required this.buyPrice,
    required this.currentPrice,
    required this.currentSL,
    required this.qty,
    required this.buyTime,
  });
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
  List<VirtualPosition> portfolioPositions = [];

  @override
  void initState() {
    super.initState();
    updateMarketStatusMessage();
    runFullDarvasScan();
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

    final Uri tvWeb = Uri.parse("https://in.tradingview.com/chart/?symbol=NSE:$symbol");
    try {
      await launchUrl(tvWeb, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void openBrokerApp(String symbol, String brokerName) async {
    await Clipboard.setData(ClipboardData(text: symbol));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("📋 '$symbol' कॉपी हो गया है! $brokerName में पेस्ट करें।"),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 3),
      ),
    );

    Uri targetUri;
    if (brokerName == "Dhan") {
      targetUri = Uri.parse("https://tv.dhan.co/?symbol=$symbol");
    } else if (brokerName == "Angel One") {
      targetUri = Uri.parse("https://trade.angelone.in/");
    } else {
      targetUri = Uri.parse("https://www.paytmmoney.com/stocks");
    }

    try {
      await launchUrl(targetUri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void showBrokerSelectionSheet(String symbol) {
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
              Text(
                "🚀 $symbol ट्रेड करें",
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 6),
              const Text("अपना डीमैट ब्रोकर चुनें (शेयर नाम स्वतः कॉपी रहेगा):",
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 20),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: const Color(0xFF0B132B),
                leading: const Icon(Icons.flash_on, color: Color(0xFF10B981), size: 28),
                title: const Text("Dhan (धन ऐप)", style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("फास्ट ट्रेडिंग व चार्ट टर्मिनल"),
                onTap: () {
                  Navigator.pop(ctx);
                  openBrokerApp(symbol, "Dhan");
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: const Color(0xFF0B132B),
                leading: const Icon(Icons.account_balance_wallet, color: Colors.blueAccent, size: 28),
                title: const Text("Angel One (एंजेल वन)", style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("एंजेल वन स्पार्क में ऑर्डर लगाएं"),
                onTap: () {
                  Navigator.pop(ctx);
                  openBrokerApp(symbol, "Angel One");
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: const Color(0xFF0B132B),
                leading: const Icon(Icons.payments, color: Colors.cyanAccent, size: 28),
                title: const Text("Paytm Money (पेटीएम)", style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("पेटीएम मनी स्टॉक्स में खोजें"),
                onTap: () {
                  Navigator.pop(ctx);
                  openBrokerApp(symbol, "Paytm Money");
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void showOrderExecutionDialog(DarvasSignal s) {
    int orderQty = s.suggestedQty;
    double totalCost = s.currentPrice * orderQty;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1C2541),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text("🛒 बाय ऑर्डर: ${s.symbol}", style: const TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("वर्तमान भाव: ₹${s.currentPrice.toStringAsFixed(2)}",
                    style: const TextStyle(fontSize: 16, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("क्वांटिटी (Shares):"),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle, color: Colors.redAccent),
                          onPressed: orderQty > 1
                              ? () {
                                  setDialogState(() {
                                    orderQty--;
                                    totalCost = s.currentPrice * orderQty;
                                  });
                                }
                              : null,
                        ),
                        Text("$orderQty", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.add_circle, color: Color(0xFF10B981)),
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
                    Text("₹${totalCost.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("उपलब्ध कैश:"),
                    Text("₹${virtualCash.toStringAsFixed(2)}",
                        style: TextStyle(
                            color: virtualCash >= totalCost ? Colors.greenAccent : Colors.redAccent,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("रद्द करें", style: TextStyle(color: Colors.white60)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                onPressed: virtualCash >= totalCost
                    ? () {
                        setState(() {
                          virtualCash -= totalCost;
                          portfolioPositions.add(VirtualPosition(
                            symbol: s.symbol,
                            buyPrice: s.currentPrice,
                            currentPrice: s.currentPrice,
                            currentSL: s.stopLoss,
                            qty: orderQty,
                            buyTime: DateTime.now(),
                          ));
                        });
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("✅ ${s.symbol} के $orderQty शेयर पोर्टफोलियो में सफलतापूर्वक जोड़े गए!"),
                            backgroundColor: const Color(0xFF10B981),
                          ),
                        );
                      }
                    : null,
                child: const Text("बाय कन्फर्म करें", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void exitVirtualTrade(VirtualPosition pos) {
    double saleProceeds = pos.currentPrice * pos.qty;
    double pnl = (pos.currentPrice - pos.buyPrice) * pos.qty;

    setState(() {
      virtualCash += saleProceeds;
      portfolioPositions.remove(pos);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "🚪 ${pos.symbol} एग्जिट! बुक किया गया P&L: ₹${pnl.toStringAsFixed(2)}",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: pnl >= 0 ? const Color(0xFF10B981) : Colors.redAccent,
      ),
    );
  }

  void openPortfolioScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => StatefulBuilder(
          builder: (context, setPortfolioState) {
            double totalInvested = 0;
            double currentHoldingValue = 0;

            for (var pos in portfolioPositions) {
              totalInvested += (pos.buyPrice * pos.qty);
              currentHoldingValue += (pos.currentPrice * pos.qty);
            }

            double totalPortfolioValue = virtualCash + currentHoldingValue;
            double totalUnrealizedPnL = currentHoldingValue - totalInvested;
            double pnlPercent = totalInvested > 0 ? (totalUnrealizedPnL / totalInvested) * 100 : 0.0;
            bool isOverallProfit = totalUnrealizedPnL >= 0;

            return Scaffold(
              appBar: AppBar(
                title: const Text("💼 डीमैट पोर्टफोलियो (वर्चुअल)"),
                backgroundColor: const Color(0xFF1C2541),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: "भाव रीफ्रेश करें",
                    onPressed: () async {
                      await runFullDarvasScan();
                      setPortfolioState(() {});
                    },
                  ),
                ],
              ),
              body: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFF111D4A),
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("कुल पोर्टफोलियो मूल्य", style: TextStyle(color: Colors.white70, fontSize: 13)),
                            Text("₹${totalPortfolioValue.toStringAsFixed(2)}",
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("इन्वेस्टेड राशि", style: TextStyle(color: Colors.white60, fontSize: 12)),
                                const SizedBox(height: 3),
                                Text("₹${totalInvested.toStringAsFixed(1)}",
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("उपलब्ध कैश", style: TextStyle(color: Colors.white60, fontSize: 12)),
                                const SizedBox(height: 3),
                                Text("₹${virtualCash.toStringAsFixed(1)}",
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text("कुल लाभ/हानि (P&L)", style: TextStyle(color: Colors.white60, fontSize: 12)),
                                const SizedBox(height: 3),
                                Text(
                                  "${isOverallProfit ? '+' : ''}₹${totalUnrealizedPnL.toStringAsFixed(1)} (${pnlPercent.toStringAsFixed(2)}%)",
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: isOverallProfit ? const Color(0xFF10B981) : Colors.redAccent,
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
                    child: portfolioPositions.isEmpty
                        ? const Center(
                            child: Text(
                              "कोई एक्टिव ट्रेड नहीं है!\nहोम स्क्रीन पर किसी भी शेयर के 'वर्चुअल खरीदें' बटन से ट्रेड लें।",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white60, height: 1.5),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: portfolioPositions.length,
                            itemBuilder: (context, index) {
                              final pos = portfolioPositions[index];
                              final pnl = (pos.currentPrice - pos.buyPrice) * pos.qty;
                              final itemPnlPercent = ((pos.currentPrice - pos.buyPrice) / pos.buyPrice) * 100;
                              final isProfit = pnl >= 0;

                              return Card(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(pos.symbol, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: (isProfit ? const Color(0xFF10B981) : Colors.redAccent).withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              "${isProfit ? '+' : ''}₹${pnl.toStringAsFixed(1)} (${itemPnlPercent.toStringAsFixed(2)}%)",
                                              style: TextStyle(
                                                color: isProfit ? const Color(0xFF10B981) : Colors.redAccent,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text("क्वांटिटी: ${pos.qty} शेयर्स", style: const TextStyle(color: Colors.white70)),
                                          Text("बाय प्राइस: ₹${pos.buyPrice.toStringAsFixed(1)}", style: const TextStyle(color: Colors.white70)),
                                          Text("LTP: ₹${pos.currentPrice.toStringAsFixed(1)}",
                                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text("🛑 ट्रेलिंग SL: ₹${pos.currentSL.toStringAsFixed(1)}",
                                              style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                                          Text("करंट वैल्यू: ₹${(pos.currentPrice * pos.qty).toStringAsFixed(1)}",
                                              style: const TextStyle(color: Colors.white)),
                                        ],
                                      ),
                                      const Divider(height: 20),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () => openTradingView(pos.symbol),
                                              icon: const Icon(Icons.show_chart, size: 16),
                                              label: const Text("चार्ट"),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: () {
                                                exitVirtualTrade(pos);
                                                setPortfolioState(() {});
                                                setState(() {});
                                              },
                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                              icon: const Icon(Icons.close, size: 16, color: Colors.white),
                                              label: const Text("Exit Position", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
            );
          },
        ),
      ),
    );
  }

  Future<void> runFullDarvasScan() async {
    if (isScanning) return;
    setState(() => isScanning = true);

    List<DarvasSignal> tempResults = [];

    for (String symbol in backgroundStockWatchlist) {
      try {
        final url = Uri.parse(
            'https://query1.finance.yahoo.com/v8/finance/chart/$symbol.NS?interval=1d&range=6mo');
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

          if (closes.length >= 40) {
            double currentPrice = closes.last;
            double currentVol = volumes.last;
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
            double boxHeight = boxTop - boxBottom;

            double riskPerShare = (currentPrice - boxBottom).abs();
            if (riskPerShare < 1.0) riskPerShare = currentPrice * 0.02;
            int qty = (1000 / riskPerShare).floor().clamp(1, 10000);

            double target1 = boxTop + (boxHeight * 2);
            double addLevel = boxTop + boxHeight;
            double nextTarget = addLevel + (boxHeight * 2);

            for (var pos in portfolioPositions) {
              if (pos.symbol == symbol) {
                pos.currentPrice = currentPrice;
                if (currentPrice > addLevel && pos.currentSL < boxTop) {
                  pos.currentSL = boxTop;
                }
              }
            }

            if (currentPrice > boxTop && currentPrice > ema50 && currentVol >= (avgVol20 * 1.15)) {
              tempResults.add(DarvasSignal(
                symbol: symbol,
                status: "BUY",
                currentPrice: currentPrice,
                entryPrice: boxTop,
                stopLoss: boxBottom,
                target1: target1,
                addLevel: addLevel,
                nextTarget: nextTarget,
                suggestedQty: qty,
                reason: "बॉक्स टॉप ब्रेकआउट + वॉल्यूम पुष्टि!",
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
                reason: "नया बॉक्स ब्रेकआउट! शेयर जोड़ें।",
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
                reason: "कंसॉलिडेशन बॉक्स के अंदर है।",
              ));
            }
          }
        }
      } catch (_) {}
    }

    setState(() {
      signalList = tempResults;
      isScanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📈 Darvas Pro Terminal', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1C2541),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                tooltip: "डीमैट पोर्टफोलियो",
                icon: const Icon(Icons.account_balance_wallet, color: Color(0xFF10B981), size: 26),
                onPressed: openPortfolioScreen,
              ),
              if (portfolioPositions.isNotEmpty)
                Positioned(
                  right: 6,
                  top: 6,
                  child: CircleAvatar(
                    radius: 9,
                    backgroundColor: Colors.redAccent,
                    child: Text(
                      '${portfolioPositions.length}',
                      style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
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
                "नोटिफिकेशन सर्विस पूरी तरह सक्रिय है!",
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
                  child: Text(marketStatus, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ),
                Text(
                  "कैश: ₹${virtualCash.toStringAsFixed(0)}",
                  style: const TextStyle(fontSize: 13, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          if (isScanning) const LinearProgressIndicator(color: Color(0xFF10B981)),
          Expanded(
            child: signalList.isEmpty && !isScanning
                ? Center(
                    child: ElevatedButton.icon(
                      onPressed: runFullDarvasScan,
                      icon: const Icon(Icons.refresh),
                      label: const Text("लाइव स्कैन शुरू करें"),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(10),
                    children: signalList.map((s) => buildInteractiveStockCard(s)).toList(),
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
    Color badgeColor = s.status == "BUY"
        ? const Color(0xFF10B981)
        : s.status == "ADD (Pyramid)"
            ? Colors.blueAccent
            : s.status == "EXIT"
                ? Colors.redAccent
                : Colors.orange;

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
                Text(s.symbol, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: badgeColor),
                  ),
                  child: Text(s.status, style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text("वर्तमान भाव: ₹${s.currentPrice.toStringAsFixed(2)}",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
            const Divider(height: 18, color: Colors.white24),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("🎯 Entry: ₹${s.entryPrice.toStringAsFixed(1)}", style: const TextStyle(color: Colors.greenAccent, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text("🛑 SL: ₹${s.stopLoss.toStringAsFixed(1)}", style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text("🏁 Target 1: ₹${s.target1.toStringAsFixed(1)}", style: const TextStyle(color: Colors.yellowAccent, fontSize: 13)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("➕ Add: ₹${s.addLevel.toStringAsFixed(1)}", style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text("🚀 Next: ₹${s.nextTarget.toStringAsFixed(1)}", style: const TextStyle(color: Colors.cyanAccent, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text("📦 Qty (1%): ${s.suggestedQty} Sh.", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: Colors.white12),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton(
                    onPressed: () => showOrderExecutionDialog(s),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text(
                      "वर्चुअल खरीदें",
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text(
                      "चार्ट",
                      style: TextStyle(fontSize: 12, color: Colors.blueAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: () => showBrokerSelectionSheet(s.symbol),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      side: const BorderSide(color: Colors.orangeAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text(
                      "डीमैट ट्रेड",
                      style: TextStyle(fontSize: 12, color: Colors.orangeAccent, fontWeight: FontWeight.bold),
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
