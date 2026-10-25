import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const DarvasProApp());
}

class DarvasProApp extends StatelessWidget {
  const DarvasProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Darvas Pro',
      theme: ThemeData.dark(),
      home: const DarvasHomeScreen(),
    );
  }
}

class DarvasHomeScreen extends StatefulWidget {
  const DarvasHomeScreen({super.key});

  @override
  State<DarvasHomeScreen> createState() => _DarvasHomeScreenState();
}

class _DarvasHomeScreenState extends State<DarvasHomeScreen> {
  List<Map<String, dynamic>> scanResults = [];
  bool isLoading = false;

  final List<String> stocks = [
    "HAL", "BEL", "TRENT", "SBIN", "RELIANCE", "DIXON", 
    "POLYCAB", "ZOMATO", "TITAN", "BAJFINANCE", "TATAMOTORS"
  ];

  Future<void> runDarvasScan() async {
    setState(() {
      isLoading = true;
      scanResults.clear();
    });

    for (String symbol in stocks) {
      try {
        final url = Uri.parse('https://query1.finance.yahoo.com/v8/finance/chart/$symbol.NS?interval=1d&range=3mo');
        final response = await http.get(url);

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final indicators = data['chart']['result'][0]['indicators']['quote'][0];
          final closes = List<double>.from(indicators['close'].where((x) => x != null));
          final highs = List<double>.from(indicators['high'].where((x) => x != null));
          final lows = List<double>.from(indicators['low'].where((x) => x != null));

          if (closes.length > 25) {
            double currentPrice = closes.last;
            double boxTop = highs.sublist(highs.length - 20, highs.length - 1).reduce((a, b) => a > b ? a : b);
            double boxBottom = lows.sublist(lows.length - 20, lows.length - 1).reduce((a, b) => a < b ? a : b);

            String signal = "HOLD";
            if (currentPrice > boxTop) {
              signal = "BUY";
            } else if (currentPrice < boxBottom) {
              signal = "EXIT";
            }

            scanResults.add({
              'stock': symbol,
              'price': currentPrice.toStringAsFixed(2),
              'boxTop': boxTop.toStringAsFixed(2),
              'boxBottom': boxBottom.toStringAsFixed(2),
              'signal': signal,
            });
          }
        }
      } catch (e) {
        // network issue ignore karein
      }
    }

    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📈 Darvas Pro Live Scanner'),
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 15),
                  Text("डार्वस बॉक्स स्कैन हो रहा है..."),
                ],
              ),
            )
          : scanResults.isEmpty
              ? const Center(child: Text('लाइव स्कैन करने के लिए नीचे बटन दबाएं'))
              : ListView.builder(
                  itemCount: scanResults.length,
                  itemBuilder: (context, index) {
                    final item = scanResults[index];
                    Color badgeColor = item['signal'] == "BUY"
                        ? Colors.green
                        : item['signal'] == "EXIT"
                            ? Colors.red
                            : Colors.orange;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: badgeColor,
                          child: Text(
                            item['signal'] == "BUY" ? "B" : item['signal'] == "EXIT" ? "E" : "H",
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text("${item['stock']}  •  ₹${item['price']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("Box Top: ₹${item['boxTop']} | Stop-Loss: ₹${item['boxBottom']}"),
                        trailing: Text(
                          item['signal'],
                          style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: runDarvasScan,
        label: const Text('लाइव स्कैन करें'),
        icon: const Icon(Icons.refresh),
      ),
    );
  }
}