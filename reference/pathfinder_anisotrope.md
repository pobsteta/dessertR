# Anisotropic least-cost path with heading state and curvature penalty.

Runs a Dijkstra over a (cell, heading) state space on the geomorphic
conductivity, with a 16-neighbourhood to curb Dijkstra's metrication
bias, a cross-orientation anisotropy penalty (a road has a direction),
and a curvature penalty on heading changes (BRIEF section 3.5). No GIS
in the crate: R passes the flat grids and cell indices, and re-attaches
the trace.

## Usage

``` r
pathfinder_anisotrope(
  sigma,
  theta,
  weight,
  nr,
  nc,
  resolution,
  k,
  lambda,
  mu,
  sigma_min,
  src,
  dst
)
```

## Arguments

- sigma:

  Geomorphic conductivity, row-major, `NA` for impassable.

- theta:

  Local line orientation (degrees), row-major; `NA` -\> isotropic.

- weight:

  Anisotropy strength per cell (e.g. vesselness, 0..1), row-major.

- nr, nc:

  Raster rows and columns.

- resolution:

  Cell size (m).

- k:

  Number of discrete headings.

- lambda:

  Anisotropy weight (cross-orientation penalty).

- mu:

  Curvature weight (heading-change penalty).

- sigma_min:

  Conductivity floor (avoids infinite resistance).

- src, dst:

  Source and target cell indices (0-based, row-major).

## Value

A list with `path` (1-based cell indices, source to target), `cost`
(total, `NA` if unreachable) and `cumcost` (min cost-to-source per
cell).
