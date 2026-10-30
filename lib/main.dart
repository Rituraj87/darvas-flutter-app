import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
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
                "Entry: ₹$boxTop | SL: ₹$boxBottom | Target: ₹${(boxTop + ((boxTop - boxBottom) * 2)).toStringAsFixed(1)} | Qty: $qty",
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

  await Workmanager().registerPeriodicTask(
    "darvas_bg_periodic_task",
    darvasTaskKey,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );

  runApp(const DarvasProApp());
}

class DarvasProApp extends StatelessWidget {
  const DarvasProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Darvas Pro Auto Pilot',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        cardColor: const Color(0xFF1E293B),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981),
          secondary: Color(0xFF3B82F6),
        ),
      ),
      home: const DarvasMainScreen(),
    );
  }
}

// मॉडल क्लास
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
  final int qty;
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
  double virtualCash = 100000.0; // ₹1 लाख की वर्चुअल पूंजी
  bool isScanning = false;
  String marketStatus = "जाँच हो रही है...";
  List<DarvasSignal> signalList = [];
  List<VirtualPosition> activePositions = [];

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
        marketStatus = "🟢 बाजार खुला है (IST: $timeStr)";
      } else {
        marketStatus = "🔴 बाजार बंद है (IST: $timeStr)";
      }
    });
  }

  // 1. ट्रेडिंगव्यू में खोलना
  Future<void> openTradingView(String symbol) async {
    final uri = Uri.parse("https://in.tradingview.com/chart/?symbol=NSE:$symbol");
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("TradingView लिंक खोलने में असमर्थ")),
      );
    }
  }

  // 2. डीमैट खाता चयन मेनू
  void showBrokerSelectionSheet(String symbol) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "🚀 $symbol ट्रेड करें - डीमैट खाता चुनें",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              ListTile(
                leading: const Icon(Icons.account_balance_wallet, color: Colors.blueAccent),
                title: const Text("Angel One (एंजेल वन)"),
                subtitle: const Text("Angel One ऐप में खोलें"),
                onTap: () {
                  Navigator.pop(ctx);
                  launchUrl(Uri.parse("angelone://spark/search?query=$symbol"),
                      mode: LaunchMode.externalApplication);
                },
              ),
              ListTile(
                leading: const Icon(Icons.flash_on, color: Color(0xFF10B981)),
                title: const Text("Dhan (धन ऐप)"),
                subtitle: const Text("Dhan ट्रेडिंग टर्मिनल खोलें"),
                onTap: () {
                  Navigator.pop(ctx);
                  launchUrl(Uri.parse("dhan://trade/$symbol"),
                      mode: LaunchMode.externalApplication);
                },
              ),
              ListTile(
                leading: const Icon(Icons.payments, color: Colors.cyanAccent),
                title: const Text("Paytm Money (पेटीएम मनी)"),
                subtitle: const Text("Paytm Money ऐप में खोजें"),
                onTap: () {
                  Navigator.pop(ctx);
                  launchUrl(Uri.parse("paytmmoney://stocks/detail?symbol=$symbol"),
                      mode: LaunchMode.externalApplication);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // 3. वर्चुअल ट्रेड खरीदना
  void buyVirtualTrade(DarvasSignal s) {
    double totalTradeValue = s.currentPrice * s.suggestedQty;
    if (virtualCash < totalTradeValue) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ वर्चुअल कैश कम है! पूंजी समाप्त हो गई है।")),
      );
      return;
    }

    setState(() {
      virtualCash -= totalTradeValue;
      activePositions.add(VirtualPosition(
        symbol: s.symbol,
        buyPrice: s.currentPrice,
        currentPrice: s.currentPrice,
        currentSL: s.stopLoss,
        qty: s.suggestedQty,
        buyTime: DateTime.now(),
      ));
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("✅ ${s.symbol} के ${s.suggestedQty} शेयर वर्चुअल पोर्टफोलियो में जोड़े गए!"),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
  }

  // वर्चुअल ट्रेड बंद (एग्जिट) करना
  void exitVirtualTrade(VirtualPosition pos) {
    double saleProceeds = pos.currentPrice * pos.qty;
    double pnl = (pos.currentPrice - pos.buyPrice) * pos.qty;

    setState(() {
      virtualCash += saleProceeds;
      activePositions.remove(pos);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "${pos.symbol} एग्जिट! P&L: ₹${pnl.toStringAsFixed(2)}",
        ),
        backgroundColor: pnl >= 0 ? const Color(0xFF10B981) : Colors.redAccent,
      ),
    );
  }

  // एक्टिव ट्रेड्स और ट्रेलिंग स्टॉप-लॉस विंडो
  void openActivePositionsWindow() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            double totalPortfolioValue = virtualCash;
            for (var pos in activePositions) {
              totalPortfolioValue += (pos.currentPrice * pos.qty);
            }

            return Scaffold(
              appBar: AppBar(
                title: const Text("📋 वर्चुअल पोर्टफोलियो व ट्रेलिंग ट्रैकर"),
                backgroundColor: const Color(0xFF1E293B),
              ),
              body: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: const Color(0xFF111827),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("उपलब्ध कैश", style: TextStyle(color: Colors.white60, fontSize: 13)),
                            Text("₹${virtualCash.toStringAsFixed(1)}",
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text("कुल पोर्टफोलियो", style: TextStyle(color: Colors.white60, fontSize: 13)),
                            Text("₹${totalPortfolioValue.toStringAsFixed(1)}",
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: activePositions.isEmpty
                        ? const Center(
                            child: Text("कोई सक्रिय पोजीशन नहीं है। सिग्नल्स से 'Buy' दबाकर ट्रेड जोड़ें।"),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: activePositions.length,
                            itemBuilder: (context, index) {
                              final pos = activePositions[index];
                              final pnl = (pos.currentPrice - pos.buyPrice) * pos.qty;
                              final isProfit = pnl >= 0;

                              return Card(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(pos.symbol, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                          Text(
                                            "${isProfit ? '+' : ''}₹${pnl.toStringAsFixed(1)}",
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: isProfit ? const Color(0xFF10B981) : Colors.redAccent,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 16),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text("खरीद भाव: ₹${pos.buyPrice.toStringAsFixed(1)}"),
                                          Text("वर्तमान भाव: ₹${pos.currentPrice.toStringAsFixed(1)}"),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text("क्वांटिटी: ${pos.qty} शेयर्स"),
                                          Text("🛑 Trailing SL: ₹${pos.currentSL.toStringAsFixed(1)}",
                                              style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          exitVirtualTrade(pos);
                                          setModalState(() {});
                                          setState(() {});
                                        },
                                        icon: const Icon(Icons.exit_to_app, color: Colors.white),
                                        label: const Text("Exit Position (ट्रेड क्लोज करें)"),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.redAccent,
                                          minimumSize: const Size.fromHeight(38),
                                        ),
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

            // एक्टिव वर्चुअल पोजीशन के ट्रेलिंग स्टॉप-लॉस को ऑटोमैटिक अपडेट करना
            for (var pos in activePositions) {
              if (pos.symbol == symbol) {
                pos.currentPrice = currentPrice;
                // अगर शेयर ऊपर के नए बॉक्स में प्रवेश करता है, तो SL को पिछले बॉक्स के टॉप पर ट्रेल करें
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
        title: const Text('📈 Darvas Pro Auto Pilot', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          // वर्चुअल पोर्टफोलियो खोलने का बटन
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                tooltip: "वर्चुअल पोर्टफोलियो",
                icon: const Icon(Icons.wallet, color: Color(0xFF10B981)),
                onPressed: openActivePositionsWindow,
              ),
              if (activePositions.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: CircleAvatar(
                    radius: 8,
                    backgroundColor: Colors.redAccent,
                    child: Text(
                      '${activePositions.length}',
                      style: const TextStyle(fontSize: 10, color: Colors.white),
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
                "नोटिफिकेशन सर्विस बैकग्राउंड के लिए पूरी तरह तैयार है!",
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF111827),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    marketStatus,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
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

  // स्वाइप और 3 क्विक एक्शन वाला कार्ड
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(s.symbol, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
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
            Text("वर्तमान भाव: ₹${s.currentPrice.toStringAsFixed(2)}", style: const TextStyle(fontSize: 15)),
            const Divider(height: 16, color: Colors.white24),

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
                      Text("📦 Qty: ${s.suggestedQty} Shares", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1, color: Colors.white12),
            const SizedBox(height: 8),

            // तीनों मुख्य एक्शन बटन
            Row(
              children: [
                // 1. वर्चुअल ट्रेडिंग में पोजीशन लेना
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => buyVirtualTrade(s),
                    icon: const Icon(Icons.add_shopping_cart, size: 16),
                    label: const Text("Buy Virtual", style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // 2. डायरेक्ट ट्रेडिंगव्यू चार्ट
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => openTradingView(s.symbol),
                    icon: const Icon(Icons.show_chart, size: 16, color: Colors.blueAccent),
                    label: const Text("TradingView", style: TextStyle(fontSize: 11, color: Colors.blueAccent)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: const BorderSide(color: Colors.blueAccent),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // 3. डीमैट खाता मेनू (Angel One, Dhan, Paytm)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => showBrokerSelectionSheet(s.symbol),
                    icon: const Icon(Icons.launch, size: 16, color: Colors.orangeAccent),
                    label: const Text("Demat App", style: TextStyle(fontSize: 11, color: Colors.orangeAccent)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: const BorderSide(color: Colors.orangeAccent),
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
