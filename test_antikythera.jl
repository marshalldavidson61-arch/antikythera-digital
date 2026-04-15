# ==========================================================================
# THE ANTIKYTHERA DIFF-ENGINE — COMPREHENSIVE TEST SUITE v2.0
# ==========================================================================
# Run: julia test_antikythera.jl
#
# Full coverage of every feature, edge case, and intractable operation.
# If this passes, the machine lives.
# ==========================================================================

include("antikythera_diff_engine.jl")
using Printf
using LinearAlgebra

# ==========================================================================
# TEST INFRASTRUCTURE
# ==========================================================================

mutable struct TestResults
    passed::Int
    failed::Int
    errors::Vector{String}
end

const TEST = TestResults(0, 0, String[])

function test(name::String, condition::Bool, detail::String="")
    if condition
        TEST.passed += 1
        println("  ✅ $(name)")
    else
        TEST.failed += 1
        push!(TEST.errors, "$(name): $(detail)")
        println("  ❌ $(name) — $(detail)")
    end
end

function test_throws(name::String, expected_msg::String, f::Function)
    try
        f()
        TEST.failed += 1
        push!(TEST.errors, "$(name): Expected exception but none thrown")
        println("  ❌ $(name) — No exception thrown")
    catch e
        if isa(e, MachineCrunch) && occursin(lowercase(expected_msg), lowercase(e.message))
            TEST.passed += 1
            println("  ✅ $(name) — Correctly threw: $(e.message)")
        else
            TEST.failed += 1
            push!(TEST.errors, "$(name): Wrong exception — $(e)")
            println("  ❌ $(name) — Wrong exception: $(e)")
        end
    end
end

function section(title::String)
    println("\n" * "═"^63)
    println("  $(title)")
    println("═"^63)
end

# ==========================================================================
# SECTION 1: MACHINE INITIALIZATION
# ==========================================================================
section("1. MACHINE INITIALIZATION")

machine = AntikytheraMap()
test("Default slack",    machine.slack == 0.01)
test("Default throttle", machine.throttle_clamp == 0.0)
test("Empty gears",      isempty(machine.gears))
test("Zero query count", machine.query_count == 0)

machine_tight = AntikytheraMap(0.001)
test("Custom slack 0.001", machine_tight.slack == 0.001)

machine_fine = AntikytheraMap(0.0001)
test("Fine slack 0.0001", machine_fine.slack == 0.0001)

test_throws("Zero slack rejected",     "POSITIVE", () -> AntikytheraMap(0.0))
test_throws("Negative slack rejected", "POSITIVE", () -> AntikytheraMap(-0.1))

# ==========================================================================
# SECTION 2: GEAR CASTING — LIBRARY + CUSTOM
# ==========================================================================
section("2. GEAR CASTING")

# Default preset: 4 standard gears
jit_cast_gears!(machine)
test("Default preset gear count", length(machine.gears) == 4)
test("Sphere loaded",       haskey(machine.gears, :Sphere))
test("Torus loaded",        haskey(machine.gears, :Torus))
test("Gyroid loaded",       haskey(machine.gears, :Gyroid))
test("TwistedTorus loaded", haskey(machine.gears, :TwistedTorus))

# All preset: full library
machine_all = AntikytheraMap(0.001)
jit_cast_gears!(machine_all; preset="all")
test("All preset >= 11 shapes", length(machine_all.gears) >= 11)

# Single gear casting
machine2 = AntikytheraMap(0.001)
cast_single!(machine2, :MySphere, "sphere", [3.0])
test("Single sphere cast",      haskey(machine2.gears, :MySphere))
test("Single sphere params",    machine2.gears[:MySphere].teeth_params == [3.0])
test("Single sphere ndims",     machine2.gears[:MySphere].ndims == 3)

# All library shapes individually
for shape in ["sphere", "torus", "box", "cylinder", "gyroid", "schwarz",
              "twisted_torus", "cone", "capsule", "plane", "ellipsoid"]
    machine_shape = AntikytheraMap(0.001)
    cast_single!(machine_shape, :Test, shape, copy(GEAR_LIBRARY[shape][2]))
    test("Shape '$(shape)' casts", haskey(machine_shape.gears, :Test))
end

# Invalid shape
test_throws("Invalid shape rejected", "NO SUCH SHAPE",
    () -> cast_single!(machine2, :Bad, "unicorn", [1.0]))

# Unknown preset
test_throws("Unknown preset rejected", "UNKNOWN PRESET",
    () -> jit_cast_gears!(machine2; preset="superspecial"))

# Cog type coercion
cog = Cog(:TypeTest, sdf_sphere, [5]; ndims=3)
test("Int param coerced to Float64",   cog.teeth_params == [5.0])
test("Float64 vector stored",          isa(cog.teeth_params, Vector{Float64}))

# Empty params rejected
test_throws("Empty params rejected", "NO TEETH",
    () -> Cog(:Ghost, sdf_sphere, Float64[]; ndims=3))

# ==========================================================================
# SECTION 3: THROTTLE AND FLOW CONTROL
# ==========================================================================
section("3. THROTTLE AND FLOW CONTROL")

machine.throttle_clamp = 0.0
test_throws("Probe blocked at throttle=0",    "THROTTLE SHUT",
    () -> probe(machine, :Sphere, [0.0, 0.0, 0.0]))
test_throws("Gradient blocked at throttle=0", "THROTTLE SHUT",
    () -> gradient(machine, :Sphere, [5.0, 0.0, 0.0]))

machine.throttle_clamp = 0.5
result = probe(machine, :Sphere, [0.0, 0.0, 0.0])
test("Probe works when throttle=0.5", isapprox(result, -5.0; atol=0.01))

