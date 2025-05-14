import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => CanBusProvider()),
    ],
    child: const MyApp(),
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'canDrive Mobile',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF252526),
          elevation: 0,
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF252526),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class CanPacket {
  final double timestamp;
  final String id;
  final String ext;
  final String rtr;
  final String data;
  final String label;

  CanPacket({
    required this.timestamp,
    required this.id,
    required this.ext,
    required this.rtr,
    required this.data,
    required this.label,
  });

  factory CanPacket.fromJson(Map<String, dynamic> json) {
    try {
      return CanPacket(
        timestamp: (json['timestamp'] ?? 0).toDouble(),
        id: json['id'] ?? '',
        ext: json['ext'] ?? '00',
        rtr: json['rtr'] ?? '00',
        data: json['data'] ?? '',
        label: json['label'] ?? '',
      );
    } catch (e) {
      print('Errore nella creazione del pacchetto: $e');
      // Restituisci un pacchetto vuoto in caso di errore
      return CanPacket(
        timestamp: 0,
        id: '',
        ext: '00',
        rtr: '00',
        data: '',
        label: '',
      );
    }
  }

  String get formattedTimestamp {
    return timestamp.toStringAsFixed(3);
  }

  String get formattedData {
    final buffer = StringBuffer();
    for (int i = 0; i < data.length; i += 2) {
      if (i + 2 <= data.length) {
        buffer.write(data.substring(i, i + 2));
        buffer.write(' ');
      }
    }
    return buffer.toString().trim();
  }

  int get dataLength {
    return data.length ~/ 2;
  }
}

class CanBusProvider extends ChangeNotifier {
  final String _baseUrl = 'http://192.168.1.100:5000/api';
  IO.Socket? _socket;
  bool _isConnected = false;
  bool _isSniffing = false;
  String _selectedPort = '';
  List<String> _availablePorts = [];
  List<CanPacket> _packets = [];
  Map<String, int> _idCounts = {};
  Map<String, String> _labels = {};
  Set<String> _filteredIds = {};

  bool get isConnected => _isConnected;
  bool get isSniffing => _isSniffing;
  String get selectedPort => _selectedPort;
  List<String> get availablePorts => _availablePorts;
  List<CanPacket> get packets => _packets;
  Map<String, int> get idCounts => _idCounts;
  Map<String, String> get labels => _labels;
  Set<String> get filteredIds => _filteredIds;

  CanBusProvider() {
    _loadSettings();
  }
  
  // Metodo pubblico per impostare la porta selezionata
  void setSelectedPort(String port) {
    _selectedPort = port;
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedPort = prefs.getString('selectedPort') ?? '';
    final filteredIdsString = prefs.getStringList('filteredIds') ?? [];
    _filteredIds = filteredIdsString.toSet();
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('selectedPort', _selectedPort);
    prefs.setStringList('filteredIds', _filteredIds.toList());
  }

