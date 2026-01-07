# Copyright (c) 2026 Festering Puppies
# SPDX-License-Identifier: MIT

# NOTE: In general, Spritesheets.jl assumes the original files are broken into subfolders
# named after each animation & the image files are prefixed with the animation name, as well.
# So, if the main path is "renders", the "walk" animation files would be "renders/walk/walk_001.png",
# "renders/walk/walk_002.png", etc.  (The numbering doesn't matter, as long as the files are in the
# correct order when read by the functions.)

"""
    Spritesheets

Utilities for converting image frames into spritesheets, cropping windows,
removing background artifacts, and simple animation blending.

Functions operate on image arrays (RGBA pixels) and read/write images from
directories of frames. See individual function docstrings for details.
"""
module Spritesheets

using FileIO
using ImageIO
using ColorTypes

export make_noneightway_sheet, make_eightway_sheets, make_empty_sprite_frames, find_animation_bounds

MAX_OUTPUT_HEIGHT = 4096
MAX_OUTPUT_WIDTH = 4096

# pixels with alpha < cutoff are set to an alpha of 0.
# NOTE: This cutoff value can be overridden when the functions are called.
# check the bg with the dropper tool in gimp/etc. to see what the alpha is.
ALPHA_CUTOFF = 0.03 

# for pixels with alpha==0, individual channels are set to 0 if value<CHANNEL_CUTOFF
CHANNEL_CUTOFF = 0.005

# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =

"""
    image_window(data, new_width, new_height)

Return a centered window (crop) of `data` with dimensions `new_width` x `new_height`.
If the requested size equals the image size the original `data` is returned.
The result is a view into `data` and will reflect changes to the source.
"""
function image_window(data, new_width, new_height)
    (h, w) = size(data)

    if new_width == w && new_height == h
        return data
    end

    # center-crop to requested size, clamping to image bounds
    ch = Int(fld(h, 2))
    cw = Int(fld(w, 2))

    nhh = Int(fld(new_height, 2))
    nwh = Int(fld(new_width, 2))

    top = max(1, ch - nhh + 1 - (isodd(new_height) ? 0 : 0))
    left = max(1, cw - nwh + 1 - (isodd(new_width) ? 0 : 0))

    bottom = min(h, top + new_height - 1)
    right = min(w, left + new_width - 1)

    return @view data[top:bottom, left:right]
end

# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =

"""
    remove_floor!(data, cutoff)

In-place cleanup of very small color values and alpha channel.
If a pixel's alpha is below `cutoff` its alpha is set to zero and any
RGB channels below a small threshold are floored to zero. This helps
remove background artifacts before compositing or packing into sheets.
"""
function remove_floor!(data, cutoff)
    @inbounds for I in CartesianIndices(data)
        px = data[I]
        a = px.alpha < cutoff ? 0.0 : px.alpha
        if iszero(a)
            r = px.r < CHANNEL_CUTOFF ? 0.0 : px.r
            g = px.g < CHANNEL_CUTOFF ? 0.0 : px.g
            b = px.b < CHANNEL_CUTOFF ? 0.0 : px.b
            data[I] = RGBA(r, g, b, a)
        else
            data[I] = RGBA(px.r, px.g, px.b, a)
        end
    end
    return
end # remove_floor

# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =

#! BUG:  This can potentially break if a window size is the dimension size

"""
    move_unused_frames(animation_name, file_path, target_path, nframes_per_anim, nframes_rendered, eight_way)

Move any extra rendered frames for `animation_name` from the source
directory under `file_path` to `target_path`. `nframes_per_anim` is the
expected number of frames per animation; `nframes_rendered` is how many
were rendered; set `eight_way` to true for 8-direction animations.

This function prints moved filenames and returns nothing.
"""
function move_unused_frames(animation_name::String, file_path::String, target_path::String,
    nframes_per_anim::Int, nframes_rendered::Int, eight_way::Bool)
    tmpdir = joinpath(file_path, animation_name)
    filelist = readdir(tmpdir)

    file_step = 1
    filelist = filelist[1:file_step:end]
    nfiles = length(filelist)

    n = eight_way ? 8 : 1

    if nfiles != (n * nframes_rendered)
        println("Don't seem to have the right number of files!  " * animation_name * " may have already been processed!")
        return
    end

    ndelta = nframes_rendered - nframes_per_anim

    indx = 0
    for i in 1:n
        indx += nframes_per_anim
        for k in 1:ndelta
            indx += 1
            println(filelist[indx] * " is getting moved!")
            mv(joinpath(tmpdir, filelist[indx]), joinpath(target_path, filelist[indx]), force=true)
        end
    end
