import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(KabbeeShare());
}

class KabbeeShare extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KabbeeShare',
      theme: ThemeData(primaryColor: Colors.blue),
      home: FileShareScreen(),
    );
  }
}

class FileShareScreen extends StatefulWidget {
  const FileShareScreen({super.key});

  @override
  State<FileShareScreen> createState() => _FileShareScreenState();
}

class _FileShareScreenState extends State<FileShareScreen> {
  String _status = 'Select a file to share';
  File? _file;

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      setState(() {
        _file = File(result.files.single.path!);
        _status = 'File selected: ${_file!.path.split('/').last}';
      });
    }
  }

  Future<void> _sendFile() async {
    if (_file == null) {
      setState(() {
        _status = "No File Selected";
      });
      return;
    }

    // Request permission
    if (!await _requestPermission()) {
      setState(() {
        _status = "Permission Denied";
      });
      return;
    }

    ServerSocket server =
        await ServerSocket.bind(InternetAddress.anyIPv4, 4040);
    setState(() {
      _status = "Waiting for receiver...";
    });

    server.listen((Socket socket) async {
      setState(() {
        _status = "Sending File...";
      });

      // Send file
      List<int> fileBytes = await _file!.readAsBytes();
      socket.add(fileBytes);
      await socket.flush();
      socket.destroy();

      setState(() {
        _status = 'File sent!';
      });
      server.close();
    });
  }

  // Receive file
  Future<void> _receiveFile() async {
    // Request permission
    if (!await _requestPermission()) {
      setState(
        () {
          _status = "Permission Denied!";
        },
      );
      return;
    }

    setState(() {
      _status = "Connecting to sender...";
    });

    Socket socket = await Socket.connect('192.168.1.100', 4040);
    setState(() {
      _status = "Receiving file...";
    });

    // Receive File
    List<int> fileBytes = [];
    socket.listen(
      (List<int> data) => fileBytes.addAll(data),
      onDone: () async {
        String filePath = "/storage/emulated/0/Download/received_file";
        File file = File(filePath);
        await file.writeAsBytes(fileBytes);
        setState(() {
          _status = "File received: $filePath";
        });
        socket.destroy();
      },
    );
  }

  Future<bool> _requestPermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    return status.isGranted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Kabbee Share"),
      ),
      body: Center(
        child: Column(
          children: [
            Text(_status),
            const SizedBox(height: 28),
            ElevatedButton(
                onPressed: _pickFile, child: const Text("Select File")),
            const SizedBox(height: 28),
            ElevatedButton(
                onPressed: _sendFile, child: const Text("Send File")),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _receiveFile,
              child: const Text("Receive File"),
            )
          ],
        ),
      ),
    );
  }
}
