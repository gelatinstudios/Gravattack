
package gbjam_space_game

import "core:runtime"
import "core:fmt"
import "core:math"
import "core:slice"
import "core:math/rand"
import "core:math/linalg"
import "core:thread"
import "core:mem"

import "vendor:sdl2"
import ttf "vendor:sdl2/ttf"
import mixer "vendor:sdl2/mixer"

BIG_SIZE :: false
DRAW_FRAME_RATE :: false

SCREEN_WIDTH  :: 1280 when BIG_SIZE else 160
SCREEN_HEIGHT ::  720 when BIG_SIZE else 144
    
CENTER_X :: SCREEN_WIDTH/2
CENTER_Y :: SCREEN_HEIGHT/2

SCREEN_SIZE :: Vector2{SCREEN_WIDTH, SCREEN_HEIGHT}

GRAVITY_CONSTANT :: 2

MAX_VELOCITY :: 400

FONT_HEIGHT :: 24
FONT_SMALLER_HEIGHT :: 16

// gravity on B from A
get_gravity_accel :: #force_inline proc(a, b: Entity) -> Vector2 {
    using linalg

    max_gravity_accel :: 100
    
    mag := GRAVITY_CONSTANT*get_mass(a)/square(distance(a.position, b.position))
    mag = min(f32(max_gravity_accel), mag)
    
    return mag*normalize0(a.position - b.position)
}

get_gravity_range :: proc(using entity: Entity) -> f32 {
    min_accel :: 1
    return math.sqrt(GRAVITY_CONSTANT*get_mass(entity))/min_accel
}

get_gravity_circle :: proc(using entity: Entity) -> Circle {
    return {
        position = position,
        radius = get_gravity_range(entity),
    }
}

Control :: enum {
    Forward,
    Brakes,
    Left,
    Right,
    Fire,
}

Controls :: bit_set[Control]

Collision_Type :: enum { None, Rectangle, Rotated_Rectangle, Circle }

Entity_Type :: enum {
    None,
    Black_Hole,
    Player,
    Enemy,
    Sun,
    Planet,
}

Entity :: struct {
    type: Entity_Type,
    using sprite: Sprite,
    density: f32,
    angle: f32,
    position, velocity, acceleration, previous_acceleration: Vector2,
        
    // for sprites with thrust
    thrust_texture, non_thrust_texture: ^sdl2.Texture,
}


entity_get_rect :: proc(using entity: Entity) -> Rect {
    s := vector2(size)
    pos := position - .5*s
    return {
        pos,
        pos + s
    }
}

Entities :: [dynamic]Entity

set_type :: #force_inline proc(entity: ^Entity, type: Entity_Type) {
    entity.type = type
}

// stars are just the background stars, not to be confused with suns
Star :: struct {
    using sprite: Sprite,
    position: Vector2_Int,
}
star_get_rect :: proc(using star: Star) -> Rect {
    pos := vector2(position)
    return {
        pos,
        pos + vector2(size),
    }
}

Laser :: struct {
    position: Vector2,
    normal: Vector2,
    angle: f32,
}

Lasers :: [dynamic]Laser

Explosion :: struct {
    position: Vector2,
    timer: f32,
}

Explosions :: [dynamic]Explosion

LASER_VELOCITY :: MAX_VELOCITY + 100
LASER_TIMEOUT :: 0.2

PLAYER_IFRAMES_TIME :: 2
EXPLOSION_TIME :: 1.5

PLAYER_LIVES :: 5

Sprites :: struct {
    star: []Sprite,
    rocketship1_sprite: Sprite,
    rocketship2_sprite: Sprite,
    planet: []Sprite,
    sun: []Sprite,
    enemy: []Sprite,
    blackhole_sprite: Sprite,
    explosion: [9]Sprite,
    laser: Sprite,
    heart: Sprite,
    arrow: Sprite,
}

Assets :: struct {
    sprites: Sprites,
    
    font: ^ttf.Font,
    font_smaller: ^ttf.Font,
    screen_texture: ^sdl2.Texture,

    laser_sound: ^mixer.Chunk,
    explosion_sound: ^mixer.Chunk,
    hit_sound: ^mixer.Chunk,
}

Game_State :: enum {
    Start_Screen,
    Playing_Game,
    Game_Over,
}

