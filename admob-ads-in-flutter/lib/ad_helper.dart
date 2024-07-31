import 'dart:io';

class AdHelper {

  static String get bannerAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3826202767168898/2209701372';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3826202767168898/8263307556';
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  static String get interstitialAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3826202767168898/9705048019';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3826202767168898/5056761535';
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  static String get rewardedAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3826202767168898/8687479811';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3826202767168898/6721196996';
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }
}