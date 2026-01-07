# Spritesheet Creation Tools

Utilities and scripts to automate rendering and building spritesheets for 2D projects.

## Overview

This repository contains tools used to render frames (via Blender) and assemble those frames into spritesheets (via Julia scripts). It is intended to help create consistent spritesheets from Blender renders and organize outputs for game engines or animation pipelines.

## Contents

- `blender_auto_render.py` — example script for automating renders (intended to be run from within Blender).
- `build_sheets.jl` — example Julia script to assemble rendered frames into spritesheets.
- `Spritesheets.jl` — Julia module relating to spritesheet generation.
- `output/` — examples of generated spritesheet outputs and auxiliary files.
- `renders/` — examples of raw rendered frames organized by character and animation.

## License

See the `LICENSE` file in the repository root for license details.
