import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:grpc/grpc.dart';
import 'package:http/http.dart' as http;

import 'proto/generated/tensorflow/core/framework/tensor.pb.dart';
import 'proto/generated/tensorflow/core/framework/tensor_shape.pb.dart';
import 'proto/generated/tensorflow/core/framework/types.pbenum.dart';
import 'proto/generated/tensorflow_serving/apis/model.pb.dart';
import 'proto/generated/tensorflow_serving/apis/predict.pb.dart';
import 'proto/generated/tensorflow_serving/apis/prediction_service.pbgrpc.dart';

enum ConnectionModeType { grpc, rest }

const grpcPort = 8500;
const restPort = 8501;
const modelName = 'spam-detection';
const signatureName = 'serving_default';

const classificationThreshold = 0.8;
const vocabFile = 'assets/vocab.txt';
const maxSentenceLength = 20;

const String initialPrompt =
    'Type some text and tap the button. The spam detection model will determine if the text is spam or not.';

void main() => runApp(const TFServingDemo());

class TFServingDemo extends StatefulWidget {
  const TFServingDemo({super.key});

  @override
  State<TFServingDemo> createState() => _TFServingDemoState();
}

class _TFServingDemoState extends State<TFServingDemo> {
  late Future<String> _futurePrediction;
  final Map<String, int> _vocabMap = {};
  final TextEditingController _inputSentenceController =
      TextEditingController();
  late List<int> _tokenIndices;
  bool usegRPC = true;
  late String _server;

  ConnectionModeType _connectionMode = ConnectionModeType.grpc;
  late PredictionServiceClient _stub;

  @override
  void initState() {
    super.initState();
    _futurePrediction = Future<String>.value(initialPrompt);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TF Serving Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('TF Serving Flutter Demo'),
        ),
        body: Center(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextField(
                    controller: _inputSentenceController,
                    decoration: const InputDecoration(
                        border: UnderlineInputBorder(),
                        hintText: 'Enter a sentence here'),
                  ),
                  Column(
                    children: <Widget>[
                      ListTile(
                        title: const Text('gRPC'),
                        leading: Radio<ConnectionModeType>(
                          value: ConnectionModeType.grpc,
                          groupValue: _connectionMode,
                          onChanged: (value) {
                            setState(() {
                              _connectionMode = value!;
                            });
                          },
                        ),
                      ),
                      ListTile(
                        title: const Text('REST'),
                        leading: Radio<ConnectionModeType>(
                          value: ConnectionModeType.rest,
                          groupValue: _connectionMode,
                          onChanged: (value) {
                            setState(() {
                              _connectionMode = value!;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        FilledButton(
                            style: FilledButton.styleFrom(
                              textStyle: const TextStyle(fontSize: 18),
                            ),
                            onPressed: () {
                              setState(() {
                                _futurePrediction = predict();
                              });
                            },
                            child: const Text('Classify')),
                        FilledButton(
                            style: FilledButton.styleFrom(
                              textStyle: const TextStyle(fontSize: 18),
                            ),
                            onPressed: () {
                              setState(() {
                                _futurePrediction =
                                    Future<String>.value(initialPrompt);
                                _inputSentenceController.clear();
                              });
                            },
                            child: const Text('Reset'))
                      ]),
                  FutureBuilder<String>(
                    future: _futurePrediction,
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return Text(snapshot.data!);
                      } else if (snapshot.hasError) {
                        return Text('${snapshot.error}');
                      }
                      // Por defecto, muestra un indicador de carga.
                      return const CircularProgressIndicator();
                    },
                  ),
                ]),
          ),
        ),
      ),
    );
  }

  Future<String> predict() async {
    // Determinar la dirección del servidor según la plataforma
    _server = Platform.isAndroid ? '10.0.2.2' : '127.0.0.1';

    // Construir _vocabMap si está vacío
    if (_vocabMap.isEmpty) {
      final vocabFileString = await rootBundle.loadString(vocabFile);
      final lines = vocabFileString.split('\n');
      for (final l in lines) {
        if (l.isNotEmpty) {
          final wordAndIndex = l.split(' ');
          _vocabMap[wordAndIndex[0]] = int.parse(wordAndIndex[1]);
        }
      }
    }

    // Tokenizar la oración de entrada
    final inputWords = _inputSentenceController.text
        .toLowerCase()
        .replaceAll(RegExp('[^a-z ]'), '')
        .split(' ');

    // Inicializar con token de relleno
    _tokenIndices = List.filled(maxSentenceLength, 0);
    var i = 0;
    for (final w in inputWords) {
      if (_vocabMap.containsKey(w)) {
        _tokenIndices[i] = _vocabMap[w]!;
        i++;
      }

      // Truncar la cadena si es más larga que maxSentenceLength
      if (i >= maxSentenceLength) {
        break;
      }
    }

    // Procesar la solicitud según el modo de conexión
    if (_connectionMode == ConnectionModeType.rest) {
      // Crear y enviar la solicitud REST
      final response = await http.post(
        Uri.parse('http://$_server:$restPort/v1/models/$modelName:predict'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'instances': [_tokenIndices]}),
      );

      // Procesar la respuesta REST
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final spamScore = result['predictions'][0][1];
        if (spamScore >= classificationThreshold) {
          return 'This sentence is spam. Spam score is $spamScore';
        }
        return 'This sentence is not spam. Spam score is $spamScore';
      } else {
        throw Exception('Error response: ${response.statusCode}');
      }
    } else if (_connectionMode == ConnectionModeType.grpc) {
      // Crear y enviar la solicitud gRPC
      final channel = ClientChannel(
        _server,
        port: grpcPort,
        options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
      );
      _stub = PredictionServiceClient(channel,
          options: CallOptions(timeout: const Duration(seconds: 10)));

      final modelSpec = ModelSpec(
        name: modelName,
        signatureName: signatureName,
      );

      final batchDim = TensorShapeProto_Dim(size: Int64(1));
      final inputDim = TensorShapeProto_Dim(size: Int64(maxSentenceLength));
      final inputTensorShape = TensorShapeProto(dim: [batchDim, inputDim]);
      final inputTensor = TensorProto(
          dtype: DataType.DT_INT32,
          tensorShape: inputTensorShape,
          intVal: _tokenIndices);

      // Actualiza los nombres de los tensores de entrada y salida si entrenaste tu propio modelo.
      const inputTensorName = 'input_3';
      const outputTensorName = 'dense_5';
      final request = PredictRequest(
          modelSpec: modelSpec, inputs: {inputTensorName: inputTensor});

      // Enviar la solicitud gRPC
      final response = await _stub.predict(request);

      // Procesar la respuesta gRPC
      if (response.outputs.containsKey(outputTensorName)) {
        final spamScore = response.outputs[outputTensorName]!.floatVal[1];
        if (spamScore > classificationThreshold) {
          return 'This sentence is spam. Spam score is $spamScore';
        }
        return 'This sentence is not spam. Spam score is $spamScore';
      } else {
        throw Exception('Error response: output tensor not found');
      }
    }
    return 'Invalid connection mode';
  }
}
