//! The map calls (design doc 14): an index of geotagged assets held in the keyring, queried per viewport.

use crate::cluster::{ClusterIndex, Filter};
use crate::proto::kernel::v1::{
    MapAssetsRequest, MapAssetsResponse, MapCluster, MapFilter, MapIndexBuildRequest, MapIndexBuildResponse,
    MapIndexDropRequest, MapIndexDropResponse, MapQueryRequest, MapQueryResponse,
};
use crate::{CallError, Keyring, invalid_request};

pub(crate) fn build(ring: &mut Keyring, request: MapIndexBuildRequest) -> Result<MapIndexBuildResponse, CallError> {
    if request.latitudes.len() != request.longitudes.len() {
        return Err(invalid_request("longitudes"));
    }
    if !request.times.is_empty() && request.times.len() != request.latitudes.len() {
        return Err(invalid_request("times"));
    }
    let points: Vec<_> = request.latitudes.into_iter().zip(request.longitudes).collect();
    let index = ClusterIndex::build_timed(&points, &request.times);
    let mapped = u32::try_from(index.mapped()).unwrap_or(u32::MAX);
    ring.last_map = ring.last_map.saturating_add(1);
    ring.maps.insert(ring.last_map, index);
    Ok(MapIndexBuildResponse {
        index: ring.last_map,
        mapped,
    })
}

pub(crate) fn query(ring: &Keyring, request: &MapQueryRequest) -> Result<MapQueryResponse, CallError> {
    let index = index(ring, request.index)?;
    let filter = filter(request.filter.as_ref())?;
    let zoom = u8::try_from(request.zoom).unwrap_or(u8::MAX);
    let found = index.query_filtered(request.west, request.south, request.east, request.north, zoom, &filter);
    let clusters = found
        .into_iter()
        .map(|c| MapCluster {
            latitude: c.lat,
            longitude: c.lon,
            count: c.count,
            asset: c.asset,
        })
        .collect();
    Ok(MapQueryResponse { clusters })
}

pub(crate) fn assets(ring: &Keyring, request: &MapAssetsRequest) -> Result<MapAssetsResponse, CallError> {
    let index = index(ring, request.index)?;
    let filter = filter(request.filter.as_ref())?;
    let limit = usize::try_from(request.limit).unwrap_or(usize::MAX);
    let (assets, total) = index.assets(request.west, request.south, request.east, request.north, &filter, limit);
    Ok(MapAssetsResponse { assets, total })
}

pub(crate) fn forget(ring: &mut Keyring, request: MapIndexDropRequest) -> Result<MapIndexDropResponse, CallError> {
    ring.maps
        .remove(&request.index)
        .map(|_| MapIndexDropResponse {})
        .ok_or_else(|| invalid_request("index"))
}

fn index(ring: &Keyring, handle: u32) -> Result<&ClusterIndex, CallError> {
    ring.maps.get(&handle).ok_or_else(|| invalid_request("index"))
}

fn filter(filter: Option<&MapFilter>) -> Result<Filter, CallError> {
    let Some(f) = filter else {
        return Ok(Filter::default());
    };
    if f.polygon.len() % 2 != 0 {
        return Err(invalid_request("filter.polygon"));
    }
    Ok(Filter {
        from: f.time_from,
        to: f.time_to,
        polygon: f.polygon.as_chunks::<2>().0.to_vec(),
    })
}
