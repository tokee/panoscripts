#!/usr/bin/env bash

#
# Given a grid of images as source for the panorama, this scripts creates a
# PTO-project, adjusts the image positions to overlap where the grid dictates
# there should be overlap and calls cpfind with the --prealigned option which
# only detects control points for overlapping images.
#
# TODO
# Expand usage()
# Clever handling og missing GRID and DIRECTION by checking for file existence
# Auto-guess ASPECT_FRACTION

# See also
# http://hugin.sourceforge.net/docs/manual/Panorama_scripting_in_a_nutshell.html

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

: ${GRID:="$1"}
: ${DIRECTION:="$2"}
shift
shift
: ${IMAGES:="$@"}
TOTAL_IMAGES="$#"
IMAGE_COUNT="$TOTAL_IMAGES"

: ${LENS:=""}
: ${ASPECT_FRACTION:="3/2"}
: ${OVERLAP_FRACTION:="0.3"}

: ${PTO="profile.pto"}
: ${OUTPUT_PREFIX="grid_panorama"}

popd > /dev/null

function usage() {
    cat <<EOF

Usage:    ./find_grid_control_points.sh <grid> <direction> <images>

Sample 1: ./find_grid_control_points.sh 8x3 td *.jpg

grid:      The layout of the panorama as WidthxHeight where width and height
           are measured in images. A panorama of 6 images can be 1x6, 2x3, 
           3x2 or 6x1.
direction: How the grid of images was taken: td (top-down) first or 
           lr (left-right) first.
EOF
    exit $1
}

check_parameters() {
    if [[ "-h" == "$GRID" ]]; then
        usage
    fi
    if [[ -z "$GRID" ]]; then
        >&2 echo "Error: No arguments specified"
        usage 2
    fi
    if [[ -z "$DIRECTION" ]]; then
        >&2 echo "Error: No direction specified"
        usage 4
    elif [[ "td" != "$DIRECTION" && "lt" != "$DIRECTION" ]]; then
        >&2 echo "Error: The direction must be either 'td' or 'lr' but was '$DIRECTION'"
        usage 5
    fi

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
    
    if [[ -z "$LENS" ]]; then
        if [[ "." == .$(which jhead) ]]; then
            >&2 echo "Error: No LENS provided and jhead is not available for auto-guessing"
            usage 10
        fi
        local FIRST=$(cut -d\  -f1 <<< "$IMAGES")
        LENS=$( jhead "$FIRST" | grep "Focal length" | sed 's/Focal length : \([0-9]\+\).*/\1/' )
        if [[ "$LENS" -gt "0" ]]; then
            echo " - Setting LENS=$LENS from first image $FIRST"
        else
            >&2 echo "Error: Unable to determing LENS (Focal length) from image $FIRST using jhead"
            usage 11
        fi
    fi

    COLUMNS="$GRID_WIDTH"
    ROWS="$GRID_HEIGHT"
    if [[ "$COLUMNS" -eq "-1" && "$ROWS" -eq "-1" ]]; then
        echo "COLUMNS==-1 && ROWS==-1. Setting COLUMNS=$TOTAL_IMAGES (total images) and ROWS=1"
        COLUMNS=$TOTAL_IMAGES
        ROWS=1
    elif [[ "$COLUMNS" -ne "-1" && "$ROWS" -ne "-1" ]]; then
        true
    elif [[ "$COLUMNS" -ne "-1" ]]; then
        ROWS=$((TOTAL_IMAGES / COLUMNS))
        echo "COLUMNS==$COLUMNS %& ROWS==-1. Setting ROWS=$ROWS (total_images $TOTAL_IMAGES / columns $COLUMNS)"
    else
        COLUMNS=$((TOTAL_IMAGES / ROWS))
        echo "COLUMNS==-1 && ROWS==${ROWS}. Setting COLUMNS=$COLUMNS (total_images $TOTAL_IMAGES / rows $ROWS)"
    fi
    if [[ "$TOTAL_IMAGES" -ne $(( COLUMNS * ROWS )) ]]; then
        >&2 echo "Error: The number of specified images $TOTAL_IMAGES is not equal to COLUMNS==$COLUMNS * ROWS==$ROWS ($((COLUMNS*ROWS)))"
        usage 5
    fi
        
    ASPECT_FRACTION="$(echo "scale=4;$ASPECT_FRACTION" | bc)"
    OVERLAP_FRACTION="$(echo "scale=4;$OVERLAP_FRACTION" | bc)"

}


################################################################################
# FUNCTIONS
################################################################################


image_count() {
    echo "Images: $IMAGE_COUNT"
}

