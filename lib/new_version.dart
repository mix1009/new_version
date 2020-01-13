library new_version;

import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:package_info/package_info.dart';
import 'package:html/parser.dart' show parse;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/cupertino.dart';
import 'dart:convert';
import 'dart:async';

/// Information about the app's current version, and the most recent version
/// available in the Apple App Store or Google Play Store.
class VersionStatus {
  /// The current version of the app.
  final String localVersion;

  /// The most recent version of the app in the store.
  String storeVersion;

  /// A link to the app store page where the app can be updated.
  String appStoreLink;

  VersionStatus({
    @required this.localVersion
  });

  bool get canUpdate {
    List<int> local = (localVersion ?? '0.0.0').split('.').map((version) => int.parse(version));
    List<int> store = (storeVersion ?? '0.0.0').split('.').map((version) => int.parse(version));

    int length = min(local.length, store.length);

    for (int i = 0; i < length; i++) {
      if (store[i] > local[i]) {
        return true;
      }
    }

    return false;
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

  NewVersion({
    @required this.context,
    this.androidId,
    this.iOSId,
  }) : assert(context != null);

  /// This checks the version status, then displays a platform-specific alert
  /// with buttons to dismiss the update alert, or go to the app store.
  Future<bool> showAlertIfNecessary({
    String title,
    String content,
    String dismiss,
    String update,
    void Function() onDismiss,
    void Function() onUpdate,
  }) async {
    VersionStatus versionStatus = await getVersionStatus();
    if (versionStatus != null && versionStatus.canUpdate) {
      showUpdateDialog(
        versionStatus,
        title: title,
        content: content,
        dismiss: dismiss,
        update: update,
        onDismiss: onDismiss,
        onUpdate: onUpdate
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

    switch (Theme.of(context).platform) {
      case TargetPlatform.android:
        final id = androidId ?? packageInfo.packageName;
        return _getAndroidStoreVersion(id, versionStatus);
        break;
      case TargetPlatform.iOS:
        final id = iOSId ?? packageInfo.packageName;
        return _getIOSStoreVersion(id, versionStatus);
        break;
      default:
        print('This target platform is not yet supported by this package.');
        return versionStatus;
    }
  }

  /// iOS info is fetched by using the iTunes lookup API, which returns a JSON document.
  _getIOSStoreVersion(String id, VersionStatus versionStatus) async {
    final url = 'http://itunes.apple.com/lookup?bundleId=$id&country=kr';
    final response = await http.get(url);
    if (response.statusCode != 200) {
      print('Can\'t find an app in the App Store with the id: $id');
      return null;
    }
    final jsonObj = json.decode(response.body);
    versionStatus.storeVersion = jsonObj['results'][0]['version'];
    versionStatus.appStoreLink = jsonObj['results'][0]['trackViewUrl'];
    return versionStatus;
  }

  /// Android info is fetched by parsing the html of the app store page.
  _getAndroidStoreVersion(String id, VersionStatus versionStatus) async {
    final url = 'https://play.google.com/store/apps/details?id=$id';
    final response = await http.get(url);
    if (response.statusCode != 200) {
      print('Can\'t find an app in the Play Store with the id: $id');
      return null;
    }
    final document = parse(response.body);
    final elements = document.getElementsByClassName('hAyfc');
    final versionElement = elements.firstWhere(
      (elm) {
        String text = elm.querySelector('.BgcNfc').text;
        return text == 'Current Version' || text == '현재 버전';
      },
    );
    versionStatus.storeVersion = versionElement.querySelector('.htlgb').text;
    versionStatus.appStoreLink = url;
    return versionStatus;
  }

  /// Shows the user a platform-specific alert about the app update. The user can dismiss the alert or proceed to the app store.
  void showUpdateDialog(VersionStatus versionStatus, {
    String title,
    String content,
    String dismiss,
    String update,
    void Function() onDismiss,
    void Function() onUpdate,
  }) async {
    final titleText = Text(title ?? 'Update Available');
    final contentText = Text(content ?? 'You can now update this app from ${versionStatus.localVersion} to ${versionStatus.storeVersion}');

    final dismissText = Text(dismiss ?? 'Maybe Later');
    final dismissAction = onDismiss ?? () {
      Navigator.pop(context);
    };

    final updateText = Text(update ?? 'Update');
    final updateAction = onUpdate ?? () {
      _launchAppStore(versionStatus.appStoreLink);
      Navigator.pop(context);
    };

    final platform = Theme.of(context).platform;

    showDialog(
      context: context,
      builder: (BuildContext context) => platform == TargetPlatform.android ? AlertDialog(
        title: titleText,
        content: contentText,
        actions: <Widget>[
          FlatButton(
            child: dismissText,
            onPressed: dismissAction,
          ),
          FlatButton(
            child: updateText,
            onPressed: updateAction,
          ),
        ],
      ) : CupertinoAlertDialog(
        title: titleText,
        content: contentText,
        actions: <Widget>[
          CupertinoDialogAction(
            child: dismissText,
            onPressed: dismissAction,
          ),
          CupertinoDialogAction(
            child: updateText,
            onPressed: updateAction,
          ),
        ],
      )
    );
  }

  /// Launches the Apple App Store or Google Play Store page for the app.
  void _launchAppStore(String appStoreLink) async {
    if (await canLaunch(appStoreLink)) {
      await launch(appStoreLink, forceWebView: true);
    } else {
      throw 'Could not launch appStoreLink';
    }
  }
}
