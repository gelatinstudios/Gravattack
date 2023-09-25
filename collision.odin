
package gbjam_space_game

import "core:math/linalg"

rects_intersect :: proc(a, b: Rect) -> bool {
    if (a.maxs[0] < b.mins[0] || a.mins[0] > b.maxs[0]) do return false
    if (a.maxs[1] < b.mins[1] || a.mins[1] > b.maxs[1]) do return false
    return true
}

point_in_cirlce :: #force_inline proc(circle: Circle, p: Vector2) -> bool {
    return linalg.length2(p-circle.position) < square(circle.radius)
}

get_vertices_bare :: proc(position: Vector2, angle: f32, size: Vector2_Int) -> [4]Vector2 {
    x_axis := get_normal(angle)
    y_axis := get_normal(angle + 90)
    w := f32(size.x)*.5
    h := f32(size.y)*.5
    return {
        position - w*x_axis - h*y_axis,
        position - w*x_axis + h*y_axis,
        position + w*x_axis + h*y_axis,
        position + w*x_axis - h*y_axis,
    }
}

get_vertices_entity :: proc(using entity: Entity) -> [4]Vector2 {
    return get_vertices_bare(position, angle, size)
}

get_vertices_rotated_rect :: proc(using r: Rotated_Rect) -> [4]Vector2 {
    return get_vertices_bare(position, angle, size)
}

get_vertices :: proc { get_vertices_bare, get_vertices_entity, get_vertices_rotated_rect }

Rotated_Rect :: struct {
    position: Vector2, // center
    angle: f32,
    size: Vector2_Int,
}

rotated_rects_intersect :: proc(a, b: Rotated_Rect) -> bool {
        project :: proc(rect: [4]Vector2, axis: Vector2) -> (f32, f32) {
        min_projection := max(f32)
        max_projection := min(f32)

        for vertex in rect {
            projection := linalg.dot(vertex, axis)
            min_projection = min(min_projection, projection)
            max_projection = max(max_projection, projection)
        }

        return min_projection, max_projection
    }
    
    axes := []Vector2 {
        get_normal(a.angle),
        get_normal(a.angle + 90),
        get_normal(b.angle),
        get_normal(b.angle + 90),
    }

    a_vertices := get_vertices(a)
    b_vertices := get_vertices(b)

    for axis in axes {
        min_a, max_a := project(a_vertices, axis)
        min_b, max_b := project(b_vertices, axis)

        if max_a < min_b || max_b < min_a do return false
    }

    return true
}

entities_intersect :: proc(a, b: Entity) -> bool {
    return rotated_rects_intersect({a.position, a.angle, a.size}, {b.position, b.angle, b.size})
}
