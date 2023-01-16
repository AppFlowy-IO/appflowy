///
//  Generated code. Do not modify.
//  source: event_map.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use userEventDescriptor instead')
const UserEvent$json = const {
  '1': 'UserEvent',
  '2': const [
    const {'1': 'InitUser', '2': 0},
    const {'1': 'SignIn', '2': 1},
    const {'1': 'SignUp', '2': 2},
    const {'1': 'SignOut', '2': 3},
    const {'1': 'UpdateUserProfile', '2': 4},
    const {'1': 'GetUserProfile', '2': 5},
    const {'1': 'CheckUser', '2': 6},
    const {'1': 'SetAppearanceSetting', '2': 7},
    const {'1': 'GetAppearanceSetting', '2': 8},
    const {'1': 'GetUserSetting', '2': 9},
  ],
};

/// Descriptor for `UserEvent`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List userEventDescriptor = $convert.base64Decode('CglVc2VyRXZlbnQSDAoISW5pdFVzZXIQABIKCgZTaWduSW4QARIKCgZTaWduVXAQAhILCgdTaWduT3V0EAMSFQoRVXBkYXRlVXNlclByb2ZpbGUQBBISCg5HZXRVc2VyUHJvZmlsZRAFEg0KCUNoZWNrVXNlchAGEhgKFFNldEFwcGVhcmFuY2VTZXR0aW5nEAcSGAoUR2V0QXBwZWFyYW5jZVNldHRpbmcQCBISCg5HZXRVc2VyU2V0dGluZxAJ');
