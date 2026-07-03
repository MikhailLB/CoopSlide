class ServerPayload {
  final bool accepted;
  final String? targetUrl;
  final String? note;
  final int? validUntil;

  const ServerPayload({
    required this.accepted,
    this.targetUrl,
    this.note,
    this.validUntil,
  });

  factory ServerPayload.fromMap(Map<String, dynamic> map) {
    return ServerPayload(
      accepted: map['ok'] as bool? ?? false,
      targetUrl: map['url'] as String?,
      note: map['message'] as String?,
      validUntil: map['expires'] as int?,
    );
  }

  factory ServerPayload.failure(String note) {
    return ServerPayload(accepted: false, note: note);
  }
}
