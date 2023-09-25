
package gbjam_space_game

import "core:mem"
import "core:math/linalg"
import "core:slice"

Rect :: struct {
    mins: Vector2,
    maxs: Vector2,
}

Circle :: struct {
    position: Vector2,
    radius: f32,
}

BVH_Internal :: struct($T: typeid) { left, right: ^T }

BVH_Rect_Internal :: struct($T: typeid) { using _bvh: BVH_Internal(BVH_Rect(T)) }

BVH_Rect :: struct($T: typeid) {
    rect: Rect,
    variant: union { BVH_Rect_Internal(T), T }
}

// TODO: is it worth it to look into doing these non-recursively?

make_bvh_rect :: proc(things: []$T, get_rect: proc(T) -> Rect, allocator := context.allocator) -> ^BVH_Rect(T) {
    result := new(BVH_Rect(T), allocator)
        
    if len(things) == 1 {
        thing := things[0]
        result.rect = get_rect(thing)
        result.variant = thing
        return result
    }

    half := len(things)/2
    left  := make_bvh_rect(things[:half], get_rect, allocator)
    right := make_bvh_rect(things[half:], get_rect, allocator)
        
    result.rect.mins.x = min(left.rect.mins.x, right.rect.mins.x)
    result.rect.mins.y = min(left.rect.mins.y, right.rect.mins.y)
    result.rect.maxs.x = max(left.rect.maxs.x, right.rect.maxs.x)
    result.rect.maxs.y = max(left.rect.maxs.y, right.rect.maxs.y)
    
    result.variant = BVH_Rect_Internal(T) {
        left = left,
        right = right,
    }
    
    return result
}

BVH_Gravity_Internal :: distinct BVH_Internal(BVH_Gravity)


BVH_Gravity :: struct {
    range: Circle,
    variant: union { BVH_Gravity_Internal, ^Entity },
}
    
make_bvh_gravity :: proc(entities: []Entity, allocator: mem.Allocator) -> ^BVH_Gravity {
    result := new(BVH_Gravity, allocator)

    assert(len(entities) > 0)
    
    if len(entities) == 1 {
        entity := entities[0]
        result.range = get_gravity_circle(entity)
        result.variant = &entities[0]
        return result
    }

    // TODO: maybe look at using welz's algorithm
    half := len(entities)/2

    left  := make_bvh_gravity(entities[:half], allocator)
    right := make_bvh_gravity(entities[half:], allocator)

    ranges := []Circle{left.range, right.range}
    for range in ranges {
        result.range.position += range.position*.5
    }
    for range in ranges {
        result.range.radius =
            max(result.range.radius, linalg.distance(result.range.position, range.position) + range.radius)
    }
    
    result.variant = BVH_Gravity_Internal {
        left  = left,
        right = right,
    }
    
    return result
}

BVH_Gravity_Maker :: struct {
    entities: []Entity,
    arena: mem.Arena,
    allocator: mem.Allocator,
    result: ^BVH_Gravity,
}

make_bvh_gravity_worker :: proc(using m: ^BVH_Gravity_Maker) {
    free_all(allocator)
    result = make_bvh_gravity(entities, allocator)
}
