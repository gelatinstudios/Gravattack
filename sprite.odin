
package gbjam_space_game

import  "vendor:sdl2"
import stbi "vendor:stb/image"

import "core:c/libc"

Sprite :: struct {
    texture: ^sdl2.Texture,
    size: Vector2_Int,
}

load_sprite :: proc(sdl: ^sdl2.Renderer, $base_filename: cstring) -> Sprite {
    path :: "../assets/processed/" + base_filename + ".png"
    p := #load(path)

    w, h, n: i32
    pixels := stbi.load_from_memory(raw_data(p), i32(len(p)), &w, &h, &n, 4)
    defer libc.free(pixels)

    depth :: 32
    pitch := w*4
    rmask :: 0x000000ff
    gmask :: 0x0000ff00
    bmask :: 0x00ff0000
    amask :: 0xff000000
    surface := sdl2.CreateRGBSurfaceFrom(pixels, w, h, depth, pitch, rmask, gmask, bmask, amask)
    defer sdl2.FreeSurface(surface)

    texture := sdl2.CreateTextureFromSurface(sdl, surface)

    return { texture, {w, h} }
}
