import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  runApp(const DarvasProApp());
}

class DarvasProApp extends StatelessWidget {
  const DarvasProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Darvas Pro Auto',
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
  final String status; // BUY, ADD (Pyramid), HOLD, EXIT
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
  bool isAutoPilot = true;
  bool isScanning = false;
  String marketStatus = "मार्केट की स्थिति जांची जा रही है...";
  Timer? autoScanTimer;
  List<DarvasSignal> signalList = [];

  // Nifty 500 हाई-मोमेंटम कोर स्टॉक्स
  final List<String> nifty500Core = [
    "HAL", "BEL", "TRENT", "DIXON", "ZOMATO", "POLYCAB", "PERSISTENT",
    "COFORGE", "RELIANCE", "SBIN", "BHARTIARTL", "LT", "BAJFINANCE",
    "M&M", "SUNPHARMA", "TITAN", "TATAMOTORS", "ADANIENT", "DLF", "SIEMENS",
    "ABB", "CUMMINSIND", "CHOLAFIN", "MUTHOOTFIN", "SHRIRAMFIN", "VEDL",
    "HCLTECH", "NTPC", "POWERGRID", "TATASTEEL", "MAZDOCK", "BSE", "CDSL"
  ];

  @override
  void initState() {
    super.initState();
    checkMarketAndStartTimer();
  }

  @override
  void dispose() {
    autoScanTimer?.cancel();
    super.dispose();
  }

  // भारतीय समय (IST) जांचना
  bool isIndianMarketOpen() {
    final nowUtc = DateTime.now().toUtc();
    final nowIst = nowUtc.add(const Duration(hours: 5, minutes: 30));

    // शनिवार (6) और रविवार (7) बंद
    if (nowIst.weekday == DateTime.saturday || nowIst.weekday == DateTime.sunday) {
      return false;
    }

    final marketOpen = DateTime(nowIst.year, nowIst.month, nowIst.day, 9, 0);
    final marketClose = DateTime(nowIst.year, nowIst.month, nowIst.day, 15, 30);

    return nowIst.isAfter(marketOpen) && nowIst.isBefore(marketClose);
  }

