// Pathfinder anisotrope avec etat (x, y, theta) et penalite de courbure
// (BRIEF section 3.5). Une route a une direction : sans l'etat d'orientation, le
// chemin coupe les virages et saute sur les linearites paralleles (fosses,
// lignes, cloisonnements). Voisinage 16 pour supprimer le biais de metrication
// du Dijkstra 8-connexe (traces en escalier a 0/45 deg). Noyau pur (regle : pas
// de SIG en Rust) : R fournit les grilles a plat et recupere le trace.

use std::cmp::Ordering;
use std::collections::BinaryHeap;
use std::f64::consts::PI;

// 16 deplacements (drow, dcol) : les 8 voisins usuels + 8 sauts « cavalier ».
// Directions distinctes -> reduit le biais de metrication de Dijkstra.
const MOVES: [(i64, i64); 16] = [
    (-1, 0), (1, 0), (0, -1), (0, 1),
    (-1, -1), (-1, 1), (1, -1), (1, 1),
    (-2, -1), (-2, 1), (2, -1), (2, 1),
    (-1, -2), (-1, 2), (1, -2), (1, 2),
];

/// Element du tas : ordonne a l'envers pour obtenir un tas-min sur le cout.
struct HeapItem {
    cost: f64,
    state: usize,
}
impl PartialEq for HeapItem {
    fn eq(&self, o: &Self) -> bool {
        self.cost == o.cost
    }
}
impl Eq for HeapItem {}
impl PartialOrd for HeapItem {
    fn partial_cmp(&self, o: &Self) -> Option<Ordering> {
        // Inverse : le plus PETIT cout doit sortir en premier du tas-max.
        o.cost.partial_cmp(&self.cost)
    }
}
impl Ord for HeapItem {
    fn cmp(&self, o: &Self) -> Ordering {
        self.partial_cmp(o).unwrap_or(Ordering::Equal)
    }
}

pub struct PathResult {
    pub path: Vec<usize>,   // cellules du trace (indices 0-based), source -> cible
    pub cost: f64,          // cout total, NaN si cible inatteignable
    pub cumcost: Vec<f64>,  // cout minimal a la source par cellule (NaN si inatteint)
}

// Ecart angulaire non oriente (ligne) dans [0, pi/2] entre deux angles (radians).
#[inline]
fn undirected_diff(a: f64, b: f64) -> f64 {
    let mut d = (a - b).abs() % PI;
    if d > PI / 2.0 {
        d = PI - d;
    }
    d
}

// Ecart angulaire oriente dans [0, pi] entre deux caps (radians).
#[inline]
fn directed_diff(a: f64, b: f64) -> f64 {
    let mut d = (a - b).abs() % (2.0 * PI);
    if d > PI {
        d = 2.0 * PI - d;
    }
    d
}

