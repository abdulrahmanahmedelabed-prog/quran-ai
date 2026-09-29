class ReturnCode {
  const ReturnCode(this._value);

  static const int success = 0;
  static const int cancel = 255;

  final int _value;

  int getValue() => _value;

  static bool isSuccess(ReturnCode? code) => code?._value == success;

  static bool isCancel(ReturnCode? code) => code?._value == cancel;
}