machine.throttle_clamp = 1.0
result2 = probe(machine, :Sphere, [0.0, 0.0, 0.0])
test("Probe works when throttle=1.0", isapprox(result2, -5.0; atol=0.01))

machine.throttle_clamp = 0.5

# ==========================================================================
# SECTION 4: PROBE OPERATION (RAW SDF VALUES)
# ==========================================================================
section("4. PROBE — RAW SDF VALUES")

# Sphere: inside / surface / outside
test("Sphere at center = -radius",    isapprox(probe(machine, :Sphere, [0.0,0.0,0.0]), -5.0; atol=0.01))
test("Sphere on surface = 0",         abs(probe(machine, :Sphere, [5.0,0.0,0.0])) < 0.01)
test("Sphere outside = positive",     probe(machine, :Sphere, [10.0,0.0,0.0]) > 0)
test("Sphere outside value",          isapprox(probe(machine, :Sphere, [10.0,0.0,0.0]), 5.0; atol=0.01))

# Torus: hole / tube surface / outside
test("Torus in hole = outside",       probe(machine, :Torus, [0.0,0.0,0.0]) > 0)
test("Torus on tube surface ≈ 0",     abs(probe(machine, :Torus, [10.0,0.0,0.0])) < 0.01)
test("Torus inside tube = negative",  probe(machine, :Torus, [8.0,0.0,0.0]) < 0)

# Gyroid at origin = 0 (minimal surface passes through origin)
test("Gyroid at origin ≈ 0",          isapprox(probe(machine, :Gyroid, [0.0,0.0,0.0]), 0.0; atol=0.01))

# Box
machine_box = AntikytheraMap(0.001)
machine_box.throttle_clamp = 0.5
cast_single!(machine_box, :Box, "box", [3.0, 4.0, 5.0])
test("Box at origin = negative (inside)",  probe(machine_box, :Box, [0.0,0.0,0.0]) < 0)
test("Box far away = positive (outside)", probe(machine_box, :Box, [10.0,0.0,0.0]) > 0)
test("Box on face ≈ 0",                   abs(probe(machine_box, :Box, [3.0,0.0,0.0])) < 0.01)

# Cylinder
machine_cyl = AntikytheraMap(0.001)
machine_cyl.throttle_clamp = 0.5
cast_single!(machine_cyl, :Cyl, "cylinder", [3.0, 5.0])
test("Cylinder inside = negative",        probe(machine_cyl, :Cyl, [0.0,0.0,0.0]) < 0)
test("Cylinder outside = positive",       probe(machine_cyl, :Cyl, [10.0,0.0,0.0]) > 0)

# New shapes
machine_new = AntikytheraMap(0.001)
machine_new.throttle_clamp = 0.5
cast_single!(machine_new, :Capsule,   "capsule",   [2.0, 4.0])
cast_single!(machine_new, :Plane,     "plane",     [0.0, 1.0, 0.0, 0.0])
cast_single!(machine_new, :Ellipsoid, "ellipsoid", [4.0, 2.0, 3.0])
test("Capsule at origin = negative (inside)",    probe(machine_new, :Capsule, [0.0,0.0,0.0]) < 0)
test("Capsule far away = positive (outside)",    probe(machine_new, :Capsule, [10.0,0.0,0.0]) > 0)
test("Plane at y=1 = 1.0",                      isapprox(probe(machine_new, :Plane, [0.0,1.0,0.0]), 1.0; atol=0.01))
test("Plane at y=-1 = -1.0",                    isapprox(probe(machine_new, :Plane, [0.0,-1.0,0.0]), -1.0; atol=0.01))
test("Ellipsoid on major axis ≈ 0",              abs(probe(machine_new, :Ellipsoid, [4.0,0.0,0.0])) < 0.02)
test("Ellipsoid inside = negative",              probe(machine_new, :Ellipsoid, [0.0,0.0,0.0]) < 0)

# Dimension mismatch
test_throws("Dimension mismatch caught", "3D",
    () -> probe(machine, :Sphere, [0.0, 0.0]))

# Query count increments
before = machine.query_count
probe(machine, :Sphere, [5.0,0.0,0.0])
test("Query count increments", machine.query_count == before + 1)

# ==========================================================================
# SECTION 5: GRADIENT (SPATIAL DIFFERENTIATION)
# ==========================================================================
section("5. GRADIENT — SPATIAL DIFFERENTIATION")

# Sphere surface normal = gradient (normalized)
g_surf = gradient(machine, :Sphere, [5.0, 0.0, 0.0])
test("Sphere gradient |g| ≈ 1",     isapprox(norm(g_surf), 1.0; atol=0.02))
test("Sphere gradient x-component", isapprox(g_surf[1], 1.0; atol=0.05))
test("Sphere gradient y≈0, z≈0",    abs(g_surf[2]) < 0.05 && abs(g_surf[3]) < 0.05)

g_y = gradient(machine, :Sphere, [0.0, 5.0, 0.0])
test("Sphere gradient y-axis direction", isapprox(g_y[2], 1.0; atol=0.05))

g_z = gradient(machine, :Sphere, [0.0, 0.0, 5.0])
test("Sphere gradient z-axis direction", isapprox(g_z[3], 1.0; atol=0.05))

# Torus gradient on outer equator
g_torus = gradient(machine, :Torus, [10.0, 0.0, 0.0])
test("Torus gradient |g| ≈ 1",      isapprox(norm(g_torus), 1.0; atol=0.02))
test("Torus gradient no NaN/Inf",   !any(isnan, g_torus) && !any(isinf, g_torus))

# Gyroid gradient at non-symmetric point
g_gyroid = gradient(machine, :Gyroid, [1.0, 1.0, 1.0])
test("Gyroid gradient no NaN/Inf",  !any(isnan, g_gyroid) && !any(isinf, g_gyroid))
test("Gyroid gradient nonzero",     norm(g_gyroid) > 0.01)

