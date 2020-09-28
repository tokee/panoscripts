# panoscripts

Scripts and notes for making panoramas from multiple images

Requirements:
 * bash
 * hugin (for `tile_panorama.sh`)
 * vips (for `tile_panorama.sh` and `make_presentation.sh`)
 * GraphicsMagic (for `tile_panorama.sh`)
 * wget (for `make_presentation.sh`)

## Scripts

### reset_exposure.sh

Resets exposure and tint for all images in a panorama.

Hugin can automatically correct exposure and tint for images.
This is done as part of the default processing, when using the simple
interface. If the images has been taken with variable exposure, this
might be a fine idea, but sometimes the result leaves very bright,
very dark or strangely tinted images.

See also http://hugin.sourceforge.net/docs/manual/Vig_optimize.html

### tile_panorama.sh

Slices a panorama into smaller tiles at PTO-level, renders the individual
tiles using hugin_executor and uses [vips](https://github.com/libvips/libvips)
for merging the resulting tiles into a single image.

Hugin uses [enblend](https://wiki.panotools.org/Enblend) for stitching
panoramas (creating the final large image). Unfortunately enblend has
a hard time scaling up to hundreds of images and gigapixels size on a
32GB machine.

Creating multiple smaller tiles is lighter than creating a single
large image and the tool `vips` is capable of merging these tiles
into a single image with ease.

The challenge here is to avoid visible seams between the tiles. This is done
by having an intermediate overlap between tiles. It has not been researched
how large that overlap should be and it probably depends on the image.
The driving problem that leas to this script was a 160000x12924 pixel 
image and when cut into tiles of 16284x16384 pixels, an overlap of 8000
was needed to make the seams invisible.

### add_masks.sh

Given a grid of images as source for the panorama, this scripts adds
exclusion masks to the bottom or to the right of every image, except
for those at the lowest row or rightmost column respectively.

enblend 4.0 sometimes complain about
[excessive overlap detected](https://wiki.panotools.org/Hugin_FAQ#enblend:_excessive_overlap_detected)
without it being possible to remove any images (without leaving
holes). "Removing" part of the overlap by adding exclusion masks
solves this problem at the cost of less pixels to blend.

The smaller amount of pixels might be a problem if the different
has different exposures.

### make_presentaion.sh

Given a finished panorama bitmap (or any bitmap), this script cuts
it into DeepZoom tiles using vips and creates a web page where the
panorama is displayed using OpenSeadragon.

## TODO

Scripts that are not implemented yet.

### validate_control_points.sh

Given a grid of images as source for the panorama, this scripts
validates the control points by checking that

* Images are connected to their neighbours
* Images are not connected to other images that they should not be connected to
* Horizontal and vertical lines does not differ from the mean by more than X percent