Game :: struct {
    using renderer: Renderer,
    using assets: Assets,
    state: Game_State,
    
    stars_bvh: ^BVH_Rect(Star),
    
    laser_timer: f32,
    lasers: Lasers,

    explosions: Explosions,
    
    entities: Entities,

    player_index: int,
    player_is_dead: bool,
    player_lives: int,
    player_iframe_timer: f32,
    player_explosion_timer: f32,

    world_size: f32,
    half_world_size: f32,
    
    you_win: bool,
    
    enemy_start_index: int,

    max_solar_system_range: f32,

    bvh_gravity_maker: BVH_Gravity_Maker,
    bvh_gravity_thread: ^thread.Thread,

    total_time: f32,
}

init_game :: proc(using game: ^Game, assets_: Assets, sdl_: ^sdl2.Renderer) {
    free_all(context.allocator)

    game^ = {}

    assets = assets_
    sdl = sdl_
    
    entities = make(Entities)
    lasers = make(Lasers)
    explosions = make(Explosions)

    // the black hole
    black_hole: Entity
    set_type(&black_hole, .Black_Hole)
    black_hole.sprite = sprites.blackhole_sprite
    black_hole.density = 400
    black_hole.position = {}
    append(&entities, black_hole)

    // generate solar systems
    max_planet_size := f32(0)
    for s in sprites.planet {
        max_planet_size = max(max_planet_size, f32(vmax(s.size)))
    }
    max_planet_size *= math.sqrt(f32(2))
    
    max_sun_size := f32(0)
    for s in sprites.sun {
        max_sun_size = max(max_sun_size, f32(vmax(s.size)))
    }
    max_sun_size *= math.sqrt(f32(2))
    
    max_solar_system_planet_count :: 8

    create_orbit :: proc(using game: ^Game, pos: Vector2, max_orbiter_size: f32,
                         create_entity: proc(^Game, Vector2, Vector2)) {
        orbiter_count :: 8
        d := max_orbiter_size/2
        distance := d
        for angle := f32(0); angle < 360; angle += 360/orbiter_count {
            create_entity(game, pos + get_normal(angle) * distance, get_normal(angle + 90))
            distance += d
        }
    }
    
    max_solar_system_range =
        f32(max_solar_system_planet_count * (max_planet_size) + max_sun_size/2)

    max_solar_system_size := max_solar_system_range * 1.2
    
    ss_size := f32(max_solar_system_size)
    suns_index := len(entities)

    create_orbit(game, {}, max_solar_system_size, proc(using game: ^Game, pos: Vector2, velocity_normal: Vector2) {
        sun: Entity
        sun.type = .Sun
        sun.sprite = rand.choice(sprites.sun)
        sun.density = 300
        sun.position = pos
        sun.velocity = 50*velocity_normal
        append(&entities, sun)
    })
    
    // generate planets AFTER generating suns
    // so that they get drawn on top
    suns_end := len(entities)
    for i in suns_index ..< suns_end {
        sun := entities[i]

        create_orbit(game, sun.position, max_planet_size + 10,
                     proc(using game: ^Game, pos: Vector2, velocity_normal: Vector2) {
                         planet: Entity
                         planet.position = pos
                         planet.type = .Planet
                         planet.sprite = rand.choice(sprites.planet)
                         planet.density = 200
                         planet.velocity = 10*velocity_normal
                         append(&entities, planet)
                     })
    }

    // set world size
    for entity in entities {
        half_world_size = max(half_world_size, abs(entity.position.x), abs(entity.position.y))
    }

    half_world_size += 1000

    world_size = half_world_size * 2

    //fmt.println("half world size =", half_world_size)
    
    // generate stars
    star_count := int(world_size * 4)
    stars := make([]Star, star_count)
    for &star in stars {
        rand_coord :: proc(half_world_size: i32) -> i32 { return rand.int31_max(half_world_size*2) - half_world_size }

        n := i32(half_world_size)
        star.position.x = rand_coord(n)
        star.position.y = rand_coord(n)
        star.sprite = rand.choice(sprites.star)
    }

    slice.sort_by(stars, proc(a, b: Star) -> bool { return a.position.x < b.position.x })

    stars_bvh = make_bvh_rect(stars, star_get_rect)
    
    // init player
    player_index = len(entities)
    player: Entity
    set_type(&player, .Player)
    player.sprite = sprites.rocketship1_sprite
    player.density = 10
    player.position={0, .9*half_world_size}
    player.non_thrust_texture = sprites.rocketship1_sprite.texture
    player.thrust_texture = sprites.rocketship2_sprite.texture
    player.angle = 270
    append(&entities, player)

    // init enemies
    enemy_start_index = len(entities)
    max_enemies_per_solar_system :: 8
    for i in suns_index ..< suns_end {
        sun := entities[i]

        for _ in 0 ..< max_enemies_per_solar_system {
            enemy: Entity
            set_type(&enemy, .Enemy)
            enemy.sprite = rand.choice(sprites.enemy)
            enemy.density = 10

            enemy.thrust_texture = enemy.sprite.texture
            enemy.non_thrust_texture = enemy.sprite.texture
            
            range := f32(max_solar_system_range)
            enemy.position.x = rand.float32_range(sun.position.x - range, sun.position.x + range)
            enemy.position.y = rand.float32_range(sun.position.y - range, sun.position.y + range)
            
            append(&entities, enemy)
        }
    }

    // other
    bvh_gravity_mem := make([]byte, 1024*1024)
    mem.arena_init(&bvh_gravity_maker.arena, bvh_gravity_mem[:])

    bvh_gravity_maker.entities = entities[:]
    bvh_gravity_maker.allocator = mem.arena_allocator(&bvh_gravity_maker.arena)
    bvh_gravity_thread = thread.create_and_start_with_poly_data(&bvh_gravity_maker, make_bvh_gravity_worker)

    player_lives = PLAYER_LIVES
}

