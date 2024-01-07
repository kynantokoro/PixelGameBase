# Simple GameBase Template
## Overview
This template is designed for the development of pixel resolution games. It includes a selection of libraries that provide a solid starting point for game creation. The template serves as a foundational tool rather than a comprehensive game development solution.

## Libraries Used
### Monarch
https://github.com/britzl/monarch
Monarch is used to standardize the creation of screen-based collections, such as pop-up screens and inventories. This method simplifies debugging each screen from the bootstrap screen.

### Crit
https://github.com/critique-gaming/crit
Crit is a set of helper libraries. Here mainly used for input handling and messaging. It supports both gamepad and keyboard inputs, offering future-proof flexibility and compatibility.

### Defos
https://github.com/subsoap/defos
Defos is utilized for OS operations, especially for handling Retina resolutions on MacOS.

## Camera and Rendering
Our custom render script is heavily based on, and largely incorporates elements from, the following projects:

https://github.com/britzl/template-lowres
Template Lowres for managing different resolutions between the game world and GUI.

https://github.com/britzl/defold-orthographic
Defold Orthographic for aspects of camera movement, lerp, deadzones, and views.

## Multitasking / Coroutine
https://github.com/rxi/coil
Upcoming Implementation:
