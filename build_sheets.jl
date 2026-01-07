# build_sheets.jl
#
# This example script contains code for converting individual images into spritesheets
# using the Spritesheets.jl module.  In general, the module isn't specific to a particular
# game engine, though a function is included for creating an empty Godot spriteframes resource.  
#
# NOTE: In general, Spritesheets.jl assumes the original files are broken into subfolders
# named after each animation & the image files are prefixed with the animation name, as well.
# So, if "render_home" is "renders", the "walk" animation files would be "renders/walk/walk_001.png",
# "renders/walk/walk_002.png", etc.  (The numbering doesn't matter, as long as the files are in the
# correct order when read by the functions.)
#
# Copyright (c) 2026 Festering Puppies
# SPDX-License-Identifier: MIT

using FileIO
using ImageIO

# = = = = = = = = = = = = = = = = = = = = = = = = = =
# import the Spritesheets module:

home_path = dirname(@__FILE__)

module_path = abspath(joinpath(home_path, "Spritesheets.jl"))

if !isfile(module_path)
    error("Spritesheets.jl not found at $module_path")
end
include(module_path)

import .Spritesheets

# = = = = = = = = = = = = = = = = = = = = = = = = = = 

# main_path is where the spritesheets will go
main_path = abspath(joinpath(home_path, "output"))

# render_home is where the original individual images are located (refer to note above)
render_home =  abspath(joinpath(home_path, "renders"))

# = = = = = = = = = = = = = = = = = = = = = = = = = = 
# define the animations
#
# information about each animation is required.  here, the info is 
# specified mostly through arrays.  a smarter way to do this might be to use a 
# mutable struct that contains all the information about a particular animation.
#
# info required:
#   -- whether or not it is 8-way
#   -- whether or not it is to be looped (Godot-related output only)
#   -- speed in frames per second (Godot-related output only)
#   -- window size used for cropping the images (distance in each direction from the middle of the image)
#   -- number of frames in each animation
#
# NOTE: This example uses dictionaries for the window size and number of frames because 
# both where constant per animal in the original use of this script.  In general,
# though, the windows and number of frames are likely to vary per animation and would
# be better as arrays like the other parameters. 

animation_list = ["Idle1", "Walk"]
eightway = fill(true, length(animation_list))
looped = fill(true, length(animation_list))
speed = fill(10, length(animation_list))

fx(x) = joinpath(render_home, x)

windows = Dict("squirrel"=>192)
nframes = Dict("squirrel"=>10)

# pixels with alpha < alpha_cutoff are set to an alpha of 0
# NOTE: Pixels with alpha==0 are also rounded down to (0,0,0) if they have channel values < 0.005.
alpha_cutoff = 0.03

# - - - - - - - - - - - - - - - - - - 

animal = "squirrel"

# process the 8-way animations:
[Spritesheets.make_eightway_sheets(anim, fx(animal), joinpath(main_path, animal); cutoff=alpha_cutoff, lower_case=true, output_width=min(nframes[animal]*windows[animal],4096), nframes_per_anim=nframes[animal], window_width=windows[animal], window_height=windows[animal]) for anim in animation_list[eightway]]

# process the non-8-way animations:
[Spritesheets.make_noneightway_sheets(anim, fx(animal), joinpath(main_path, animal); cutoff=alpha_cutoff, lower_case=true, output_width=min(nframes[animal]*windows[animal],4096), nframes_per_anim=nframes[animal], window_width=windows[animal], window_height=windows[animal]) for anim in animation_list[broadcast(!, eightway)]]

# create empty Godot spriteframes data that can be copied into a spriteframes resource
Spritesheets.make_empty_sprite_frames(joinpath(main_path, "empty_sprite_frames_animal.txt"), broadcast(x->split(x, "_Blended")[1], animation_list), looped, speed, eightway; do_lower=true)

# can use find_animation_bounds to determine the minimum bounds around image contents,
# so that cropping can be performed.  (would do this before the above processing so that "windows" can be set.)
[Spritesheets.find_animation_bounds(anim, fx(animal); cutoff=alpha_cutoff) for anim in animation_list[eightway]]

# this function can be used to copy the spritesheets somewhere.
# it assumes the spritesheets are arranged (in the target path) into subfolders by player/character/etc name.
function copy2somewhere(directory::String, playername::String, out_path::String; force::Bool=false, name2::String="")
    if name2 == ""
        name2 = playername
    end
    tmp1 = joinpath(directory, name2, "processed")
    tmp2 = joinpath(out_path, playername)

    files = readdir(tmp1)

    for x in files
        tmp3 = joinpath(tmp1, x)
        tmp4 = joinpath(tmp2, x)
        cp(tmp3, tmp4; force=force)
    end
end

# NOTE: The spritesheet file sizes can sometimes be reduced by using GIMP (or whatever) to resave the image.
# This process can be scripted & performed before copying the spritesheets somewhere.
 
# copy2somewhere(main_path, animal, target_path; force=true)