end

"""
    make_noneightway_sheet(animation_name, file_path, output_path; kwargs...)

Create a single spritesheet for the animation named `animation_name`.
Frames are loaded from `joinpath(file_path, animation_name)`. Optional
keyword arguments control output size, optional center-window cropping
(`window_width`, `window_height`), filename suffix, slicing (`filelist`,
`file_step`) and whether to lowercase the output name.

Returns the number of images per row written in the sheet.
"""
function make_noneightway_sheet(animation_name::String, file_path::String, output_path::String;
    output_width::Int=MAX_OUTPUT_WIDTH, window_width::Int=0, window_height::Int=0,
    output_suffix="", filelist=[], lower_case::Bool=false, file_step::Int=1, cutoff=ALPHA_CUTOFF)

    println("Hello ", animation_name)
    println("  output_width=", output_width, " window_width=", window_width, " window_height=", window_height)

    do_window = (window_width != 0) && (window_height != 0)

    tmpdir = joinpath(file_path, animation_name)
    if isempty(filelist)
        filelist = readdir(tmpdir)
    end

    # apply file step slicing once
    filelist = filelist[1:file_step:end]
    nfiles = length(filelist)

    tmp = load(joinpath(tmpdir, filelist[1]))
    emptypixel = zero(typeof(tmp[1,1]))

    if do_window
        image_height = window_height
        image_width = window_width
    else
        (image_height, image_width) = size(tmp)
    end

    n_per_row = max(1, output_width ÷ image_width)
    n_rows = Int(ceil(nfiles / n_per_row))

    out_width = min(image_width * n_per_row, output_width)
    out_height = n_rows * image_height

    out_image2 = fill(emptypixel, (out_height, out_width))

    println("  output size = ", out_width, " x ", out_height, " image size = ", image_width, " x ", image_height, " n_per_row = ", n_per_row, " n_rows = ", n_rows)

    @inbounds for k in 1:nfiles
        row = Int(fld(k-1, n_per_row))
        col = (k-1) % n_per_row

        println(k, " ", filelist[k])
        tmp = load(joinpath(tmpdir, filelist[k]))
        if do_window
            tmp = image_window(tmp, window_width, window_height)
        end
        remove_floor!(tmp, cutoff)

        aa = row * image_height + 1
        bb = (row + 1) * image_height
        cc = col * image_width + 1
        dd = (col + 1) * image_width

        out_image2[aa:bb, cc:dd] = tmp
    end

    if lower_case
        animation_name = lowercase(animation_name)
    end

    outname = joinpath(output_path, animation_name * "_sheet" * output_suffix * ".png")
    save(outname, out_image2)
    println("Wrote ", outname)
    return n_per_row
end # make_noneightway_sheet

# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =

"""
    make_eightway_sheets(animation_name, file_path, output_path; nframes_per_anim=12, kwargs...)

Split frames for an eight-way animation into one or more sheets so that
no sheet exceeds `output_width` x `output_height`. Frames are assumed to be
grouped by animation direction; `nframes_per_anim` specifies how many
frames belong to each direction. This calls `make_noneightway_sheet`
internally for each sheet created and returns `n_per_row`.
"""
function make_eightway_sheets(animation_name::String, file_path::String, output_path::String; nframes_per_anim::Int=12, 
    output_width::Int=MAX_OUTPUT_WIDTH, output_height::Int=MAX_OUTPUT_HEIGHT, window_width::Int=0, window_height::Int=0,
    lower_case::Bool=false, cutoff=ALPHA_CUTOFF)

    tmpdir = joinpath(file_path, animation_name)
    filelist0 = readdir(tmpdir)
    nfiles = length(filelist0)
    n_animations = Int(nfiles/nframes_per_anim)

    tmp = load(joinpath(tmpdir, filelist0[1]))

    if (window_width != 0) && (window_height != 0)
        image_height = window_height
        image_width = window_width
    else
        (image_height, image_width) = size(tmp)
    end

    n_per_row = convert(Int, floor(output_width/image_width))
    n_rows = convert(Int, ceil(nfiles/n_per_row))

    # need to find how many whole animations will fit on a sheet
    max_rows_per_sheet = Int(floor(output_height/image_height))
    max_images_per_sheet = max_rows_per_sheet * n_per_row
    n_anim_per_sheet = Int(floor(max_images_per_sheet/nframes_per_anim))
    nsheets = Int(ceil(n_animations/n_anim_per_sheet))
    n_images_per_sheet = nframes_per_anim * n_anim_per_sheet

    println(animation_name)
    println(file_path)
    println(output_path)
    for i in 1:nsheets
        slice_start = (i-1)*n_images_per_sheet + 1
        slice_end = min(i * n_images_per_sheet, nfiles)
        make_noneightway_sheet(animation_name, file_path, output_path;
            filelist = filelist0[slice_start:slice_end], output_suffix = sprint(show,i),
            window_height = window_height, window_width = window_width, output_width = output_width, lower_case = lower_case, cutoff = cutoff)
    end

    return n_per_row
end # make_eightway_sheets

# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =

"""
    blend_animations(anim_name1, anim_name2, file_path, output_path, start_frame, crossover_frame; animation_length=0)

Blend two animations frame-by-frame by linearly interpolating between
frames of `anim_name1` and `anim_name2`. The interpolation begins after
`start_frame` and reaches full `anim_name2` at `crossover_frame`.
Saved blended frames are written under `output_path/{anim_name1}_blended`.
"""
function blend_animations(anim_name1::String, anim_name2::String, 
    file_path::String, output_path::String, start_frame::Int, crossover_frame::Int;
    animation_length::Int=0)

    tmpdir1 = joinpath(file_path, anim_name1, "")
    filelist1 = readdir(tmpdir1)
    nfiles = length(filelist1)

    tmpdir2 = joinpath(file_path, anim_name2, "")
    filelist2 = readdir(tmpdir2)
    nfiles2 = length(filelist2)

    @assert nfiles==nfiles2

    output_anim_name = anim_name1 * "_blended"

    # will have to make the output folder if it doesn't exist
    full_output_path = joinpath(output_path, output_anim_name)

    # Use the isdir function to check if the directory exists
    if isdir(full_output_path)
        println("The directory $full_output_path already exists.")
    else
        # Use the mkpath function to create the directory and any intermediate directories if needed
        mkpath(full_output_path)
        println("The directory $full_output_path was created.")
    end

    k = 0

    for i in 1:nfiles
        tmp1 = load(joinpath(tmpdir1, filelist1[i]))
        tmp2 = load(joinpath(tmpdir2, filelist2[i]))

        outname = joinpath(full_output_path, output_anim_name * "_" * string(i, pad=4) * ".png")

        if iszero(animation_length)
            k = i
        else
            k += 1
        end

        if k<=start_frame
            out_image = tmp1
        elseif k>=crossover_frame
            out_image = tmp2
        else
            sf = (k - start_frame)/(crossover_frame - start_frame)
            tmp3 = (1 - sf)*tmp1 .+ sf*tmp2
            out_image = tmp3
        end       
        
        if k==animation_length
            k = 0
        end

        save(outname, out_image)
    end

end # blend_animations

# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =

"""
    make_empty_sprite_frames(fname, animation_list, loop, speed, eight_way; do_lower=true)

Write Godot spriteframes data to `fname` with empty frames for
each entry in `animation_list`. `loop` and `speed` provide per-animation
values and `eight_way` can expand each name into 8 directional entries.
The resulting data can be copied into a Godot spriteframes resource (before frames
are added to the animations in the Godot editor).
"""
function make_empty_sprite_frames(fname::String, animation_list, loop, speed, eight_way; do_lower::Bool=true)

    io = open(fname, "w");

    println(io, "animations = [{");

    n = length(animation_list)

    for i in 1:n

        if do_lower
            tmpname = lowercase(animation_list[i])
        else
            tmpname = animation_list[i]
        end

        if eight_way[i]
            for j=0:7
                println(io, "\"frames\": [],")
                println(io, "\"loop\": ", loop[i], ",")
                println(io, "\"name\": &\"", tmpname, "_", j, "\",")
                println(io, "\"speed\": ", speed[i])
                if j<7 
                    println(io, "}, {")
                end
            end
        else
            println(io, "\"frames\": [],")
            println(io, "\"loop\": ", loop[i], ",")
            println(io, "\"name\": &\"", tmpname, "\",")
            println(io, "\"speed\": ", speed[i])
        end
        if i<n
            println(io, "}, {")
        else
            println(io, "}]")
        end
    end

    close(io)

end # make_empty_sprite_frames

# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =

# try to find the minimum box around stuff

"""
    get_box(data, cutoff)

Return the smallest bounding box that contains non-empty content in
`data`. A pixel is considered content if its alpha is >= `cutoff` and
not equal to fully-zero RGBA. Returns `((min_row, max_row), (min_col, max_col))`.
If no content is found the full image range is returned.
"""
function get_box(data, cutoff)
    h, w = size(data)

    min_r = typemax(Int)
    max_r = 0
    min_c = typemax(Int)
    max_c = 0

    @inbounds for I in CartesianIndices(data)
        px = data[I]
        if !(px.alpha == 0 && px.r == 0 && px.g == 0 && px.b == 0) && px.alpha >= cutoff
            r = I.I[1]
            c = I.I[2]
            if r < min_r; min_r = r; end
            if r > max_r; max_r = r; end
            if c < min_c; min_c = c; end
            if c > max_c; max_c = c; end
        end
    end

    if max_r == 0
        # no content found; return full range
        return ((1, h), (1, w))
    end

    return ((min_r, max_r), (min_c, max_c))
end # get_box

"""
    get_all_boxes(animation_name, file_path)

Scan all frames in the animation folder and return a tuple
`(thang, bigx, bigy)` where `thang` is a vector of `(minr, maxr, minc, maxc)`
for each frame and `bigx`/`bigy` contain row/column ranges respectively.
"""
function get_all_boxes(animation_name::String, file_path::String; cutoff=ALPHA_CUTOFF)
    tmpdir = joinpath(file_path, animation_name)
    filelist0 = readdir(tmpdir)

    bigx = Vector{Tuple{Int,Int}}()
    bigy = Vector{Tuple{Int,Int}}()
    thang = Vector{NTuple{4,Int}}()

    for fname in filelist0
        tmp = load(joinpath(tmpdir, fname))
        (xr, yr) = get_box(tmp, cutoff)
        push!(bigx, xr)
        push!(bigy, yr)
        push!(thang, (xr[1], xr[2], yr[1], yr[2]))
    end

    return (thang, bigx, bigy)
end # get_all_boxes

"""
    find_animation_bounds(animation_name, file_path)

Aggregate bounding boxes across all frames of `animation_name` and
return `(min_row, max_row, min_col, max_col)` representing the union
of content extents across the animation.
"""
function find_animation_bounds(animation_name::String, file_path::String; cutoff=ALPHA_CUTOFF)
    out = get_all_boxes(animation_name, file_path; cutoff)
    arr = reduce(hcat, [collect(t) for t in out[1]])'
    return (minimum(arr[:,1]), maximum(arr[:,2]), minimum(arr[:,3]), maximum(arr[:,4]))
end # find_animation_bounds

end # module Spritesheets

