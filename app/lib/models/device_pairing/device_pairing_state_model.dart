import 'device_pairing_bundle_model.dart';
import 'device_pairing_draft_model.dart';

enum DevicePairingStage {
  idle,
  unavailable,
  refreshingPorts,
  portReady,
  usbLinked,
  armed,
  sending,
  awaitingOnline,
  paired,
  failed,
}

class DevicePairingStateModel {
  static const Object _unset = Object();

  const DevicePairingStateModel({
    required this.stage,
    required this.platformSupported,
    required this.availablePorts,
    required this.draft,
    required this.connectedPortName,
    required this.deviceOnline,
    required this.transportState,
    required this.transportReason,
    required this.deviceId,
    required this.firmwareVersion,
    required this.bundle,
    required this.statusMessage,
    required this.errorMessage,
  });

  final DevicePairingStage stage;
  final bool platformSupported;
  final List<String> availablePorts;
  final DevicePairingDraftModel draft;
  final String connectedPortName;
  final bool deviceOnline;
  final String transportState;
  final String? transportReason;
  final String? deviceId;
  final String? firmwareVersion;
  final DevicePairingBundleModel? bundle;
  final String? statusMessage;
  final String? errorMessage;

  bool get usbLinked => connectedPortName.trim().isNotEmpty;
  bool get isArmed =>
      transportState == 'armed' || stage == DevicePairingStage.armed;
  bool get isBusy =>
      stage == DevicePairingStage.refreshingPorts ||
      stage == DevicePairingStage.sending ||
      stage == DevicePairingStage.awaitingOnline;

  DevicePairingStateModel copyWith({
    DevicePairingStage? stage,
    bool? platformSupported,
    List<String>? availablePorts,
    DevicePairingDraftModel? draft,
    String? connectedPortName,
    bool? deviceOnline,
    String? transportState,
    Object? transportReason = _unset,
    Object? deviceId = _unset,
    Object? firmwareVersion = _unset,
    Object? bundle = _unset,
    Object? statusMessage = _unset,
    Object? errorMessage = _unset,
  }) {
    return DevicePairingStateModel(
      stage: stage ?? this.stage,
      platformSupported: platformSupported ?? this.platformSupported,
      availablePorts: availablePorts ?? this.availablePorts,
      draft: draft ?? this.draft,
      connectedPortName: connectedPortName ?? this.connectedPortName,
      deviceOnline: deviceOnline ?? this.deviceOnline,
      transportState: transportState ?? this.transportState,
      transportReason: identical(transportReason, _unset)
          ? this.transportReason
          : transportReason as String?,
      deviceId: identical(deviceId, _unset)
          ? this.deviceId
          : deviceId as String?,
      firmwareVersion: identical(firmwareVersion, _unset)
          ? this.firmwareVersion
          : firmwareVersion as String?,
      bundle: identical(bundle, _unset)
          ? this.bundle
          : bundle as DevicePairingBundleModel?,
      statusMessage: identical(statusMessage, _unset)
          ? this.statusMessage
          : statusMessage as String?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  factory DevicePairingStateModel.initial({required bool platformSupported}) {
    return DevicePairingStateModel(
      stage: platformSupported
          ? DevicePairingStage.idle
          : DevicePairingStage.unavailable,
      platformSupported: platformSupported,
      availablePorts: const <String>[],
      draft: DevicePairingDraftModel.empty(),
      connectedPortName: '',
      deviceOnline: false,
      transportState: 'idle',
      transportReason: platformSupported
          ? 'Select a USB serial device to start pairing.'
          : 'Robot pairing is only available on desktop builds.',
      deviceId: null,
      firmwareVersion: null,
      bundle: null,
      statusMessage: platformSupported
          ? 'Robot pairing is ready once the backend and USB link are available.'
          : 'Pairing unavailable on this platform.',
      errorMessage: null,
    );
  }
}
