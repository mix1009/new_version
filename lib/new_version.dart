library new_version;


import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:launch_review/launch_review.dart';
import 'package:package_info/package_info.dart';
import 'package:html/parser.dart' show parse;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:convert';
import 'dart:async';

/// Information about the app's current version, and the most recent version
/// available in the Apple App Store or Google Play Store.
class VersionStatus {
  /// The current version of the app.
  final String localVersion;

  /// The most recent version of the app in the store.
  final String storeVersion;

  final TargetPlatform platform;

  VersionStatus({
    @required this.localVersion,
    this.storeVersion,
    this.platform,
  });

  bool get canUpdate {
    List<int> local = (localVersion ?? '0.0.0').split('.').map((version) => int.parse(version)).toList();
    List<int> store = (storeVersion ?? localVersion ?? '0.0.0').split('.').map((version) => int.parse(version)).toList();

    if (local.length == store.length) {
      for (int i = 0; i < store.length; i++) {
        if (store[i] > local[i]) {
          return true;
        } else if (store[i] < local[i]) {
          return false;
        }
      }

      return false;
    } else {
      return store.length > local.length;
    }
  }

  /// Launches the Apple App Store or Google Play Store page for the app.
  void launchAppStore() async {
    if (TargetPlatform.android == platform || TargetPlatform.iOS == platform) {
      await LaunchReview.launch(writeReview: false);
    } else {
      _printNotSupportedMessage();
    }
  }
}

class NewVersion {
  /// This is required to check the user's platform and display alert dialogs.
  final BuildContext context;

  /// An optional value that can override the default packageName when
  /// attempting to reach the Google Play Store. This is useful if your app has
  /// a different package name in the Play Store for some reason.
  final String androidId;

  /// An optional value that can override the default packageName when
  /// attempting to reach the Apple App Store. This is useful if your app has
  /// a different package name in the App Store for some reason.
  final String iOSId;

  /// This is used to check whether current device is android, iOS, or etc.
  final TargetPlatform _platform;

  NewVersion({
    @required this.context,
    this.androidId,
    this.iOSId,
  }) : assert(context != null), _platform = Theme.of(context).platform;

  /// This checks the version status, then displays a platform-specific alert
  /// with buttons to dismiss the update alert, or go to the app store.
  Future<bool> showAlertIfNecessary({
    bool dismissible = true,
    Widget title,
    Widget content,
    Widget dismiss,
    Widget submit,
    void Function() onDismiss,
    void Function() onSubmit,
  }) async {
    VersionStatus versionStatus = await getVersionStatus();
    if (versionStatus.canUpdate) {
      showUpdateDialog(
        versionStatus,
        dismissible: dismissible,
        title: title,
        content: content,
        dismiss: dismiss,
        submit: submit,
        onDismiss: onDismiss,
        onSubmit: onSubmit
      );

      return true;
    } else {
      return false;
    }
  }

  /// This checks the version status and returns the information. This is useful
  /// if you want to display a custom alert, or use the information in a different
  /// way.
  Future<VersionStatus> getVersionStatus() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    VersionStatus versionStatus = VersionStatus(
      localVersion: packageInfo.version,
    );

    if (TargetPlatform.android == _platform) {
      versionStatus = await _getAndroidStoreVersion(androidId ?? packageInfo.packageName, versionStatus);
    } else if (TargetPlatform.iOS == _platform) {
      versionStatus = await _getIOSStoreVersion(iOSId ?? packageInfo.packageName, versionStatus);
    } else {
      _printNotSupportedMessage();
    }

    return versionStatus;
  }

  /// iOS info is fetched by using the iTunes lookup API, which returns a JSON document.
  Future<VersionStatus> _getIOSStoreVersion(String id, VersionStatus versionStatus) async {
    final response = await http.get('http://itunes.apple.com/lookup?bundleId=$id&country=kr');

    if (response.statusCode == 200) {
      final jsonObj = json.decode(response.body);

      return VersionStatus(
        localVersion: versionStatus.localVersion,
        storeVersion: jsonObj['results'][0]['version'],
        platform: TargetPlatform.iOS
      );
    } else {
      print('Can\'t find an app in the App Store with the id: $id');
      return versionStatus;
    }
  }

  /// Android info is fetched by parsing the html of the app store page.
  Future<VersionStatus> _getAndroidStoreVersion(String id, VersionStatus versionStatus) async {
    final response = await http.get('https://play.google.com/store/apps/details?id=$id');

    if (response.statusCode == 200) {
      final versionElement = parse(response.body).getElementsByClassName('hAyfc').firstWhere(
        (elm) {
          String text = elm.querySelector('.BgcNfc').text;
          return text == 'Current Version' || text == '현재 버전';
        },
      );

      return VersionStatus(
        localVersion: versionStatus.localVersion,
        storeVersion: versionElement.querySelector('.htlgb').text,
        platform: TargetPlatform.android
      );
    } else {
      print('Can\'t find an app in the Play Store with the id: $id');
      return versionStatus;
    }
  }

  /// Shows the user a platform-specific alert about the app update. The user can dismiss the alert or proceed to the app store.
  void showUpdateDialog(VersionStatus versionStatus, {
    bool dismissible = true,
    Widget title,
    Widget content,
    Widget dismiss,
    Widget submit,
    void Function() onDismiss,
    void Function() onSubmit,
  }) async {
    final titleText = title ?? Text('Update Available');
    final contentText = content ?? Text('You can now update this app from ${versionStatus.localVersion} to ${versionStatus.storeVersion}');

    final dismissText = dismiss ?? Text('Maybe Later');
    final submitText = submit ?? Text(
      'Update',
      style: TextStyle(fontWeight: FontWeight.w600)
    );

    final dismissAction = onDismiss ?? () => Navigator.of(context, rootNavigator: true).pop();
    final submitAction = onSubmit ?? () {
      versionStatus.launchAppStore();
      Navigator.of(context, rootNavigator: true).pop();
    };

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => _platform == TargetPlatform.android ? AlertDialog(
        title: titleText,
        content: contentText,
        actions: <Widget>[
          if (dismissible) FlatButton(
            child: dismissText,
            onPressed: dismissAction,
          ),
          FlatButton(
            child: submitText,
            onPressed: submitAction,
          ),
        ],
      ) : CupertinoAlertDialog(
        title: titleText,
        content: contentText,
        actions: <Widget>[
          if (dismissible) CupertinoDialogAction(
            child: dismissText,
            onPressed: dismissAction,
          ),
          CupertinoDialogAction(
            child: submitText,
            onPressed: submitAction,
          ),
        ],
      )
    );
  }
}

void _printNotSupportedMessage() {
  print('This target platform is not yet supported by this package.');
}