# TwistedTorus gradient — brutal for symbolic diff
g_twisted = gradient(machine, :TwistedTorus, [10.0, 0.0, 0.0])
test("TwistedTorus gradient no NaN", !any(isnan, g_twisted))
test("TwistedTorus gradient |g| > 0", norm(g_twisted) > 0.01)

# Plane has constant gradient = normal vector
g_plane = gradient(machine_new, :Plane, [3.14, 2.71, 1.41])
test("Plane gradient = [0,1,0]", isapprox(g_plane[2], 1.0; atol=0.01) &&
     abs(g_plane[1]) < 0.01 && abs(g_plane[3]) < 0.01)

# ==========================================================================
# SECTION 6: SURFACE NORMAL
# ==========================================================================
section("6. SURFACE NORMAL")

n_sphere = surface_normal(machine, :Sphere, [5.0, 0.0, 0.0])
test("Sphere normal unit length",   isapprox(norm(n_sphere), 1.0; atol=0.01))
test("Sphere normal x≈1",          isapprox(n_sphere[1], 1.0; atol=0.05))

n_torus = surface_normal(machine, :Torus, [10.0, 0.0, 0.0])
test("Torus normal unit length",   isapprox(norm(n_torus), 1.0; atol=0.02))

n_gyroid = surface_normal(machine, :Gyroid, [1.57, 0.0, 0.0])
test("Gyroid normal unit length",  isapprox(norm(n_gyroid), 1.0; atol=0.05))

# Zero gradient point → should auto-project to surface (not throw)
# The sphere origin [0,0,0] has zero gradient (inside, SDF=-5).
# surface_normal will project to the sphere surface before computing.
n_zero_start = surface_normal(machine, :Sphere, [0.0, 0.0, 0.0])
test("Normal at zero-gradient point: auto-projected, unit length",
    isapprox(norm(n_zero_start), 1.0; atol=0.01))

# ==========================================================================
# SECTION 7: CURVATURE (HESSIAN) — INTRACTABLE FOR SYMBOLIC DIFF
# ==========================================================================
section("7. CURVATURE — INTRACTABLE FOR SYMBOLIC DIFF")

# Sphere: mean ≈ 1/R = 0.2, Gaussian ≈ 1/R² = 0.04
# Both principal curvatures = 1/R → equal
curv = curvature(machine, :Sphere, [5.0, 0.0, 0.0])
test("Sphere mean curvature ≈ 1/R=0.2",  abs(curv.mean - 0.2) < 0.02)
test("Sphere Gaussian curv ≈ 1/R²=0.04", abs(curv.gaussian - 0.04) < 0.01)
test("Sphere principal curvatures equal", abs(curv.k1 - curv.k2) < 0.02)
test("Sphere k1 ≈ 0.2",                  abs(curv.k1 - 0.2) < 0.02)

# Torus: at outer equator [10,0,0], surface is on tube outer edge
# Use a surface point: [10,0,0] is at major radius + minor radius = on surface
curv_torus = curvature(machine, :Torus, [10.0, 0.0, 0.0])
test("Torus mean curvature computed",     !isnan(curv_torus.mean))
test("Torus Gaussian curvature computed", !isnan(curv_torus.gaussian))

# Gyroid: minimal surface → mean curvature should be ≈ 0
curv_gyroid = curvature(machine, :Gyroid, [1.0, 1.0, 1.0])
test("Gyroid curvature no NaN",           !isnan(curv_gyroid.mean))
test("Gyroid curvature finite",           !isinf(curv_gyroid.mean))

# Minimal surface property: mean curvature at origin ≈ 0
curv_gyroid_origin = curvature(machine, :Gyroid, [0.1, 0.1, 0.1])
test("Gyroid mean curvature ≈ 0 (minimal surface)", abs(curv_gyroid_origin.mean) < 0.5)

# TwistedTorus: nested trig composition — symbolic Hessian nightmare
curv_twisted = curvature(machine, :TwistedTorus, [10.0, 0.0, 0.0])
test("TwistedTorus curvature computed",   !isnan(curv_twisted.mean))

# Zero gradient → curvature auto-projects to surface (not throw)
# The sphere origin [0,0,0] has zero gradient. Auto-projected to surface before computing.
curv_zero_start = curvature(machine, :Sphere, [0.0, 0.0, 0.0])
test("Curvature at zero-gradient point: auto-projected, mean ≈ 1/R=0.2",
    abs(curv_zero_start.mean - 0.2) < 0.03)
test("Curvature at zero-gradient point: no NaN",
    !isnan(curv_zero_start.mean) && !isinf(curv_zero_start.mean))

# ==========================================================================
# SECTION 8: LAPLACIAN AND DIVERGENCE
# ==========================================================================
section("8. LAPLACIAN / DIVERGENCE")

lapl = laplacian(machine, :Sphere, [5.0, 0.0, 0.0])
test("Sphere Laplacian computed",     !isnan(lapl) && !isinf(lapl))

div_val = divergence(machine, :Sphere, [5.0, 0.0, 0.0])
test("Divergence == Laplacian",       isapprox(div_val, lapl; atol=1e-10))

lapl_gyroid = laplacian(machine, :Gyroid, [1.0, 1.0, 1.0])
test("Gyroid Laplacian computed",     !isnan(lapl_gyroid))

lapl_twisted = laplacian(machine, :TwistedTorus, [10.0, 0.0, 0.0])
test("TwistedTorus Laplacian computed", !isnan(lapl_twisted))

# Plane has Laplacian = 0 (linear function)
lapl_plane = laplacian(machine_new, :Plane, [1.0, 2.0, 3.0])
test("Plane Laplacian ≈ 0",           abs(lapl_plane) < 0.01)