  void initSocket() {
    try {
      _socket = IO.io('http://192.168.1.100:5000', <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
        'reconnection': true,
        'reconnectionAttempts': 5,
        'reconnectionDelay': 1000,
      });

      _socket?.on('connect', (_) {
        print('Socket connesso');
        notifyListeners();
      });

      _socket?.on('can_packet', (data) {
        try {
          final packet = CanPacket.fromJson(data);
          _addPacket(packet);
        } catch (e) {
          print('Errore nella decodifica del pacchetto: $e');
        }
      });

      _socket?.on('disconnect', (_) {
        print('Socket disconnesso');
        notifyListeners();
      });

      _socket?.on('error', (error) {
        print('Errore socket: $error');
      });

      _socket?.connect();
    } catch (e) {
      print('Errore nell\'inizializzazione del socket: $e');
    }
  }

  void disposeSocket() {
    try {
      _socket?.disconnect();
      _socket?.dispose();
      _socket = null;
    } catch (e) {
      print('Errore nella chiusura del socket: $e');
    }
  }

  void _addPacket(CanPacket packet) {
    if (packet.id.isEmpty || packet.data.isEmpty) {
      print('Pacchetto non valido: ID o dati mancanti');
      return;
    }
    
    _packets.add(packet);
    if (_packets.length > 1000) {
      _packets.removeAt(0);
    }

    // Aggiorna il conteggio degli ID
    if (_idCounts.containsKey(packet.id)) {
      _idCounts[packet.id] = (_idCounts[packet.id] ?? 0) + 1;
    } else {
      _idCounts[packet.id] = 1;
    }

    // Aggiorna l'etichetta se presente
    if (packet.label.isNotEmpty) {
      _labels[packet.id] = packet.label;
    }

    notifyListeners();
  }

  Future<void> scanPorts() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/ports'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _availablePorts = List<String>.from(data['ports']);
        notifyListeners();
      }
    } catch (e) {
      print('Errore nella scansione delle porte: $e');
    }
  }

  Future<bool> connect(String port, {int baudrate = 115200}) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/connect'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'port': port, 'baudrate': baudrate}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          _isConnected = true;
          _selectedPort = port;
          _saveSettings();
          initSocket();
          notifyListeners();
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Errore nella connessione: $e');
      return false;
    }
  }

  Future<bool> disconnect() async {
    try {
      final response = await http.post(Uri.parse('$_baseUrl/disconnect'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          _isConnected = false;
          _isSniffing = false;
          disposeSocket();
          notifyListeners();
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Errore nella disconnessione: $e');
      return false;
    }
  }

  Future<bool> startSniffing() async {
    try {
      final response = await http.post(Uri.parse('$_baseUrl/start_sniffing'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          _isSniffing = true;
          _packets.clear();
          _idCounts.clear();
          notifyListeners();
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Errore nell\'avvio dello sniffing: $e');
      return false;
    }
  }

  Future<bool> stopSniffing() async {
    try {
      final response = await http.post(Uri.parse('$_baseUrl/stop_sniffing'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          _isSniffing = false;
          notifyListeners();
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Errore nell\'arresto dello sniffing: $e');
      return false;
    }
  }

  Future<bool> sendPacket(String id, String data, {String ext = '00', String rtr = '00'}) async {
    try {
      // Validazione dei dati prima dell'invio
      if (id.isEmpty || !RegExp(r'^[0-9A-Fa-f]+$').hasMatch(id)) {
        print('ID non valido: $id');
        return false;
      }
      
      if (data.isEmpty || !RegExp(r'^[0-9A-Fa-f]+$').hasMatch(data) || data.length % 2 != 0) {
        print('Dati non validi: $data');
        return false;
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/send_packet'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': id, 'ext': ext, 'rtr': rtr, 'data': data}),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        return responseData['success'] ?? false;
      }
      return false;
    } catch (e) {
      print('Errore nell\'invio del pacchetto: $e');
      return false;
    }
  }

  void toggleIdFilter(String id) {
    if (_filteredIds.contains(id)) {
      _filteredIds.remove(id);
    } else {
      _filteredIds.add(id);
    }
    _saveSettings();
    notifyListeners();
  }

  void clearFilters() {
    _filteredIds.clear();
    _saveSettings();
    notifyListeners();
  }

  List<CanPacket> get filteredPackets {
    if (_filteredIds.isEmpty) {
      return _packets;
    }
    return _packets.where((packet) => !_filteredIds.contains(packet.id)).toList();
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('canDrive Mobile'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.list), text: 'Messaggi'),
            Tab(icon: Icon(Icons.filter_list), text: 'Filtri'),
            Tab(icon: Icon(Icons.send), text: 'Invio'),
          ],
        ),
        actions: [
          Consumer<CanBusProvider>(builder: (context, provider, child) {
            return IconButton(
              icon: Icon(provider.isSniffing ? Icons.stop : Icons.play_arrow),
              onPressed: provider.isConnected
                  ? () async {
                      if (provider.isSniffing) {
                        await provider.stopSniffing();
                      } else {
                        await provider.startSniffing();
                      }
                    }
                  : null,
              tooltip: provider.isSniffing ? 'Ferma sniffing' : 'Avvia sniffing',
            );
          }),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'connect') {
                _showConnectionDialog(context);
              } else if (value == 'disconnect') {
                final provider = Provider.of<CanBusProvider>(context, listen: false);
                await provider.disconnect();
              }
            },
            itemBuilder: (context) {
              final provider = Provider.of<CanBusProvider>(context, listen: false);
              return [
                if (!provider.isConnected)
                  const PopupMenuItem<String>(
                    value: 'connect',
                    child: Text('Connetti'),
                  ),
                if (provider.isConnected)
                  const PopupMenuItem<String>(
                    value: 'disconnect',
                    child: Text('Disconnetti'),
                  ),
              ];
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          MessagesTab(),
          FiltersTab(),
          SendTab(),
        ],
      ),
    );
  }

  void _showConnectionDialog(BuildContext context) async {
    final provider = Provider.of<CanBusProvider>(context, listen: false);
    await provider.scanPorts();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connetti alla porta seriale'),
        content: SizedBox(
          width: double.maxFinite,
          child: Consumer<CanBusProvider>(builder: (context, provider, child) {
            return provider.availablePorts.isEmpty
                ? const Text('Nessuna porta disponibile')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...provider.availablePorts.map((port) => RadioListTile<String>(
                            title: Text(port),
                            value: port,
                            groupValue: provider.selectedPort,
                            onChanged: (value) {
                              if (value != null) {
                                // Utilizziamo un setter pubblico invece di accedere direttamente alla proprietà privata
                                provider.setSelectedPort(value);
                              }
                            },
                          )),
                    ],
                  );
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          Consumer<CanBusProvider>(builder: (context, provider, child) {
            return TextButton(
              onPressed: provider.selectedPort.isEmpty
                  ? null
                  : () async {
                      final success = await provider.connect(provider.selectedPort);
                      if (success && mounted) {
                        Navigator.pop(context);
                      }
                    },
              child: const Text('Connetti'),
            );
          }),
        ],
      ),
    );
  }
}

