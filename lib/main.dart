import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const String darvasTaskKey = "com.darvaspro.backgroundScanTask";

final List<String> backgroundStockWatchlist = [
  "HAL", "BEL", "TRENT", "DIXON", "ZOMATO", "POLYCAB", "PERSISTENT",
  "COFORGE", "RELIANCE", "SBIN", "BHARTIARTL", "LT", "BAJFINANCE",
  "M&M", "SUNPHARMA", "TITAN", "TATAMOTORS", "ADANIENT", "DLF", "SIEMENS",
  "ABB", "CUMMINSIND", "CHOLAFIN", "MUTHOOTFIN", "SHRIRAMFIN", "VEDL"
];

// भारतीय बाजार समय सत्यापन (सुबह 9:00 से दोपहर 3:30, सोम-शुक्र)
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

// ऐप पूरी तरह बंद होने पर चलने वाला स्वतंत्र बैकग्राउंड टास्क
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
                "बॉक्स बॉटम टूट गया है! पूंजी सुरक्षा के लिए तुरंत बाहर निकलें।",
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

  // WorkManager को बैकग्राउंड शेड्यूलिंग के लिए इनिशियलाइज़ करना
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );

  // हर 15 मिनट में चलने वाला बैकग्राउंड टास्क रजिस्टर करना
  await Workmanager().registerPeriodicTask(
    "darvas_bg_periodic_task",
    darvasTaskKey,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
    existingWorkPolicy: ExistingWorkPolicy.keep,
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

class DarvasMainScreen extends StatefulWidget {
  const DarvasMainScreen({super.key});

  @override
  State<DarvasMainScreen> createState() => _DarvasMainScreenState();
}

class _DarvasMainScreenState extends State<DarvasMainScreen> {
  double totalCapital = 100000.0;
  bool isScanning = false;
  String marketStatus = "मार्केट स्थिति जांची जा रही है...";
  List<DarvasSignal> signalList = [];

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
        marketStatus = "🟢 बाजार चालू है (IST: $timeStr) | ऑटो बैकग्राउंड एक्टिव";
      } else {
        marketStatus = "🔴 बाजार बंद है (IST: $timeStr)";
      }
    });
  }

  Future<void> runFullDarvasScan() async {
    if (isScanning) return;
    setState(() {
      isScanning = true;
    });

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

            double riskAmount = totalCapital * 0.01;
            double riskPerShare = (currentPrice - boxBottom).abs();
            if (riskPerShare < 1.0) riskPerShare = currentPrice * 0.02;
            int qty = (riskAmount / riskPerShare).floor();
            if (qty < 1) qty = 1;

            double target1 = boxTop + (boxHeight * 2);
            double addLevel = boxTop + boxHeight;
            double nextTarget = addLevel + (boxHeight * 2);

            if (currentPrice > boxTop &&
                currentPrice > ema50 &&
                currentVol >= (avgVol20 * 1.15)) {
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
    final buySignals = signalList
        .where((s) => s.status == "BUY" || s.status == "ADD (Pyramid)")
        .toList();
    final otherSignals = signalList
        .where((s) => s.status != "BUY" && s.status != "ADD (Pyramid)")
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('📈 Darvas Pro Auto Pilot',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          IconButton(
            tooltip: "टेस्ट नोटिफिकेशन",
            icon: const Icon(Icons.notifications_active),
            onPressed: () {
              triggerNotification(
                "🔔 Darvas Pro Test Alert",
                "WorkManager और नोटिफिकेशन सर्विस बैकग्राउंड के लिए तैयार है!",
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
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  "कैपिटल: ₹${totalCapital.toStringAsFixed(0)}",
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF10B981)),
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
                      label: const Text("लाइव स्कैन शुरू करें"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(10),
                    children: [
                      if (buySignals.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text("🔥 एक्टिव ब्रेकआउट व ऐड सिग्नल्स",
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF10B981))),
                        ),
                        ...buySignals.map((s) => buildSignalCard(s)),
                      ],
                      if (otherSignals.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text("📊 होल्ड व एग्जिट वॉचलिस्ट",
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white70)),
                        ),
                        ...otherSignals.map((s) => buildSignalCard(s)),
                      ],
                    ],
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

  Widget buildSignalCard(DarvasSignal s) {
    Color badgeColor = s.status == "BUY"
        ? const Color(0xFF10B981)
        : s.status == "ADD (Pyramid)"
            ? Colors.blueAccent
            : s.status == "EXIT"
                ? Colors.redAccent
                : Colors.orange;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  s.symbol,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: badgeColor),
                  ),
                  child: Text(
                    s.status,
                    style: TextStyle(
                        color: badgeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "वर्तमान भाव: ₹${s.currentPrice.toStringAsFixed(2)}",
              style: const TextStyle(fontSize: 15, color: Colors.white),
            ),
            const Divider(height: 16, color: Colors.white24),
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
                      Text("🛑 Stop-Loss: ₹${s.stopLoss.toStringAsFixed(1)}",
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
                      Text("➕ Add Level: ₹${s.addLevel.toStringAsFixed(1)}",
                          style: const TextStyle(
                              color: Colors.lightBlueAccent, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text("🚀 Next Target: ₹${s.nextTarget.toStringAsFixed(1)}",
                          style: const TextStyle(
                              color: Colors.cyanAccent, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text("📦 Qty (1% Risk): ${s.suggestedQty} Shares",
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
                  color: Colors.white60,
                  fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}
