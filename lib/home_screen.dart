import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:percent_indicator/percent_indicator.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final String userName = "User${DateTime.now().millisecondsSinceEpoch % 1000}";
  Map<String, ConnectionInfo> endpointMap = {};
  String? selectedEndpointId;
  List<String> filesToSend = [];
  bool isAdvertising = false;
  bool isDiscovering = false;
  bool isSending = false;
  bool isReceiving = false;
  double sendingProgress = 0.0;
  double receivingProgress = 0.0;
  String currentReceivingFile = '';
  String currentSendingFile = '';

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.storage.request();
    await Permission.location.request();
    await Permission.bluetooth.request();
    await Permission.bluetoothAdvertise.request();
    await Permission.bluetoothConnect.request();
    await Permission.bluetoothScan.request();
    await Permission.nearbyWifiDevices.request();
  }

  Future<bool> _checkPermissions() async {
    if (await Permission.storage.isGranted &&
        await Permission.location.isGranted &&
        await Permission.bluetooth.isGranted &&
        await Permission.bluetoothAdvertise.isGranted &&
        await Permission.bluetoothConnect.isGranted &&
        await Permission.bluetoothScan.isGranted &&
        await Permission.nearbyWifiDevices.isGranted) {
      return true;
    } else {
      Fluttertoast.showToast(msg: "Please grant all permissions");
      return false;
    }
  }

  Future<void> _startAdvertising() async {
    try {
      await Nearby().startAdvertising(
        userName,
        Strategy.P2P_CLUSTER,
        onConnectionInitiated: (id, info) {
          _onConnectionInitiated(id, info);
        },
        onConnectionResult: (id, status) {
          _onConnectionResult(id, status);
        },
        onDisconnected: (id) {
          _onDisconnected(id);
        },
      );
      setState(() {
        isAdvertising = true;
      });
      Fluttertoast.showToast(msg: "Advertising started");
    } catch (e) {
      Fluttertoast.showToast(msg: "Error starting advertising: $e");
    }
  }

  Future<void> _stopAdvertising() async {
    await Nearby().stopAdvertising();
    setState(() {
      isAdvertising = false;
    });
    Fluttertoast.showToast(msg: "Advertising stopped");
  }

  Future<void> _startDiscovery() async {
    try {
      await Nearby().startDiscovery(
        userName,
        Strategy.P2P_CLUSTER,
        onEndpointFound: (id, name, serviceId) {
          _onEndpointFound(id, name);
        },
        onEndpointLost: (id) {
          _onEndpointLost(id!);
        },
      );
      setState(() {
        isDiscovering = true;
      });
      Fluttertoast.showToast(msg: "Discovery started");
    } catch (e) {
      Fluttertoast.showToast(msg: "Error starting discovery: $e");
    }
  }

  Future<void> _stopDiscovery() async {
    await Nearby().stopDiscovery();
    setState(() {
      isDiscovering = false;
    });
    Fluttertoast.showToast(msg: "Discovery stopped");
  }

  void _onEndpointFound(String id, String name) {
    setState(() {
      endpointMap[id] = ConnectionInfo(name, id, true);
    });
    Fluttertoast.showToast(msg: "Found endpoint: $name");
  }

  void _onEndpointLost(String id) {
    setState(() {
      endpointMap.remove(id);
      if (selectedEndpointId == id) {
        selectedEndpointId = null;
      }
    });
    Fluttertoast.showToast(msg: "Lost endpoint: $id");
  }

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (endpointId, payload) {
        _onPayloadReceived(endpointId, payload);
      },
      onPayloadTransferUpdate: (endpointId, payloadTransferUpdate) {
        _onPayloadTransferUpdate(endpointId, payloadTransferUpdate);
      },
    );
    Fluttertoast.showToast(
        msg: "Connection initiated with ${info.endpointName}");
  }

  void _onConnectionResult(String id, Status status) {
    if (status == Status.CONNECTED) {
      Fluttertoast.showToast(
          msg: "Connected to ${endpointMap[id]?.endpointName}");
    } else {
      Fluttertoast.showToast(msg: "Failed to connect: $status");
      setState(() {
        endpointMap.remove(id);
        if (selectedEndpointId == id) {
          selectedEndpointId = null;
        }
      });
    }
  }

  void _onDisconnected(String id) {
    Fluttertoast.showToast(
        msg: "Disconnected from ${endpointMap[id]?.endpointName}");
    setState(() {
      endpointMap.remove(id);
      if (selectedEndpointId == id) {
        selectedEndpointId = null;
      }
    });
  }

  void _onPayloadReceived(String endpointId, Payload payload) async {
    if (payload.type == PayloadType.BYTES) {
      String str = String.fromCharCodes(payload.bytes!);
      Fluttertoast.showToast(msg: "Received message: $str");
    } else if (payload.type == PayloadType.FILE) {
      final filePath = payload.filePath;
      if (filePath != null) {
        final directory = await getExternalStorageDirectory();
        final newFilePath = '${directory!.path}/${filePath.split('/').last}';
        File(filePath).renameSync(newFilePath);
        Fluttertoast.showToast(msg: "File received: $newFilePath");
      }
      setState(() {
        isReceiving = true;
        currentReceivingFile = payload.id.toString();
        receivingProgress = 0.0;
      });

      // File is automatically saved to Downloads folder by the plugin
      // You can access it using payload.filePath after transfer is complete
      Fluttertoast.showToast(msg: "File received: ${payload.filePath}");
    }
  }

  void _onPayloadTransferUpdate(
      String endpointId, PayloadTransferUpdate update) {
    if (update.status == PayloadStatus.IN_PROGRESS) {
      double progress = update.bytesTransferred / update.totalBytes;
      if (update.status == PayloadStatus.IN_PROGRESS) {
        setState(() {
          if (isSending) {
            sendingProgress = progress;
          } else if (isReceiving) {
            receivingProgress = progress;
          }
        });
      } else {
        if (isSending) {
          isSending = false;
          sendingProgress = 0.0;
          currentSendingFile = '';
          Fluttertoast.showToast(msg: 'File sent successfully');
        } else if (isReceiving) {
          isReceiving = false;
          receivingProgress = 0.0;
          currentReceivingFile = '';
          Fluttertoast.showToast(msg: 'File received successfully');
        }

        setState(() {
          // receivingProgress = progress;
        });
      }
    } else if (update.status == PayloadStatus.SUCCESS) {
      setState(() {
        if (isSending) {
          isSending = false;
          sendingProgress = 0.0;
          currentSendingFile = '';
          Fluttertoast.showToast(msg: 'File Sent Successfully');
        } else if (isReceiving) {
          isReceiving = false;
          receivingProgress = 0.0;
          currentReceivingFile = '';
          Fluttertoast.showToast(msg: 'File Received Successfully');
        }
        // isSending = false;
        // sendingProgress = 0.0;
        // currentSendingFile = '';
      });
    } else if (update.status == PayloadStatus.FAILURE) {
      setState(() {
        if (isSending) {
          isSending = false;
          sendingProgress = 0.0;
          currentSendingFile = '';
          Fluttertoast.showToast(msg: "File sending failed");
        } else if (isReceiving) {
          isReceiving = false;
          receivingProgress = 0.0;
          currentReceivingFile = '';
          Fluttertoast.showToast(msg: "File receiving failed");
        }
      });
    }
  }

  Future<void> _requestConnection(String endpointId) async {
    if (endpointMap.containsKey(endpointId)) {
      try {
        await Nearby().requestConnection(
          userName,
          endpointId,
          onConnectionInitiated: (id, info) {
            _onConnectionInitiated(id, info);
          },
          onConnectionResult: (id, status) {
            _onConnectionResult(id, status);
          },
          onDisconnected: (id) {
            _onDisconnected(id);
          },
        );
        setState(() {
          selectedEndpointId = endpointId;
        });
      } catch (e) {
        Fluttertoast.showToast(msg: "Error requesting connection: $e");
      }
    }
  }

  Future<void> _disconnect(String endpointId) async {
    await Nearby().disconnectFromEndpoint(endpointId);
    setState(() {
      if (selectedEndpointId == endpointId) {
        selectedEndpointId = null;
      }
    });
  }

  Future<void> _pickFiles() async {
    try {
      FilePickerResult? result =
          await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result != null) {
        setState(() {
          filesToSend = result.paths.map((path) => path!).toList();
        });
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "Error picking files: $e");
    }
  }

  Future<void> _sendFiles() async {
    // if (!await _checkPermissions()) return;
    if (selectedEndpointId == null || filesToSend.isEmpty) return;

    setState(() {
      isSending = true;
      sendingProgress = 0.0;
    });

    try {
      for (String filePath in filesToSend) {
        File file = File(filePath);
        log("File: $file");

        if (!file.existsSync()) {
          Fluttertoast.showToast(msg: 'File does not exist: $filePath');
          continue;
        }

        String fileName = filePath.split('/').last;
        currentSendingFile = fileName;

        await Nearby().sendFilePayload(
          selectedEndpointId!,
          filePath,
        );
        Fluttertoast.showToast(msg: 'File Transfer Initiated: $fileName');
      }

      setState(() {
        filesToSend.clear();
      });
    } catch (e) {
      setState(() {
        isSending = false;
        sendingProgress = 0.0;
        currentSendingFile = '';
      });
      Fluttertoast.showToast(msg: "Error sending files: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('K Share'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Connection Controls
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        'Connection',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            onPressed: isAdvertising
                                ? _stopAdvertising
                                : _startAdvertising,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  isAdvertising ? Colors.red : Colors.green,
                            ),
                            child: Text(isAdvertising
                                ? 'Stop Advertising'
                                : 'Start Advertising'),
                          ),
                          ElevatedButton(
                            onPressed: isDiscovering
                                ? _stopDiscovery
                                : _startDiscovery,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  isDiscovering ? Colors.red : Colors.green,
                            ),
                            child: Text(isDiscovering
                                ? 'Stop Discovery'
                                : 'Start Discovery'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Nearby Devices
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        'Nearby Devices',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      if (endpointMap.isEmpty) const Text('No devices found'),
                      ...endpointMap.entries.map((entry) {
                        final isConnected = selectedEndpointId == entry.key;
                        return ListTile(
                          title: Text(entry.value.endpointName),
                          trailing: isConnected
                              ? IconButton(
                                  icon: const Icon(Icons.close,
                                      color: Colors.red),
                                  onPressed: () => _disconnect(entry.key),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.link,
                                      color: Colors.green),
                                  onPressed: () =>
                                      _requestConnection(entry.key),
                                ),
                          subtitle:
                              isConnected ? const Text('Connected') : null,
                          tileColor: isConnected
                              ? Colors.green.withOpacity(0.1)
                              : null,
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),

              // File Transfer
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        'File Transfer',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: _pickFiles,
                        child: const Text('Select Files to Send'),
                      ),
                      const SizedBox(height: 10),
                      if (filesToSend.isNotEmpty)
                        Column(
                          children: [
                            const Text('Selected Files:'),
                            ...filesToSend
                                .map((path) => Text(path.split('/').last))
                                .toList(),
                            const SizedBox(height: 10),
                            ElevatedButton(
                              onPressed: selectedEndpointId != null
                                  ? _sendFiles
                                  : null,
                              child: const Text('Send Files'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              // Transfer Status
              if (isSending || isReceiving)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Text(
                          'Transfer Status',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        if (isSending)
                          Column(
                            children: [
                              const Text('Sending:'),
                              Text(currentSendingFile),
                              LinearPercentIndicator(
                                percent: sendingProgress,
                                center: Text(
                                    '${(sendingProgress * 100).toStringAsFixed(1)}%'),
                                lineHeight: 20.0,
                                progressColor: Colors.green,
                              ),
                            ],
                          ),
                        if (isReceiving)
                          Column(
                            children: [
                              const Text('Receiving:'),
                              Text(currentReceivingFile),
                              LinearPercentIndicator(
                                percent: receivingProgress,
                                center: Text(
                                    '${(receivingProgress * 100).toStringAsFixed(1)}%'),
                                lineHeight: 20.0,
                                progressColor: Colors.blue,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
