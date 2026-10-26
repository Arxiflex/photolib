//! Hierarchical clustering of geotagged assets for the map view (design doc 14), on the device's own replica.

/// One marker of the map: a group of assets, or one asset when `count` is 1.
#[derive(Clone, Debug, PartialEq)]
pub struct Cluster {
    /// Centroid latitude in degrees.
    pub lat: f64,
    /// Centroid longitude in degrees.
    pub lon: f64,
    /// Assets in the cluster.
    pub count: u32,
    /// For a single asset, its index in the slice given to `ClusterIndex::build`.
    pub asset: Option<u32>,
}

/// Cells per axis of the finest grid, as a power of two; one asset per cell is the leaf level.
const LEAF_BITS: u32 = 20;
/// The last zoom that merges assets (64 px cells); deeper zooms return single assets.
const MAX_CLUSTER_ZOOM: u8 = 15;
/// Key bits dropped from a leaf's key to get its cell at `MAX_CLUSTER_ZOOM` (64 px cells: `2 * (20 - 2 - 15)`).
const LEAF_TO_TOP_SHIFT: u32 = 6;
/// The Web Mercator limit of latitude.
const MAX_LAT: f64 = 85.051_128_779_8;

/// A cell's assets: coordinate sums are Web Mercator x and y in 0..1, the key interleaves the cell's column and row.
#[derive(Clone, Copy)]
struct Node {
    key: u64,
    sx: f64,
    sy: f64,
    count: u32,
    asset: u32,
}

/// Clusters of every zoom level, built once and queried per viewport.
pub struct ClusterIndex {
    /// Zoom 0 to `MAX_CLUSTER_ZOOM`, each sorted by key, one node per 64 px cell of its zoom.
    levels: Vec<Vec<Node>>,
    /// One node per asset, sorted by key at `LEAF_BITS`.
    leaf: Vec<Node>,
    /// Capture time of every asset by position, or empty when none is known.
    times: Vec<i64>,
}

/// Which assets a map call considers; the default is all of them.
#[derive(Clone, Debug, Default)]
pub struct Filter {
    /// Capture time in seconds, both ends included.
    pub from: Option<i64>,
    /// The latest capture time, included.
    pub to: Option<i64>,
    /// A lasso as [latitude, longitude] vertices; fewer than three means none.
    pub polygon: Vec<[f64; 2]>,
}

impl Filter {
    fn lasso(&self) -> Vec<(f64, f64)> {
        let corners: Vec<_> = self
            .polygon
            .iter()
            .filter_map(|&[lat, lon]| mercator(lat, lon))
            .collect();
        if corners.len() >= 3 { corners } else { Vec::new() }
    }

    fn is_all(&self) -> bool {
        self.from.is_none() && self.to.is_none() && self.lasso().is_empty()
    }
}

/// Whether (x, y) lies inside the polygon, by the even-odd rule.
fn inside(polygon: &[(f64, f64)], x: f64, y: f64) -> bool {
    let mut odd = false;
    let mut before = polygon.last().copied();
    for &(x2, y2) in polygon {
        if let Some((x1, y1)) = before
            && (y1 > y) != (y2 > y)
            && x < (x2 - x1) * (y - y1) / (y2 - y1) + x1
        {
            odd = !odd;
        }
        before = Some((x2, y2));
    }
    odd
}

fn spread(v: u64) -> u64 {
    let mut v = v & 0xf_ffff;
    v = (v | (v << 16)) & 0x0000_ffff_0000_ffff;
    v = (v | (v << 8)) & 0x00ff_00ff_00ff_00ff;
    v = (v | (v << 4)) & 0x0f0f_0f0f_0f0f_0f0f;
    v = (v | (v << 2)) & 0x3333_3333_3333_3333;
    (v | (v << 1)) & 0x5555_5555_5555_5555
}

fn morton(col: u64, row: u64) -> u64 {
    spread(col) | (spread(row) << 1)
}

fn mercator(lat: f64, lon: f64) -> Option<(f64, f64)> {
    if !(lat.abs() <= MAX_LAT && lon.abs() <= 180.0) {
        return None;
    }
    let x = (lon + 180.0) / 360.0;
    let y = 0.5 - (std::f64::consts::FRAC_PI_4 + lat.to_radians() / 2.0).tan().ln() / std::f64::consts::TAU;
    Some((x, y.clamp(0.0, 1.0)))
}

