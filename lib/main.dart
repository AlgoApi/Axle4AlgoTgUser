import 'dart:async';
import 'dart:convert';
import 'dart:io';
import "package:path/path.dart" show dirname;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Axle4AlgoTgUser',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MyHomePage(),
    );
  }
}

class AppConfig {
  String login;
  String phone;
  String text;
  String agent;
  String agentPass;
  String passwordTg;
  bool closed;

  AppConfig(
      {required this.login,
        required this.phone,
        required this.text,
        required this.agent,
        required this.agentPass,
        required this.passwordTg,
        this.closed = false});

  factory AppConfig.fromMap(Map<String, dynamic> map) {
    return AppConfig(
        login: map['login'] as String,
        phone: map['phone'] as String,
        text: map['text'] as String,
        agent: map['agent'] as String,
        agentPass: map['agentPass'] as String,
        passwordTg: map['passwordTg'] as String
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'login': login,
      'phone': phone,
      'text': text,
      'agent': agent,
      'agentPass': agentPass,
      'passwordTg': passwordTg
    };
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin {
  List<AppConfig> _appConfigs = [];
  List<Process?> _processes = [];
  List<TextEditingController> _outputControllers = [];
  List<TextEditingController> _inputControllers = [];
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  TabController? _tabController;
  final agentController = TextEditingController();
  final agentPassController = TextEditingController();
  AudioPlayer player = AudioPlayer();

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

    for (var process in _processes) {
      process?.kill();
    }
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
    //prefs.clear();
    final String? jsonString = prefs.getString('app_configs');
    if (jsonString != null) {
      List<dynamic> jsonList = jsonDecode(jsonString);
      setState(() {
        _appConfigs = jsonList.map((json) => AppConfig.fromMap(json)).toList();
        _outputControllers = List.generate(_appConfigs.length, (_) => TextEditingController(), growable:true);
        _inputControllers = List.generate(_appConfigs.length, (_) => TextEditingController(), growable:true);
        _isTabHighlighted = List.filled(_appConfigs.length, false, growable:true);
        if (_appConfigs.isNotEmpty) {
          agentController.text = _appConfigs[0].agent;
          agentPassController.text = _appConfigs[0].agentPass;
        }
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
    //prefs.clear();
    String? jsonString = prefs.getString('app_configs');
    jsonString = jsonEncode(_appConfigs.map((config) => config.toMap()).toList());
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
          "${dirname(Platform.resolvedExecutable.toString())}\\src\\AlgoTgUser.exe",
          ['--login=${config.login}', '--phone=${config.phone}',
            '--text=${config.text}', '--agent=${config.agent}',
            '--agentPass=${config.agentPass}', '--passwordTg=${config.passwordTg}']);
      _processes.add(process);

      process.stdout.transform(utf8.decoder).listen((data) {
        setState(() {
          _outputControllers[index].text += data;
          _scrollController
              .jumpTo(_scrollController.position.maxScrollExtent);
          _focusNode.requestFocus();
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
      setState(() {
        _outputControllers[index].text += 'ERROR starting process: $e';
      });
    }
  }

  void _checkForTriggers(String data, int index) {
    for (var trigger in highlightTriggers) {
      if (data.toLowerCase().contains(trigger.toLowerCase())) {
        player.setSource(AssetSource('alarm.wav'));
        player.resume();
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

  void _addAppConfig(String login, String phone, String text, String agent,
      String agentPass, String passwordTg) {
    final newConfig = AppConfig(login: login, phone: phone,
        text: text, agent: agent, agentPass:agentPass, passwordTg:passwordTg);
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

  void _removeAppConfig(int index, {bool save = true}) {
    setState(() {
      _appConfigs[index].closed = true;
      if (save){
        _appConfigs.removeAt(index);
      }
      if (_processes.isNotEmpty){
        _processes[index]?.kill();
        //_processes.removeAt(index);
      }
      //_outputControllers.removeAt(index);
      //_inputControllers.removeAt(index);
      //_isTabHighlighted.removeAt(index);
      _initializeTabController();
    });
    if (save){
      _saveAppConfigs();
    }
  }

  void _openSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Настройки менеджера TgUser'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: agentController,
                  decoration: const InputDecoration(labelText: 'ВАШ логин ОСНОВНОГО тг без "@"'),
                  readOnly: (agentController.text.isNotEmpty) ? true:false),
              TextField(controller: agentPassController,
                  decoration: const InputDecoration(labelText: 'ВАШ пароль агента'),
                  readOnly: (agentPassController.text.isNotEmpty) ? true:false) ,
              ...List.generate(_appConfigs.length, (index) {
                return ListTile(
                  title: Text('${_appConfigs[index].login} ${index + 1}: ${_appConfigs[index].phone}'),
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
                  final loginController = TextEditingController();
                  final phoneController = TextEditingController();
                  final textController = TextEditingController();
                  final passwordTgController = TextEditingController();

                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Добавить новую конфигурацию'),
                      content: SingleChildScrollView(
                        child: Column(
                          children: [
                            TextField(controller: loginController, decoration: const InputDecoration(labelText: 'Логин тг без "@"')),
                            TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Номер телефона в международном формате(+7...)')),
                            TextField(controller: textController, decoration: const InputDecoration(labelText: 'Спам текст')),
                            TextField(controller: passwordTgController, decoration: const InputDecoration(labelText: 'Пароль двухфакторной аутентификации\n(оставьте поле пустым если нет)'))
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            _addAppConfig(
                                loginController.text,
                                phoneController.text,
                                textController.text,
                                agentController.text,
                                agentPassController.text,
                                (passwordTgController.text.isNotEmpty) ? passwordTgController.text : "0"
                            );
                            Navigator.of(context).pop();
                          },
                          child: const Text('Добавить'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Отмена'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Добавить новую конфигурацию'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
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
        title: Text("Axle4AlgoTgUser (${_processes.length} конфигураций запущенно)"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettingsDialog,
          ),
        ],
        bottom: _tabController != null
            ? TabBar(
          isScrollable: true,
          controller: _tabController,
          tabs: List<Widget>.generate(
              _appConfigs.length,
                  (index) => _appConfigs[index].closed ? Container()
                  :Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          color: _isTabHighlighted[index] ? Colors.red : Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                          child: Text('${_appConfigs[index].login} ${index + 1}'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => _removeAppConfig(index, save: false), // Call _closeTab when pressed
                        )
                      ]
                )
              ), growable: true),
        )
            : null,
      ),
      body: _tabController != null
          ? TabBarView(
        controller: _tabController,
        children: List<Widget>.generate(_appConfigs.length, (index) {
          if (_appConfigs[index].closed){
            return Container();
          }
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Expanded(
                  child: TextField(
                    controller: _outputControllers[index],
                    style: const TextStyle(fontFamily: 'Courier'),
                    maxLines: null,
                    readOnly: true,
                    focusNode: _focusNode,
                    scrollController: _scrollController,
                    decoration: const InputDecoration(
                      isDense: false,
                      labelText: 'Вывод',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                TextField(
                  controller: _inputControllers[index],
                  decoration: const InputDecoration(
                    labelText: 'Ввод',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _sendInput(index),
                ),
                ElevatedButton(
                  onPressed: () => _sendInput(index),
                  child: const Text('Отправить'),
                ),
              ],
            ),
          );
        }, growable: true),
      )
          : const Center(child: Text('Нет конфигураций')),
    );
  }
}