# ==========================================================================
# SECTION 9: BOOLEAN OPERATIONS — CSG
# ==========================================================================
section("9. BOOLEAN OPERATIONS — DERIVATIVE DISCONTINUITY TERRITORY")

machine_csg = AntikytheraMap(0.001)
machine_csg.throttle_clamp = 0.5
cast_single!(machine_csg, :A, "sphere", [3.0])
cast_single!(machine_csg, :B, "sphere", [3.0])

# Union
boolean_union!(machine_csg, :UnionAB, :A, :B)
test("Union created",              haskey(machine_csg.gears, :UnionAB))
u_val = probe(machine_csg, :UnionAB, [0.0,0.0,0.0])
test("Union probe at origin",      !isnan(u_val) && u_val < 0)
u_grad = gradient(machine_csg, :UnionAB, [3.0,0.0,0.0])
test("Union gradient computed",    !any(isnan, u_grad))

# Intersect
boolean_intersect!(machine_csg, :IntersectAB, :A, :B)
test("Intersect created",          haskey(machine_csg.gears, :IntersectAB))
i_val = probe(machine_csg, :IntersectAB, [0.0,0.0,0.0])
test("Intersect probe works",      !isnan(i_val))

# Subtract
boolean_subtract!(machine_csg, :SubtractAB, :A, :B)
test("Subtract created",           haskey(machine_csg.gears, :SubtractAB))

# Gradient at min/max junction (the intractable point for symbolic AD)
junction_grad = gradient(machine_csg, :UnionAB, [2.9, 0.0, 0.0])
test("Gradient through CSG junction no NaN/Inf",
     !any(isnan, junction_grad) && !any(isinf, junction_grad))

# Curvature through boolean (extra brutal for symbolic diff)
curv_union = curvature(machine_csg, :UnionAB, [3.0, 0.0, 0.0])
test("Curvature through Union computed", !isnan(curv_union.mean))

# Nested boolean chain
cast_single!(machine_csg, :C, "sphere", [2.0])
boolean_union!(machine_csg, :UnionBC, :B, :C)
boolean_subtract!(machine_csg, :ComplexShape, :UnionAB, :UnionBC)
test("Nested boolean created",     haskey(machine_csg.gears, :ComplexShape))
complex_val = probe(machine_csg, :ComplexShape, [0.0, 0.0, 0.0])
test("Nested boolean probe works", !isnan(complex_val))

# ==========================================================================
# SECTION 10: SMOOTH BLEND
# ==========================================================================
section("10. SMOOTH BLEND — NO CLOSED-FORM GRADIENT")

blend!(machine_csg, :BlendAB, :A, :B, 2.0)
test("Blend created",                    haskey(machine_csg.gears, :BlendAB))

bval = probe(machine_csg, :BlendAB, [1.5, 0.0, 0.0])
test("Blend probe in fillet zone",       !isnan(bval))

bgrad = gradient(machine_csg, :BlendAB, [1.5, 0.0, 0.0])
test("Blend gradient computed",          !any(isnan, bgrad))

bcurv = curvature(machine_csg, :BlendAB, [3.0, 0.0, 0.0])
test("Blend curvature in fillet computed", !isnan(bcurv.mean))

# k=0 blend degenerates to hard boolean
blend!(machine_csg, :HardBlend, :A, :B, 0.0)
hval = probe(machine_csg, :HardBlend, [0.0, 0.0, 0.0])
test("k=0 blend = hard boolean",         isapprox(hval, u_val; atol=0.001))

# Negative k rejected
test_throws("Negative blend radius rejected", "BLEND RADIUS",
    () -> blend!(machine_csg, :BadBlend, :A, :B, -1.0))

# ==========================================================================
# SECTION 11: MORPH — INTERMEDIATE STATES WITH NO NAME
# ==========================================================================
section("11. MORPH — INTERMEDIATE STATES WITH NO NAME")

machine_morph = AntikytheraMap(0.001)
machine_morph.throttle_clamp = 0.5
cast_single!(machine_morph, :MS, "sphere", [5.0])

morph!(machine_morph, :MS, [10.0], 0.0)
test("Morph t=0 → unchanged",       isapprox(machine_morph.gears[:MS].teeth_params[1], 5.0; atol=0.001))

morph!(machine_morph, :MS, [10.0], 1.0)
test("Morph t=1 → target",          isapprox(machine_morph.gears[:MS].teeth_params[1], 10.0; atol=0.001))

machine_morph.gears[:MS].teeth_params[1] = 5.0
morph!(machine_morph, :MS, [10.0], 0.5)
test("Morph t=0.5 → midpoint",      isapprox(machine_morph.gears[:MS].teeth_params[1], 7.5; atol=0.001))

machine_morph.gears[:MS].teeth_params[1] = 5.0
morph!(machine_morph, :MS, [10.0], 0.25)
test("Morph t=0.25 → quarter",      isapprox(machine_morph.gears[:MS].teeth_params[1], 6.25; atol=0.001))

# Gradient still works after morphing
g_morphed = gradient(machine_morph, :MS, [7.5, 0.0, 0.0])
test("Gradient on morphed gear works",    !any(isnan, g_morphed))
test("Gradient on morphed gear |g| ≈ 1", isapprox(norm(g_morphed), 1.0; atol=0.05))

# Invalid morph params
test_throws("Morph t<0 rejected",    "MORPH t", () -> morph!(machine_morph, :MS, [10.0], -0.1))
test_throws("Morph t>1 rejected",    "MORPH t", () -> morph!(machine_morph, :MS, [10.0], 1.5))
test_throws("Morph wrong param count rejected", "PARAMS",
    () -> morph!(machine_morph, :MS, [10.0, 3.0], 0.5))

