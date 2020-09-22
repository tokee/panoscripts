#!/usr/bin/env bash


#
# 
#

# TODO: Sanity check that there will be more than one slice

###############################################################################
# CONFIG
###############################################################################

if [[ -s "pano.conf" ]]; then
    source "pano.conf"     # Local overrides
fi
pushd ${BASH_SOURCE%/*} > /dev/null
if [[ -s "pano.conf" ]]; then
    source "pano.conf"     # General overrides
fi
: ${MERGE:="true"} # If false, the merging of the tiles will be skipped
: ${PTO:="$1"}
: ${OUTPUT:="$2"}
: ${TILE_DIMENSIONS:="$3"}
: ${TILE_DIMENSIONS:="8192x8192"}
popd > /dev/null

function usage() {
    cat <<EOF
Usage:  ./tile_panorama.sh <pto_file> [output_image] [tile_dimensions]
Sample: ./tile_panorama.sh large.pto large.tif 2048x2048

pto_file:        A PTO file from Hugin or similar.
output_image:    The filename for the final large image.
tile_dimensions: The size of the intermediate tiles to generate.
                 This is optional, with the default being 8192x8192.

If no output_image is given, the script will write the size of the crop area
specified for the panorama.

Slices a panorama into smaller tiles and optionally uses vips for merging the
resulting tiles into a single image.
EOF
    exit $1
}

check_parameters() {
    if [[ "-h" == "$PTO" ]]; then
        usage
    fi
    if [[ -z "$PTO" ]]; then
        >&2 echo "Error: No pto_file specified"
        usage 2
    fi
    if [[ ! -s "$PTO" ]]; then
        >&2 echo "Error: Unable to locate $PTO"
        usage 3
    fi
    if [[ -s "$OUTPUT_IMAGE" ]]; then
        >&2 echo "Error: The output_image already exists: $OUTPUT_IMAGE"
        usage 13
    fi
    TILE_WIDTH=$(cut -dx -f1 <<< "$TILE_DIMENSIONS")
    TILE_HEIGHT=$(cut -dx -f2 <<< "$TILE_DIMENSIONS")
}

################################################################################
# FUNCTIONS
################################################################################

# Extracts width, height & crop from the panorama, creating crop parameters if they are missing
get_stats() {
    # p f0 w5097 h4590 v92  E0.638545 R0 S462,4583,264,2024 n"TIFF_m c:LZW r:CROP"
    # width=5097, height=4590
    # crop left=462, right=4583, top=264, bottom=2024
    # Note: crop might not be present
    local P=$(grep -m 1 "^p" "$PTO")
    if [[ -z "$P" ]]; then
        >&2 echo "Error: Unable to locate p-line in $PTO"
        exit 21
    fi

    PTO_WIDTH=$(sed 's/.* w\([0-9]*\) .*/\1/' <<< "$P")
    PTO_HEIGHT=$(sed 's/.* h\([0-9]*\) .*/\1/' <<< "$P")
    PTO_CROP=$(grep -o "S[0-9]\+,[0-9]\+,[0-9]\+,[0-9]\+" <<< "$P" | tr -d S)

    if [[ ! -z "$CROP" ]]; then
        PTO_CROP_LEFT=$(cut -d, -f1 <<< "$PTO_CROP")
        PTO_CROP_RIGHT=$(cut -d, -f2 <<< "$PTO_CROP")
        PTO_CROP_TOP=$(cut -d, -f2 <<< "$PTO_CROP")
        PTO_CROP_BOTTOM=$(cut -d, -f2 <<< "$PTO_CROP")
    else
        PTO_CROP_LEFT="0"
        PTO_CROP_RIGHT="$PTO_WIDTH"
        PTO_CROP_TOP="0"
        PTO_CROP_BOTTOM="$PTO_HEIGHT"
    fi

    PTO_CROP_WIDTH=$((PTO_CROP_RIGHT - PTO_CROP_LEFT))
    PTO_CROP_HEIGHT=$((PTO_CROP_BOTTOM - PTO_CROP_TOP))

    TILES_HORISONTAL=$(( (PTO_CROP_WIDTH*2-1)/TILE_WIDTH ))
    TILES_VERTICAL=$(( (PTO_CROP_HEIGHT*2-1)/TILE_HEIGHT ))
    if [[ "$TILES_HORISONTAL" -eq "0" ]]; then
        TILES_HORISONTAL=1
    fi
    if [[ "$TILES_VERTICAL" -eq "0" ]]; then
        TILES_VERTICAL=1
    fi
}

stats() {
    get_stats
    
    echo "Panorama $PTO"
    echo "Width:  $PTO_WIDTH"
    echo "Height: $PTO_HEIGHT"
    if [[ -z "$PTO_CROP" ]]; then
        echo "Crop:   Not present"
    else
        echo "Crop:   $PTO_CROP (left, right, top, bottom)"
    fi
    echo "Tiles:  ${TILES_HORISONTAL}x${TILES_VERTICAL} (tile dimensions $TILE_DIMENSIONS)"
}

slice() {
    >&2 echo "Error: Slicing not implemented yet"
    exit 41
}

###############################################################################
# CODE
###############################################################################

check_parameters "$@"
if [[ -z "$OUTPUT" ]]; then
    stats
else
    slice
fi
