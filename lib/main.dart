import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

// ============================================================================
// 1. СЛОЙ ДАННЫХ: РЕАЛИЗАЦИЯ DBProvider ДЛЯ SQFLITE
// ============================================================================
class DBProvider {
  DBProvider._();
  static final DBProvider db = DBProvider._();
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    String databasesPath = await getDatabasesPath();
    String path = p.join(databasesPath, 'bmi_history.db');
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute("""CREATE TABLE BmiRecord(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        weight TEXT,
        height TEXT,
        bmi REAL,
        category TEXT,
        date TEXT
      );""");
  }

  Future<void> addBmiRecord(Map<String, dynamic> record) async {
    Database databaseInstance = await this.database;
    await databaseInstance.insert("BmiRecord", record);
  }

  Future<List<Map<String, dynamic>>> getAllRecords() async {
    Database databaseInstance = await this.database;
    return await databaseInstance.query("BmiRecord", orderBy: "id DESC");
  }

  Future<void> clearHistory() async {
    Database databaseInstance = await this.database;
    await databaseInstance.delete("BmiRecord");
  }
}

// ============================================================================
// 2. БИЗНЕС-ЛОГИКА И UI ОСНОВНОГО ЭКРАНА (ИЗ ЛР 4)
// ============================================================================
@immutable
abstract class MainScreenState {}
class MainScreenInputState extends MainScreenState {}
class MainScreenResultState extends MainScreenState {
  final double bmi; 
  final String category; 
  final String interpretation;
  MainScreenResultState({required this.bmi, required this.category, required this.interpretation});
}
class MainScreenErrorState extends MainScreenState {
  final String errorMessage; 
  MainScreenErrorState(this.errorMessage);
}

class MainScreenCubit extends Cubit<MainScreenState> {
  final TextEditingController weightController = TextEditingController();
  final TextEditingController heightController = TextEditingController();

  MainScreenCubit() : super(MainScreenInputState()) {
    loadLastInputFromPrefs(); 
  }

  void loadLastInputFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedWeight = prefs.getString('last_weight') ?? '';
    final savedHeight = prefs.getString('last_height') ?? '';
    weightController.text = savedWeight;
    heightController.text = savedHeight;
  }

  void calculateBmi() async {
    final String weightText = weightController.text;
    final String heightText = heightController.text;

    if (weightText.isEmpty || heightText.isEmpty) {
      emit(MainScreenErrorState("Пожалуйста, заполните все поля"));
      return;
    }

    final double? weight = double.tryParse(weightText);
    final double? heightCm = double.tryParse(heightText);

    if (weight == null || heightCm == null || weight <= 0 || heightCm <= 0) {
      emit(MainScreenErrorState("Введите корректные положительные числа"));
      return;
    }

    final double heightM = heightCm / 100;
    final double bmi = weight / pow(heightM, 2);
    final double formattedBmi = double.parse(bmi.toStringAsFixed(1));

    String category; 
    String interpretation;
    if (bmi < 18.5) {
      category = "Дефицит массы"; 
      interpretation = "Вес ниже нормы. Сбалансируйте питание.";
    } else if (bmi >= 18.5 && bmi < 25) {
      category = "Нормальный вес"; 
      interpretation = "Отличный показатель! Так держать.";
    } else if (bmi >= 25 && bmi < 30) {
      category = "Избыточный вес"; 
      interpretation = "Небольшой избыток. Обратите внимание на активность.";
    } else {
      category = "Ожирение"; 
      interpretation = "Показатель превышает норму. Проконсультируйтесь с врачом.";
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_weight', weightText);
    await prefs.setString('last_height', heightText);

    final String currentDate = DateTime.now().toString().substring(0, 16);
    await DBProvider.db.addBmiRecord({
      'weight': weightText,
      'height': heightText,
      'bmi': formattedBmi,
      'category': category,
      'date': currentDate,
    });

    emit(MainScreenResultState(bmi: formattedBmi, category: category, interpretation: interpretation));
  }

  void reset() {
    emit(MainScreenInputState());
    loadLastInputFromPrefs(); 
  }
  
  @override
  Future<void> close() {
    weightController.dispose();
    heightController.dispose();
    return super.close();
  }
}