/// Plus court chemin anisotrope de `src` a `dst` (cellules 0-based, ordre
/// ligne-major) sur la conductivite `sigma`. Le cout d'un pas combine la
/// resistance (1 / sigma), une penalite d'anisotropie qui rencherit les
/// deplacements EN TRAVERS de l'orientation locale `theta_deg` (ponderee par
/// `weight`, p. ex. la vesselness), et une penalite de COURBURE sur le
/// changement de cap. L'etat est (cellule, cap discretise en `k` directions).
#[allow(clippy::too_many_arguments)]
pub fn shortest_path(
    sigma: &[f64],
    theta_deg: &[f64],
    weight: &[f64],
    nrow: usize,
    ncol: usize,
    resolution: f64,
    k: usize,
    lambda: f64,
    mu: f64,
    sigma_min: f64,
    src: usize,
    dst: usize,
) -> PathResult {
    let ncell = nrow * ncol;
    let nstate = ncell * k;

    // Geometrie des deplacements : distance (m) et cap geographique (y vers le
    // haut : dy = -drow), precalcules une fois.
    let mv_dist: Vec<f64> = MOVES
        .iter()
        .map(|&(dr, dc)| ((dr * dr + dc * dc) as f64).sqrt() * resolution)
        .collect();
    let mv_dir: Vec<f64> = MOVES
        .iter()
        .map(|&(dr, dc)| {
            let dx = dc as f64;
            let dy = -(dr as f64);
            dy.atan2(dx).rem_euclid(2.0 * PI)
        })
        .collect();
    // Cap associe a chaque direction discrete.
    let head_ang: Vec<f64> = (0..k).map(|h| h as f64 * 2.0 * PI / k as f64).collect();
    let quantize = |ang: f64| -> usize {
        ((ang.rem_euclid(2.0 * PI) / (2.0 * PI / k as f64)).round() as usize) % k
    };

    let resistance = |c: usize| -> f64 {
        let s = sigma[c];
        if s.is_nan() {
            f64::NAN
        } else {
            1.0 / s.max(sigma_min)
        }
    };

    let mut dist = vec![f64::INFINITY; nstate];
    let mut prev = vec![usize::MAX; nstate];
    let mut heap = BinaryHeap::new();

    // Source : tous les caps autorises, cout nul (le premier pas fixe le cap).
    for h in 0..k {
        let st = src * k + h;
        dist[st] = 0.0;
        heap.push(HeapItem { cost: 0.0, state: st });
    }

    let mut target_state = usize::MAX;
    while let Some(HeapItem { cost, state }) = heap.pop() {
        if cost > dist[state] {
            continue;
        }
        let c = state / k;
        let h = state % k;
        if c == dst {
            target_state = state;
            break;
        }
        let row = (c / ncol) as i64;
        let col = (c % ncol) as i64;
        let res_c = resistance(c);
        if res_c.is_nan() {
            continue;
        }

        for (mi, &(dr, dc)) in MOVES.iter().enumerate() {
            let nr = row + dr;
            let nc = col + dc;
            if nr < 0 || nc < 0 || nr >= nrow as i64 || nc >= ncol as i64 {
                continue;
            }
            let nb = (nr as usize) * ncol + (nc as usize);
            let res_nb = resistance(nb);
            if res_nb.is_nan() {
                continue;
            }
            // Sauts « cavalier » (un pas de 2) : verrouiller par la cellule
            // intermediaire, sinon le trace FRANCHIT une barriere NA d'une seule
            // cellule (eau, exclusion) au lieu de la contourner.
            if dr.abs() == 2 || dc.abs() == 2 {
                let gr = nr - dr.signum();
                let gc = nc - dc.signum();
                let gate = (gr as usize) * ncol + (gc as usize);
                if resistance(gate).is_nan() {
                    continue;
                }
            }

            // Cout de base : resistance moyenne x distance parcourue.
            let base = 0.5 * (res_c + res_nb) * mv_dist[mi];

            // Anisotropie : penaliser le deplacement EN TRAVERS de l'orientation
            // locale, d'autant plus que la structure lineaire est marquee.
            let w = if weight[nb].is_nan() { 0.0 } else { weight[nb] };
            let aniso = if theta_deg[nb].is_nan() || w <= 0.0 {
                1.0
            } else {
                let th = theta_deg[nb].to_radians();
                let ad = undirected_diff(mv_dir[mi], th);
                1.0 + lambda * w * ad.sin().powi(2)
            };

            // Courbure : penaliser le changement de cap.
            let dh = directed_diff(head_ang[h], mv_dir[mi]);
            let turn = mu * dh * dh;

            let step = base * aniso + turn;
            let nh = quantize(mv_dir[mi]);
            let nst = nb * k + nh;
            let nd = cost + step;
            if nd < dist[nst] {
                dist[nst] = nd;
                prev[nst] = state;
                heap.push(HeapItem { cost: nd, state: nst });
            }
        }
    }

    // Cout minimal par cellule (toutes orientations confondues).
    let mut cumcost = vec![f64::NAN; ncell];
    for c in 0..ncell {
        let mut best = f64::INFINITY;
        for h in 0..k {
            let d = dist[c * k + h];
            if d < best {
                best = d;
            }
        }
        if best.is_finite() {
            cumcost[c] = best;
        }
    }

    if target_state == usize::MAX {
        return PathResult { path: Vec::new(), cost: f64::NAN, cumcost };
    }

    // Reconstruction du trace (cellules), source -> cible.
    let total = dist[target_state];
    let mut cells = Vec::new();
    let mut st = target_state;
    while st != usize::MAX {
        let c = st / k;
        if cells.last().map_or(true, |&last| last != c) {
            cells.push(c);
        }
        st = prev[st];
    }
    cells.reverse();
    PathResult { path: cells, cost: total, cumcost }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Grille uniforme : le trace coin a coin ne fait pas d'escalier (voisinage
    // 16) -> sa longueur approche la distance euclidienne, pas la distance L1.
    #[test]
    fn uniform_grid_is_near_straight() {
        let (nr, nc) = (30usize, 30usize);
        let sigma = vec![0.7; nr * nc];
        let theta = vec![f64::NAN; nr * nc];
        let weight = vec![0.0; nr * nc];
        let r = shortest_path(&sigma, &theta, &weight, nr, nc, 1.0, 16, 0.0, 0.0,
            0.05, 0, nr * nc - 1);
        assert!(r.cost.is_finite());
        // Longueur du trace (en cellules) proche de la diagonale (~29*sqrt2).
        let diag = ((nr - 1) as f64) * 2f64.sqrt();
        assert!((r.path.len() as f64) < diag * 1.3);
    }

    // Traverser l'orientation locale coute plus cher que la longer.
    #[test]
    fn anisotropy_penalizes_crossing() {
        let (nr, nc) = (20usize, 20usize);
        let sigma = vec![0.7; nr * nc];
        let theta = vec![0.0; nr * nc]; // orientation E-W partout
        let weight = vec![1.0; nr * nc];
        // Trajet vertical (N-S) = traverse theta ; compare lambda 0 vs 6.
        let src = 0; // coin haut-gauche
        let dst = (nr - 1) * nc; // coin bas-gauche (meme colonne)
        let iso = shortest_path(&sigma, &theta, &weight, nr, nc, 1.0, 16, 0.0, 0.0, 0.05, src, dst);
        let ani = shortest_path(&sigma, &theta, &weight, nr, nc, 1.0, 16, 6.0, 0.0, 0.05, src, dst);
        assert!(ani.cost > iso.cost);
    }

    // Une barriere de NA rend la cible inatteignable -> cout NaN, trace vide.
    #[test]
    fn na_barrier_blocks_path() {
        let (nr, nc) = (10usize, 10usize);
        let mut sigma = vec![0.5; nr * nc];
        for r in 0..nr {
            sigma[r * nc + 5] = f64::NAN; // colonne infranchissable
        }
        let r = shortest_path(&sigma, &vec![f64::NAN; nr * nc], &vec![0.0; nr * nc],
            nr, nc, 1.0, 8, 0.0, 0.0, 0.05, 0, nr * nc - 1);
        assert!(r.cost.is_nan());
        assert!(r.path.is_empty());
    }
}
