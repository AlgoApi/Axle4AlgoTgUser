import 'dart:async';
import 'dart:convert';
import 'dart:io';
import "package:path/path.dart" show dirname;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:rxdart/rxdart.dart';

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
  List<BehaviorSubject<List<String>>> _outputControllers = [];
  List<TextEditingController> _inputControllers = [];
  late List<ScrollController> _scrollController;
  TabController? _tabController;
  final agentController = TextEditingController();
  final agentPassController = TextEditingController();
  AudioPlayer audioPlayer = AudioPlayer();
  int correction = 0;
  late List<List<String>> _outputtextLines;
  late List<bool> _shouldAutoScroll;
  late List<StreamBuilder> _streamBuilders;

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
    'Ошибка'
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
    audioPlayer.dispose();
    for (var controller in _scrollController) {
      controller.dispose();
    }
    for (var process in _processes) {
      process?.kill();
    }
    for (var controller in _outputControllers) {
      controller.close();
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
        _outputControllers = List.generate(_appConfigs.length, (_) => BehaviorSubject<List<String>>(), growable:true);
        _inputControllers = List.generate(_appConfigs.length, (_) => TextEditingController(), growable:true);
        _isTabHighlighted = List.filled(_appConfigs.length, false, growable:true);
        _outputtextLines = List.generate(_appConfigs.length, (index) => ["${index}", ], growable:true);
        _shouldAutoScroll = List.filled(_appConfigs.length, true, growable:true);
        _scrollController = List.generate(_appConfigs.length, (_) => ScrollController(), growable:true);
        _streamBuilders = List.generate(_appConfigs.length, (index) => genStreamBuilder(index), growable:true);
        if (_appConfigs.isNotEmpty) {
          agentController.text = _appConfigs[0].agent;
          agentPassController.text = _appConfigs[0].agentPass;
        }
      });
      _initializeTabController();
      for (int index = 0; index < _appConfigs.length; index++){
        _scrollController[index].addListener(() {
          // Если пользователь прокрутил вверх, отключаем автопрокрутку
          if (_scrollController[index].position.pixels <
              _scrollController[index].position.maxScrollExtent) {
            setState(() {
              _shouldAutoScroll[index] = false;
            });
          }

          // Если пользователь прокрутил в самый низ, включаем автопрокрутку
          if (_scrollController[index].position.pixels ==
              _scrollController[index].position.maxScrollExtent) {
            setState(() {
              _shouldAutoScroll[index] = true;
            });
          }
        });
      }
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
          "${dirname(Platform.resolvedExecutable.toString())}\\src\\AlgoTgUserAPI.exe",
          ['--login=${config.login}', '--phone=${config.phone}',
            '--text=${config.text}', '--agent=${config.agent}',
            '--agentPass=${config.agentPass}', '--passwordTg=${config.passwordTg}']);
      _processes.add(process);

      process.stdout.transform(utf8.decoder).listen((data) {
        //setState(() {

        //});
        if (data != "") {
          _outputtextLines[index].add(data.substring(0, data.length -2));
        }
        _outputControllers[index].add(_outputtextLines[index]); // Отправка нового текста в поток
        if (_shouldAutoScroll[index]) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollController[index].jumpTo(
                _scrollController[index].position.maxScrollExtent);
          });
        }
        _checkForTriggers(data, index);
      });

      process.stderr.transform(utf8.decoder).listen((data) {
        setState(() {
          if (data != "") {
            _outputtextLines[index].add('ERROR: $data');
          }
          _outputControllers[index].add(_outputtextLines[index]); // Отправка нового текста в поток
          if (_shouldAutoScroll[index]) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollController[index].jumpTo(
                  _scrollController[index].position.maxScrollExtent);
            });
          }
        });
        _checkForTriggers(data, index);
      });

      setState(() {});
    } catch (e) {
      setState(() {
        if (e != "") {
          _outputtextLines[index].add('ERROR starting process: $e');
        }
        _outputControllers[index].add(_outputtextLines[index]); // Отправка нового текста в поток
        if (_shouldAutoScroll[index]) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollController[index].jumpTo(
                _scrollController[index].position.maxScrollExtent);
          });
        }
      });
    }
  }

  StreamBuilder genStreamBuilder(int index) {
    return StreamBuilder<List<String>>(
      stream: _outputControllers[index].stream,
      builder: (context, snapshot) {
        final outlines = snapshot.data;
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.blue, width: 2), // Рамка синего цвета
              borderRadius: const BorderRadius.all(Radius.circular(8)), // Закругленные углы
            ),
            child: ListView.builder(
              controller: _scrollController[index],
              itemCount: outlines?.length ?? 0,
              itemBuilder: (context, index){
                return Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Text(
                    outlines?[index] ?? "",
                    style: const TextStyle(fontFamily: 'Courier'),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _checkForTriggers(String data, int index) async {
    for (var trigger in highlightTriggers) {
      if (data.toLowerCase().contains(trigger.toLowerCase())) {
        await audioPlayer.play(AssetSource('alarm.wav'));
        setState(() {
          _isTabHighlighted[index] = true;
          _tabController?.animateTo(index);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollController[index].jumpTo(
                _scrollController[index].position.maxScrollExtent);
          });
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
      _outputControllers.add(BehaviorSubject<List<String>>());
      _inputControllers.add(TextEditingController());
      _isTabHighlighted.add(false);
      _outputtextLines.add(["added", ]);
      _shouldAutoScroll.add(true);
      _scrollController.add(ScrollController());
      _streamBuilders.add(genStreamBuilder(_appConfigs.length - 1 + correction));

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
        _processes[index]?.kill();
        correction += 1;
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
                  decoration: const InputDecoration(labelText: 'ВАШ логин агента'),
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
        title: Text("Axle4AlgoTgUser (${_processes.length - correction} конфигураций запущенно)"),
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
                  child: _streamBuilders[index + correction]
                ),

                TextField(
                  controller: _inputControllers[index],
                  decoration: const InputDecoration(
                    labelText: 'Ввод: (Enter для отправки)',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _sendInput(index),
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