apply_friction :: proc(using entity: ^Entity, dt: f32, friction := f32(3)) {
    velocity *= 1 / (1 + dt*friction)
}

apply_controls :: proc(game: ^Game, using entity: ^Entity, dt: f32, controls: Controls) {
    if .Forward in controls {
        texture = thrust_texture
    } else {
        texture = non_thrust_texture
    }

    da := 200*dt
    if .Left  in controls do angle -= da
    if .Right in controls do angle += da

    for angle > 360 do angle -= 360
    for angle <   0 do angle += 360

    //precision :: 5
    //angle = math.round(angle / precision) * precision

    normal := get_normal(angle)
    
    if .Forward in controls {
        mag :: 100
        acceleration =  mag*normal
    }

    if .Brakes in controls {
        apply_friction(entity, dt)
    }

    if .Fire in controls {
        if game.laser_timer <= 0 {
            laser: Laser
            
            laser.position = position
            laser.position += normal*(f32(size.x)*.4)
            laser.position += normal*(f32(game.sprites.laser.size.x)*.5)
            laser.normal = normal
            laser.angle = angle
            append(&game.lasers, laser)

            game.laser_timer = LASER_TIMEOUT

            mixer.PlayChannel(-1, game.laser_sound, 0)
        }
    }
}

add_explosion :: proc(using game: ^Game, pos: Vector2) {
    append(&explosions, Explosion{pos, EXPLOSION_TIME})
    mixer.PlayChannel(-1, explosion_sound, 0)
}

