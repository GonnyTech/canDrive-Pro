import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

// Importa il provider dall'app principale
import 'main.dart';

class CanPacketDetailPage extends StatefulWidget {
  final String canId;

  const CanPacketDetailPage({Key? key, required this.canId}) : super(key: key);

  @override
  State<CanPacketDetailPage> createState() => _CanPacketDetailPageState();
}

class _CanPacketDetailPageState extends State<CanPacketDetailPage> {
  int _selectedByteIndex = -1;
  bool _showBinaryView = false;
  bool _showChart = true;

  @override
  Widget build(BuildContext context) {
    return Consumer<CanBusProvider>(builder: (context, provider, child) {
      // Filtra i pacchetti per l'ID selezionato
      final packetsWithId = provider.packets
          .where((packet) => packet.id == widget.canId)
          .toList();

      // Ottieni l'etichetta per questo ID
      final label = provider.labels[widget.canId] ?? '';

      return Scaffold(
        appBar: AppBar(
          title: Text('Dettagli ID: ${widget.canId}'),
          actions: [
            IconButton(
              icon: Icon(_showChart ? Icons.show_chart : Icons.bar_chart),
              onPressed: () {
                setState(() {
                  _showChart = !_showChart;
                });
              },
              tooltip: _showChart ? 'Nascondi grafico' : 'Mostra grafico',
            ),
            IconButton(
              icon: Icon(_showBinaryView ? Icons.hexagon : Icons.numbers),
              onPressed: () {
                setState(() {
                  _showBinaryView = !_showBinaryView;
                });
              },
              tooltip: _showBinaryView ? 'Vista esadecimale' : 'Vista binaria',
            ),
          ],
        ),
        body: packetsWithId.isEmpty
            ? const Center(child: Text('Nessun pacchetto trovato per questo ID'))
            : Column(
                children: [
                  // Informazioni sull'ID
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label.isNotEmpty ? label : 'ID: ${widget.canId}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Pacchetti ricevuti: ${packetsWithId.length}',
                              style: const TextStyle(fontSize: 14),
                            ),
                            Text(
                              'Lunghezza dati: ${packetsWithId.last.dataLength} byte',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Grafico dei valori nel tempo
                  if (_showChart && packetsWithId.length > 1)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: SizedBox(
                        height: 200,
                        child: _buildDataChart(packetsWithId),
                      ),
                    ),

                  // Visualizzazione byte per byte
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: _buildByteGrid(packetsWithId.last),
                  ),

                  // Dettagli del byte selezionato
                  if (_selectedByteIndex >= 0)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: _buildByteDetail(packetsWithId, _selectedByteIndex),
                    ),

                  // Lista degli ultimi pacchetti
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Card(
                        child: ListView.builder(
                          itemCount: packetsWithId.length,
                          itemBuilder: (context, index) {
                            final packet =
                                packetsWithId[packetsWithId.length - 1 - index];
                            return ListTile(
                              title: Text(
                                'Tempo: ${packet.formattedTimestamp}s',
                                style: const TextStyle(fontSize: 14),
                              ),
                              subtitle: Text(
                                _showBinaryView
                                    ? _formatBinary(packet.data)
                                    : packet.formattedData,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      );
    });
  }

  Widget _buildByteGrid(CanPacket packet) {
    final byteCount = packet.dataLength;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dati (byte per byte):',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(byteCount, (index) {
                final byteValue = _getByteAt(packet.data, index);
                final isSelected = index == _selectedByteIndex;
                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedByteIndex = isSelected ? -1 : index;
                    });
                  },
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                          : Theme.of(context).cardColor,
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade700,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Byte $index',
                          style: const TextStyle(fontSize: 10),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _showBinaryView
                              ? _byteToFormattedBinary(byteValue)
                              : byteValue,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildByteDetail(List<CanPacket> packets, int byteIndex) {
    // Estrai i valori del byte selezionato da tutti i pacchetti
    final byteValues = packets
        .map((p) => int.parse(_getByteAt(p.data, byteIndex), radix: 16))
        .toList();

    // Calcola min, max e media
    final min = byteValues.reduce((a, b) => a < b ? a : b);
    final max = byteValues.reduce((a, b) => a > b ? a : b);
    final avg = byteValues.reduce((a, b) => a + b) / byteValues.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dettagli Byte $byteIndex',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatCard('Min', min.toInt()),
                _buildStatCard('Max', max.toInt()),
                _buildStatCard('Media', avg.toInt()),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Rappresentazioni:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildRepresentationCard(
                  'Hex',
                  byteValues.last.toRadixString(16).padLeft(2, '0').toUpperCase(),
                ),
                _buildRepresentationCard(
                  'Dec',
                  byteValues.last.toString(),
                ),
                _buildRepresentationCard(
                  'Bin',
                  byteValues.last.toRadixString(2).padLeft(8, '0'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, int value) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value.toString(),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildRepresentationCard(String title, String value) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade700),
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDataChart(List<CanPacket> packets) {
    // Se è selezionato un byte specifico, mostra solo quel byte
    final byteIndex = _selectedByteIndex >= 0 ? _selectedByteIndex : 0;

    // Estrai i dati per il grafico
    final spots = <FlSpot>[];
    for (int i = 0; i < packets.length; i++) {
      final packet = packets[i];
      final byteValue = int.parse(_getByteAt(packet.data, byteIndex), radix: 16);
      spots.add(FlSpot(i.toDouble(), byteValue.toDouble()));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: Theme.of(context).colorScheme.primary,
            barWidth: 2,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
        ],
      ),
    );
  }

  String _getByteAt(String data, int index) {
    if (index * 2 + 2 <= data.length) {
      return data.substring(index * 2, index * 2 + 2);
    }
    return '00';
  }

  String _formatBinary(String hexData) {
    final buffer = StringBuffer();
    for (int i = 0; i < hexData.length; i += 2) {
      if (i + 2 <= hexData.length) {
        final hexByte = hexData.substring(i, i + 2);
        final intValue = int.parse(hexByte, radix: 16);
        final binary = intValue.toRadixString(2).padLeft(8, '0');
        buffer.write(binary);
        buffer.write(' ');
      }
    }
    return buffer.toString().trim();
  }

  String _byteToFormattedBinary(String hexByte) {
    final intValue = int.parse(hexByte, radix: 16);
    return intValue.toRadixString(2).padLeft(8, '0');
  }
}