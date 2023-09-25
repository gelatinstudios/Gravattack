
package gbjam_space_game

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:math/linalg"

import "vendor:sdl2"
import sdl2_ttf "vendor:sdl2/ttf"

get_camera_rect :: proc(camera: Vector2) -> Rect {
    return {
        camera,
        camera + SCREEN_SIZE,
    }
}

Renderer :: struct {
    sdl: ^sdl2.Renderer,
    camera: Vector2,
}

world_to_screen :: proc(camera: Vector2, p: Vector2) -> Vector2_Int {
    draw_pos := p - camera
    draw_x := i32(math.floor(draw_pos.x))
    draw_y := i32(math.floor(draw_pos.y))
    return {draw_x, draw_y}
}

set_draw_color :: proc(sdl: ^sdl2.Renderer, color: u32) {
    sdl2.SetRenderDrawColor(sdl, u8(color>>16), u8(color>>8), u8(color), 0xff)
}

draw_rect :: proc(using renderer: Renderer, rect: Rect, color: u32, $filled: bool) {
    pos := world_to_screen(camera, rect.mins)
    width  := i32(math.round(rect.maxs.x - rect.mins.x))
    height := i32(math.round(rect.maxs.y - rect.mins.y))
    dest_rect := sdl2.Rect{pos.x, pos.y, width, height}

    set_draw_color(sdl, color)
    if   filled do sdl2.RenderFillRect(sdl, &dest_rect)
    else        do sdl2.RenderDrawRect(sdl, &dest_rect)
}

draw_sprite :: proc(using renderer: Renderer, using sprite: Sprite, position: Vector2, angle := f32(0), precision := f32(10)) {
    pos := position - 0.5*vector2(size)
    pos -= camera
    angle := angle
    angle = math.round(angle / precision) * precision
    s := vector2(size)
    center := s*.5
    dest_rect := sdl2.FRect{math.round(pos.x), math.round(pos.y), s.x, s.y}
    sdl2.RenderCopyExF(sdl, texture, nil, &dest_rect, f64(angle), transmute(^sdl2.FPoint)&center, nil)
}

draw_bvh_rects :: proc(using game: Game, camera_rect: Rect, bvh: BVH_Rect($T), draw_proc: proc(Game, T)) {
    if !rects_intersect(camera_rect, bvh.rect) do return

    switch v in bvh.variant {
        case BVH_Rect_Internal(T):
            draw_bvh_rects(game, camera_rect, v.left^, draw_proc)
            draw_bvh_rects(game, camera_rect, v.right^, draw_proc)

        case T:
            draw_proc(game, v)
    }
}

draw_text :: proc(using game: Game, color: u32, pos: Vector2_Int, text: cstring) {
    surface := sdl2_ttf.RenderText_Solid(font, text, sdl2.Color{u8(color>>16),u8(color>>8),u8(color),0xff})
    defer sdl2.FreeSurface(surface)

    texture := sdl2.CreateTextureFromSurface(sdl, surface)
    defer sdl2.DestroyTexture(texture)

    dest_rect := sdl2.Rect{pos.x, pos.y, surface.w, surface.h}
    sdl2.RenderCopy(sdl, texture, nil, &dest_rect)
}

draw_text_top_right :: proc(using game: Game, text: cstring) {
    surface := sdl2_ttf.RenderText_Solid(font_smaller, text, text_color)
    defer sdl2.FreeSurface(surface)

    texture := sdl2.CreateTextureFromSurface(sdl, surface)
    defer sdl2.DestroyTexture(texture)

    x := SCREEN_WIDTH - surface.w - 1
    y :: 1
    
    dest_rect := sdl2.Rect{x, y, surface.w, surface.h}
    sdl2.RenderCopy(sdl, texture, nil, &dest_rect)
}

text_color_hex :: 0x081820
text_color :: sdl2.Color{(text_color_hex>>16)&0xff,
                         (text_color_hex>>8)&0xff,
                         text_color_hex&0xff, 0xff}

draw_title_text :: proc(using game: Game, text: cstring) {
    surface := sdl2_ttf.RenderText_Solid(font, text, text_color)
    defer sdl2.FreeSurface(surface)

    texture := sdl2.CreateTextureFromSurface(sdl, surface)
    defer sdl2.DestroyTexture(texture)

    x := SCREEN_WIDTH/2 - surface.w/2
    y := SCREEN_HEIGHT/2 - surface.h/2
    dest_rect := sdl2.Rect{x, y, surface.w, surface.h}
    sdl2.RenderCopy(sdl, texture, nil, &dest_rect)
}