update_game :: proc(using game: ^Game, dt: f32, controls: Controls) {
    if laser_timer > 0 do laser_timer -= dt

    total_time += dt
    
    player_in_iframes := player_iframe_timer > 0
    
    // update
    bvh_aabb := make_bvh_rect(entities[:], entity_get_rect, context.temp_allocator)

    thread.join(bvh_gravity_thread)
    
    // update player
    player := &entities[player_index]
    if !player_is_dead {
        if player_lives <= 0 {
            add_explosion(game, player.position)
            player_is_dead = true
            player_explosion_timer = EXPLOSION_TIME
        }
        apply_controls(game, player, dt, controls)
    } else {
        player_explosion_timer -= dt
        if player_explosion_timer <= 0 {
            state = .Game_Over
            return
        }
    }

    if len(entities[enemy_start_index:]) == 0 {
        you_win = true
        state = .Game_Over
        return
    }
    
    if player_iframe_timer > 0 do player_iframe_timer -= dt
    
    // enemy ai
    for &enemy in entities[enemy_start_index:] {
        using linalg
        
        when ODIN_DEBUG do assert(enemy.type == .Enemy)

        controls: Controls

        // TODO: We could let enemies fire lasers here if we wanted to...
        if distance(player.position, enemy.position) > f32(max_solar_system_range) {
            controls += {.Brakes}
        } else {
            enemy_to_player := player.position - enemy.position

            angle_to_player_radians := atan2(enemy_to_player.y, enemy_to_player.x)
            angle_to_player := math.to_degrees(angle_to_player_radians)
            
            d := angle_diff(enemy.angle, (angle_to_player))

            sigma :: 10
            
            if d > -sigma && d < sigma {
                controls += {.Forward}
            } else {
                if d > 0 {
                    controls += {.Right}
                } else {
                    controls += {.Left}
                }
            }
        }
        apply_controls(game, &enemy, dt, controls)
    }

    for &laser in lasers {
        laser.position += laser.normal*LASER_VELOCITY*dt
    }

    bvh_gravity := bvh_gravity_maker.result
    
    // do gravity
    for &entity in entities {
        @static stack: []BVH_Gravity
        @static stack_is_allocated := false
        count: int

        if !stack_is_allocated {
            stack_is_allocated = true
            stack = make([]BVH_Gravity, len(entities))
        }

        stack[count] = bvh_gravity^; count += 1
        
        for count > 0 {
            count -= 1
            bvh := stack[count]

            if !point_in_cirlce(bvh.range, entity.position) do continue
            
            switch v in bvh.variant {
                case BVH_Gravity_Internal:
                    stack[count] = v.left^; count += 1
                    stack[count] = v.right^; count += 1
                    
                case ^Entity:
                    if v == &entity do continue
                    entity.acceleration += get_gravity_accel(v^, entity)
            }
        }
    }
    
    // do collisions
    do_border_collisions :: proc(using game: ^Game, using entity: ^Entity, dt: f32) {
        controls: Controls
        d_veloctiy: Vector2
        mag :: 100
        do_friction := false
        for coord, i in position {
            if coord < -half_world_size {
                do_friction = true
                d_veloctiy[i] += mag
            }
            if coord > half_world_size {
                do_friction = true
                d_veloctiy[i] -= mag
            }
        }
        if do_friction do apply_friction(entity, dt, 9)
        velocity += d_veloctiy*dt
    }

    //do_border_collisions(game, player, dt)

    for &entity in entities {
        do_border_collisions(game, &entity, dt)
    }

    for laser, i in lasers {
        if laser.position.x < -half_world_size ||
            laser.position.x >  half_world_size ||
            laser.position.y < -half_world_size ||
            laser.position.y >  half_world_size {
                unordered_remove(&lasers, i)
            }
    }

    for &explosion, i in explosions {
        explosion.timer -= dt
        if explosion.timer < 0 do unordered_remove(&explosions, i)
    }
    
    for &enemy, enemy_offset in entities[enemy_start_index:] {
        when ODIN_DEBUG do assert(enemy.type == .Enemy)

        for laser, i in lasers {
            laser_rect := Rotated_Rect{laser.position, laser.angle, sprites.laser.size}
            enemy_rect := Rotated_Rect{enemy.position, enemy.angle, enemy.size}
            if rotated_rects_intersect(laser_rect, enemy_rect) {
                add_explosion(game, enemy.position)
                
                unordered_remove(&lasers, i)
                unordered_remove(&entities, enemy_start_index + enemy_offset)

                break
            }
        }
    }
    
    if !player_in_iframes {
        for &enemy in entities[enemy_start_index:] {
            when ODIN_DEBUG do assert(enemy.type == .Enemy)
            
            if entities_intersect(player^, enemy) {
                player_iframe_timer = PLAYER_IFRAMES_TIME
                player_lives -= 1
                mixer.PlayChannel(-1, hit_sound, 0)
                break
            }
        }
    }

    // black hole index == 0
    // do not update the black hole's position
    for &entity, i in entities[1:] {
        using entity

        if entity.type == .Sun do continue
        
        position += velocity*dt + 0.5*acceleration*dt*dt
        velocity += 0.5*(acceleration + previous_acceleration)*dt

        using linalg
        
        velocity_magnitude := length(velocity)
        if velocity_magnitude > MAX_VELOCITY {
            velocity = normalize0(velocity)*MAX_VELOCITY
        }
        
        previous_acceleration = acceleration
        acceleration = {}
    }

    thread.start(bvh_gravity_thread)
    
    if !player_is_dead { // set camera
        using linalg
        
        max_camera_distance :: 0.4*min(SCREEN_WIDTH, SCREEN_HEIGHT)
        max_velocity :: 100

        t := length(player.velocity) / max_velocity
        t = clamp(t, 0, 1)
        camera = player.position + max_camera_distance*t*normalize0(player.velocity)
        camera -= SCREEN_SIZE*.5
    }
}


