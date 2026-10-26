/// Where the photo of a timeline tile is (ADR-0200 proposal 1): only on this
/// device, on it and backed up, or only on the server.
enum Availability {
  /// Only on this device.
  notBackedUp('not_backed_up'),

  /// On this device and verified on the server.
  backedUp('backed_up'),

  /// Only on the server.
  cloudOnly('cloud_only');

  new(this.sql);

  /// Its name in the replica's timeline.
  final String sql;
}
