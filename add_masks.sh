#!/usr/bin/env bash


#
# Given a grid of images as source for the panorama, this scripts adds
# exclusion masks to the bottom or to the right of every image, except
# for those at the lowest row or rightmost column respectively.
#

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
: ${PTO:="$1"}
: ${GRID:="$2"}
: ${MASK1:="$3"}
: ${MASK2:="$4"}

popd > /dev/null

function usage() {
    cat <<EOF

Usage:    ./add_masks.sh <pto_file> <grid> <mask> [mask]

Sample 1: ./add_masks.sh large_overlap.pto 8x3 r200 > less_overlap.pto
Sample 2: ./add_masks.sh large_overlap.pto 8x3 r200 b200 > even_less_overlap.pto

grid: The layout of the panorama as WidthxHeight where width and height are
      measured in images. A panorama of 6 images can be 1x6, 2x3, 3x2 or 6x1.
mask: rXXXX or bXXXX, where r=right, b=bottom and XXXX is the amount of pixels.

If no grid or mask is given, the amount of images in the panorams is printed.

Given a grid of images as source for the panorama, this scripts adds
exclusion masks to the bottom or to the right of every image, except
for those at the lowest row or rightmost column respectively.
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
}

################################################################################
# FUNCTIONS
################################################################################

calc_stats() {
    IMAGE_COUNT=$(grep "^i " "$PTO" | wc -l)
}

image_count() {
    calc_stats
    echo "Panorama $PTO"
    echo "Images: $IMAGE_COUNT"
}

resolve_grid() {
    calc_stats
    GRID_WIDTH=$(cut -dx -f1 <<< "$GRID")
    GRID_HEIGHT=$(cut -dx -f2 <<< "$GRID")
    if [[ -z "$GRID_WIDTH" ]]; then
        GRID_WIDTH=$(( IMAGE_COUNT / GRID_HEIGHT ))
    fi
    if [[ -z "$GRID_HEIGHT" ]]; then
        GRID_HEIGHT=$(( IMAGE_COUNT / GRID_WIDTH ))
    fi
    local GRID_IMAGES=$(( GRID_WIDTH * GRID_HEIGHT ))
    if [[ "$GRID_IMAGES" -ne "$IMAGE_COUNT" ]]; then
        >&2 echo "Error: The defined grid ${GRID_WIDTH}x${GRID_HEIGHT} requires ${GRID_IMAGES} images, while the panorama contains $IMAGE_COUNT"
        usage 11
    fi
}

resolve_masks() {
    if [[ -z "$MASK1" ]]; then
        >&2 echo "Error: No masks defined"
        usage 10
    fi

    MASK_RIGHT=0
    MASK_BOTTOM=0
    for MASK in $MASK1 $MASK2; do
        if [[ "." == ".$(grep "\(r\|b\)[0-9]*" <<< "$MASK")" ]]; then
            >&2 echo "Error: The mask command '$MASK' does not parse"
            usage 12
        fi
        if [[ "$MASK" == r* ]]; then
            MASK_RIGHT=$(grep -o "[0-9]*" <<< "$MASK")
        else
            MASK_BOTTOM=$(grep -o "[0-9]*" <<< "$MASK")
        fi
    done
}

trim() {
    resolve_grid
    resolve_masks

    #echo "Adding mask_right=$MASK_RIGHT and mask_bottom=$MASK_BOTTOM to the ${GRID_WIDTH}x${GRID_HEIGHT} grid panorama $PTO"
    cat "$PTO"
    echo "#masks"
    local COL=1
    local ROW=1
    while read -r LINE; do
        local IMAGE="$(grep "^i" <<< "$LINE")"
        if [[ -< "$IMAGE" ]]; then
            continue
        fi
        local IMAGE_WIDTH=$(cut -d\  -f1 | tr -dw)
        local IMAGE_HEIGHT=$(cut -d\  -f1 | tr -dh)

        ########### Needs to be aware if it's top-down or left-right first
        COL
        
    done < "$PTO"
    while [[ "$ROW" -le "$GRID_HEIGHT" ]]; do
        if [[ "$COL" -lt "$GRID_WIDTH" && "$MASK_RIGHT" -gt "0" ]]; then
            
    done
    
}

###############################################################################
# CODE
###############################################################################

check_parameters "$@"
if [[ -z "$GRID" ]]; then
    image_count
else
    trim
fi
