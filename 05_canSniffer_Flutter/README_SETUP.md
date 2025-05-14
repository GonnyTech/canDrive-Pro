# Guida all'installazione e utilizzo dell'integrazione Flutter

Questa guida spiega come configurare e utilizzare l'integrazione tra l'applicazione desktop canSniffer e l'app Flutter per visualizzare i messaggi CAN da smartphone.

## Prerequisiti

- Python 3.7 o superiore
- Flutter SDK 2.10 o superiore
- Android Studio o Xcode (per compilare l'app mobile)
- Un dispositivo Arduino con il firmware canSniffer

## Configurazione del server API

1. Navigare nella directory del server API:
   ```
   cd 05_canSniffer_Flutter/api_server
   ```

2. Installare le dipendenze Python:
   ```
   pip install -r requirements.txt
   ```

3. Avviare il server API:
   ```
   python can_api_server.py
   ```

   Il server sarà disponibile all'indirizzo `http://localhost:5000`.

4. Prendere nota dell'indirizzo IP del computer su cui è in esecuzione il server API. Sarà necessario per configurare l'app Flutter.

## Configurazione dell'app Flutter

1. Navigare nella directory dell'app Flutter:
   ```
   cd 05_canSniffer_Flutter/flutter_app
   ```

2. Modificare l'indirizzo IP del server nel file `lib/main.dart`:
   ```dart
   // Cerca questa riga e sostituisci l'indirizzo IP con quello del tuo computer
   final String _baseUrl = 'http://192.168.1.100:5000/api';
   ```

3. Installare le dipendenze Flutter:
   ```
   flutter pub get
   ```

4. Compilare e installare l'app sul dispositivo mobile:
   ```
   flutter run
   ```

## Utilizzo

### Utilizzo simultaneo con l'applicazione desktop

È possibile utilizzare l'app Flutter contemporaneamente all'applicazione desktop canSniffer, ma è necessario seguire questi passaggi:

1. Avviare prima il server API
2. Connettere l'applicazione desktop canSniffer alla porta seriale dell'Arduino
3. Avviare l'app Flutter e connettersi alla stessa porta seriale

### Utilizzo indipendente

L'app Flutter può anche essere utilizzata indipendentemente dall'applicazione desktop:

1. Avviare il server API
2. Connettere l'app Flutter alla porta seriale dell'Arduino
3. Iniziare lo sniffing dei messaggi CAN

## Risoluzione dei problemi

### L'app Flutter non si connette al server API

- Verificare che il server API sia in esecuzione
- Controllare che l'indirizzo IP configurato nell'app Flutter sia corretto
- Assicurarsi che il dispositivo mobile e il computer siano sulla stessa rete

### Non vengono visualizzati messaggi CAN

- Verificare che l'Arduino sia correttamente collegato al bus CAN del veicolo
- Controllare che la velocità del bus CAN configurata nell'Arduino sia corretta
- Assicurarsi che lo sniffing sia stato avviato nell'app

### Conflitti con l'applicazione desktop

- Se entrambe le applicazioni tentano di accedere alla stessa porta seriale contemporaneamente, potrebbero verificarsi conflitti
- Utilizzare porte seriali diverse per l'applicazione desktop e l'app Flutter, se possibile
- In alternativa, utilizzare solo una delle due applicazioni alla volta