/// The column or row of `v` (0..1) in a grid of `2^bits` cells.
#[allow(
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    clippy::cast_precision_loss
)] // bits <= 20
fn cell(v: f64, bits: u32) -> u64 {
    let n = 1_u64 << bits;
    ((v * n as f64) as u64).min(n.saturating_sub(1))
}

impl ClusterIndex {
    /// Indexes `points` (latitude, longitude in degrees); points that are not finite or off the map are skipped.
    pub fn build(points: &[(f64, f64)]) -> Self {
        Self::build_timed(points, &[])
    }

    /// As `build`, with the capture time in seconds of each point; `times` is empty or as long as `points`.
    pub fn build_timed(points: &[(f64, f64)], times: &[i64]) -> Self {
        let mut leaf: Vec<Node> = points
            .iter()
            .zip(0..=u32::MAX)
            .filter_map(|(&(lat, lon), asset)| {
                let (x, y) = mercator(lat, lon)?;
                let key = morton(cell(x, LEAF_BITS), cell(y, LEAF_BITS));
                Some(Node {
                    key,
                    sx: x,
                    sy: y,
                    count: 1,
                    asset,
                })
            })
            .collect();
        leaf.sort_unstable_by_key(|n| n.key);
        let mut levels = Vec::new();
        let mut below = &leaf;
        for zoom in (0..=MAX_CLUSTER_ZOOM).rev() {
            let shift = if zoom == MAX_CLUSTER_ZOOM { LEAF_TO_TOP_SHIFT } else { 2 };
            let mut level: Vec<Node> = Vec::new();
            for n in below {
                let key = n.key >> shift;
                match level.last_mut() {
                    Some(last) if last.key == key => {
                        last.sx += n.sx;
                        last.sy += n.sy;
                        last.count = last.count.saturating_add(n.count);
                    }
                    _ => level.push(Node { key, ..*n }),
                }
            }
            levels.push(level);
            below = levels.last().unwrap_or(&leaf);
        }
        levels.reverse();
        Self {
            levels,
            leaf,
            times: if times.len() == points.len() {
                times.to_vec()
            } else {
                Vec::new()
            },
        }
    }

    /// How many assets the map shows.
    pub fn mapped(&self) -> usize {
        self.leaf.len()
    }