draw_centered_lines :: proc(using game: Game, lines: []cstring) {
    total_height := i32(0)
    total_width := i32(0)
    
    surfaces := make([]^sdl2.Surface, len(lines), context.temp_allocator)
    defer for surface in surfaces do sdl2.FreeSurface(surface)
    for line, i in lines {
        f := i == 0 ? font : font_smaller
        surface := sdl2_ttf.RenderText_Solid(f, line, text_color)

        if surface == nil do continue
        
        total_height += i == 0 ? FONT_HEIGHT : FONT_SMALLER_HEIGHT
        total_width = max(total_width, surface.w)
        
        surfaces[i] = surface
    }

    y := SCREEN_HEIGHT/2 - total_height/2
    
    for surface, i in surfaces {
        if surface == nil do continue
        
        x := SCREEN_WIDTH/2 - surface.w/2

        texture := sdl2.CreateTextureFromSurface(sdl, surface)
        defer sdl2.DestroyTexture(texture)

        dest_rect := sdl2.Rect{x, y, surface.w, surface.h}
        
        sdl2.RenderCopy(sdl, texture, nil, &dest_rect)

        y += (i == 0 ? FONT_HEIGHT : FONT_SMALLER_HEIGHT)
    }
}

enemy_was_drawn: bool

draw_game :: proc(using game: Game, dt: f32) {
    camera_rect := Rect{camera, camera + SCREEN_SIZE}

    set_draw_color(sdl, 0x081820)
    sdl2.RenderClear(sdl)

    // color play area
    draw_rect(renderer, {{-half_world_size, -half_world_size}, {half_world_size, half_world_size}}, 0x346856, true)

    draw_bvh_rects(game, camera_rect, stars_bvh^, proc(using game: Game, using star: Star) {
        pos := vector2(position) + 0.5*vector2(size)
        draw_sprite(renderer, sprite, pos)
    })

    enemy_was_drawn = false
    bvh_draw := make_bvh_rect(entities[:], entity_get_rect, context.temp_allocator)
    draw_bvh_rects(game, camera_rect, bvh_draw^, proc(using game: Game, using entity: Entity) {
        if entity.type == .Player {
            if player_is_dead do return
            if player_iframe_timer > 0 {
                if rand.int31_max(2) == 0 do return
            }
        }
        if entity.type == .Enemy {
            enemy_was_drawn = true
        } 
        draw_sprite(renderer, sprite, position, angle)
    })
    
    for explosion in explosions {
        using explosion
        t := 1 - (timer / EXPLOSION_TIME)
        sprite_index := i32(t * len(sprites.explosion))
        draw_sprite(renderer, sprites.explosion[sprite_index], position)
    }

    {
        using sprites.heart
        x := size.x/2
        y := size.y/2
        for i in 1..=player_lives {
            dest_rect := sdl2.Rect{x, y, size.x, size.y}
            sdl2.RenderCopy(sdl, texture, nil, &dest_rect)
            
            x += size.x + size.x/2
        }
    }

    player_position := entities[player_index].position

    if !enemy_was_drawn {
        closest_enemy: ^Entity
        closest_enemy_distance2 := max(f32)
        for &enemy in entities[enemy_start_index:] {
            distance2 := linalg.length2(enemy.position - player_position)
            if distance2 < closest_enemy_distance2 {
                closest_enemy_distance2 = distance2
                closest_enemy = &enemy
            }
        }

        if closest_enemy != nil {
            normal := linalg.normalize(closest_enemy.position - player_position)
            
            distance := math.sqrt(closest_enemy_distance2)

            min_d :: 100
            max_d :: 1000

            t := clamp((distance - min_d) / max_d, 0, 1) * 25 + 25
            
            pos := player_position + t*normal
            draw_sprite(renderer, sprites.arrow, pos, get_angle(normal), 45)
        }
    }
    

    for laser in lasers {
        position := laser.position
        draw_sprite(renderer, sprites.laser, position, get_angle(laser.normal))
    }
    
    draw_text_top_right(game, fmt.ctprintf("Enemies: {}", len(entities[enemy_start_index:])))
    
    // temp arena tracking
    when false {
        temp_allocator_data := (^runtime.Default_Temp_Allocator)(context.temp_allocator.data)
        temp_allocator_arena := temp_allocator_data.arena

        fmt.printf("%#v\n", temp_allocator_arena)
    }
}
