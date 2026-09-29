import 'return_code.dart';

class FFmpegSession {
  const FFmpegSession(this._returnCode);

  final ReturnCode _returnCode;

  Future<ReturnCode?> getReturnCode() async => _returnCode;
}
