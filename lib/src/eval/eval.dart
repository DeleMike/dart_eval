import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/dart_eval_bridge.dart';

dynamic eval(String source, {String function = 'main', List<BridgeClass> bridgeClasses = const []}) {
  final compiler = Compiler();
  compiler.defineBridgeClasses(bridgeClasses);

  var _source = source;

  if (!RegExp(r'(?:\w* )?' + function + r'\s?\([\s\S]*?\)\s?{').hasMatch(_source)) {
    if (!_source.contains(';')) {
      _source = '$_source;';
      if (!_source.contains('return')) {
        _source = 'return $_source';
      }
    }
    _source = 'dynamic $function() {$_source}';
  }

  final program = compiler.compile({
    'default': {'main.dart': _source}
  });

  final runtime = Runtime.ofProgram(program);
  runtime.defineBridgeClasses(bridgeClasses);

  final result = runtime.executeNamed(0, function);

  if (result is EvalValue) {
    return result.$reified;
  }
  return result;
}