class MainScreenProvider extends StatelessWidget {
  const MainScreenProvider({super.key});
  @override
  Widget build(BuildContext context) {
    return BlocProvider<MainScreenCubit>(
      create: (context) => MainScreenCubit(),
      child: const MainScreen(),
    );
  }
}

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bmi Cubit & Storage'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        leading: IconButton(
          icon: const Icon(Icons.history),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const HistoryScreenProvider()),
            );
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: BlocBuilder<MainScreenCubit, MainScreenState>(
          builder: (context, state) {
            if (state is MainScreenResultState) return _buildResultView(context, state);
            if (state is MainScreenErrorState) return _buildErrorView(context, state.errorMessage);
            return _buildInputView(context);
          },
        ),
      ),
    );
  }

  Widget _buildInputView(BuildContext context) {
    final cubit = BlocProvider.of<MainScreenCubit>(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: cubit.heightController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Рост (в см)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.height)),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: cubit.weightController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Вес (в кг)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.scale)),
        ),
        const SizedBox(height: 30),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            padding: const EdgeInsets.all(16),
          ),
          onPressed: () => cubit.calculateBmi(),
          child: const Text('Рассчитать и сохранить', style: TextStyle(fontSize: 18)),
        ),
      ],
    );
  }

  Widget _buildResultView(BuildContext context, MainScreenResultState state) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Ваш Индекс Массы Тела:', style: TextStyle(fontSize: 20, color: Colors.grey)),
          const SizedBox(height: 10),
          Text('${state.bmi}', style: TextStyle(fontSize: 72, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 10),
          Text(state.category, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          const SizedBox(height: 20),
          Text(state.interpretation, style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: () => BlocProvider.of<MainScreenCubit>(context).reset(),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Назад'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 64),
          const SizedBox(height: 16),
          Text(error, style: const TextStyle(color: Colors.red, fontSize: 18)),
          const SizedBox(height: 30),
          ElevatedButton(onPressed: () => BlocProvider.of<MainScreenCubit>(context).reset(), child: const Text('Назад')),
        ],
      ),
    );
  }
}

// ============================================================================
// 3. СЛОЙ БИЗНЕС-ЛОГИКИ И ЭКРАН ИСТОРИИ ИЗ БД
// ============================================================================
@immutable
abstract class HistoryState {}
class HistoryLoadingState extends HistoryState {}
class HistoryLoadedState extends HistoryState {
  final List<Map<String, dynamic>> records;
  HistoryLoadedState(this.records);
}

class HistoryCubit extends Cubit<HistoryState> {
  HistoryCubit() : super(HistoryLoadingState());

  // Метод кубита, обеспечивающий асинхронную загрузку данных (Пункт 6 задания)
  void loadHistory() async {
    emit(HistoryLoadingState());
    final data = await DBProvider.db.getAllRecords();
    emit(HistoryLoadedState(data));
  }

  void clearAll() async {
    await DBProvider.db.clearHistory();
    loadHistory();
  }
}

class HistoryScreenProvider extends StatelessWidget {
  const HistoryScreenProvider({super.key});

  @override
  Widget build(BuildContext context) {
    // ИСПРАВЛЕНО: Добавлен обязательный дженерик <HistoryCubit> для BlocProvider
    return BlocProvider<HistoryCubit>(
      create: (context) => HistoryCubit()..loadHistory(),
      child: const HistoryScreen(),
    );
  }
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('История расчетов (SQL)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            // ИСПРАВЛЕНО: Добавлен дженерик <HistoryCubit> в BlocProvider.of
            onPressed: () => BlocProvider.of<HistoryCubit>(context).clearAll(),
          ),
        ],
      ),
      body: BlocBuilder<HistoryCubit, HistoryState>(
        builder: (context, state) {
          if (state is HistoryLoadingState) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is HistoryLoadedState) {
            if (state.records.isEmpty) {
              return const Center(
                child: Text('История пуста', style: TextStyle(fontSize: 18, color: Colors.grey)),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.records.length,
              itemBuilder: (context, index) {
                final item = state.records[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Text('${item['bmi']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    title: Text('${item['category']}'),
                    subtitle: Text('Вес: ${item['weight']} кг | Рост: ${item['height']} см'),
                    trailing: Text('${item['date']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                );
              },
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ============================================================================
// 4. ТОЧКА ВХОДА ПРИЛОЖЕНИЯ
// ============================================================================
void main() {
  // Инициализация нативных связей перед работой с асинхронными хранилищами
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal), 
        useMaterial3: true,
      ),
      home: const MainScreenProvider(),
    );
  }
}