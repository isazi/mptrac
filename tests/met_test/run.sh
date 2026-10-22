#! /bin/bash

# Set environment...
export LD_LIBRARY_PATH=../../libs/build/lib:$LD_LIBRARY_PATH
export OMP_NUM_THREADS=4

# Setup...
trac=../../src

# Create directories...
rm -rf data && mkdir -p data

# Loop over meteo files...
for metfile in ../data/ei_2011_06_05_00.nc ../data/era5ml_2011_06_05_00.nc ; do

    # Set variables...
    base=$(basename $metfile .nc)
    metparam=$([ "$base" = "era5ml_2011_06_05_00" ] && echo "MET_VERT_COORD 1 MET_PRESS_LEVEL_DEF 6")
    
    # Sampling tools...
    $trac/met_lapse - data/lapse_${base}.tab $metfile $metparam
    
    $trac/met_map - data/map_${base}.tab $metfile $metparam \
		  MAP_LON0 -180 MAP_LON1 180 MAP_DLON 6 \
		  MAP_LAT0 -90 MAP_LAT1 90 MAP_DLAT 4 \
		  MAP_THETA 380 TROPO 3 \
		  OH_CHEM_BETA 0.6
    
    $trac/met_prof - data/prof_${base}.tab $metfile $metparam \
		   PROF_Z0 0 PROF_Z1 60 PROF_DZ 0.1 \
		   PROF_LON0 20 PROF_LON1 30 PROF_DLON 1 \
		   PROF_LAT0 40 PROF_LAT1 50 PROD_DLAT 1 \
		   TROPO 4
    
    $trac/met_zm - data/zm_${base}.tab $metfile $metparam \
		 ZM_Z0 0 ZM_Z1 60 ZM_DZ 1 \
		 ZM_LON0 -180 ZM_LON1 180 ZM_DLON 1 \
		 ZM_LAT0 -90 ZM_LAT1 90 ZM_DLAT 3 \
		 TROPO 5
    
    $trac/met_spec - data/spec_${base}.tab $metfile $metparam \
		   SPEC_WAVEMAX 3
    
done

# Calculate subgrid-scale variability...
$trac/met_subgrid - data/subgrid_ei_2011_06_05_00.tab \
		  ../data/ei_2011_06_05_00.nc \
		  ../data/ei_2011_06_06_00.nc

# Create init file for sampling...
tm=$($trac/time2jsec 2011 6 5 12 0 0 0)
$trac/atm_init - data/atm_init.tab \
	       INIT_T0 "$tm" INIT_T1 "$tm" INIT_UT 86400 \
	       INIT_Z0 30 INIT_Z1 30 INIT_UZ 60 \
	       INIT_ULON 360 INIT_ULAT 180 \
	       INIT_EVENLY 1 INIT_REP 3000

# Sample meteo data...
$trac/met_sample - data/sample_ei_2011_06_05_00.tab data/atm_init.tab \
		 METBASE ../data/ei DT_MET 86400.0

# Compare files...
echo -e "\nCompare results..."
error=0
for f in $(ls data.ref/*.tab) ; do
    # Rounding differences between compilers and platforms can flip the last
    # printed digit of a few values, so numbers are compared with a relative
    # tolerance instead of bit-for-bit.
    if awk -v tol=1e-4 -v atol=1e-9 -v spec="$([[ $(basename "$f") == spec_* ]] && echo 1 || echo 0)" '
        NR == FNR { if (!/^#/ && NF > 0) ref[++n] = $0; next }
        /^#/ || NF == 0 { next }
        { if (++m > n) { bad = 1; exit }
          nf = split(ref[m], r)
          if (nf != NF) { bad = 1; exit }
          for (i = 1; i <= NF; i++) {
              # nan is equal to nan, regardless of its sign (platform
              # dependent), but not to a number.
              rn = (r[i] ~ /nan/); an = ($i ~ /nan/)
              if (rn || an) { if (rn && an) continue; bad = 1; exit }
              if ($i "" == r[i] "") continue
              d = $i - r[i]; if (d < 0) d = -d
              a = $i < 0 ? -$i : $i; b = r[i] < 0 ? -r[i] : r[i]
              if (b > a) a = b
              # Absolute floor for values that are numerically zero.
              if (d <= atol) continue
              # The phase of a spectral component with ~zero amplitude is
              # arbitrary (e.g., 0 vs. 180 deg).
              if (spec && i > 7 && (i - 1) % 3 == 0) {
                  p = $(i-1) < 0 ? -$(i-1) : $(i-1)
                  q = r[i-1] < 0 ? -r[i-1] : r[i-1]
                  if (p < atol && q < atol) continue
              }
              if (d > tol * a) { bad = 1; exit }
          } }
        END { exit (bad || m != n) }' "$f" data/"$(basename "$f")" ; then
	echo "Files data/$(basename "$f") and $f are equal within tolerance"
    else
	echo "Files data/$(basename "$f") and $f differ"
	error=1
    fi
done
exit $error
