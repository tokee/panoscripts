#!/usr/bin/env bash


#
# Slices a panorama into smaller tiles at PTO-level, renders the individual tiles
# using hugin_executor and uses vips (https://github.com/libvips/libvips) for
# merging the resulting tiles into a single image.
#
# Use this when direct rendering of a large panorama is not possible using Hugin/enblend
# due to memory restraints.
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
: ${MERGE:="true"} # If false, the merging of the tiles will be skipped
: ${PTO:="$1"}
: ${OUTPUT_IMAGE:="$2"}
: ${WORK_FOLDER:="${OUTPUT_IMAGE%.*}"}
: ${TILE_DIMENSIONS:="$3"}
: ${TILE_DIMENSIONS:="16384x16384"}
: ${CLEANUP:="false"} # If true, intermediate files will be deleted after full processing
popd > /dev/null

function usage() {
    cat <<EOF

Usage:  ./tile_panorama.sh <pto_file> [output_image] [tile_dimensions]
Sample: ./tile_panorama.sh large.pto large.tif 2048x2048

pto_file:        A PTO file from Hugin or similar.
output_image:    The filename for the final large image.
tile_dimensions: The size of the intermediate tiles to generate.
                 This is optional, with the default being 16384x16384.

If no output_image is given, the script will write the size of the crop area
specified for the panorama.

Slices a panorama into smaller tiles and optionally uses vips for merging the
resulting tiles into a single image.
EOF
    exit $1
}

check_parameters() {
    for REQUIRED in hugin_executor convert; do
        if [[ -z $(which $REQUIRED) ]]; then
            >&2 echo "Error: The tool $REQUIRED must be available. Please install it"
            exit 61
        fi
    done
    if [[ -z $(which vips) ]]; then
        >&2 echo "Error: The tool vips must be available. Please install it (try 'sudo apt-get install libvips-tools')"
        exit 61
    fi
        
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
    mkdir -p "$WORK_FOLDER"
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

    TILES_HORISONTAL=$(( (PTO_CROP_WIDTH+TILE_WIDTH-1)/TILE_WIDTH ))
    TILES_VERTICAL=$(( (PTO_CROP_HEIGHT+TILE_HEIGHT-1)/TILE_HEIGHT ))
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
        echo "Crop:   ${PTO_CROP_LEFT},${PTO_CROP_RIGHT},${PTO_CROP_TOP},${PTO_CROP_BOTTOM} (left, right, top, bottom)"
    fi
    echo "Tiles:  ${TILES_HORISONTAL}x${TILES_VERTICAL} (tile dimensions $TILE_DIMENSIONS)"
}

make_tile() {
    local CROP="$1"
    local DEST="$2"
    sed "s/^\(p .*R[0-9]* \)[^ ]*\( \?n.*\)/\1S${CROP}\2/" "$PTO" > slice.pto
    hugin_executor --stitching --prefix ${WORK_FOLDER}/slice.last.tif slice.pto &>> ${WORK_FOLDER}/slice.log
    convert ${WORK_FOLDER}/slice.last.tif +repage "${DEST}" &>> ${WORK_FOLDER}/slice.log # Remove fancy TIFF viewports
    if [[ ! -s "${DEST}" ]]; then
        >&2 echo "Error: Slicing did not produce ${DEST} as expected. Please see ${WORK_FOLDER}/slice.log for errors"
        exit 51
    fi
}

slice() {
    echo "Starting processing at $(date +%Y%m%d-%H%M%S)"
    stats
    if [[ "$TILES_HORISONTAL" -eq "1" && "$TILES_VERTICAL" -eq "1" ]]; then
        echo "Skipping processing as only a single tile would be output"
        exit
    fi
    local MAX_SLICES=$(( TILES_VERTICAL * TILES_HORISONTAL ))
    echo "Creating $MAX_SLICES slices..."
    local X=0
    local Y=0
    local SLICE=1
    local IMAGES=""
    while [[ "$Y" -lt "$TILES_VERTICAL" ]]; do
        local CROP_LEFT=$(( PTO_CROP_LEFT + X*TILE_WIDTH ))
        local CROP_RIGHT=$(( CROP_LEFT + TILE_WIDTH ))
        if [[ "$CROP_RIGHT" -gt "$PTO_CROP_RIGHT" ]]; then
            local CROP_RIGHT="$PTO_CROP_RIGHT"
        fi
        local CROP_TOP=$(( PTO_CROP_TOP + Y*TILE_HEIGHT ))
        local CROP_BOTTOM=$(( CROP_TOP + TILE_HEIGHT ))
        if [[ "$CROP_BOTTOM" -gt "$PTO_CROP_BOTTOM" ]]; then
            local CROP_BOTTOM="$PTO_CROP_BOTTOM"
        fi
        local TILE="$((X+1))x$((Y+1))"
        local DEST="${WORK_FOLDER}/${TILE}.tif"
        local CROP="${CROP_LEFT},${CROP_RIGHT},${CROP_TOP},${CROP_BOTTOM}"
        if [[ "." == ".$IMAGES" ]]; then
            local IMAGES="$DEST"
        else
            local IMAGES="$IMAGES $DEST"
        fi
        
        if [[ -s "${DEST}" ]]; then
            echo "${SLICE}/${MAX_SLICES} Skipping tile $TILE as ${DEST} already exists"
        else
            echo "${SLICE}/${MAX_SLICES} Generating and executing PTO for tile $TILE at crop ${CROP} with destination ${DEST}"
            make_tile "$CROP" "$DEST"
        fi
        
        local X=$((X + 1))
        if [[ "$X" -eq "$TILES_HORISONTAL" ]]; then
            local X=0
            local Y=$(( Y + 1 ))
        fi
        local SLICE=$(( SLICE + 1 ))
    done
    
    if [[ -s ${WORK_FOLDER}/uncropped.last.tif ]]; then
        echo "Skipping merging as ${WORK_FOLDER}/uncropped.last.tif already exists"
    else
        echo "Calling merge with"
        echo "> vips arrayjoin \"$IMAGES\" t.tif --across 2"
        vips arrayjoin "$IMAGES" ${WORK_FOLDER}/uncropped.last.tif --across 2
    fi

    if [[ -s "$OUTPUT_IMAGE" ]]; then
        echo "Skipping final trimming to ${PTO_CROP_WIDTH}x${PTO_CROP_HEIGHT} as $OUTPUT_IMAGE already exists"
    else        
        echo "Trimming image to dimensions ${PTO_CROP_WIDTH}x${PTO_CROP_HEIGHT} and saving final image with command"
        echo "> vips crop ${WORK_FOLDER}/uncropped.last.tif \"$OUTPUT_IMAGE\" 0 0 ${PTO_CROP_WIDTH} ${PTO_CROP_HEIGHT}"
        vips crop ${WORK_FOLDER}/uncropped.last.tif "$OUTPUT_IMAGE" 0 0 ${PTO_CROP_WIDTH} ${PTO_CROP_HEIGHT}
    fi
    if [[ ! -s "$OUTPUT_IMAGE" ]]; then
        >&2 echo "Error: Output image $OUTPUT_IMAGE not produced"
        exit 62
    fi

    echo ""
    echo "Finished producing $OUTPUT_IMAGE at $(date +%Y%m%d-%H%M%S)"
    if [[ "$CLEANUP" == "true" ]]; then
        rm -r "${WORK_FOLDER}"
    else
        echo "The work folder ${WORK_FOLDER} can be safely deleted"
    fi
}

###############################################################################
# CODE
###############################################################################

check_parameters "$@"
if [[ -z "$OUTPUT_IMAGE" ]]; then
    stats
else
    slice
fi