    /// The leaf nodes inside the box that pass the filter, in key order.
    fn matching<'a>(&'a self, bounds: (f64, f64, f64, f64), filter: &Filter) -> Vec<&'a Node> {
        let (west, south, east, north) = bounds;
        let (Some((_, y0)), Some((_, y1))) = (
            mercator(north.clamp(-MAX_LAT, MAX_LAT), 0.0),
            mercator(south.clamp(-MAX_LAT, MAX_LAT), 0.0),
        ) else {
            return Vec::new();
        };
        let norm = |lon: f64| (lon.clamp(-180.0, 180.0) + 180.0) / 360.0;
        let spans = if west > east {
            vec![(norm(west), 1.0), (0.0, norm(east))]
        } else {
            vec![(norm(west), norm(east))]
        };
        let lasso = filter.lasso();
        self.leaf
            .iter()
            .filter(|n| {
                (y0..=y1).contains(&n.sy)
                    && spans.iter().any(|(a, b)| (*a..=*b).contains(&n.sx))
                    && (!lasso.is_empty() && inside(&lasso, n.sx, n.sy) || lasso.is_empty())
                    && (filter.from.is_none() && filter.to.is_none() || {
                        let t = self.times.get(n.asset as usize).copied();
                        t.is_some_and(|t| filter.from.is_none_or(|f| t >= f) && filter.to.is_none_or(|u| t <= u))
                    })
            })
            .collect()
    }

    /// As `query`, over only the assets that pass the filter (a scan of the leaves, not a lookup).
    pub fn query_filtered(
        &self,
        west: f64,
        south: f64,
        east: f64,
        north: f64,
        zoom: u8,
        filter: &Filter,
    ) -> Vec<Cluster> {
        if filter.is_all() {
            return self.query(west, south, east, north, zoom);
        }
        let bits = u32::from(zoom).saturating_add(2).min(LEAF_BITS);
        let shift = LEAF_BITS.saturating_sub(bits).saturating_mul(2);
        let mut nodes: Vec<Node> = Vec::new();
        for n in self.matching((west, south, east, north), filter) {
            let key = n.key >> shift;
            match nodes.last_mut() {
                Some(last) if last.key == key => {
                    last.sx += n.sx;
                    last.sy += n.sy;
                    last.count = last.count.saturating_add(1);
                }
                _ => nodes.push(Node { key, ..*n }),
            }
        }
        nodes.iter().map(to_cluster).collect()
    }

    /// The positions of the assets in the box that pass the filter, ascending and cut to `limit` (0 for all), and how
    /// many pass in all.
    pub fn assets(
        &self,
        west: f64,
        south: f64,
        east: f64,
        north: f64,
        filter: &Filter,
        limit: usize,
    ) -> (Vec<u32>, u32) {
        let mut found: Vec<u32> = self
            .matching((west, south, east, north), filter)
            .iter()
            .map(|n| n.asset)
            .collect();
        found.sort_unstable();
        let total = u32::try_from(found.len()).unwrap_or(u32::MAX);
        if limit > 0 {
            found.truncate(limit);
        }
        (found, total)
    }

    /// The clusters at integer `zoom` whose cell meets the box; `west > east` means it crosses the antimeridian.
    pub fn query(&self, west: f64, south: f64, east: f64, north: f64, zoom: u8) -> Vec<Cluster> {
        let (nodes, bits) = match self.levels.get(usize::from(zoom)) {
            Some(level) => (level, u32::from(zoom) + 2),
            None => (&self.leaf, LEAF_BITS),
        };
        let wrap = west > east;
        let spans = if wrap {
            [(west, 180.0), (-180.0, east)]
        } else {
            [(west, east), (1.0, 0.0)]
        };
        let (Some((_, y0)), Some((_, y1))) = (
            mercator(north.clamp(-MAX_LAT, MAX_LAT), 0.0),
            mercator(south.clamp(-MAX_LAT, MAX_LAT), 0.0),
        ) else {
            return Vec::new();
        };
        let mut out = Vec::new();
        for (w, e) in spans.into_iter().take(if wrap { 2 } else { 1 }) {
            let (x0, x1) = (
                (w.clamp(-180.0, 180.0) + 180.0) / 360.0,
                (e.clamp(-180.0, 180.0) + 180.0) / 360.0,
            );
            let (c0, c1, r0, r1) = (cell(x0, bits), cell(x1, bits), cell(y0, bits), cell(y1, bits));
            if c0 > c1 || r0 > r1 {
                continue;
            }
            if c1
                .saturating_sub(c0)
                .saturating_add(1)
                .saturating_mul(r1.saturating_sub(r0).saturating_add(1))
                <= nodes.len() as u64
            {
                for row in r0..=r1 {
                    for col in c0..=c1 {
                        let key = morton(col, row);
                        let from = nodes.partition_point(|n| n.key < key);
                        let to =
                            from.saturating_add(nodes.get(from..).map_or(0, |t| t.partition_point(|n| n.key == key)));
                        out.extend(nodes.get(from..to).into_iter().flatten().map(to_cluster));
                    }
                }
            } else {
                let inside = |n: &&Node| {
                    let (col, row) = (
                        cell(n.sx / f64::from(n.count), bits),
                        cell(n.sy / f64::from(n.count), bits),
                    );
                    (c0..=c1).contains(&col) && (r0..=r1).contains(&row)
                };
                out.extend(nodes.iter().filter(inside).map(to_cluster));
            }
        }
        out
    }
}

fn to_cluster(n: &Node) -> Cluster {
    let c = f64::from(n.count);
    let (x, y) = (n.sx / c, n.sy / c);
    Cluster {
        lat: (std::f64::consts::PI * 2.0_f64.mul_add(-y, 1.0))
            .sinh()
            .atan()
            .to_degrees(),
        lon: x.mul_add(360.0, -180.0),
        count: n.count,
        asset: (n.count == 1).then_some(n.asset),
    }
}
