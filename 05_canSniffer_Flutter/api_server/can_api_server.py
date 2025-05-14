# canDrive @ 2024
# Server API per l'integrazione con l'app Flutter
#----------------------------------------------------------------
import os
import time
import json
import threading
import serial
import serial.tools.list_ports
from flask import Flask, jsonify, request
from flask_socketio import SocketIO, emit
from flask_cors import CORS
import sys

# Aggiungi il percorso della directory principale per importare i moduli esistenti
sys.path.append(os.path.join(os.path.dirname(__file__), '..', '..', '02_canSniffer_GUI'))

# Importa i moduli esistenti dal progetto canSniffer
import SerialReader
import SerialWriter

app = Flask(__name__)
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*")

# Classe per gestire la comunicazione CAN e condividere i dati con l'app Flutter
class CanBusManager:
    def __init__(self):
        self.serial_controller = serial.Serial()
        self.serial_reader = None
        self.serial_writer = None
        self.is_connected = False
        self.is_sniffing = False
        self.received_packets = []
        self.id_dict = {}
        self.label_dict = {}
        self.start_time = 0
        
        # Carica le etichette salvate se disponibili
        self.load_label_dict()
    
    def load_label_dict(self):
        try:
            label_dict_path = os.path.join(os.path.dirname(__file__), '..', '..', '02_canSniffer_GUI', 'save', 'labelDict.csv')
            if os.path.exists(label_dict_path):
                with open(label_dict_path, 'r') as f:
                    for line in f:
                        if ',' in line:
                            parts = line.strip().split(',', 1)
                            if len(parts) == 2:
                                self.label_dict[parts[0]] = parts[1]
        except Exception as e:
            print(f"Errore nel caricamento delle etichette: {e}")
    
    def scan_ports(self):
        ports = []
        for port in serial.tools.list_ports.comports():
            ports.append(port.device)
        return ports
    
    def connect(self, port, baudrate=115200):
        try:
            if self.is_connected:
                self.disconnect()
                
            self.serial_controller.port = port
            self.serial_controller.baudrate = baudrate
            self.serial_controller.timeout = 0.1
            self.serial_controller.open()
            
            self.serial_reader = SerialReader.SerialReaderThread(self.serial_controller)
            self.serial_writer = SerialWriter.SerialWriterThread(self.serial_controller)
            
            self.serial_reader.receivedPacketSignal.connect(self.on_packet_received)
            self.serial_reader.start()
            self.serial_writer.start()
            
            self.is_connected = True
            return True
        except Exception as e:
            print(f"Errore di connessione: {e}")
            return False
    
    def disconnect(self):
        if self.is_connected:
            try:
                if self.serial_reader:
                    self.serial_reader.stop()
                if self.serial_writer:
                    self.serial_writer.stop()
                if self.serial_controller.is_open:
                    self.serial_controller.close()
                self.is_connected = False
                return True
            except Exception as e:
                print(f"Errore di disconnessione: {e}")
                return False
        return True
    
    def start_sniffing(self):
        if self.is_connected and not self.is_sniffing:
            self.start_time = time.time()
            self.is_sniffing = True
            return True
        return False
    
    def stop_sniffing(self):
        if self.is_sniffing:
            self.is_sniffing = False
            return True
        return False
    
    def on_packet_received(self, data, timestamp):
        if not self.is_sniffing:
            return
            
        try:
            # Formato del pacchetto: ID,EXT,RTR,DATA
            parts = data.strip().split(',')
            if len(parts) >= 4:
                can_id = parts[0]
                ext = parts[1]
                rtr = parts[2]
                data_bytes = ''.join(parts[3:])
                
                # Crea un pacchetto formattato
                packet = {
                    'timestamp': timestamp - self.start_time,
                    'id': can_id,
                    'ext': ext,
                    'rtr': rtr,
                    'data': data_bytes,
                    'label': self.label_dict.get(can_id, '')
                }
                
                # Aggiorna la lista dei pacchetti ricevuti
                self.received_packets.append(packet)
                if len(self.received_packets) > 1000:  # Limita la dimensione della lista
                    self.received_packets = self.received_packets[-1000:]
                
                # Aggiorna il dizionario degli ID
                if can_id not in self.id_dict:
                    self.id_dict[can_id] = 1
                else:
                    self.id_dict[can_id] += 1
                
                # Emetti il pacchetto tramite Socket.IO
                socketio.emit('can_packet', packet)
        except Exception as e:
            print(f"Errore nell'elaborazione del pacchetto: {e}")
    
    def send_packet(self, can_id, ext, rtr, data):
        if not self.is_connected:
            return False
            
        try:
            # Formatta il pacchetto per l'invio
            packet = f"{can_id},{ext},{rtr},{data}\n"
            self.serial_writer.write(packet)
            return True
        except Exception as e:
            print(f"Errore nell'invio del pacchetto: {e}")
            return False
    
    def get_recent_packets(self, limit=100):
        return self.received_packets[-limit:]
    
    def get_id_dict(self):
        return self.id_dict
    
    def get_label_dict(self):
        return self.label_dict

# Crea un'istanza del gestore CAN
can_manager = CanBusManager()

# Definisci le route API
@app.route('/api/ports', methods=['GET'])
def get_ports():
    ports = can_manager.scan_ports()
    return jsonify({'ports': ports})

@app.route('/api/connect', methods=['POST'])
def connect():
    data = request.json
    port = data.get('port')
    baudrate = data.get('baudrate', 115200)
    
    if not port:
        return jsonify({'success': False, 'error': 'Porta non specificata'}), 400
        
    success = can_manager.connect(port, baudrate)
    return jsonify({'success': success})

@app.route('/api/disconnect', methods=['POST'])
def disconnect():
    success = can_manager.disconnect()
    return jsonify({'success': success})

@app.route('/api/start_sniffing', methods=['POST'])
def start_sniffing():
    success = can_manager.start_sniffing()
    return jsonify({'success': success})

@app.route('/api/stop_sniffing', methods=['POST'])
def stop_sniffing():
    success = can_manager.stop_sniffing()
    return jsonify({'success': success})

@app.route('/api/packets', methods=['GET'])
def get_packets():
    limit = request.args.get('limit', 100, type=int)
    packets = can_manager.get_recent_packets(limit)
    return jsonify({'packets': packets})

@app.route('/api/ids', methods=['GET'])
def get_ids():
    ids = can_manager.get_id_dict()
    return jsonify({'ids': ids})

@app.route('/api/labels', methods=['GET'])
def get_labels():
    labels = can_manager.get_label_dict()
    return jsonify({'labels': labels})

@app.route('/api/send_packet', methods=['POST'])
def send_packet():
    data = request.json
    can_id = data.get('id')
    ext = data.get('ext', '00')
    rtr = data.get('rtr', '00')
    data_bytes = data.get('data', '')
    
    if not can_id:
        return jsonify({'success': False, 'error': 'ID CAN non specificato'}), 400
        
    success = can_manager.send_packet(can_id, ext, rtr, data_bytes)
    return jsonify({'success': success})

# Socket.IO events
@socketio.on('connect')
def handle_connect():
    print('Client connesso')

@socketio.on('disconnect')
def handle_disconnect():
    print('Client disconnesso')

# Avvia il server
if __name__ == '__main__':
    socketio.run(app, host='0.0.0.0', port=5000, debug=True, allow_unsafe_werkzeug=True)