# blender_auto_render.py
#
# This is an example script for creating animation frame images compatible with Spritesheets.jl.
# It assumes the following objects are present:
#    "rig" -- The animation rig for the character
#    "visibleground" -- A visible ground plane/object that isn't used for renders
#    "ShadowPlane" -- A transparent(ish) plane that collects shadows from the character
# These objects and names are somewhat specific to the original case for which the file was created.
# 
# In this example, muting and unmuting are applied to the ground planes.  In practice, they can
# be used to change the status of any objects -- such as accessories that should appear only in certain
# animations.
#
# Copyright (c) 2026 Festering Puppies
# SPDX-License-Identifier: MIT

import bpy
import os

def mute_tracks (tracks, mute):
    for track in tracks:
        track.mute = mute

def render_frame (frame, filepath):
    bpy.context.scene.frame_set (frame)
    bpy.context.scene.render.filepath = filepath
    bpy.ops.render.render (write_still=True)

def write_animations (tracks_to_mute, tracks_to_unmute, output_path, step):
    start_frame = bpy.context.scene.frame_start
    end_frame = bpy.context.scene.frame_end
    for frame in range (start_frame, end_frame + 1, step):
        mute_tracks (tracks_to_mute, True)
        mute_tracks (tracks_to_unmute, False)
        render_frame (frame, output_path + str (frame).zfill (3) + ".png")

def mute_and_unmute (objects, tracks_to_mute, tracks_to_unmute):
    for x in zip(objects, tracks_to_mute, tracks_to_unmute):
        obj = bpy.data.objects.get(x[0])
        if x[1]!=0:
            for y in x[1]:
                obj.animation_data.nla_tracks[y].mute = True
        if x[2]!=0:
            for z in x[2]:
                obj.animation_data.nla_tracks[z].mute = False

def write_animations2 (output_path, step, start_frame = bpy.context.scene.frame_start, end_frame = bpy.context.scene.frame_end):
    for frame in range (start_frame, end_frame + 1, step):
        render_frame (frame, output_path + "_" + str (frame).zfill (3) + ".png")

def reset_tracks (obj):
    for x in obj:
        bpy.context.scene.frame_set(1)
        mute_tracks(bpy.data.objects.get(x).animation_data.nla_tracks, True)

        bpy.data.objects.get(x).animation_data.nla_tracks["reset"].mute = False
        bpy.data.objects.get(x).animation_data.nla_tracks["reset"].mute = True

        mute_tracks(bpy.data.objects.get(x).animation_data.nla_tracks, True)
        bpy.data.objects.get(x).animation_data.nla_tracks["reset"].mute = False
        bpy.context.scene.frame_set(1)
        bpy.data.objects.get(x).animation_data.nla_tracks["reset"].mute = True
        
def hide_objects(objects, true_or_false):
    for x in objects:
        obj2 = bpy.data.objects.get(x)
        obj2.hide_render = true_or_false
        obj2.hide_viewport = true_or_false

def run_case (animal_name):
    base_path = os.path.join(bpy.path.abspath("//"), "renders") + os.sep

    # turn the shadow plane on and make sure the visible ground is off
    # (these seem to work even if they are buried in collections)
    hide_objects(["visibleground"], True)
    hide_objects(["ShadowPlane"], False)

    mute_rig = []

    start_frame = 1

    match animal_name:
        case "squirrel":
            objects = ["rig"]
            bpy.context.scene.frame_end = 160 # 8 directions x 20 frames each
        case _:
            print("Animal " + animal_name + " not supported!")
    
    animation_list = ["Idle1", "Walk"]

    # NOTE: In practice, elements such as end_frame, step, and the rigs/objects to be
    # hidden or muted/unmuted will be set per animation (possibly through a 'match' statement).
    # Those elements (and the animation list) could also be changed per character (or, animal, in this example), 
    # if the script is used for multiple characters. 

    for anim in animation_list:
        
        end_frame = bpy.context.scene.frame_end
        step = 2

        unmute_rig = [anim, "Rotation"]

        hide_objects(["ShadowPlane"], False)

        reset_tracks(objects)

        mute_and_unmute(objects, [mute_rig], [unmute_rig])

        output_path = os.path.join(base_path + animal_name, anim)

        if not os.path.exists(output_path):
            os.makedirs(output_path)

        write_animations2(os.path.join(output_path, anim), step, start_frame, end_frame)

# = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =

run_case("squirrel")