# Torus morph: 2 params
cast_single!(machine_morph, :MT, "torus", [8.0, 2.0])
morph!(machine_morph, :MT, [12.0, 3.0], 0.5)
test("Torus morph: major radius", isapprox(machine_morph.gears[:MT].teeth_params[1], 10.0; atol=0.001))
test("Torus morph: minor radius", isapprox(machine_morph.gears[:MT].teeth_params[2], 2.5; atol=0.001))

# ==========================================================================
# SECTION 12: FLOW — STREAMLINE TRACING
# ==========================================================================
section("12. FLOW — STREAMLINE THROUGH COMPLEX TOPOLOGY")

# Descent from outside sphere → should reach surface
flow_outside = flow(machine, :Sphere, [10.0, 0.0, 0.0]; steps=100, step_size=0.3, direction=:descent)
test("Flow descent from outside generates path", length(flow_outside) > 1)
test("Flow descent reaches sphere surface",      abs(probe(machine, :Sphere, flow_outside[end])) < 0.05)

# Ascent from inside sphere → should reach surface
flow_inside = flow(machine, :Sphere, [0.0, 0.0, 0.0]; steps=100, step_size=0.3, direction=:ascent)
test("Flow ascent from inside generates path",   length(flow_inside) > 1)
test("Flow ascent reaches sphere surface",       abs(probe(machine, :Sphere, flow_inside[end])) < 0.05)

# Descent on TwistedTorus from non-degenerate point
flow_twisted = flow(machine, :TwistedTorus, [0.0, 0.0, 0.0]; steps=100, step_size=0.3)
test("Flow on TwistedTorus from origin generates path", length(flow_twisted) > 1)
test("Flow on TwistedTorus reaches surface",            abs(probe(machine, :TwistedTorus, flow_twisted[end])) < 0.05)

# Gyroid flow
flow_gyroid = flow(machine, :Gyroid, [2.0, 2.0, 2.0]; steps=100, step_size=0.2)
test("Flow on Gyroid computed",                  length(flow_gyroid) > 1)

# Flow with explicit direction=:ascent
flow_ascent = flow(machine, :Sphere, [3.0, 0.0, 0.0]; steps=50, step_size=0.2, direction=:ascent)
test("Flow ascent generates path",               length(flow_ascent) > 1)

# ==========================================================================
# SECTION 13: LEVELSET (RAY MARCHING)
# ==========================================================================
section("13. LEVELSET — RAY-SURFACE INTERSECTION")

# Ray toward sphere (15,0,0) → (-1,0,0): should hit at distance 10
hit = levelset(machine, :Sphere, [15.0, 0.0, 0.0], [-1.0, 0.0, 0.0])
test("Ray hits sphere",           hit.hit)
test("Ray hit distance ≈ 10",     isapprox(hit.distance, 10.0; atol=0.1))
test("Ray hit point on surface",  abs(probe(machine, :Sphere, hit.point)) < 0.02)
test("Ray hit step count > 0",    hit.steps > 0)

# Ray away from sphere: should miss
miss = levelset(machine, :Sphere, [15.0, 0.0, 0.0], [1.0, 0.0, 0.0]; max_dist=20.0)
test("Ray misses sphere",         !miss.hit)

# Ray through Gyroid: periodic surface, should find intersection
gyroid_hit = levelset(machine, :Gyroid, [0.0, 0.0, -10.0], [0.0, 0.0, 1.0]; max_dist=20.0)
test("Gyroid ray result computed", gyroid_hit.steps > 0)

# Torus ray
torus_hit = levelset(machine, :Torus, [0.0, 0.0, 20.0], [0.0, 0.0, -1.0])
test("Torus ray computed",         torus_hit.steps > 0)

# Zero direction rejected
test_throws("Zero ray direction rejected", "ZERO",
    () -> levelset(machine, :Sphere, [0.0,0.0,0.0], [0.0,0.0,0.0]))

# ==========================================================================
# SECTION 14: GEODESIC — APPROXIMATE SURFACE DISTANCE
# ==========================================================================
section("14. GEODESIC — APPROXIMATE SURFACE DISTANCE")

geo = geodesic(machine, :Sphere, [5.0,0.0,0.0], [-5.0,0.0,0.0]; max_steps=300)
test("Geodesic on sphere computed",    length(geo.path) > 1)
test("Geodesic distance > 0",         geo.distance > 0)
# Half-circumference of sphere R=5: π*R ≈ 15.7
test("Geodesic distance reasonable",  geo.distance > 5.0 && geo.distance < 50.0)

geo_torus = geodesic(machine, :Torus, [10.0,0.0,0.0], [8.0,2.0,0.0]; max_steps=300)
test("Geodesic on Torus computed",     length(geo_torus.path) > 1)
test("Geodesic on Torus distance > 0", geo_torus.distance > 0)

geo_gyroid = geodesic(machine, :Gyroid, [1.0,0.0,0.0], [-1.0,0.0,0.0]; max_steps=200)
test("Geodesic on Gyroid computed",    length(geo_gyroid.path) > 1)

# ==========================================================================
# SECTION 15: USER-DEFINED SDF — RUNTIME GEOMETRY
# ==========================================================================
section("15. USER-DEFINED SDF — RUNTIME GEOMETRY")

machine_user = AntikytheraMap(0.001)
machine_user.throttle_clamp = 0.5

# Sphere as user SDF
u1 = parse_user_sdf!(machine_user, "sqrt(x*x + y*y + z*z) - a", [3.0])
test("User SDF created",          haskey(machine_user.gears, u1))
test("User SDF probe at center",  isapprox(probe(machine_user, u1, [0.0,0.0,0.0]), -3.0; atol=0.1))
test("User SDF on surface ≈ 0",   abs(probe(machine_user, u1, [3.0,0.0,0.0])) < 0.05)