load_embedded_file :: proc($path: string) -> ^sdl2.RWops {
    raw_slice :: #load(path)
    return sdl2.RWFromConstMem(raw_data(raw_slice), i32(len(raw_slice)))
}


load_font :: proc(size: i32) -> ^ttf.Font {
    rw := load_embedded_file("../assets/LCDBlock.ttf")
    return ttf.OpenFontRW(rw, false, size)
}

load_sound :: proc($path: string, turn_down_please := false) -> ^mixer.Chunk {
    result := mixer.LoadWAV_RW(load_embedded_file("../assets/" + path + ".wav"), false)

    if turn_down_please {
        mixer.VolumeChunk(result, mixer.MAX_VOLUME/8)
    }
    
    return result
}

main :: proc() {
    sdl2.Init(sdl2.INIT_EVERYTHING)

    window_width := i32(SCREEN_WIDTH)
    window_height := i32(SCREEN_HEIGHT)
    
    display_mode: sdl2.DisplayMode
    err := sdl2.GetDesktopDisplayMode(0, &display_mode)
    if err == 0 {
        for {
            new_window_width  := window_width + SCREEN_WIDTH
            new_window_height := window_height + SCREEN_HEIGHT

            if new_window_width > display_mode.w || new_window_height > display_mode.h {
                break
            }

            window_width = new_window_width
            window_height = new_window_height
        }
    }
    
    window_flags := sdl2.WindowFlags{}
    window := sdl2.CreateWindow("Gravattack", sdl2.WINDOWPOS_CENTERED, sdl2.WINDOWPOS_CENTERED,
                                window_width, window_height,
                                window_flags)

    sdl := sdl2.CreateRenderer(window, -1, {.SOFTWARE})

    renderer_info: sdl2.RendererInfo
    sdl2.GetRendererInfo(sdl, &renderer_info)
    texture_format := renderer_info.texture_formats[0]
    screen_texture := sdl2.CreateTexture(sdl, texture_format, .TARGET, SCREEN_WIDTH, SCREEN_HEIGHT)

    assets: Assets

    // load sprites
    assets.sprites.heart = load_sprite(sdl, "heart")
    assets.sprites.laser = load_sprite(sdl, "lazer2")
    assets.sprites.arrow = load_sprite(sdl, "arrow")
    
    assets.sprites.explosion[0] = load_sprite(sdl, "frame_0_delay-0.1s")
    assets.sprites.explosion[1] = load_sprite(sdl, "frame_1_delay-0.1s")
    assets.sprites.explosion[2] = load_sprite(sdl, "frame_2_delay-0.1s")
    assets.sprites.explosion[3] = load_sprite(sdl, "frame_3_delay-0.1s")
    assets.sprites.explosion[4] = load_sprite(sdl, "frame_4_delay-0.1s")
    assets.sprites.explosion[5] = load_sprite(sdl, "frame_5_delay-0.1s")
    assets.sprites.explosion[6] = load_sprite(sdl, "frame_6_delay-0.1s")
    assets.sprites.explosion[7] = load_sprite(sdl, "frame_7_delay-0.1s")
    assets.sprites.explosion[8] = load_sprite(sdl, "frame_8_delay-0.1s")
    
    assets.sprites.rocketship1_sprite = load_sprite(sdl, "playership2straight")
    assets.sprites.rocketship2_sprite = load_sprite(sdl, "playership2straight")

    assets.sprites.star = []Sprite {
        load_sprite(sdl, "star1_background"),
        load_sprite(sdl, "star2_background"),
        load_sprite(sdl, "star3_background"),
    }

    assets.sprites.sun = []Sprite {
        load_sprite(sdl, "sun"),
        load_sprite(sdl, "smallstar"),
    }

    assets.sprites.planet = []Sprite {
        load_sprite(sdl, "aqua"),
        load_sprite(sdl, "cool"),
        load_sprite(sdl, "dwarfplanet"),
        load_sprite(sdl, "horizantalringworld"),
        load_sprite(sdl, "planetBob"),
        load_sprite(sdl, "smalltoroidalearth"),
        load_sprite(sdl, "Will"),
        
        load_sprite(sdl, "moon"),
        load_sprite(sdl, "gasgiant"),
        load_sprite(sdl, "ringworld"),
    }

    assets.sprites.blackhole_sprite = load_sprite(sdl, "blackhole")

    assets.sprites.enemy = []Sprite {
        load_sprite(sdl, "enemy1"),
        load_sprite(sdl, "enemy2"),
        load_sprite(sdl, "nya"),
    }
    
    // load font
    // TODO: build into exe
    ttf.Init()
    assets.font = load_font(FONT_HEIGHT)
    assets.font_smaller = load_font(FONT_SMALLER_HEIGHT)

    // load music
    mixer.Init({})
    mixer.Volume(-1, mixer.MAX_VOLUME/2)

    mixer.OpenAudio(44100, mixer.DEFAULT_FORMAT, 2, 4096)
    
    music := load_sound("music")

    if music == nil {
        fmt.eprintln("Error loading music:", sdl2.GetError())
    }
    
    mixer.PlayChannel(-1, music, -1)

    // load sounds
    assets.laser_sound = load_sound("laser_sound", true)
    assets.hit_sound = load_sound("hit_sound", true)
    assets.explosion_sound = load_sound("explosion_sound", true)
    
    // main game loop
    previous_tick := sdl2.GetPerformanceCounter()
    tick_freq := sdl2.GetPerformanceFrequency()

    game := &Game{}
    game.assets = assets
    game.sdl = sdl
        
    main_loop: for {
        current_tick := sdl2.GetPerformanceCounter()
        dt := (f32(current_tick - previous_tick) / f32(tick_freq))

        previous_tick = current_tick

        free_all(context.temp_allocator)
        
        controls: Controls
        
        // process input
        event: sdl2.Event
        start_was_pressed := false
        for sdl2.PollEvent(&event) {
            if event.type ==  .QUIT do break main_loop

            if event.type == .KEYDOWN {
                if event.key.keysym.sym == .RETURN {
                    if event.key.state == sdl2.PRESSED do start_was_pressed = true
                }
            }
        }

        {
            num_keys: i32
            keyboard_state := sdl2.GetKeyboardState(&num_keys)
            
            keymap :: [](struct {scancode: sdl2.Scancode, control: Control}) {
                {sdl2.Scancode.UP,    .Forward},
                {sdl2.Scancode.DOWN,  .Brakes},
                {sdl2.Scancode.LEFT,  .Left},
                {sdl2.Scancode.RIGHT, .Right},
                {sdl2.Scancode.X,     .Fire},
                {sdl2.Scancode.Z,     .Fire},
            }

            for entry in keymap {
                using entry
                if keyboard_state[scancode] != 0 do controls += {control}
            }
        }

        // update
        switch game.state {
            case .Start_Screen:
                if start_was_pressed {
                    init_game(game, assets, sdl)
                    game.state = .Playing_Game
                }
                
            case .Playing_Game:
                update_game(game, dt, controls)
                
            case .Game_Over:
                if start_was_pressed {
                    game.state = .Start_Screen
                }
        }

        // draw
        sdl2.SetRenderTarget(sdl, screen_texture)

        draw_lines :: proc(using game: Game, lines: []cstring) {
                set_draw_color(sdl, 0x346856)
                sdl2.RenderClear(sdl)
                draw_centered_lines(game, lines)
        }
        
        switch game.state {
            case .Start_Screen:
                lines := []cstring {
                    "Gravattack!",

                    "Accel - UP",
                    "Brakes - DOWN",
                    "Left/Right - Turn",
                    "Z or X - Fire",
                    "Press Start"
                }
                draw_lines(game^, lines)
                
            case .Playing_Game:
                draw_game(game^, dt)
                
            case .Game_Over:
                if game.you_win {
                    lines := []cstring {
                        "You Win!",
                        fmt.ctprintf("Time: {} s", game.total_time),

                        "Art by Seiso",
                        "Everything else by Jelly",
                        "Press Start to play again",
                    }
                    draw_lines(game^, lines)
                } else {
                    draw_game(game^, dt)
                    draw_title_text(game^, "GAME OVER")
                }
        }

        sdl2.SetRenderTarget(sdl, nil)
        sdl2.RenderCopy(sdl, screen_texture, nil, nil)
        when DRAW_FRAME_RATE { // draw frame rate
            frame_rate := 1 / dt
            draw_text(game^, 0xffffff, {5,5}, fmt.ctprintf("{} {}", dt*1000, frame_rate))
        }
        sdl2.RenderPresent(sdl)
    }
}
