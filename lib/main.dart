import 'package:flutter/material.dart';
import 'package:room_conferrence/room.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  TextEditingController editingController = TextEditingController();
  String status = "";

  void joinRoom() {
    if (editingController.text.trim() == "") {
      setState(() {
        status = "Bạn chưa nhập tên";
      });
      return;
    }
    setState(() {
      status = "";
    });
    Navigator.push(context, PageRouteBuilder(pageBuilder: (context, a1, a2) {
      return RoomUI(displayName: editingController.text);
    }));
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: SizedBox(
          width: 300,
          height: 300,
          child: Column(
            children: [
              TextField(
                style: const TextStyle(color: Colors.black),
                decoration: const InputDecoration(border: OutlineInputBorder(borderSide: BorderSide(color: Colors.blue)), hintText: "Enter your name"),
                controller: editingController
              ),
              TextButton(
                style: ButtonStyle(backgroundColor: MaterialStateProperty.all(Colors.black)),
                onPressed: () => joinRoom(),
                child: const Text("Join room"),
              ),
              Text(status)
            ],
          ),
        )
      ),
    );
  }
}