u1_grad = gradient(machine_user, u1, [3.0, 0.0, 0.0])
test("User SDF gradient computed",    !any(isnan, u1_grad))
test("User SDF gradient |g| ≈ 1",    isapprox(norm(u1_grad), 1.0; atol=0.1))

u1_curv = curvature(machine_user, u1, [3.0, 0.0, 0.0])
test("User SDF curvature computed",   !isnan(u1_curv.mean))

# Parametric torus as user SDF: sqrt((sqrt(x^2+z^2)-a)^2 + y^2) - b
u2 = parse_user_sdf!(machine_user, "sqrt((sqrt(x*x+z*z)-a)^2+y*y)-b", [6.0, 1.5])
test("User torus SDF created",        haskey(machine_user.gears, u2))
u2_grad = gradient(machine_user, u2, [7.5, 0.0, 0.0])
test("User torus gradient no NaN",    !any(isnan, u2_grad))

# No-param SDF: sin wave surface
u3 = parse_user_sdf!(machine_user, "sin(x) + cos(y) + sin(z)", [])
test("No-param user SDF created",     haskey(machine_user.gears, u3))
u3_grad = gradient(machine_user, u3, [1.0, 1.0, 1.0])
test("No-param SDF gradient",         !any(isnan, u3_grad))
u3_curv = curvature(machine_user, u3, [1.0, 1.0, 1.0])
test("No-param SDF curvature",        !isnan(u3_curv.mean))

# Ellipsoid SDF
u4 = parse_user_sdf!(machine_user, "sqrt(x*x/(a*a)+y*y/(b*b)+z*z/(b*b))-1", [4.0, 2.0])
test("User ellipsoid SDF created",    haskey(machine_user.gears, u4))

# Multiple params
u5 = parse_user_sdf!(machine_user, "sqrt(x*x+y*y+z*z) - a - b*0.1", [3.0, 1.0])
test("Multi-param user SDF created",  haskey(machine_user.gears, u5))

# Empty expression rejected
test_throws("Empty SDF rejected", "EMPTY",
    () -> parse_user_sdf!(machine_user, "", [1.0]))

# ==========================================================================
# SECTION 16: USER-DEFINED DIFFERENTIAL OPERATORS
# ==========================================================================
section("16. USER-DEFINED DIFFERENTIALS — ARBITRARY DERIVATIVES")

# Spec parsing
spec_dx    = parse_diff_spec("dx")
spec_dy    = parse_diff_spec("dy")
spec_dz    = parse_diff_spec("dz")
spec_d2x   = parse_diff_spec("d2x")
spec_dxdz  = parse_diff_spec("dxdz")
spec_d3xd2z = parse_diff_spec("d3xd2z")

test("Parse dx",     spec_dx.specs    == [(1,1)] && spec_dx.total_order    == 1)
test("Parse dy",     spec_dy.specs    == [(2,1)] && spec_dy.total_order    == 1)
test("Parse dz",     spec_dz.specs    == [(3,1)] && spec_dz.total_order    == 1)
test("Parse d2x",    spec_d2x.specs   == [(1,2)] && spec_d2x.total_order   == 2)
test("Parse dxdz",   spec_dxdz.specs  == [(1,1),(3,1)] && spec_dxdz.total_order == 2)
test("Parse d3xd2z total_order=5", spec_d3xd2z.total_order == 5)

# Numerical correctness: df/dx of sphere at surface = gradient_x
diff_dx = apply_differential(machine, :Sphere, [5.0, 0.0, 0.0], spec_dx)
test("dx matches gradient_x",   isapprox(diff_dx, g_surf[1]; atol=0.01))

diff_dy = apply_differential(machine, :Sphere, [5.0, 0.0, 0.0], spec_dy)
test("dy matches gradient_y",   isapprox(diff_dy, g_surf[2]; atol=0.01))

# d²x on sphere at surface
diff_d2x = apply_differential(machine, :Sphere, [5.0, 0.0, 0.0], spec_d2x)
test("d²x computed, finite",    !isnan(diff_d2x) && !isinf(diff_d2x))

# Mixed: dxdz on Gyroid
diff_dxdz = apply_differential(machine, :Gyroid, [1.0, 1.0, 1.0], spec_dxdz)
test("d²f/dxdz on Gyroid finite",  !isnan(diff_dxdz) && !isinf(diff_dxdz))

# High order: d⁴f/dx²dz² on Gyroid
spec_d2xd2z = parse_diff_spec("d2xd2z")
diff_4th = apply_differential(machine, :Gyroid, [1.0, 1.0, 1.0], spec_d2xd2z)
test("d⁴f/dx²dz² on Gyroid finite", !isnan(diff_4th) && !isinf(diff_4th))

# Insane: d⁶f/dx³dy²dz on TwistedTorus — symbolic diff would EXPLODE
spec_insane = parse_diff_spec("d3xd2ydz")
diff_6th = apply_differential(machine, :TwistedTorus, [10.0, 0.0, 0.0], spec_insane)
test("d⁶f/dx³dy²dz on TwistedTorus — SYMBOLIC DIFF WOULD EXPLODE",
    !isnan(diff_6th) && !isinf(diff_6th))

# d⁵ on user SDF: completely custom
spec_d5 = parse_diff_spec("d2xd2ydz")
diff_user = apply_differential(machine_user, u3, [1.0, 1.0, 1.0], spec_d5)
test("d⁵ on no-param user SDF",  !isnan(diff_user) && !isinf(diff_user))

# Invalid spec rejected
test_throws("Invalid spec 'xyz' rejected", "INVALID",
    () -> parse_diff_spec("xyz"))
test_throws("Empty spec rejected", "EMPTY",
    () -> parse_diff_spec(""))

# ==========================================================================
# SECTION 17: ERROR HANDLING — ALL MACHINE CRUNCHES
# ==========================================================================
section("17. ERROR HANDLING")

