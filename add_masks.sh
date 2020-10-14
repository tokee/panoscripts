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
: ${DIRECTION:="$3"}
: ${MASK1:="$4"}
: ${MASK2:="$5"}
: ${REMOVE_EXISTING_MASKS:="false"}

popd > /dev/null

function usage() {
    cat <<EOF

Usage:    ./add_masks.sh <pto_file> <grid> <direction> <mask> [mask]

Sample 1: ./add_masks.sh large_overlap.pto 8x3 td r200 > less_overlap.pto
Sample 2: ./add_masks.sh another.pto 12x5 lr r200 b200 > lesser_overlap.pto

grid:      The layout of the panorama as WidthxHeight where width and height
           are measured in images. A panorama of 6 images can be 1x6, 2x3, 
           3x2 or 6x1.
direction: How the grid of images was taken: td (top-down) first or 
           lr (left-right) first.
mask:      rXXXX or bXXXX, where r=right, b=bottom and XXXX is the amount of
           pixels.

If no grid, direction or mask is given, the amount of images in the panorams is
printed.

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

trim_check_parameters() {
    if [[ -z "$GRID" ]]; then
        >&2 echo "Error: No grid specified"
        usage 4
    fi
    if [[ -z "$DIRECTION" ]]; then
        >&2 echo "Error: No direction specified"
        usage 4
    elif [[ "td" != "$DIRECTION" && "lt" != "$DIRECTION" ]]; then
        >&2 echo "Error: The direction must be either 'td' or 'lr' but was '$DIRECTION'"
        usage 5
    fi
    if [[ -z "$MASK1" ]]; then
        >&2 echo "Error: No mask specified"
        usage 7
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
    if [[ "true" == "$REMOVE_EXISTING_MASKS" ]]; then
        cat "$PTO" | grep -v "^#masks" | grep -v "^k"
    else
        cat "$PTO"
    fi
    echo "#masks"
    local COL=1
    local ROW=1
    local IMAGE_ID=0
    while read -r IMAGE; do
        local IMAGE_WIDTH=$(cut -d\  -f2 <<< "$IMAGE" | tr -d w)
        local IMAGE_HEIGHT=$(cut -d\  -f3 <<< "$IMAGE" | tr -d h)

        if [[ "$MASK_RIGHT" -gt 0 && "$COL" -ne "$GRID_WIDTH" ]]; then
            #echo "At ${COL}x${ROW} make right mask $MASK_RIGHT"
            echo "k i${IMAGE_ID} t0 p\"$((IMAGE_WIDTH-MASK_RIGHT)) 0 $IMAGE_WIDTH 0 $IMAGE_WIDTH $IMAGE_HEIGHT $((IMAGE_WIDTH-MASK_RIGHT)) $IMAGE_HEIGHT\"" 
        fi
        if [[ "$MASK_BOTTOM" -gt 0 && "$ROW" -ne "$GRID_HEIGHT" ]]; then
            #echo "At ${COL}x${ROW} make bottom mask $MASK_BOTTOM"
            echo "k i${IMAGE_ID} t0 p\"0 $((IMAGE_HEIGHT-MASK_BOTTOM)) $IMAGE_WIDTH $((IMAGE_HEIGHT-MASK_BOTTOM)) $IMAGE_WIDTH $IMAGE_HEIGHT 0 $IMAGE_HEIGHT\"" 
        fi
        
        # cut is not on edge
        
        if [[ "td" == "$DIRECTION" ]]; then
            ROW=$(( ROW + 1 ))
            if [[ "$ROW" -gt "$GRID_HEIGHT" ]]; then
                ROW=1
                COL=$(( COL + 1 ))
            fi
        else # lr
            COL=$(( COL + 1 ))
            if [[ "$COL" -gt "$GRID_WIDTH" ]]; then
                COL=1
                ROW=$(( ROW + 1 ))
            fi
        fi
        local IMAGE_ID=$(( IMAGE_ID + 1 ))
    done <<< $(grep "^i" < "$PTO")
}

###############################################################################
# CODE
###############################################################################

check_parameters "$@"
if [[ -z "$GRID" ]]; then
    image_count
else
    trim_check_parameters "$@"
    trim
fi
