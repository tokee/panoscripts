# panoscripts

Scripts and notes for making panoramas from multiple images

## Scripts

### reset_exposure.sh

Resets exposure and tint for all images in a panorama.

Hugin can automatically correct exposure and ting for images.
This is done as part of the default processing when using the simple
interface. If the images has been taken with variable exposure, this
might be a fine idea, but sometimes the result leaves very bright,
very dark or strangely tinted images.

See also http://hugin.sourceforge.net/docs/manual/Vig_optimize.html


## TODO

### validate_control_points.sh

Given a grid of images as source for the panorams, this scripts
validates the control points. It checks that images are connected
to their neighbours and that they are not connected to other images.

This script is not implemented yet.
