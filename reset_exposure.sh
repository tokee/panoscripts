#!/usr/bin/env bash


#
# 
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
: ${EXPOSURE:="$2"}
: ${EXPOSURE:="14.0"}
popd > /dev/null

function usage() {
    cat <<EOF

Usage: ./reset_exposure.sh <pto_file> [exposure] > <new_pto>

pto_file: A PTO file from Hugin or similar.
exposure: The wanted exposure value. Default is 14.0

Sample: ./reset_exposure.sh strange_colors.pto 14.5 > okay.pto

Resets exposure (Eev) for all images to the same value and resets tint
adjustment (Er and Eb) to 1.0. Normally used if the auto-exposure failed
and made some images very bright, dark or strangely colored.
(As of 2020-09-22 Hugin does not seem to have a build-in reset function)
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

process() {
    sed -e "s/Eev1[0-9]\?[.][0-9]\+/Eev${EXPOSURE}/" -e 's/Er[0-9][.][0-9]\+/Er1.0/'  -e 's/Eb[0-9][.][0-9]\+/Eb1.0/' "$PTO"
}

###############################################################################
# CODE
###############################################################################

check_parameters "$@"
process
