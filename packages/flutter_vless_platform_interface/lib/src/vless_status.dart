enum VlessConnectionState {
  connected,
  connecting,
  disconnected,
  disconnecting,
  unknown;

  static VlessConnectionState parse(Object? value) {
    final normalized = value?.toString().trim().toUpperCase();
    return switch (normalized) {
      'CONNECTED' => VlessConnectionState.connected,
      'CONNECTING' => VlessConnectionState.connecting,
      'DISCONNECTED' => VlessConnectionState.disconnected,
      'DISCONNECTING' => VlessConnectionState.disconnecting,
      _ => VlessConnectionState.unknown,
    };
  }

  String get wireName {
    return switch (this) {
      VlessConnectionState.connected => 'CONNECTED',
      VlessConnectionState.connecting => 'CONNECTING',
      VlessConnectionState.disconnected => 'DISCONNECTED',
      VlessConnectionState.disconnecting => 'DISCONNECTING',
      VlessConnectionState.unknown => 'UNKNOWN',
    };
  }
}

class VlessStatus {
  final int duration;
  final int uploadSpeed;
  final int downloadSpeed;
  final int upload;
  final int download;
  final String state;
  final VlessConnectionState connectionState;

  VlessStatus({
    this.duration = 0,
    this.uploadSpeed = 0,
    this.downloadSpeed = 0,
    this.upload = 0,
    this.download = 0,
    this.state = "DISCONNECTED",
    VlessConnectionState? connectionState,
  }) : connectionState = connectionState ?? VlessConnectionState.parse(state);

  factory VlessStatus.fromMap(Map<Object?, Object?> map) {
    final state = _readString(map, const ['state', 'status']) ??
        VlessConnectionState.disconnected.wireName;
    return VlessStatus(
      duration: _readInt(map, const ['duration']),
      uploadSpeed: _readInt(map, const ['uploadSpeed', 'upload_speed']),
      downloadSpeed: _readInt(map, const ['downloadSpeed', 'download_speed']),
      upload: _readInt(map, const ['upload']),
      download: _readInt(map, const ['download']),
      state: state,
    );
  }

  factory VlessStatus.fromList(List<Object?> values) {
    return VlessStatus(
      duration: _parseInt(_valueAt(values, 0)),
      uploadSpeed: _parseInt(_valueAt(values, 1)),
      downloadSpeed: _parseInt(_valueAt(values, 2)),
      upload: _parseInt(_valueAt(values, 3)),
      download: _parseInt(_valueAt(values, 4)),
      state: _valueAt(values, 5)?.toString() ??
          VlessConnectionState.disconnected.wireName,
    );
  }

  factory VlessStatus.fromEvent(Object? event) {
    if (event is VlessStatus) {
      return event;
    }
    if (event is Map<Object?, Object?>) {
      return VlessStatus.fromMap(event);
    }
    if (event is List<Object?>) {
      return VlessStatus.fromList(event);
    }
    throw FormatException('Unsupported VLESS status payload: $event');
  }

  static VlessStatus? tryParse(Object? event) {
    try {
      return VlessStatus.fromEvent(event);
    } on FormatException {
      return null;
    }
  }

  Map<String, Object> toMap() => {
        'duration': duration,
        'uploadSpeed': uploadSpeed,
        'downloadSpeed': downloadSpeed,
        'upload': upload,
        'download': download,
        'state': state,
      };

  @override
  String toString() {
    return 'VlessStatus('
        'duration: $duration, '
        'uploadSpeed: $uploadSpeed, '
        'downloadSpeed: $downloadSpeed, '
        'upload: $upload, '
        'download: $download, '
        'state: $state'
        ')';
  }

  @override
  bool operator ==(Object other) {
    return other is VlessStatus &&
        other.duration == duration &&
        other.uploadSpeed == uploadSpeed &&
        other.downloadSpeed == downloadSpeed &&
        other.upload == upload &&
        other.download == download &&
        other.state == state &&
        other.connectionState == connectionState;
  }

  @override
  int get hashCode => Object.hash(
        duration,
        uploadSpeed,
        downloadSpeed,
        upload,
        download,
        state,
        connectionState,
      );

  static Object? _valueAt(List<Object?> values, int index) {
    return index < values.length ? values[index] : null;
  }

  static int _readInt(Map<Object?, Object?> map, List<String> keys) {
    for (final key in keys) {
      if (map.containsKey(key)) {
        return _parseInt(map[key]);
      }
    }
    return 0;
  }

  static String? _readString(Map<Object?, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value != null) {
        return value.toString();
      }
    }
    return null;
  }

  static int _parseInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}
