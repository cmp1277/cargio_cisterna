abstract final class AppConfig {
  static const apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://cisternas-api-wqac.onrender.com/api/mobile',
  );

  static Uri get endpoint => Uri.parse(apiUrl);
}
