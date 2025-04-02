import "dart:developer";
import "dart:io";
import "dart:typed_data";
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
  List<String> discoveredDevices = [];
  String connectedDevice = "";
  bool isAdvertising = false;
  bool isDiscovering = false;
  String deviceName = "Device-${DateTime.now().millisecondsSinceEpoch}";

  @override
  void initState() {
    super.initState();
    requestPermissions();
  }

  void requestPermissions() async {
    await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.storage,
      Permission.nearbyWifiDevices
    ].request();
  }

  void startAdvertising() async {
    try {
      bool success = await Nearby().startAdvertising(
        deviceName,
        strategy,
        onConnectionInitiated: onConnectionInitiated,
        onConnectionResult: (id, status) {
          log('id: $id');
          log("Status: $status");
          if (status == Status.CONNECTED) {
            setState(() {
              connectedDevice = id;
            });
          }
        },
        onDisconnected: (id) {
          connectedDevice = "";
          setState(() {});
        },
      );
      log("SUCCESS ADVERTISING: $success");
      if (success) setState(() => isAdvertising = true);
      log('isAdvertising: $isAdvertising');
    } catch (err) {
      log("Error advertising: $err");
    }
  }

  void startDiscovery() async {
    try {
      bool success = await Nearby().startDiscovery(
        deviceName,
        strategy,
        onEndpointFound: (id, name, serviceId) {
          log('Found Device: $name ($id)');
          setState(() {
            discoveredDevices.add(id);
          });
        },
        onEndpointLost: (id) {
          setState(() {
            discoveredDevices.remove(id);
          });
        },
      );
      if (success) setState(() => isDiscovering = true);
    } catch (err) {
      log("Error discovering: $err");
    }
  }

  void stopAdvertising() {
    Nearby().stopAdvertising();
    setState(() => isAdvertising = false);
  }

  void stopDiscovery() {
    Nearby().stopDiscovery();
    setState(() => isDiscovering = false);
  }

  void onConnectionInitiated(String id, ConnectionInfo info) {
    connectedDevice = id;
    setState(() {});
    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (id, payload) async {
        if (payload.type == PayloadType.FILE) {
          log("Receiving file...");
        } else if (payload.type == PayloadType.BYTES) {
          String fileName = String.fromCharCodes(payload.bytes!);
          log("Receiving metadata: $fileName");
        }
      },
      onPayloadTransferUpdate: (id, payloadTransferUpdate) async {
        if (payloadTransferUpdate.status == PayloadStatus.IN_PROGRESS) {
          log("File transfer in progress: ${payloadTransferUpdate.bytesTransferred}/${payloadTransferUpdate.totalBytes}");
        } else if (payloadTransferUpdate.status == PayloadStatus.SUCCESS) {
          log("File transfer successful! Processing file...");

          // Move received file to a readable directory
          List<Directory>? externalDirs = await getExternalStorageDirectories();
          if (externalDirs != null && externalDirs.isNotEmpty) {
            String targetPath = "${externalDirs.first.path}/received_file";
            File receivedFile = File(targetPath);
            log("File saved at: $targetPath");
          } else {
            log("Could not access external storage.");
          }
        } else if (payloadTransferUpdate.status == PayloadStatus.FAILURE) {
          log("File transfer failed!");
        }
      },
    );
  }

  void sendFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null && connectedDevice.isNotEmpty) {
      File file = File(result.files.single.path!);

      try {
        // Send file payload
        int payloadId =
            await Nearby().sendFilePayload(connectedDevice, file.path);
        log("Sending file: ${file.path}");

        // Send file name as metadata
        Uint8List fileNameBytes =
            Uint8List.fromList(file.uri.pathSegments.last.codeUnits);
        Nearby().sendBytesPayload(connectedDevice, fileNameBytes);
      } catch (e) {
        log("Error sending file: $e");
      }
    } else {
      log("No file selected or no device connected.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text("KAbbeeShare")),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              ElevatedButton(
                onPressed: isAdvertising ? stopAdvertising : startAdvertising,
                child: Text(
                    isAdvertising ? "Stop Advertising" : "Start Advertising"),
              ),
              ElevatedButton(
                onPressed: isDiscovering ? stopDiscovery : startDiscovery,
                child: Text(
                    isDiscovering ? "Stop Discovering" : "Start Discovering"),
              ),
              const SizedBox(height: 20),
              Text("Discovered Devices"),
              Expanded(
                child: ListView.builder(
                  itemCount: discoveredDevices.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      title: Text(discoveredDevices[index]),
                      trailing: ElevatedButton(
                        onPressed: () => Nearby().requestConnection(
                          deviceName,
                          discoveredDevices[index],
                          onConnectionInitiated: onConnectionInitiated,
                          onConnectionResult: (id, status) {},
                          onDisconnected: (id) {},
                        ),
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
                        onPressed: sendFile, child: Text("Send File")),
                  ],
                )
            ],
          ),
        ),
      ),
    );
  }
}
