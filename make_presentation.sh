#!/usr/bin/env bash


#
# Makes a simple presentation webpage with the given image, using OpenSeadragon
# for display.
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
: ${IMAGE:="$1"}
: ${OUTPUT_FOLDER:="$2"}
: ${OUTPUT_FOLDER:="${IMAGE%.*}"}
: ${OVERWRITE:="false"}

: ${JPEG_QUALITY:="85"}
: ${TILE_SIZE:="256"}
: ${TILE_OVERLAP:="0"}

: ${CACHE:="$(pwd)/cache"}
: ${TEMPLATE:="$(pwd)/osd_template.html"}
: ${MAX_ZOOM_PIXEL_RATIO:="2.0"}
   
: ${TITLE:="${IMAGE%.*}"}
: ${DESIGNATION:="$TITLE"}

# Where to get OpenSeadragon
: ${OSD_VERSION:=2.4.1}
: ${OSD_ZIP:="openseadragon-bin-${OSD_VERSION}.zip"}
: ${OSD_URL:="http://github.com/openseadragon/openseadragon/releases/download/v${OSD_VERSION}/$OSD_ZIP"}
popd > /dev/null

function usage() {
    cat <<EOF

Usage: ./make_presentation.sh <image> [output_folder]
EOF
    exit $1
}

check_parameters() {
    if [[ "-h" == "$IMAGE" ]]; then
        usage
    fi
    if [[ -z $(which vips) ]]; then
        >&2 echo "Error: The tool vips must be available. Please install it (try 'sudo apt-get install libvips-tools')"
        exit 62
    fi
    if [[ -z "$IMAGE" ]]; then
        >&2 echo "Error: No image specified"
        usage 2
    fi
    if [[ ! -s "$IMAGE" ]]; then
        >&2 echo "Error: Unable to locate $IMAGE"
        usage 3
    fi
    if [[ -d "$OUTPUT_FOLDER" ]]; then
        if [[ "true" == "$OVERWRITE" ]]; then
            echo "- Overwriting content in '$OUTPUT_FOLDER'"
        else 
            >&2 echo "Error: Output folder '$OUTPUT_FOLDER' already exists"
            usage 4
        fi
    fi
    mkdir -p "$OUTPUT_FOLDER"
}

################################################################################
# FUNCTIONS
################################################################################

# http://stackoverflow.com/questions/14434549/how-to-expand-shell-variables-in-a-text-file
# Input: template-file
function ctemplate() {
    if [[ ! -s "$1" ]]; then
        >&2 echo "Error: Template '$1' could not be found"
        exit 8
    fi
    local TMP=$(mktemp /tmp/juxta_XXXXXXXX)
    echo 'cat <<END_OF_TEXT' >  "$TMP"
    cat  "$1"                >> "$TMP"
    echo 'END_OF_TEXT'       >> "$TMP"
    . "$TMP"
    rm "$TMP"
}

# Fetch OpenSeadragon
ensure_osd() {
    if [[ -s "${CACHE}/$OSD_ZIP" ]]; then
        return
    fi
    mkdir -p "${CACHE}"
    echo "- Fetching $OSD_ZIP from $OSD_URL"
    wget --quiet "$OSD_URL" -O  "${CACHE}/$OSD_ZIP"
    if [[ ! -s "${CACHE}/$OSD_ZIP" ]]; then
        >&2 echo "Error: Unable to fetch OpenSeadragon from $OSD_URL"
        >&2 echo "Please download is manually and store it in ${CACHE}"
        usage 21
    fi
}

# https://libvips.github.io/libvips/API/current/Making-image-pyramids.md.html
make_deepzoom_tiles() {
    echo "- Creating DeepZoom tiles from $IMAGE to folder $OUTPUT_FOLDER using command"
    echo "> vips dzsave \"$IMAGE\" \"$OUTPUT_FOLDER\" --suffix \".jpg[Q=${JPEG_QUALITY}]\" --tile-size \"$TILE_SIZE\" --overlap \"$TILE_OVERLAP\""
    vips dzsave "$IMAGE" "${OUTPUT_FOLDER}/deepzoom" --suffix ".jpg[Q=${JPEG_QUALITY}]" --tile-size "$TILE_SIZE" --overlap "$TILE_OVERLAP"
}

# Create index.html from the template and add tile setup
make_webpage() {
    echo "- Creating webpage ${OUTPUT_FOLDER}/index.html"
    pushd "$OUTPUT_FOLDER" > /dev/null
    # OpenSeadragon files
    mkdir -p resources resources/images
    unzip -q -o -j -d "resources/" "${CACHE}/openseadragon-bin-${OSD_VERSION}.zip" ${OSD_ZIP%.*}/openseadragon.min.js
    unzip -q -o -j -d "resources/images/" "${CACHE}/openseadragon-bin-${OSD_VERSION}.zip" $(unzip -l "${CACHE}/openseadragon-bin-"*.zip | grep -o "opensea.*.png" | tr '\n' ' ')

    WIDTH="$(grep "Width" < "deepzoom.dzi" | grep -o "[0-9]*")"
    HEIGHT=$(grep "Height" < "deepzoom.dzi" | grep -o "[0-9]*")
    MEGA_PIXELS=$((WIDTH*HEIGHT/1000000))
    GIGA_PIXELS=$((WIDTH*HEIGHT/1000000000))
    TILE_SOURCES="tileSources:   {
    Image: {
        xmlns:    \"http://schemas.microsoft.com/deepzoom/2008\",
        Url:      \"deepzoom_files/\",
        Format:   \"$(grep "Format" < "deepzoom.dzi" | cut -d= -f2 | grep -o "[a-z]*")\", 
        Overlap:  \"$(grep "Overlap" < "deepzoom.dzi" | grep -o "[0-9]*")\", 
        TileSize: \"$(grep "TileSize" < "deepzoom.dzi" | grep -o "[0-9]*")\",
        Size: {
            Width: \"$WIDTH\",
            Height:  \"$HEIGHT\"
        }
    }
}"
    ctemplate "$TEMPLATE" > index.html
    popd > /dev/null
}    


###############################################################################
# CODE
###############################################################################

check_parameters "$@"
ensure_osd
make_deepzoom_tiles
make_webpage