test_throws("Missing gear throws",        "MISSING",
    () -> probe(machine, :Nonexistent, [0.0,0.0,0.0]))
test_throws("Dimension mismatch 2D→3D",  "3D",
    () -> probe(machine, :Sphere, [0.0,0.0]))
test_throws("Throttle shut throws",       "THROTTLE",
    () -> begin
        m_test = AntikytheraMap(0.001)
        jit_cast_gears!(m_test)
        probe(m_test, :Sphere, [5.0,0.0,0.0])
    end)
# Zero gradient → auto-projection (no exception). Verify projection produces valid result.
n_proj = surface_normal(machine, :Sphere, [0.0,0.0,0.0])
test("Zero gradient normal: auto-projects to surface, unit length",
    isapprox(norm(n_proj), 1.0; atol=0.01))
c_proj = curvature(machine, :Sphere, [0.0,0.0,0.0])
test("Zero gradient curvature: auto-projects, mean ≈ 0.2",
    abs(c_proj.mean - 0.2) < 0.03)
test_throws("Invalid diff spec throws",   "INVALID",
    () -> parse_diff_spec("xyz"))
test_throws("Empty SDF expr throws",      "EMPTY",
    () -> parse_user_sdf!(machine_user, "", [1.0]))
test_throws("Morph out-of-range t throws", "MORPH t",
    () -> morph!(machine_morph, :MS, [10.0], 2.0))
test_throws("Zero ray direction throws",  "ZERO",
    () -> levelset(machine, :Sphere, [0.0,0.0,0.0], [0.0,0.0,0.0]))
test_throws("Negative blend radius throws", "BLEND RADIUS",
    () -> blend!(machine_csg, :X, :A, :B, -0.5))

# MachineCrunch has message and context
e = try
    probe(machine, :Nonexistent, [0.0,0.0,0.0])
    nothing
catch ex
    ex
end
test("MachineCrunch has message field",  e isa MachineCrunch && !isempty(e.message))
test("MachineCrunch has context field",  e isa MachineCrunch && !isempty(e.context))

# ==========================================================================
# SECTION 18: PERFORMANCE / STRESS TESTS
# ==========================================================================
section("18. PERFORMANCE STRESS TESTS")

# 100 gradient probes on Gyroid
t0 = time()
for _ in 1:100
    gradient(machine, :Gyroid, [rand(), rand(), rand()])
end
elapsed = time() - t0
test("100 Gyroid gradients < 1 second", elapsed < 1.0, @sprintf("%.3fs", elapsed))

# 20 curvature probes on TwistedTorus
t0 = time()
for _ in 1:20
    curvature(machine, :TwistedTorus, [rand()*10.0+5.0, rand()*2.0, rand()])
end
elapsed = time() - t0
test("20 TwistedTorus curvatures < 2 seconds", elapsed < 2.0, @sprintf("%.3fs", elapsed))

# 50 levelset ray marches
t0 = time()
for _ in 1:50
    levelset(machine, :Sphere, [15.0,0.0,0.0], [-1.0,0.0,0.0])
end
elapsed = time() - t0
test("50 levelset ray marches < 2 seconds", elapsed < 2.0, @sprintf("%.3fs", elapsed))

# Deep CSG chain: 10 unions
machine_deep = AntikytheraMap(0.001)
machine_deep.throttle_clamp = 0.5
cast_single!(machine_deep, :Base, "sphere", [5.0])
deep_current = :Base   # top-level variable
for i in 1:10
    cast_single!(machine_deep, Symbol("S$(i)"), "sphere", [Float64(i)])
    uname = Symbol("U$(i)")
    boolean_union!(machine_deep, uname, deep_current, Symbol("S$(i)"))
    global deep_current = uname  # update outer scope
end
test("Deep CSG chain 10 unions created",   length(machine_deep.gears) >= 21)
deep_val = probe(machine_deep, deep_current, [0.0,0.0,0.0])
test("Deep CSG chain probe works",         !isnan(deep_val))
deep_grad = gradient(machine_deep, deep_current, [5.0,0.0,0.0])
test("Deep CSG chain gradient works",      !any(isnan, deep_grad))

# Query count is tracked
before = machine.query_count
for _ in 1:10
    probe(machine, :Sphere, [5.0,0.0,0.0])
end
test("Query count tracks 10 probes", machine.query_count == before + 10)

# ==========================================================================
# SECTION 19: INTEGRATION — FULL PIPELINE
# ==========================================================================
section("19. INTEGRATION — FULL PIPELINE")

machine_int = AntikytheraMap(0.001)
machine_int.throttle_clamp = 0.5
jit_cast_gears!(machine_int)

# Create complex geometry: union of sphere and torus, blended with gyroid
boolean_union!(machine_int, :SphTor, :Sphere, :Torus)
blend!(machine_int, :SphTorGyr, :SphTor, :Gyroid, 0.5)

test("Complex composed shape created",  haskey(machine_int.gears, :SphTorGyr))
cp = probe(machine_int, :SphTorGyr, [5.0, 0.0, 0.0])
test("Complex shape probe works",       !isnan(cp))
cg = gradient(machine_int, :SphTorGyr, [5.0, 0.0, 0.0])
test("Complex shape gradient works",    !any(isnan, cg))
cc = curvature(machine_int, :SphTorGyr, [5.0, 0.0, 0.0])
test("Complex shape curvature works",   !isnan(cc.mean))
cl = levelset(machine_int, :SphTorGyr, [20.0, 0.0, 0.0], [-1.0,0.0,0.0])
test("Complex shape ray march works",   cl.steps > 0)

