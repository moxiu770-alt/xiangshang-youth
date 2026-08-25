/**
 * Reconciles volatile edge-device liveness into durable operational state.
 * Explicit disabled/maintenance states are never overwritten by a timeout.
 */
export async function reconcileFieldLiveness(executor, offlineAfterSeconds) {
  const devices = await executor.query(`UPDATE test_devices
    SET status='offline',updated_at=now()
    WHERE status='online' AND (last_heartbeat_at IS NULL OR last_heartbeat_at < now() - ($1::int * interval '1 second'))
    RETURNING id,school_id AS "schoolId",station_id AS "stationId",device_code AS "deviceCode",last_heartbeat_at AS "lastHeartbeatAt"`, [offlineAfterSeconds]);
  if (!devices.rowCount) return { devices: [], stations: [] };
  const stationIds = [...new Set(devices.rows.map((device) => device.stationId).filter(Boolean))];
  if (!stationIds.length) return { devices: devices.rows, stations: [] };
  const stations = await executor.query(`UPDATE test_stations station
    SET status='offline',updated_at=now()
    WHERE station.id = ANY($1::text[]) AND station.status='online'
      AND NOT EXISTS (SELECT 1 FROM test_devices device
        WHERE device.station_id=station.id AND device.status='online' AND device.device_type='edge_host'
          AND device.last_heartbeat_at >= now() - ($2::int * interval '1 second'))
    RETURNING id,school_id AS "schoolId",station_code AS "stationCode"`, [stationIds, offlineAfterSeconds]);
  return { devices: devices.rows, stations: stations.rows };
}
