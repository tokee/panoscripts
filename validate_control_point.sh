#!/usr/bin/env bash


#
# Given a grid of images as source for the panorama, this scripts
# validates the control points by checking that
# 
# * Images are connected to their neighbours
# * Images are not connected to other images that they should not be connected to
# * Horizontal and vertical lines does not differ from the mean by more than X
#   percent
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
: ${FIXED_PTO:="${PTO%.*}_fixedcp.pto"}
#: ${REMOVE_FAULTY_CONNECTIONS:="false"}
popd > /dev/null

function usage() {
    cat <<EOF

Usage:    ./validate_control_points.sh <pto_file> <grid> <direction>

Sample 1: ./validate_control_points.sh pano.pto 8x3 td

grid:      The layout of the panorama as WidthxHeight where width and height
           are measured in images. A panorama of 6 images can be 1x6, 2x3, 
           3x2 or 6x1.
direction: How the grid of images was taken: td (top-down) first or 
           lr (left-right) first.

If no grid is given, the amount of images in the panorams is printed.

Given a grid of images as source for the panorama, this scripts
validates the control points by checking that

* Images are connected to at least one neighbour
* Images are not connected to other images that they should not be connected to

To be implemented in future versions:

* Horizontal and vertical lines does not differ from the mean by more than X percent

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

validate_check_parameters() {
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
    if [[ "$DIRECTION" == "lr" ]]; then
        >&2 echo "Error:Not implemented yet (sorry)"
        exit 71
    fi
    if [[ -z "$DIRECTION" ]]; then
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

# Extracts control points from the PTO, returning only image indices
# Output: from to (both ways represented)
extract_links() {
    local T=$(mktemp)
    local T2=$(mktemp)
    grep -o "^c n[0-9]* N[0-9]*" "$PTO" | sed 's/c n\([0-9]*\) N\([0-9]*\)/\1 \2/' | sort -n | uniq > "$T"
    cp "$T" "$T2"
    sed 's/\([0-9]*\) \([0-9]*\)/\2 \1/' < "$T" >> "$T2"
    sort -n < "$T2" | uniq > "$T"
    rm "$T2"
    echo "$T"
}

validate() {
    local LINKS=$(extract_links)
    echo "Calculating IDs for connected images that should not be connected..."

    local UNCONNECTED=""
    local REMOVABLES=""
    local COL=1
    local ROW=1
    local ID=0
    local ANY=false
    while read -r IMAGE; do

        # Calculate all valid connections
        local VALIDS="$ID"
        if [[ "$COL" -gt "0" && "$ROW" -gt 0 ]]; then # Up left
            VALIDS="$VALIDS\|$((ID - 1 - GRID_HEIGHT))"
        fi
        if [[ "$ROW" -gt "0" ]]; then # Up
            VALIDS="$VALIDS\|$((ID - 1))"
        fi
        if [[ "$COL" -lt "$GRID_WIDTH" && "$ROW" -gt "0" ]]; then # Up right
            VALIDS="$VALIDS\|$((ID - 1 + GRID_HEIGHT))"
        fi
        if [[ "$COL" -gt "0" ]]; then # Left
            VALIDS="$VALIDS\|$((ID - GRID_HEIGHT))"
        fi
        if [[ "$COL" -lt "$GRID_WIDTH" ]]; then # Right
            VALIDS="$VALIDS\|$((ID + GRID_HEIGHT))"
        fi
        if [[ "$COL" -gt "0" && "$ROW" -lt "$GRID_HEIGHT" ]]; then # Down left
            VALIDS="$VALIDS\|$((ID + 1 - GRID_HEIGHT))"
        fi
        if [[ "$ROW" -lt "$GRID_HEIGHT" ]]; then # Down
            VALIDS="$VALIDS\|$((ID + 1))"
        fi
        if [[ "$COL" -lt "$GRID_WIDTH" && "$ROW" -lt "$GRID_HEIGHT" ]]; then # Down right
            VALIDS="$VALIDS\|$((ID + 1 + GRID_HEIGHT))"
        fi

        # Get the real connections
        local END_POINTS=$(grep "^$ID " "$LINKS" | cut -d\  -f2)
        local FAULTY=$(grep -v "$VALIDS" <<< "$END_POINTS" | tr '\n' ' ')
        local OKAY=$(grep "$VALIDS" <<< "$END_POINTS" | tr '\n' ' ')

        if [[ ! -z "$FAULTY" && ! " " == "$FAULTY" ]]; then
            ANY=true
            for F in $FAULTY; do
                if [[ ! -z "$REMOVABLES" ]]; then
                    REMOVABLES="$REMOVABLES\|"
                fi
                REMOVABLES="${REMOVABLES}c n$ID N$F \|"
                REMOVABLES="${REMOVABLES}c n$F N$ID "
            done
            echo "$ID: $FAULTY"
        fi
        if [[ -z "$OKAY" ]]; then
            if [[ ! -z "$UNCONNECTED" ]]; then
                UNCONNECTED="${UNCONNECTED}, "
            fi
            UNCONNECTED="${UNCONNECTED}$ID"
        fi
        

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
        local ID=$(( ID + 1 ))
    done <<< $(grep "^i" < "$PTO")
    if [[ "false" == "$ANY" ]]; then
        echo "No problematic image connections located"
    else
        grep -v "$REMOVABLES" "$PTO" > "$FIXED_PTO"
        echo "The control points for the wrongly connected images has been removed and"
        echo "the result has been stored as ${FIXED_PTO}"
    fi
    if [[ -z "$UNCONNECTED" ]]; then
        echo "There were no unconnected images"
    else
        echo "Warning: There were unconnected images with IDs: $UNCONNECTED"
        echo "These must be connected to other images for the panorama to render properly"
    fi
    rm "$LINKS"
}

###############################################################################
# CODE
###############################################################################

check_parameters "$@"
if [[ -z "$GRID" ]]; then
    image_count
else
    resolve_grid
    validate_check_parameters
    validate
    #cat $(extract_links)
fi
