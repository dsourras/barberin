part of 'main.dart';

bool get isBarberinMacOS => !kIsWeb && Platform.isMacOS;

bool get isBarberinDesktopNotificationFallback =>
    isBarberinWindows || isBarberinMacOS;

bool get isBarberinFirebaseMessagingSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);
