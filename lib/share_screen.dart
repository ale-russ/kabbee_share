import 'dart:math';
import 'dart:typed_data';
import 'dart:developer' as developer;

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:permission_handler/permission_handler.dart'
    as permission_handler;

class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  final String userName = Random().nextInt(10000).toString();
  final Strategy strategy = Strategy.P2P_STAR;
  Map<String, ConnectionInfo> endpointMap = {};

  double sendingProgress = 0.0;
  double receivingProgress = 0.0;
  bool isSending = false;
  bool isReceiving = false;
  String currentSendingFile = ""; //file currently being sent
  String currentReceivingFile = ""; //file currently being received

  String? tempFileUri; //reference to the file currently being transferred
  Map<int, String> map = {}; //store filename mapped to corresponding payloadId
  Map<permission_handler.Permission, permission_handler.PermissionStatus>
      statuses = {};
  List<permission_handler.Permission> notGrantedPermissions = [];

  Future<void> checkAndRequestPermissions(
      List<permission_handler.Permission> permissions) async {
    //Filter only permissions that are not granted
    for (var permission in permissions) {
      if (!(await permission.isGranted)) {
        notGrantedPermissions.add(permission);
        setState(() {});
      }
    }

    //Request only the permissions that are not granted
    if (notGrantedPermissions.isNotEmpty) {
      // Map<permission_handler.Permission, permission_handler.PermissionStatus>
      statuses = await notGrantedPermissions.request();
      setState(() {});

      developer.log("Permissions: $statuses");

      bool allGranted = statuses.values.every((status) => status.isGranted);

      if (allGranted) {
        showSnackbar("All permissions granted :)");
      } else {
        showSnackbar("Some permissions are not granted :(");
      }
    } else {
      showSnackbar("All permissions already granted :)");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ListView(
          children: <Widget>[
            const Text(
              "Permissions",
            ),
            Wrap(
              children: <Widget>[
                ElevatedButton(
                    onPressed: () async {
                      await checkAndRequestPermissions(
                        [
                          permission_handler.Permission.locationWhenInUse,
                          permission_handler.Permission.storage,
                          permission_handler.Permission.bluetooth,
                          permission_handler.Permission.bluetoothAdvertise,
                          permission_handler.Permission.bluetoothConnect,
                          permission_handler.Permission.bluetoothScan,
                          permission_handler.Permission.nearbyWifiDevices,
                        ],
                      );
                    },
                    child: Text('Request All Permissions')),
              ],
            ),
            notGrantedPermissions.isNotEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: notGrantedPermissions
                        .map((element) => ElevatedButton(
                            onPressed: () => element,
                            child: Text(element.toString())))
                        .toList(),
                  )
                : const SizedBox.shrink(),
            const Divider(),
            Text("User Name: $userName"),
            Wrap(
              children: <Widget>[
                ElevatedButton(
                  child: const Text("Start Advertising"),
                  onPressed: () async {
                    try {
                      bool a = await Nearby().startAdvertising(
                        userName,
                        strategy,
                        onConnectionInitiated: onConnectionInit,
                        onConnectionResult: (id, status) {
                          showSnackbar(status);
                        },
                        onDisconnected: (id) {
                          showSnackbar(
                              "Disconnected: ${endpointMap[id]!.endpointName}, id $id");
                          setState(() {
                            endpointMap.remove(id);
                          });
                        },
                      );
                      showSnackbar("ADVERTISING: $a");
                    } catch (exception) {
                      showSnackbar(exception);
                    }
                  },
                ),
                ElevatedButton(
                  child: const Text("Stop Advertising"),
                  onPressed: () async {
                    await Nearby().stopAdvertising();
                  },
                ),
              ],
            ),
            Wrap(
              children: <Widget>[
                ElevatedButton(
                  child: const Text("Start Discovery"),
                  onPressed: () async {
                    try {
                      bool a = await Nearby().startDiscovery(
                        userName,
                        strategy,
                        onEndpointFound: (id, name, serviceId) {
                          // show sheet automatically to request connection
                          showModalBottomSheet(
                            context: context,
                            builder: (builder) {
                              return Center(
                                child: Column(
                                  children: <Widget>[
                                    Text("id: $id"),
                                    Text("Name: $name"),
                                    Text("ServiceId: $serviceId"),
                                    ElevatedButton(
                                      child: const Text("Request Connection"),
                                      onPressed: () {
                                        Navigator.pop(context);
                                        Nearby().requestConnection(
                                          userName,
                                          id,
                                          onConnectionInitiated: (id, info) {
                                            onConnectionInit(id, info);
                                          },
                                          onConnectionResult: (id, status) {
                                            showSnackbar(status);
                                          },
                                          onDisconnected: (id) {
                                            setState(() {
                                              endpointMap.remove(id);
                                            });
                                            showSnackbar(
                                                "Disconnected from: ${endpointMap[id]!.endpointName}, id $id");
                                          },
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                        onEndpointLost: (id) {
                          showSnackbar(
                              "Lost discovered Endpoint: ${endpointMap[id]?.endpointName}, id $id");
                        },
                      );
                      showSnackbar("DISCOVERING: $a");
                    } catch (e) {
                      showSnackbar(e);
                    }
                  },
                ),
                ElevatedButton(
                  child: const Text("Stop Discovery"),
                  onPressed: () async {
                    await Nearby().stopDiscovery();
                  },
                ),
              ],
            ),
            Text("Number of connected devices: ${endpointMap.length}"),
            ElevatedButton(
              child: const Text("Stop All Endpoints"),
              onPressed: () async {
                await Nearby().stopAllEndpoints();
                setState(() {
                  endpointMap.clear();
                });
              },
            ),
            const Divider(),
            const Text(
              "Sending Data",
            ),
            ElevatedButton(
              child: const Text("Send Random Bytes Payload"),
              onPressed: () async {
                endpointMap.forEach((key, value) {
                  String a = Random().nextInt(100).toString();

                  showSnackbar("Sending $a to ${value.endpointName}, id: $key");
                  Nearby()
                      .sendBytesPayload(key, Uint8List.fromList(a.codeUnits));
                });
              },
            ),
            ElevatedButton(
              child: const Text("Send File Payload"),
              onPressed: () async {
                FilePickerResult? file = await FilePicker.platform.pickFiles();

                if (file == null || file.files.single.path == null) return;
                setState(() {
                  isSending = true;
                  sendingProgress = 0.0;
                  currentSendingFile = file.files.single.name;
                });

                String filePath = file.files.single.path!;

                for (MapEntry<String, ConnectionInfo> entry
                    in endpointMap.entries) {
                  int payloadId =
                      await Nearby().sendFilePayload(entry.key, filePath);
                  showSnackbar("Sending file to ${entry.key}");
                  Nearby().sendBytesPayload(
                      entry.key,
                      Uint8List.fromList(
                          "$payloadId:${filePath.split('/').last}".codeUnits));
                }
              },
            ),
            ElevatedButton(
              child: const Text("Print file names."),
              onPressed: () async {
                final dir = (await getExternalStorageDirectory())!;
                final files = (await dir.list(recursive: true).toList())
                    .map((f) => f.path)
                    .toList()
                    .join('\n');
                showSnackbar(files);
              },
            ),
            if (isSending || isReceiving)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text('Transfer Status',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      if (isSending)
                        Column(
                          children: [
                            const Text('Sending: '),
                            Text(currentSendingFile),
                            LinearPercentIndicator(
                              percent: sendingProgress,
                              center: Text(
                                  '${(sendingProgress * 100).toStringAsFixed(1)}%'),
                              lineHeight: 20.0,
                              progressBorderColor: Colors.green,
                            )
                          ],
                        ),
                      if (isReceiving)
                        Column(
                          children: [
                            const Text('Receiving: '),
                            Text(currentReceivingFile),
                            LinearPercentIndicator(
                              percent: receivingProgress,
                              center: Text(
                                  '${(receivingProgress * 100).toStringAsFixed(1)}%'),
                              lineHeight: 20.0,
                              progressBorderColor: Colors.blue,
                            )
                          ],
                        )
                    ],
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }

  void showSnackbar(dynamic a) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(a.toString()),
      ),
    );
  }

  Future<bool> moveFile(String uri, String fileName) async {
    String parentDir = (await getExternalStorageDirectory())!.absolute.path;
    final b =
        await Nearby().copyFileAndDeleteOriginal(uri, '$parentDir/$fileName');

    showSnackbar("Moved file:$b");
    return b;
  }

  /// Called upon Connection request (on both devices)
  /// Both need to accept connection to start sending/receiving
  void onConnectionInit(String id, ConnectionInfo info) {
    showModalBottomSheet(
      context: context,
      builder: (builder) {
        return Center(
          child: Column(
            children: <Widget>[
              Text("id: $id"),
              Text("Token: ${info.authenticationToken}"),
              Text("Name${info.endpointName}"),
              Text("Incoming: ${info.isIncomingConnection}"),
              ElevatedButton(
                child: const Text("Accept Connection"),
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    endpointMap[id] = info;
                  });
                  Nearby().acceptConnection(
                    id,
                    onPayLoadRecieved: (endid, payload) async {
                      if (payload.type == PayloadType.BYTES) {
                        String str = String.fromCharCodes(payload.bytes!);
                        showSnackbar("$endid: $str");

                        if (str.contains(':')) {
                          int payloadId = int.parse(str.split(':')[0]);
                          String fileName = (str.split(':')[1]);

                          if (map.containsKey(payloadId)) {
                            if (tempFileUri != null) {
                              moveFile(tempFileUri!, fileName);
                            } else {
                              showSnackbar("File doesn't exist");
                            }
                          } else {
                            //add to map if not already
                            map[payloadId] = fileName;
                          }
                        }
                      } else if (payload.type == PayloadType.FILE) {
                        showSnackbar("$endid: File transfer started");
                        tempFileUri = payload.uri;
                        setState(() {
                          isReceiving = true;
                          receivingProgress = 0.0;
                        });
                      }
                    },
                    onPayloadTransferUpdate: (endid, payloadTransferUpdate) {
                      developer.log('isSending: $isSending');
                      double progress = payloadTransferUpdate.bytesTransferred /
                          payloadTransferUpdate.totalBytes;
                      if (payloadTransferUpdate.status ==
                          PayloadStatus.IN_PROGRESS) {
                        // developer.log(
                        //     'Bytes Transferred ${payloadTransferUpdate.bytesTransferred}');
                        setState(() {
                          if (isSending) {
                            sendingProgress = progress;
                          } else if (isReceiving) {
                            receivingProgress = progress;
                          }
                        });
                      } else if (payloadTransferUpdate.status ==
                          PayloadStatus.FAILURE) {
                        developer.log("failed");
                        showSnackbar("$endid: FAILED to transfer file");
                        if (isSending) {
                          isSending = false;
                          sendingProgress = 0.0;
                        } else if (isReceiving) {
                          isReceiving = false;
                          receivingProgress = 0.0;
                        }
                      } else if (payloadTransferUpdate.status ==
                          PayloadStatus.SUCCESS) {
                        showSnackbar(
                            "$endid success, total bytes = ${payloadTransferUpdate.totalBytes}");

                        if (map.containsKey(payloadTransferUpdate.id)) {
                          //rename the file now
                          String name = map[payloadTransferUpdate.id]!;
                          moveFile(tempFileUri!, name);
                        } else {
                          //bytes not received till yet
                          map[payloadTransferUpdate.id] = "";
                        }
                        if (isSending) {
                          isSending = false;
                          sendingProgress = 0.0;
                        } else if (isReceiving) {
                          isReceiving = false;
                          receivingProgress = 0.0;
                        }
                      }
                    },
                  );
                },
              ),
              ElevatedButton(
                child: const Text("Reject Connection"),
                onPressed: () async {
                  Navigator.pop(context);
                  try {
                    await Nearby().rejectConnection(id);
                  } catch (e) {
                    showSnackbar(e);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
