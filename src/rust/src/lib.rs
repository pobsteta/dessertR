use extendr_api::prelude::*;

mod rvt;

/// Sky-view factor and openness (RVT micro-relief channels).
///
/// Ports RVT's `sky_view_factor_compute` (Relief Visualization Toolbox, ZRC SAZU
/// / Univ. Ljubljana, Apache 2.0): a `roll`+`fmax` horizon sweep over
/// `num_directions` azimuths and search radii, from which the **sky-view factor**
/// (hemisphere) and **openness** (sphere, degrees) fall out of the same pass.
/// These channels light up the platform, embankments and ditches of a forest
/// track under canopy -- inputs for the geomorphic conductivity channel. No GIS
/// in the crate: R passes the flat elevation grid and re-attaches the channels to
/// the DEM. **Negative openness** is obtained by calling this on the negated DEM.
///
/// Kernel vendored from the `foretaccess` package (same author), itself validated
/// pixel-to-pixel against the RVT Python oracle.
///
/// @param height Elevation values (row-major, `NA`/`NaN` as NoData).
/// @param nr Number of raster rows.
/// @param nc Number of raster columns.
/// @param resolution Cell size (m); corrects the vertical horizon angle.
/// @param radius_max Maximal search radius in **pixels**.
/// @param radius_min Minimal search radius in **pixels** (noise reduction).
/// @param num_directions Number of azimuth directions swept.
/// @param compute_svf Whether to compute the sky-view factor.
/// @param compute_opns Whether to compute the openness (degrees).
/// @return A list with `svf` (0..1) and `opns` (degrees), each row-major with
///   `NaN` where the input elevation is `NaN`; an unrequested channel is empty.
/// @keywords internal
#[extendr]
#[allow(clippy::too_many_arguments)]
fn rvt_svf_opns(
    height: Vec<f64>,
    nr: i32,
    nc: i32,
    resolution: f64,
    radius_max: f64,
    radius_min: f64,
    num_directions: i32,
    compute_svf: bool,
    compute_opns: bool,
) -> List {
    let out = rvt::svf_opns(
        &height,
        nr as usize,
        nc as usize,
        resolution,
        radius_max,
        radius_min,
        num_directions.max(1) as usize,
        compute_svf,
        compute_opns,
    );
    list!(
        svf = out.svf.unwrap_or_default(),
        opns = out.opns.unwrap_or_default()
    )
}

// Macro to generate exports.
// This ensures exported functions are registered with R.
// See corresponding C code in `entrypoint.c`.
extendr_module! {
    mod dessert_r;
    fn rvt_svf_opns;
}
