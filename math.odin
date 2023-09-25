
package gbjam_space_game

import "core:math"

Vector2 :: [2]f32
Vector2_Int :: [2]i32

max_vector2 :: proc(v: Vector2) -> f32 { return max(v.x, v.y) }
max_vector2_int :: proc(v: Vector2_Int) -> i32 { return max(v.x, v.y) }

vmax :: proc{ max_vector2, max_vector2_int }

// angle in degrees!!!
get_normal :: proc(angle: f32) -> Vector2 {
    using math
    a := to_radians(angle)
    return {cos(a), sin(a)}
}

get_angle :: proc(normal: Vector2) -> f32 {
    angle := math.to_degrees(math.atan2(normal.y, normal.x))
    if angle < 0 do angle += 360
    return angle
}

vector2 :: proc(v: Vector2_Int) -> Vector2 {
    return {f32(v.x), f32(v.y)}
}

square :: proc(x: $T) -> T { return x*x }  

angle_diff :: proc(angle1, angle2: f32) -> f32 {
    diff0 := angle2 - angle1;
    diff1 := angle2 - angle1 + 360;
    diff2 := angle2 - angle1 - 360;
    
    fabdiff0 := abs(diff0);
    fabdiff1 := abs(diff1);
    fabdiff2 := abs(diff2);
    
    if      (fabdiff0 < fabdiff1 && fabdiff0 < fabdiff2) do return diff0;
    else if (fabdiff1 < fabdiff0 && fabdiff1 < fabdiff2) do return diff1;
    else if (fabdiff2 < fabdiff0 && fabdiff2 < fabdiff1) do return diff2;
    return 0.0;
}

get_mass :: proc(using entity: Entity) -> f32 {
    return f32(size.x) * f32(size.y) * density
}