resolve_grid() {
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

    if [[ ! -z "$PTO_CROP" ]]; then
        PTO_CROP_LEFT=$(cut -d, -f1 <<< "$PTO_CROP")
        PTO_CROP_RIGHT=$(cut -d, -f2 <<< "$PTO_CROP")
        PTO_CROP_TOP=$(cut -d, -f3 <<< "$PTO_CROP")
        PTO_CROP_BOTTOM=$(cut -d, -f4 <<< "$PTO_CROP")
    else
        PTO_CROP_LEFT="0"
        PTO_CROP_RIGHT="$PTO_WIDTH"
        PTO_CROP_TOP="0"
        PTO_CROP_BOTTOM="$PTO_HEIGHT"
    fi

    PTO_CROP_WIDTH=$((PTO_CROP_RIGHT - PTO_CROP_LEFT))
    PTO_CROP_HEIGHT=$((PTO_CROP_BOTTOM - PTO_CROP_TOP))
}

# Adapted from https://groups.google.com/d/msg/hugin-ptx/ImcaDTH7KMY/GcHI-wNnFAAJ

# --------------------------------------------------------------- 
# huginpan.rex --- run Hugin with layout hints                    
# --------------------------------------------------------------- 
#                                                                 
# Call as:                                                        
#                                                                 
#   huginpan pattern lens columns rows order                      
#                                                                 
# where:                                                          
#                                                                 
#   pattern -- source files pattern (e.g., P*.jpg)                
#   lens    -- lens length (mm, 35mm equivalent)                  
#   columns -- number of images in X dimension                    
#   rows    -- ditto in Y                                         
#   order   -- mapping of image sequence to rectangle             
#                                                                 
# pattern, lens, and columns are required                         
# rows default=1, order default=0                                 
#                                                                 
# order is:                                                       
#                                                                 
#   0 -- rows, left->right, top->bottom (start top-left)          
#   1 -- columns, top->bottom, left->right (start top-left)       
#                                                                 
# Before using this, it is suggested that you copy the source     
# files to their own subdirectory, then run this command with     
# that as the current directory.                                  
#                                                                 
# Return codes from pto_ commands are not documented, so ignored. 
# --------------------------------------------------------------- 
#-- 2015.11.04 mfc initial vesrion
#-- 2015.11.06 add lens length as parameter
#-- 2020.01.20 Toke Eskildsen: Ported to bash
#-- 2020.10.14 Toke Eskildsen: Further modifications to match other scripts


calc_setup() {
    echo " - Calculating setup from LENS=$LENS and $TOTAL_IMAGES images ordered $DIRECTION"
    #-- calculate total degrees vertical and horizontal
    # h=2*arctan((27*aspect) / (2*lens)) -- sensor horizontal degrees
    # v=2*arctan(27 / (2*lens))          -- ditto vertical
    #                 -- swap if portrait
    FUDGE_H=31.5 # Why is fudging needed? The formula seems off
    FUDGE_V=32.5
    H="$(echo "scale=4;$FUDGE_H*2*a((27*$ASPECT_FRACTION) / (2*$LENS))" | bc -l)" # sensor horizontal degrees
    V="$(echo "scale=4;$FUDGE_V*2*a(27 / (2*$LENS))" | bc -l)" # sensor vertical degrees
    #-- now have degrees for h and v for one image
    echo "Image degrees: ${H}x${V}"

    #totalh=h*(columns - overlap*(columns-1))
    #totalv=v*(rows    - overlap*(rows-1))
    #say 'Total degrees:' totalh 'x' totalv
    TOTAL_H="$(echo "scale=4;$H*($COLUMNS - $OVERLAP_FRACTION*($COLUMNS-1))" | bc -l)"
    TOTAL_V="$(echo "scale=4;$V*($ROWS - $OVERLAP_FRACTION*($ROWS-1))" | bc -l)"
    echo "Total degrees: ${TOTAL_H}x${TOTAL_V}"

    #-- set up the pitch and yaw formulae
    #-- absolute origin non-critical
    #eh=h*(1-overlap)                   -- effective horizontal degrees
    #ev=v*(1-overlap)                   -- effective vertical degrees
    #offseth=totalh/2 - h/2             -- offset for 0,0 image
    #offsetv=totalv/2 - v/2             -- ..
    EH="$(echo "scale=4;$H*(1-$OVERLAP_FRACTION)" | bc -l)"
    EV="$(echo "scale=4;$V*(1-$OVERLAP_FRACTION)" | bc -l)"
    OFFSET_H="$(echo "scale=4;$TOTAL_H/2 - $H/2" | bc -l)"
    OFFSET_V="$(echo "scale=4;$TOTAL_V/2 - $V/2" | bc -l)"
    echo "Effective single image degrees: horizontal=$EH vertical=$EV"
    echo "Offset for the 0,0 image: horizontal=$OFFSET_H vertical=$OFFSET_V"
    
    if [[ "$DIRECTION" == "lr" ]]; then
        #when order=0 then do             -- TL, by row, left->right
        #yaw='(i%'columns')*'eh'-'offseth
        #pitch=offsetv'-(floor(i/'columns')*'ev')'
        YAW="$(echo "scale=4;($TOTAL_IMAGES % $COLUMNS)*$EH-$OFFSET_H" | bc -l)"
        # TODO: Is the ROWS*COLUMNS=TOTAL_IMAGES too harsh? This seems to be whet the removed floor is for
        PITCH="$(echo "scale=4;OFFSET_V-($TOTAL_IMAGES / $COLUMNS)*$EV" | bc -l)"
    elif [[ "$DIRECTION" == "td" ]]; then
        #when order=1 then do             -- TL, by column, top->bottom
        #yaw='(floor(i/'rows')*'eh')-'offseth
        #pitch=offsetv'-(i%'rows')*'ev
        # TODO: Is the ROWS*COLUMNS=TOTAL_IMAGES too harsh? This seems to be whet the removed floor is for
        YAW="$(echo "scale=4;(($TOTAL_IMAGES / $ROWS)*$EH)-$OFFSET_H" | bc -l)"
        PITCH="$(echo "scale=4;$OFFSET_V-($TOTAL_IMAGES % $ROWS)*$EV" | bc -l)"
    fi
    echo "yaw=$YAW pitch=$PITCH"
}

