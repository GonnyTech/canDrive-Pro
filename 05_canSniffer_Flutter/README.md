# canSniffer Flutter App

Questo modulo contiene un'app Flutter per visualizzare i messaggi CAN da dispositivi mobili e un server API che si integra con l'applicazione desktop canSniffer.

## Struttura

- `api_server/`: Server API Python che espone i dati CAN tramite REST API
- `flutter_app/`: Applicazione Flutter per dispositivi mobili

## Funzionalità

- Visualizzazione in tempo reale dei messaggi CAN
- Sincronizzazione con l'applicazione desktop
- Interfaccia utente ottimizzata per dispositivi mobili
- Supporto per la decodifica dei pacchetti CAN

## Requisiti

### Server API
- Python 3.7+
- Flask
- PySerial
- Flask-SocketIO

### App Flutter
- Flutter SDK 2.10+
- Dart 2.16+
- Dipendenze gestite tramite pubspec.yaml