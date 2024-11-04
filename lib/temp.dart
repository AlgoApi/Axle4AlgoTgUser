import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Console App Manager',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MyHomePage(),
    );
  }
}

class AppConfig {
  String path;
  String login;
  String phone;
  String text;

  AppConfig(
      {required this.path,
        required this.login,
        required this.phone,
        required this.text});

  factory AppConfig.fromMap(Map<String, dynamic> map) {
    return AppConfig(
      path: map['path'] as String,
      login: map['login'] as String,
      phone: map['phone'] as String,
      text: map['text'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'login': login,
      'phone': phone,
      'text': text,
    };
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin {
  List<AppConfig> _appConfigs = [];
  List<Process?> _processes = [];
  List<TextEditingController> _outputControllers = [];
  List<TextEditingController> _inputControllers = [];
  TabController? _tabController;

  final List<String> highlightTriggers = [
    'Введи ПОРЯДКОВЫЙ номер кнопки',
    'Доступных кнопок нет',
    'ERROR',
    'Не удалось',
    'message.entities[0].user IS None',
    'пользователь без логина, id нет',
    'НЕ найдено фото, фото НЕ скачано',
    'ДОСТИГНКТ ЛИМИТ',
    'ACCESS DENIED',
    'ЧЕЛОВЕК НЕ ДОБАВЛЕН В ИГНОР ЛИСТ',
    'ОШИБКА ОТПРАВКИ',
    'CONNECTION TERMINATED',
    'нет логина или id',
    'Ошибка',
    'Вы забыли заполнить конфиг'
  ];
  List<bool> _isTabHighlighted = [];

  @override
  void initState() {
    super.initState();
    _loadAppConfigs();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    for (var controller in _outputControllers) {
      controller.dispose();
    }
    for (var controller in _inputControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAppConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString('app_configs');
    if (jsonString != null) {
      List<dynamic> jsonList = jsonDecode(jsonString);
      setState(() {
        _appConfigs = jsonList.map((json) => AppConfig.fromMap(json)).toList();
        _outputControllers = List.generate(_appConfigs.length, (_) => TextEditingController(), growable:true);
        _inputControllers = List.generate(_appConfigs.length, (_) => TextEditingController(), growable:true);
        _isTabHighlighted = List.filled(_appConfigs.length, false, growable:true);
      });
      _initializeTabController();
      _startAllProcesses();
    }
  }

  void _initializeTabController() {
    _tabController?.dispose();
    if (_appConfigs.isNotEmpty) {
      _tabController = TabController(length: _appConfigs.length, vsync: this);
    } else {
      _tabController = null;
    }
  }

  Future<void> _saveAppConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonString = jsonEncode(_appConfigs.map((config) => config.toMap()).toList());
    await prefs.setString('app_configs', jsonString);
  }

  Future<void> _startAllProcesses() async {
    for (int i = 0; i < _appConfigs.length; i++) {
      _startProcess(i);
    }
  }

  Future<void> _startProcess(int index) async {
    final config = _appConfigs[index];
    try {
      final process = await Process.start(
        config.path,
        ['--login=${config.login}', '--phone=${config.phone}', '--text=${config.text}'],
      );
      _processes.add(process);

      process.stdout.transform(utf8.decoder).listen((data) {
        setState(() {
          _outputControllers[index].text += data;
        });
        _checkForTriggers(data, index);
      });

      process.stderr.transform(utf8.decoder).listen((data) {
        setState(() {
          _outputControllers[index].text += 'ERROR: $data';
        });
        _checkForTriggers(data, index);
      });

      setState(() {});
    } catch (e) {
      print('Error starting process: $e');
    }
  }

  void _checkForTriggers(String data, int index) {
    for (var trigger in highlightTriggers) {
      if (data.toLowerCase().contains(trigger.toLowerCase())) {
        setState(() {
          _isTabHighlighted[index] = true;
          _tabController?.animateTo(index);
        });
        break;
      }
    }
  }

  void _sendInput(int index) {
    final input = _inputControllers[index].text;
    _processes[index]?.stdin.writeln(input);
    _inputControllers[index].clear();
    _isTabHighlighted[index] = false;
  }

  void _addAppConfig(String path, String login, String phone, String text) {
    final newConfig = AppConfig(path: path, login: login, phone: phone, text: text);
    setState(() {
      _appConfigs.add(newConfig);
      _outputControllers.add(TextEditingController());
      _inputControllers.add(TextEditingController());
      _isTabHighlighted.add(false);
      _initializeTabController();
    });
    _saveAppConfigs();
    _startProcess(_appConfigs.length - 1);
  }

  void _removeAppConfig(int index) {
    setState(() {
      _appConfigs.removeAt(index);
      _processes[index]?.kill();
      _processes.removeAt(index);
      _outputControllers.removeAt(index);
      _inputControllers.removeAt(index);
      _isTabHighlighted.removeAt(index);
      _initializeTabController();
    });
    _saveAppConfigs();
  }

  void _openSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Manage Console Apps'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...List.generate(_appConfigs.length, (index) {
                return ListTile(
                  title: Text('App ${index + 1}: ${_appConfigs[index].path}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () {
                      _removeAppConfig(index);
                      Navigator.of(context).pop();
                    },
                  ),
                );
              }, growable: true),
              const Divider(),
              ElevatedButton(
                onPressed: () {
                  final pathController = TextEditingController();
                  final loginController = TextEditingController();
                  final phoneController = TextEditingController();
                  final textController = TextEditingController();

                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Add New App Configuration'),
                      content: SingleChildScrollView(
                        child: Column(
                          children: [
                            TextField(controller: pathController, decoration: const InputDecoration(labelText: 'Path')),
                            TextField(controller: loginController, decoration: const InputDecoration(labelText: 'Login')),
                            TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Phone')),
                            TextField(controller: textController, decoration: const InputDecoration(labelText: 'Text')),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            _addAppConfig(
                              pathController.text,
                              loginController.text,
                              phoneController.text,
                              textController.text,
                            );
                            Navigator.of(context).pop();
                          },
                          child: const Text('Add'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Add New Configuration'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Console App Manager (${_processes.length} active)"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettingsDialog,
          ),
        ],
        bottom: _tabController != null
            ? TabBar(
          controller: _tabController,
          tabs: List<Widget>.generate(
            _appConfigs.length,
                (index) => Tab(
              child: Container(
                color: _isTabHighlighted[index] ? Colors.red : Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                child: Text('App ${index + 1}'),
              ),
            ), growable: true),
        )
            : null,
      ),
      body: _tabController != null
          ? TabBarView(
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
                    decoration: const InputDecoration(
                      labelText: 'Output',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                TextField(
                  controller: _inputControllers[index],
                  decoration: const InputDecoration(
                    labelText: 'Input',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _sendInput(index),
                ),
                ElevatedButton(
                  onPressed: () => _sendInput(index),
                  child: const Text('Send'),
                ),
              ],
            ),
          );
        }, growable: true),
      )
          : const Center(child: Text('No applications configured.')),
    );
  }
}