generate_profile() {
    echo " - Generating and adjusting Hugin project file '$PTO'"
    if [[ -s "$PTO" ]]; then
        rm "$PTO"
    fi

    #-- create the Hugin project file
    #'pto_gen -o' profile pattern
    pto_gen -o "$PTO" $IMAGES
    cp "$PTO" "h0.pto"
    #-- update/set rough geometricals
    #'pto_var "--set=y='yaw',p='pitch'" --output='profile profile
    # TODO: Superceeded by the loop below?
    pto_var "--set=y=${YAW},p=${PITCH}" --output="$PTO" "$PTO" > /dev/null
    cp "$PTO" "h1-var.pto"

    COL=0
    ROW=0
    Y=$YAW   # Horizontal
    P=$PITCH # Vertical
    while [[ $((COL*ROW)) -lt "$TOTAL_IMAGES" ]]; do
        IMG=$((COL*ROWS+ROW))
        Y=$(echo "scale=4;$YAW+($COL*$EH)" | bc -l)
        P=$(echo "scale=4;$PITCH-($ROW*$EV)" | bc -l)
        pto_var "--set=y${IMG}=${Y},p${IMG}=${P}" --output="$PTO" "$PTO" > /dev/null
        
        if [[ "$DIRECTION" == "lr" ]]; then # left->right
            COL=$((COL+1))
            if [[ $COL -eq $COLS ]]; then
                COL=1
                ROW=$((ROW+1))
            fi
        else # top->bottom
            ROW=$((ROW+1))
            if [[ $ROW -eq $ROWS ]]; then
                ROW=0
                COL=$((COL+1))
            fi
        fi
    done
    cp "$PTO" "h1-var-adjust.pto"
}

process_profile() {
    echo " - Finding control points using cpfind for '$PTO'"
    # -- find control points
    #'cpfind --output='profile '--prealigned' profile
    cpfind --output="$PTO" --prealigned "$PTO"
    cp "$PTO" "h2-cpfind.pto"

    # TODO: Check that points were added
    
    echo " - Adding missing control points using geocpset for '$PTO'"
    #-- add missing control points using geometry
    geocpset --output="$PTO" "$PTO"
    cp "$PTO" "h3-geocpset.pto"

    #echo " - Finding vertical lines using linefind for '$PTO'"
    
    echo " - Performing alignment autooptimizer for '$PTO'"
    autooptimiser -a -l -s -o "$PTO" "$PTO"
    #    hugin_executor --assistant profile.pto
    cp "$PTO" "h4-autooptimizer.pto"

    echo " - Performing straighten, auto crop and similar polishing for '$PTO'"
    pano_modify -o "$PTO" --center --straighten --canvas=AUTO --crop=AUTO "$PTO"
    cp "$PTO" "h5-center-crop-straighten.pto"

    # TODO: Consider linefind

    get_stats
    cat <<EOF
Finished pre-processing. Please use Hugin to inspect
$PTO

Consider optimizing photometric parameters if the exposure was not fixed.

The finished panorama will be ${PTO_CROP_WIDTH}x${PTO_CROP_HEIGHT} pixels.
Render the panorama from Hugin or call
hugin_executor --stitching $PTO --prefix=\"$OUTPUT_PREFIX\"
or use tiled rendering if the image is too large for the machine
./tile_panorama.sh $PTO ${OUTPUT_PREFIX}.tif
EOF
    
#    echo "Performing stitching using hugin_Executor for '$PTO'"
#    hugin_executor --stitching profile.pto --prefix="$OUTPUT_PREFIX"
}


###############################################################################
# CODE
###############################################################################

check_parameters "$@"
echo "Processing $TOTAL_IMAGES in grid ${GRID_WIDTH}x${GRID_HEIGHT} ordered $DIRECTION"
calc_setup
generate_profile
process_profile
