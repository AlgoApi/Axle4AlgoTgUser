import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert' show utf8;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Multi Console Interaction'),
        ),
        body: ConsoleAppManager(),
      ),
    );
  }
}

class AppConfig {
  final String path;
  final String login;
  final String phone;
  final String text;

  AppConfig({required this.path, required this.login, required this.phone, required this.text});

  Map<String, String> toMap() {
    return {
      'path': path,
      'login': login,
      'phone': phone,
      'text': text,
    };
  }

  factory AppConfig.fromMap(Map<String, dynamic> map) {
    return AppConfig(
      path: map['path']!,
      login: map['login']!,
      phone: map['phone']!,
      text: map['text']!,
    );
  }
}

class ConsoleAppManager extends StatefulWidget {
  @override
  _ConsoleAppManagerState createState() => _ConsoleAppManagerState();
}

class _ConsoleAppManagerState extends State<ConsoleAppManager> with TickerProviderStateMixin {
  final List<AppConfig> _appConfigs = [];
  final List<Process?> _processes = [];
  final List<TextEditingController> _outputControllers = [];
  final List<TextEditingController> _inputControllers = [];
  TabController? _tabController;

  Color statusColor = Colors.transparent;

  final _pathController = TextEditingController();
  final _loginController = TextEditingController();
  final _phoneController = TextEditingController();
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAppConfigs();
  }

  Future<void> _loadAppConfigs() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedConfigs = prefs.getStringList('appConfigs');
    if (savedConfigs != null) {
      for (var config in savedConfigs) {
        _appConfigs.add(AppConfig.fromMap(jsonDecode(config)));
        _outputControllers.add(TextEditingController());
        _inputControllers.add(TextEditingController());
      }
      _tabController = TabController(length: _appConfigs.length, vsync: this);
    }
  }



  Future<void> _saveAppConfigs() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> configList = _appConfigs.map((config) => jsonEncode(config.toMap())).toList();
    await prefs.setStringList('appConfigs', configList);
  }

  void _addAppConfig(String path, String login, String phone, String text, {bool save = true}) {
    setState(() {
      final newConfig = AppConfig(path: path, login: login, phone: phone, text: text);
      _appConfigs.add(newConfig);
      _outputControllers.add(TextEditingController());
      _inputControllers.add(TextEditingController());
      _tabController = TabController(length: _appConfigs.length, vsync: this);
      _startProcess(newConfig, _outputControllers.length - 1);
    });
    if (save) _saveAppConfigs();
  }

  Future<void> _startProcess(AppConfig config, int index) async {
    final process = await Process.start(
      config.path,
      ['--login', config.login, '--phone', config.phone, '--text', config.text],
    );
    _processes.add(process);

    process.stdout.transform(utf8.decoder).listen((data) {
      if (data.contains("Введи ПОРЯДКОВЫЙ номер кнопки(чтобы проигнорировать введите больше чем есть кнопок):")){
        setState(() {
          statusColor = Colors.redAccent;
        });
      }
      setState(() {
        _outputControllers[index].text += data;
        _tabController?.animateTo(index);
      });
    });

    process.stderr.transform(const SystemEncoding().decoder).listen((error) {
      setState(() {
        _outputControllers[index].text += 'Error: $error\n';
      });
    });

    process.exitCode.then((exitCode) {
      setState(() {
        _outputControllers[index].text += '\nProcess exited with code $exitCode';
      });
    });
  }

  void _sendInput(int index) {
    String input = _inputControllers[index].text;
    _processes[index]?.stdin.writeln(input);
    _inputControllers[index].clear();
  }

  void _removeAppConfig(int index) {
    setState(() {
      _appConfigs.removeAt(index);
      _processes[index]?.kill();
      _processes.removeAt(index);
      _outputControllers.removeAt(index);
      _inputControllers.removeAt(index);
      _tabController = TabController(length: _appConfigs.length, vsync: this);
      _saveAppConfigs();
    });
  }

  @override
  void dispose() {
    for (var process in _processes) {
      process?.kill();
    }
    for (var controller in _outputControllers) {
      controller.dispose();
    }
    for (var controller in _inputControllers) {
      controller.dispose();
    }
    _pathController.dispose();
    _loginController.dispose();
    _phoneController.dispose();
    _textController.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Manage Console Apps'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _pathController,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Path to executable',
                  ),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: _loginController,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Login',
                  ),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: _phoneController,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Phone',
                  ),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: _textController,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Text',
                  ),
                ),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    String path = _pathController.text;
                    String login = _loginController.text;
                    String phone = _phoneController.text;
                    String text = _textController.text;
                    if (path.isNotEmpty) {
                      _addAppConfig(path, login, phone, text);
                      _pathController.clear();
                      _loginController.clear();
                      _phoneController.clear();
                      _textController.clear();
                    }
                    Navigator.of(context).pop();
                  },
                  child: Text('Add App'),
                ),
                Divider(),
                Text('Existing Apps:', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Column(
                  children: List.generate(_appConfigs.length, (index) {
                    return ListTile(
                      title: Text(_appConfigs[index].path),
                      subtitle: Text('Login: ${_appConfigs[index].login}, Phone: ${_appConfigs[index].phone}, Text: ${_appConfigs[index].text}'),
                      trailing: IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          _removeAppConfig(index);
                          Navigator.of(context).pop();
                        },
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppBar(
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _showSettingsDialog,
            ),
          ],
        ),
        if (_appConfigs.isNotEmpty)
          Expanded(
            child: Column(
              children: [
                TabBar(
                  indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(90), // Creates border
                      color: statusColor),
                  controller: _tabController,
                  isScrollable: true,
                  tabs: List<Widget>.generate(_appConfigs.length, (index) {
                    return Tab(text: 'App ${index + 1}');
                  }),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: List<Widget>.generate(_appConfigs.length, (index) {
                      return Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _outputControllers[index],
                                maxLines: null,
                                readOnly: true,
                                decoration: InputDecoration(
                                  border: const OutlineInputBorder(),
                                  labelText: 'Output from App ${index + 1}',
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _inputControllers[index],
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                labelText: 'Enter input for App ${index + 1}',
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () => _sendInput(index),
                              child: Text('Send to App ${index + 1}'),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