class MessagesTab extends StatelessWidget {
  const MessagesTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<CanBusProvider>(builder: (context, provider, child) {
      final packets = provider.filteredPackets;
      return packets.isEmpty
          ? const Center(child: Text('Nessun messaggio ricevuto'))
          : ListView.builder(
              itemCount: packets.length,
              itemBuilder: (context, index) {
                final packet = packets[packets.length - 1 - index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    title: Row(
                      children: [
                        Text(
                          packet.id,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        if (packet.label.isNotEmpty)
                          Expanded(
                            child: Text(
                              packet.label,
                              style: const TextStyle(fontStyle: FontStyle.italic),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tempo: ${packet.formattedTimestamp}s'),
                        Text('Dati: ${packet.formattedData}'),
                      ],
                    ),
                    trailing: Text('${packet.dataLength} byte'),
                    onTap: () => _showPacketDetails(context, packet),
                  ),
                );
              },
            );
    });
  }

  void _showPacketDetails(BuildContext context, CanPacket packet) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Dettagli pacchetto ${packet.id}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (packet.label.isNotEmpty) Text('Etichetta: ${packet.label}'),
            Text('Timestamp: ${packet.formattedTimestamp}s'),
            Text('ID: ${packet.id}'),
            Text('EXT: ${packet.ext}'),
            Text('RTR: ${packet.rtr}'),
            Text('Lunghezza dati: ${packet.dataLength} byte'),
            const SizedBox(height: 8),
            const Text('Dati (hex):', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(packet.formattedData),
            const SizedBox(height: 8),
            const Text('Dati (bin):', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(_hexToBinary(packet.data)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  String _hexToBinary(String hex) {
    final buffer = StringBuffer();
    for (int i = 0; i < hex.length; i += 2) {
      if (i + 2 <= hex.length) {
        final hexByte = hex.substring(i, i + 2);
        final intValue = int.parse(hexByte, radix: 16);
        final binary = intValue.toRadixString(2).padLeft(8, '0');
        buffer.write(binary);
        buffer.write(' ');
      }
    }
    return buffer.toString().trim();
  }
}

class FiltersTab extends StatelessWidget {
  const FiltersTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<CanBusProvider>(builder: (context, provider, child) {
      final idCounts = provider.idCounts;
      final sortedIds = idCounts.keys.toList()
        ..sort((a, b) => idCounts[b]!.compareTo(idCounts[a]!));

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'ID trovati: ${idCounts.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: provider.clearFilters,
                  child: const Text('Cancella filtri'),
                ),
              ],
            ),
          ),
          Expanded(
            child: idCounts.isEmpty
                ? const Center(child: Text('Nessun ID trovato'))
                : ListView.builder(
                    itemCount: sortedIds.length,
                    itemBuilder: (context, index) {
                      final id = sortedIds[index];
                      final count = idCounts[id]!;
                      final label = provider.labels[id] ?? '';
                      final isFiltered = provider.filteredIds.contains(id);

                      return ListTile(
                        title: Row(
                          children: [
                            Text(
                              id,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isFiltered ? Colors.grey : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (label.isNotEmpty)
                              Expanded(
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontStyle: FontStyle.italic,
                                    color: isFiltered ? Colors.grey : null,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$count msg'),
                            Checkbox(
                              value: !isFiltered,
                              onChanged: (_) => provider.toggleIdFilter(id),
                            ),
                          ],
                        ),
                        onTap: () => provider.toggleIdFilter(id),
                      );
                    },
                  ),
          ),
        ],
      );
    });
  }
}

class SendTab extends StatefulWidget {
  const SendTab({Key? key}) : super(key: key);

  @override
  State<SendTab> createState() => _SendTabState();
}

class _SendTabState extends State<SendTab> {
  final _idController = TextEditingController();
  final _dataController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _idController.dispose();
    _dataController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CanBusProvider>(builder: (context, provider, child) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _idController,
                decoration: const InputDecoration(
                  labelText: 'ID CAN (hex)',
                  hintText: 'es. 7DF',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Inserisci un ID valido';
                  }
                  if (!RegExp(r'^[0-9A-Fa-f]+$').hasMatch(value)) {
                    return 'Inserisci un valore esadecimale valido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _dataController,
                decoration: const InputDecoration(
                  labelText: 'Dati (hex)',
                  hintText: 'es. 0102030405060708',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Inserisci dei dati validi';
                  }
                  if (!RegExp(r'^[0-9A-Fa-f]+$').hasMatch(value)) {
                    return 'Inserisci un valore esadecimale valido';
                  }
                  if (value.length % 2 != 0) {
                    return 'La lunghezza dei dati deve essere pari';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: provider.isConnected
                    ? () async {
                        if (_formKey.currentState!.validate()) {
                          final success = await provider.sendPacket(
                            _idController.text,
                            _dataController.text,
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  success
                                      ? 'Pacchetto inviato con successo'
                                      : 'Errore nell\'invio del pacchetto',
                                ),
                                backgroundColor:
                                    success ? Colors.green : Colors.red,
                              ),
                            );
                          }
                        }
                      }
                    : null,
                child: const Text('Invia pacchetto'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Nota: Assicurati che l\'applicazione desktop sia connessa alla stessa porta seriale e che il server API sia in esecuzione.',
                style: TextStyle(fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    });
  }
}