  void checkMarketAndStartTimer() {
    updateMarketStatusMessage();
    // हर 10 मिनट में ऑटोमैटिक चक्र
    autoScanTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      updateMarketStatusMessage();
      if (isIndianMarketOpen() && isAutoPilot) {
        runFullDarvasScan();
      }
    });

    // ऐप खुलते ही तुरंत पहला स्कैन
    runFullDarvasScan();
  }

  void updateMarketStatusMessage() {
    final nowUtc = DateTime.now().toUtc();
    final nowIst = nowUtc.add(const Duration(hours: 5, minutes: 30));
    setState(() {
      if (isIndianMarketOpen()) {
        marketStatus = "🟢 भारतीय बाजार चालू है (9:00 AM - 3:30 PM)";
      } else {
        marketStatus = "🔴 बाजार बंद है (IST: ${nowIst.hour.toString().padLeft(2, '0')}:${nowIst.minute.toString().padLeft(2, '0')})";
      }
    });
  }

  Future<void> sendNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'darvas_channel_id',
      'Darvas Alerts',
      channelDescription: 'Real-time Darvas Box Buy/Sell signals',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );
    const NotificationDetails notificationDetails = NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond,
      title,
      body,
      notificationDetails,
    );
  }

  // डार्वस बॉक्स अल्गोरिदम
  Future<void> runFullDarvasScan() async {
    if (isScanning) return;
    setState(() {
      isScanning = true;
    });

    List<DarvasSignal> tempResults = [];

    for (String symbol in nifty500Core) {
      try {
        final url = Uri.parse(
            'https://query1.finance.yahoo.com/v8/finance/chart/$symbol.NS?interval=1d&range=6mo');
        final response = await http.get(url, headers: {
          'User-Agent': 'Mozilla/5.0 (Android; Mobile; rv:109.0) Gecko/109.0 Firefox/119.0'
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

          if (closes.length >= 45) {
            double currentPrice = closes.last;
            double currentVol = volumes.last;

            // 20 दिन का औसत वॉल्यूम
            double avgVol20 = volumes
                    .sublist(volumes.length - 21, volumes.length - 1)
                    .reduce((a, b) => a + b) /
                20;

            // 50 दिन EMA
            double ema50 = closes.sublist(closes.length - 35).reduce((a, b) => a + b) / 35;

            // डार्वस 3-Day Pivot Box
            double boxTop = highs.sublist(highs.length - 20, highs.length - 2).reduce((a, b) => a > b ? a : b);
            double boxBottom = lows.sublist(lows.length - 20, lows.length - 2).reduce((a, b) => a < b ? a : b);
            double boxHeight = boxTop - boxBottom;

            // 1% रिस्क प्रबंधन
            double riskAmount = totalCapital * 0.01;
            double riskPerShare = (currentPrice - boxBottom).abs();
            if (riskPerShare < 1.0) riskPerShare = currentPrice * 0.02;
            int qty = (riskAmount / riskPerShare).floor();
            if (qty < 1) qty = 1;

            double target1 = boxTop + (boxHeight * 2);
            double addLevel = boxTop + boxHeight; // अगला बॉक्स ब्रेकआउट
            double nextTarget = addLevel + (boxHeight * 2);

            // सिग्नल की गणना
            if (currentPrice > boxTop && currentPrice > ema50 && currentVol >= (avgVol20 * 1.2)) {
              // फ्रेश ब्रेकआउट
              final sig = DarvasSignal(
                symbol: symbol,
                status: "BUY",
                currentPrice: currentPrice,
                entryPrice: boxTop,
                stopLoss: boxBottom,
                target1: target1,
                addLevel: addLevel,
                nextTarget: nextTarget,
                suggestedQty: qty,
                reason: "बॉक्स टॉप ब्रेकआउट + 1.2x वॉल्यूम पुष्टि!",
              );
              tempResults.add(sig);
              sendNotification(
                "🟢 BUY ALERT: $symbol @ ₹${currentPrice.toStringAsFixed(1)}",
                "Entry: ₹$boxTop | SL: ₹$boxBottom | Target: ₹${target1.toStringAsFixed(1)} | Qty: $qty",
              );
            } else if (currentPrice > addLevel) {
              // पिरामिडिंग (Pyramiding - शेयर जोड़ने का स्तर)
              final sig = DarvasSignal(
                symbol: symbol,
                status: "ADD (Pyramid)",
                currentPrice: currentPrice,
                entryPrice: addLevel,
                stopLoss: boxTop, // Trailed SL
                target1: nextTarget,
                addLevel: addLevel + boxHeight,
                nextTarget: nextTarget + boxHeight,
                suggestedQty: (qty * 0.5).floor().clamp(1, 9999),
                reason: "नया बॉक्स ब्रेकआउट! पुरानी पोजीशन में और शेयर जोड़ें।",
              );
              tempResults.add(sig);
            } else if (currentPrice < boxBottom) {
              // स्टॉप लॉस हिट
              final sig = DarvasSignal(
                symbol: symbol,
                status: "EXIT",
                currentPrice: currentPrice,
                entryPrice: boxTop,
                stopLoss: boxBottom,
                target1: target1,
                addLevel: addLevel,
                nextTarget: nextTarget,
                suggestedQty: 0,
                reason: "बॉक्स बॉटम टूट गया! तुरंत बाहर निकलें।",
              );
              tempResults.add(sig);
              sendNotification(
                "🔴 EXIT ALERT: $symbol @ ₹${currentPrice.toStringAsFixed(1)}",
                "स्टॉप-लॉस टूट गया है! पूंजी की सुरक्षा के लिए एग्जिट करें।",
              );
            } else {
              // बॉक्स के अंदर होल्ड
              final sig = DarvasSignal(
                symbol: symbol,
                status: "HOLD",
                currentPrice: currentPrice,
                entryPrice: boxTop,
                stopLoss: boxBottom,
                target1: target1,
                addLevel: addLevel,
                nextTarget: nextTarget,
                suggestedQty: qty,
                reason: "डार्वस बॉक्स के अंदर कंसॉलिडेशन चल रहा है।",
              );
              tempResults.add(sig);
            }
          }
        }
      } catch (_) {
        // नेटवर्क एरर होने पर अगले शेयर पर जाएं
      }
    }

    setState(() {
      signalList = tempResults;
      isScanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final buySignals = signalList.where((s) => s.status == "BUY" || s.status == "ADD (Pyramid)").toList();
    final otherSignals = signalList.where((s) => s.status != "BUY" && s.status != "ADD (Pyramid)").toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('📈 Darvas Pro Auto Pilot', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => showSettingsDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          // स्टेटस बार
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
                  "कैपिटल: ₹${totalCapital.toStringAsFixed(0)}",
                  style: const TextStyle(fontSize: 13, color: Color(0xFF10B981)),
                ),
              ],
            ),
          ),
          if (isScanning)
            const LinearProgressIndicator(color: Color(0xFF10B981)),

          Expanded(
            child: signalList.isEmpty && !isScanning
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.candlestick_chart, size: 60, color: Colors.grey),
                        const SizedBox(height: 12),
                        const Text("डेटा लोड करने के लिए नीचे 'लाइव स्कैन' दबाएं"),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: runFullDarvasScan,
                          icon: const Icon(Icons.refresh),
                          label: const Text("लाइव स्कैन शुरू करें"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                          ),
                        )
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(10),
                    children: [
                      if (buySignals.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text("🔥 एक्टिव ब्रेकआउट व ऐड सिग्नल्स",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                        ),
                        ...buySignals.map((s) => buildSignalCard(s)),
                      ],
                      if (otherSignals.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text("📊 होल्ड व एग्जिट वॉचलिस्ट",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)),
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
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: badgeColor),
                  ),
                  child: Text(
                    s.status,
                    style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 13),
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

            // ट्रेडिंग मैट्रिक्स
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("🎯 Entry: ₹${s.entryPrice.toStringAsFixed(1)}",
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text("🛑 Stop-Loss: ₹${s.stopLoss.toStringAsFixed(1)}",
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text("🏁 Target 1: ₹${s.target1.toStringAsFixed(1)}",
                          style: const TextStyle(color: Colors.yellowAccent, fontSize: 13)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("➕ Add Level: ₹${s.addLevel.toStringAsFixed(1)}",
                          style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text("🚀 Next Target: ₹${s.nextTarget.toStringAsFixed(1)}",
                          style: const TextStyle(color: Colors.cyanAccent, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text("📦 Qty (1% Risk): ${s.suggestedQty} Shares",
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "विवरण: ${s.reason}",
              style: const TextStyle(fontSize: 12, color: Colors.white60, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  void showSettingsDialog() {
    final controller = TextEditingController(text: totalCapital.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("सेटिंग्स"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "कुल ट्रेडिंग पूंजी (₹)"),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              title: const Text("ऑटो-पायलट स्कैन"),
              subtitle: const Text("9:00 AM - 3:30 PM ऑटो स्कैन"),
              value: isAutoPilot,
              onChanged: (val) {
                setState(() => isAutoPilot = val);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                totalCapital = double.tryParse(controller.text) ?? 100000.0;
              });
              Navigator.pop(ctx);
            },
            child: const Text("सेव करें"),
          )
        ],
      ),
    );
  }
}