# User-defined SDF → full pipeline
machine_int2 = AntikytheraMap(0.001)
machine_int2.throttle_clamp = 0.5
u_name = parse_user_sdf!(machine_int2, "sin(x)*cos(y) - a*z", [0.5])
boolean_union!(machine_int2, :UserUnion, u_name, u_name)
test("User SDF → boolean union created", haskey(machine_int2.gears, :UserUnion))
uu_val = probe(machine_int2, :UserUnion, [1.0,1.0,0.0])
test("User SDF → union probe works",     !isnan(uu_val))

# ==========================================================================
# SECTION 20: DEMO COMMAND REGRESSION — THE 4 PREVIOUSLY-FAILING COMMANDS
# ==========================================================================
# GRUG: These commands broke the demo video. Now they must never break again.
#        Each one hit a zero-gradient degenerate point. Now auto-projected.
# ==========================================================================
section("20. DEMO REGRESSION — AUTO-PROJECTION AT DEGENERATE POINTS")

machine_demo = AntikytheraMap(0.001)
machine_demo.throttle_clamp = 0.5
jit_cast_gears!(machine_demo)

# --- Demo command 1: /curvature Torus 8.0 0.0 0.0 ---
# [8,0,0] is at the tube axis of Torus[8,2]. SDF=-2, |grad|≈0.
# Should auto-project to inner equator [6,0,0] and compute curvature.
c_torus_deg = curvature(machine_demo, :Torus, [8.0, 0.0, 0.0])
test("Demo: /curvature Torus 8.0 0.0 0.0 — no NaN",   !isnan(c_torus_deg.mean))
test("Demo: /curvature Torus 8.0 0.0 0.0 — no Inf",   !isinf(c_torus_deg.mean))
test("Demo: /curvature Torus 8.0 0.0 0.0 — reasonable mean",
    abs(c_torus_deg.mean) < 5.0)

# --- Demo command 2: /gear TwistedDonut twisted_torus 8.0 2.0 2.5 then /curvature ---
# TwistedDonut not in default set — must cast it first.
# [8,0,0] is at tube axis of TwistedDonut[8,2,2.5]. SDF=-2, |grad|≈0.
cast_single!(machine_demo, :TwistedDonut, "twisted_torus", [8.0, 2.0, 2.5])
test("Demo: /gear TwistedDonut cast", haskey(machine_demo.gears, :TwistedDonut))

c_twisted_deg = curvature(machine_demo, :TwistedDonut, [8.0, 0.0, 0.0])
test("Demo: /curvature TwistedDonut 8.0 0.0 0.0 — no NaN", !isnan(c_twisted_deg.mean))
test("Demo: /curvature TwistedDonut 8.0 0.0 0.0 — no Inf", !isinf(c_twisted_deg.mean))

# --- Demo command 3: /geodesic Torus 8.0 0.0 0.0 -8.0 0.0 0.0 ---
# Both [8,0,0] and [-8,0,0] are inside the torus tube. Auto-projected to surface.
geo_demo = geodesic(machine_demo, :Torus, [8.0, 0.0, 0.0], [-8.0, 0.0, 0.0]; max_steps=500)
test("Demo: /geodesic Torus 8.0 0.0 0.0 -8.0 0.0 0.0 — path exists",
    length(geo_demo.path) > 1)
test("Demo: /geodesic Torus 8.0 0.0 0.0 -8.0 0.0 0.0 — distance > 0",
    geo_demo.distance > 0)
# Path endpoints should be on the surface (after projection)
test("Demo: /geodesic Torus — start projected to surface",
    abs(probe(machine_demo, :Torus, geo_demo.path[1])) < 0.05)
test("Demo: /geodesic Torus — end projected to surface",
    abs(probe(machine_demo, :Torus, geo_demo.path[end])) < 0.05)

# --- Demo command 4: /gear MorphTorus + /morph + /curvature MorphTorus 10.0 0.0 0.0 ---
# After morph from [8,2]→[12,3] at t=0.5, params=[10,2.5].
# [10,0,0] is at tube axis of Torus[10,2.5]. SDF=-2.5, |grad|=0.
cast_single!(machine_demo, :MorphTorus, "torus", [8.0, 2.0])
morph!(machine_demo, :MorphTorus, [12.0, 3.0], 0.5)
test("Demo: MorphTorus params after morph — major R=10",
    isapprox(machine_demo.gears[:MorphTorus].teeth_params[1], 10.0; atol=0.001))
test("Demo: MorphTorus params after morph — minor r=2.5",
    isapprox(machine_demo.gears[:MorphTorus].teeth_params[2], 2.5; atol=0.001))

c_morph_deg = curvature(machine_demo, :MorphTorus, [10.0, 0.0, 0.0])
test("Demo: /curvature MorphTorus 10.0 0.0 0.0 — no NaN", !isnan(c_morph_deg.mean))
test("Demo: /curvature MorphTorus 10.0 0.0 0.0 — no Inf", !isinf(c_morph_deg.mean))
test("Demo: /curvature MorphTorus 10.0 0.0 0.0 — reasonable mean",
    abs(c_morph_deg.mean) < 5.0)

# ==========================================================================
# FINAL SUMMARY
# ==========================================================================

println("\n" * "═"^64)
println("  TEST SUMMARY")
println("═"^64)
println("  Passed: $(TEST.passed)")
println("  Failed: $(TEST.failed)")
println("  Total:  $(TEST.passed + TEST.failed)")

if TEST.failed > 0
    println("\n  FAILURES:")
    for err in TEST.errors
        println("    - $(err)")
    end
end

println("\n" * "═"^64)
if TEST.failed == 0
    println("  ⚙️  ALL TESTS PASSED — THE MACHINE LIVES  ⚙️")
else
    println("  ⚠️  SOME TESTS FAILED — CHECK THE MACHINE")
end
println("═"^64 * "\n")

exit(TEST.failed > 0 ? 1 : 0)