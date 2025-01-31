import "dart:developer";
import "dart:io";
import 'dart:typed_data';

import "package:flutter/material.dart";
import 'package:nearby_connections/nearby_connections.dart';
import "package:file_picker/file_picker.dart";
import "package:path_provider/path_provider.dart";
import "package:permission_handler/permission_handler.dart";

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final Strategy strategy = Strategy.P2P_CLUSTER;
  List<String> discoverdDevices = [];
  String connectedDevice = "";
  bool isAdevertising = false;
  bool isDiscovering = false;

  @override
  void initState() {
    super.initState();
    requestPermissions();
  }

  void requestPermissions() async {
    await [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.bluetoothScan,
      Permission.storage,
      Permission.nearbyWifiDevices
    ].request();
  }

  void startAdvertising() async {
    try {
      bool success = await Nearby().startAdvertising(
          "Device-${DateTime.now().millisecondsSinceEpoch}", strategy,
          onConnectionInitiated: onConnectionInitiated,
          onConnectionResult: (id, status) {
        if (status == Status.CONNECTED) {
          setState(() {
            connectedDevice = id;
          });
        }
      }, onDisconnected: (id) {
        setState(() {
          connectedDevice = "";
        });
      });
      if (success) setState(() => isAdevertising = true);
    } catch (err) {
      log("Error advertising: $err");
    }
  }

  void startDiscovery() async {
    try {
      bool success = await Nearby().startDiscovery(
          "Device-${DateTime.now().millisecondsSinceEpoch}", strategy,
          onEndpointFound: (id, name, serviceId) {
        setState(() {
          discoverdDevices.add(id);
        });
      }, onEndpointLost: (id) {
        setState(() {
          discoverdDevices.remove(id);
        });
      });
      if (success) setState(() => isDiscovering = true);
    } catch (err) {
      log("Error discovering: $err");
    }
  }

  void stopAdvertising() {
    Nearby().stopAdvertising();
    setState(() => isAdevertising = false);
  }

  void onConnectionInitiated(String id, ConnectionInfo info) {
    Nearby().acceptConnection(id, onPayLoadRecieved: (id, payload) async {
      if (payload.type == PayloadType.BYTES) {
        String fileName = String.fromCharCode(payload.bytes! as int);
        List<Directory>? dir = await getExternalStorageDirectories();
        File file = File("${dir?[0].path}/$fileName");
        file.writeAsBytes(payload.bytes!);
        log("Received File: $fileName at ${file.path}");
      }
    });
  }

  void sendFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null && connectedDevice.isNotEmpty) {
      File file = File(result.files.single.path!);

      try {
        // Payload filePayload = Payload.fromFile(file.path); // Corrected method
        Nearby().sendFilePayload(connectedDevice, file as String);
        print("Sending: ${file.path}");
      } catch (e) {
        print("Error sending file: $e");
      }
    } else {
      print("No file selected or no device connected.");
    }
  }

  void stopDiscovery() {
    Nearby().stopDiscovery();
    setState(() => isDiscovering = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: Text("KAbbeeSHare"),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              ElevatedButton(
                  child:
                      const Text("Check Bluetooth Permission (>= Android 12"),
                  onPressed: () async {
                    if (!(await Future.wait([
                      Permission.bluetooth.isGranted,
                      Permission.bluetoothAdvertise.isGranted,
                      Permission.bluetoothConnect.isGranted,
                      Permission.bluetoothScan.isGranted
                    ]))
                        .any((element) => false)) {
                      log("Bluetooth permission granted");
                    } else {
                      log("Bluetooth permission is not granted");
                    }
                  }),
              ElevatedButton(
                onPressed: isAdevertising ? stopAdvertising : startAdvertising,
                child: Text(
                    isAdevertising ? "Stop Advertising" : "Start Advertising"),
              ),
              ElevatedButton(
                  onPressed: isDiscovering ? stopDiscovery : startDiscovery,
                  child: Text(isDiscovering
                      ? "Stop Discovering"
                      : "Start Discovering")),
              const SizedBox(height: 20),
              Text("Discovered Devices"),
              Expanded(
                child: ListView.builder(
                  itemCount: discoverdDevices.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      title: Text(
                        discoverdDevices[index],
                      ),
                      trailing: ElevatedButton(
                        onPressed: () => Nearby().requestConnection(
                            "Device-${DateTime.now().millisecondsSinceEpoch}",
                            discoverdDevices[index],
                            onConnectionInitiated: onConnectionInitiated,
                            onConnectionResult: (id, status) {},
                            onDisconnected: (id) {}),
                        child: Text("Connect"),
                      ),
                    );
                  },
                ),
              ),
              if (connectedDevice.isNotEmpty)
                Column(
                  children: [
                    Text("Connected to: $connectedDevice"),
                    ElevatedButton(
                        onPressed: sendFile, child: Text("Send File"))
                  ],
                )
            ],
          ),
        ),
      ),
    );
  }
}
