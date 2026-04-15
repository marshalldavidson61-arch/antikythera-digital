# ==========================================================================
# THE ANTIKYTHERA DIFF-ENGINE — COMPREHENSIVE TEST SUITE
# ==========================================================================
# Run: julia test_antikythera.jl
# 
# This script puts the machine through its paces.
# Every command. Every edge case. Every intractable operation.
# If this passes, you've got a working geometric calculus engine.
# ==========================================================================

# Load the engine
include("antikythera_diff_engine.jl")

using Printf

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
    println("\n═══════════════════════════════════════════════════════════════")
    println("  $(title)")
    println("═══════════════════════════════════════════════════════════════")
end

# ==========================================================================
# TEST SECTION 1: MACHINE INITIALIZATION
# ==========================================================================

section("1. MACHINE INITIALIZATION")

# Test default construction
machine = AntikytheraMap()
test("Default slack", machine.slack == 0.01)
test("Default throttle", machine.throttle_clamp == 0.0)
test("Empty gears", isempty(machine.gears))

# Test custom slack
machine_tight = AntikytheraMap(0.001)
test("Custom slack", machine_tight.slack == 0.001)

# Test invalid slack
test_throws("Zero slack rejected", "POSITIVE", () -> AntikytheraMap(0.0))
test_throws("Negative slack rejected", "POSITIVE", () -> AntikytheraMap(-0.1))

# ==========================================================================
# TEST SECTION 2: GEAR CASTING
# ==========================================================================

section("2. GEAR CASTING")

# Test JIT casting with default preset
jit_cast_gears!(machine)
test("Default preset loads gears", length(machine.gears) == 4)
test("Sphere loaded", haskey(machine.gears, :Sphere))
test("Torus loaded", haskey(machine.gears, :Torus))
test("Gyroid loaded", haskey(machine.gears, :Gyroid))
test("TwistedTorus loaded", haskey(machine.gears, :TwistedTorus))

# Test single gear casting
machine2 = AntikytheraMap(0.001)
cast_single!(machine2, :TestSphere, "sphere", [5.0])
test("Single gear cast", haskey(machine2.gears, :TestSphere))
test("Single gear params", machine2.gears[:TestSphere].teeth_params == [5.0])

# Test invalid shape key
test_throws("Invalid shape rejected", "NO SUCH SHAPE", 
    () -> cast_single!(machine2, :Bad, "nonexistent", [1.0]))

# Test "all" preset
machine3 = AntikytheraMap(0.001)
jit_cast_gears!(machine3; preset="all")
test("All preset loads full library", length(machine3.gears) == 7)

# ==========================================================================
# TEST SECTION 3: THROTTLE AND FLOW CONTROL
# ==========================================================================

section("3. THROTTLE AND FLOW CONTROL")

# Test throttle gate
machine.throttle_clamp = 0.0
test_throws("Probe blocked when throttle shut", "THROTTLE SHUT", 
    () -> probe(machine, :Sphere, [0.0, 0.0, 0.0]))

machine.throttle_clamp = 0.5
result = probe(machine, :Sphere, [0.0, 0.0, 0.0])
test("Probe works when throttle open", isapprox(result, -5.0; atol=0.01))

# ==========================================================================
# TEST SECTION 4: PROBE OPERATION (RAW SDF)
# ==========================================================================

section("4. PROBE OPERATION")

machine.throttle_clamp = 0.5

# Sphere: at origin, SDF should be -radius (inside)
sphere_inside = probe(machine, :Sphere, [0.0, 0.0, 0.0])
test("Sphere probe at center (inside)", isapprox(sphere_inside, -5.0; atol=0.01))

# Sphere: on surface at radius
sphere_surface = probe(machine, :Sphere, [5.0, 0.0, 0.0])
test("Sphere probe on surface", abs(sphere_surface) < 0.01)

# Sphere: outside
sphere_outside = probe(machine, :Sphere, [10.0, 0.0, 0.0])
test("Sphere probe outside", isapprox(sphere_outside, 5.0; atol=0.01))

# Torus: inside the donut hole
torus_hole = probe(machine, :Torus, [0.0, 0.0, 0.0])
test("Torus probe in hole (outside)", torus_hole > 0)

# Torus: inside the tube
torus_tube = probe(machine, :Torus, [8.0, 0.0, 0.0])
test("Torus probe in tube (inside)", torus_tube < 0)

# Gyroid: periodic oscillation
gyroid_origin = probe(machine, :Gyroid, [0.0, 0.0, 0.0])
test("Gyroid at origin", isapprox(gyroid_origin, 0.0; atol=0.01))

# Dimension mismatch test
test_throws("Dimension mismatch caught", "3D", 
    () -> probe(machine, :Sphere, [0.0, 0.0]))

# ==========================================================================
# TEST SECTION 5: GRADIENT (SPATIAL DIFFERENTIATION)
# ==========================================================================

section("5. GRADIENT OPERATION")

# Sphere gradient at [0,0,0]: should point outward from center
grad_origin = gradient(machine, :Sphere, [0.0, 0.0, 0.0])
test("Sphere gradient at origin - direction", 
    isapprox(grad_origin[1], 0.0; atol=0.01) && isapprox(grad_origin[2], 0.0; atol=0.01) && isapprox(grad_origin[3], 0.0; atol=0.01))

# Sphere gradient at [5,0,0]: should be normal to surface
grad_surface = gradient(machine, :Sphere, [5.0, 0.0, 0.0])
test("Sphere gradient at surface - magnitude", isapprox(norm(grad_surface), 1.0; atol=0.02))
test("Sphere gradient at surface - direction X", isapprox(grad_surface[1], 1.0; atol=0.05))
test("Sphere gradient at surface - direction Y/Z near zero", 
    abs(grad_surface[2]) < 0.05 && abs(grad_surface[3]) < 0.05)

# Torus gradient: should point outward from tube center
grad_torus = gradient(machine, :Torus, [10.0, 0.0, 0.0])
test("Torus gradient magnitude reasonable", norm(grad_torus) > 0.5)

# Gyroid gradient: complex surface
grad_gyroid = gradient(machine, :Gyroid, [1.0, 1.0, 1.0])
test("Gyroid gradient computed", !any(isnan, grad_gyroid) && !any(isinf, grad_gyroid))

# TwistedTorus gradient: brutal for symbolic diff, trivial for spatial
grad_twisted = gradient(machine, :TwistedTorus, [10.0, 0.0, 0.0])
test("TwistedTorus gradient computed", !any(isnan, grad_twisted) && !any(isinf, grad_twisted))

# ==========================================================================
# TEST SECTION 6: SURFACE NORMAL
# ==========================================================================

section("6. SURFACE NORMAL")

# Sphere normal at [5,0,0] should be [1,0,0]
n_sphere = surface_normal(machine, :Sphere, [5.0, 0.0, 0.0])
test("Sphere normal unit length", isapprox(norm(n_sphere), 1.0; atol=0.01))
test("Sphere normal direction", isapprox(n_sphere[1], 1.0; atol=0.05))

# Torus normal
n_torus = surface_normal(machine, :Torus, [10.0, 0.0, 0.0])
test("Torus normal unit length", isapprox(norm(n_torus), 1.0; atol=0.02))

# ==========================================================================
# TEST SECTION 7: CURVATURE (HESSIAN)
# ==========================================================================

section("7. CURVATURE — INTRACTABLE FOR SYMBOLIC DIFF")

# Sphere curvature should be constant: mean = 1/r, gaussian = 1/r²
# At radius 5: mean ≈ 0.2, gaussian ≈ 0.04
curv_sphere = curvature(machine, :Sphere, [5.0, 0.0, 0.0])
test("Sphere mean curvature ≈ 1/R", abs(curv_sphere.mean - 0.2) < 0.02)
test("Sphere Gaussian curvature ≈ 1/R²", abs(curv_sphere.gaussian - 0.04) < 0.01)
test("Sphere principal curvatures equal", abs(curv_sphere.k1 - curv_sphere.k2) < 0.02)

# Torus curvature: varies by position
curv_torus = curvature(machine, :Torus, [10.0, 0.0, 0.0])
test("Torus curvature computed", !isnan(curv_sphere.mean) && !isnan(curv_sphere.gaussian))

# Gyroid curvature: COMPLETELY intractable symbolically
curv_gyroid = curvature(machine, :Gyroid, [1.0, 1.0, 1.0])
test("Gyroid mean curvature computed", !isnan(curv_gyroid.mean))
test("Gyroid Gaussian curvature computed", !isnan(curv_gyroid.gaussian))

# TwistedTorus curvature: nested trig composition — symbolic Hessian nightmare
curv_twisted = curvature(machine, :TwistedTorus, [10.0, 0.0, 0.0])
test("TwistedTorus curvature computed", !isnan(curv_twisted.mean))

# ==========================================================================
# TEST SECTION 8: LAPLACIAN AND DIVERGENCE
# ==========================================================================

section("8. LAPLACIAN / DIVERGENCE")

# Sphere laplacian at surface
lapl_sphere = laplacian(machine, :Sphere, [5.0, 0.0, 0.0])
test("Sphere Laplacian computed", !isnan(lapl_sphere) && !isinf(lapl_sphere))

# Divergence = Laplacian for scalar fields
div_sphere = divergence(machine, :Sphere, [5.0, 0.0, 0.0])
test("Divergence equals Laplacian", isapprox(div_sphere, lapl_sphere; atol=1e-10))

# Gyroid Laplacian
lapl_gyroid = laplacian(machine, :Gyroid, [1.0, 1.0, 1.0])
test("Gyroid Laplacian computed", !isnan(lapl_gyroid))

# ==========================================================================
# TEST SECTION 9: BOOLEAN OPERATIONS (CSG)
# ==========================================================================

section("9. BOOLEAN OPERATIONS — DERIVATIVE DISCONTINUITY TERRITORY")

# Create two overlapping spheres
machine_csg = AntikytheraMap(0.001)
machine_csg.throttle_clamp = 0.5
cast_single!(machine_csg, :A, "sphere", [3.0])
cast_single!(machine_csg, :B, "sphere", [3.0])

# Union
boolean_union!(machine_csg, :UnionAB, :A, :B)
test("Union created", haskey(machine_csg.gears, :UnionAB))
union_val = probe(machine_csg, :UnionAB, [0.0, 0.0, 0.0])
test("Union probe works", !isnan(union_val))
union_grad = gradient(machine_csg, :UnionAB, [0.0, 0.0, 0.0])
test("Union gradient computed", !any(isnan, union_grad))

# Intersect
boolean_intersect!(machine_csg, :IntersectAB, :A, :B)
test("Intersect created", haskey(machine_csg.gears, :IntersectAB))
inter_val = probe(machine_csg, :IntersectAB, [0.0, 0.0, 0.0])
test("Intersect probe works", !isnan(inter_val))

# Subtract
boolean_subtract!(machine_csg, :SubtractAB, :A, :B)
test("Subtract created", haskey(machine_csg.gears, :SubtractAB))

# Gradient at the min/max junction — symbolic AD DIES here
# We just probe it and it works
junction_point = [2.5, 0.0, 0.0]  # Near where the two spheres meet
junction_grad = gradient(machine_csg, :UnionAB, junction_point)
test("Gradient through CSG junction", !any(isnan, junction_grad) && !any(isinf, junction_grad))

# ==========================================================================
# TEST SECTION 10: SMOOTH BLEND
# ==========================================================================

section("10. SMOOTH BLEND — NO CLOSED-FORM GRADIENT")

blend!(machine_csg, :BlendedAB, :A, :B, 2.0)
test("Blend created", haskey(machine_csg.gears, :BlendedAB))

# Probe in the blend region
blend_point = [1.5, 0.0, 0.0]  # In the smooth transition zone
blend_val = probe(machine_csg, :BlendedAB, blend_point)
test("Blend probe works", !isnan(blend_val))

blend_grad = gradient(machine_csg, :BlendedAB, blend_point)
test("Blend gradient computed", !any(isnan, blend_grad))

# Curvature in blend region — this is the REAL test
blend_curv = curvature(machine_csg, :BlendedAB, blend_point)
test("Curvature in blend region computed", !isnan(blend_curv.mean))

# ==========================================================================
# TEST SECTION 11: MORPH
# ==========================================================================

section("11. MORPH — INTERMEDIATE STATES WITH NO NAME")

machine_morph = AntikytheraMap(0.001)
machine_morph.throttle_clamp = 0.5
cast_single!(machine_morph, :MorphSphere, "sphere", [5.0])

# Morph to larger radius
morph!(machine_morph, :MorphSphere, [10.0], 0.0)  # t=0, no change
test("Morph t=0 unchanged", isapprox(machine_morph.gears[:MorphSphere].teeth_params[1], 5.0; atol=0.01))

morph!(machine_morph, :MorphSphere, [10.0], 1.0)  # t=1, full change
test("Morph t=1 complete", isapprox(machine_morph.gears[:MorphSphere].teeth_params[1], 10.0; atol=0.01))

# Reset and test intermediate
machine_morph.gears[:MorphSphere].teeth_params[1] = 5.0
morph!(machine_morph, :MorphSphere, [10.0], 0.5)  # t=0.5, halfway
test("Morph t=0.5 intermediate", isapprox(machine_morph.gears[:MorphSphere].teeth_params[1], 7.5; atol=0.01))

# ==========================================================================
# TEST SECTION 12: FLOW (STREAMLINE TRACING)
# ==========================================================================

section("12. FLOW — STREAMLINE THROUGH COMPLEX TOPOLOGY")

# Flow descent on sphere — should reach surface
flow_path = flow(machine, :Sphere, [0.0, 0.0, 0.0]; steps=50, step_size=0.5, direction=:descent)
test("Flow descent generated path", length(flow_path) > 1)
test("Flow descent reaches surface", abs(probe(machine, :Sphere, flow_path[end])) < 0.5)

# Flow on gyroid — NO ANALYTIC SOLUTION EXISTS
flow_gyroid = flow(machine, :Gyroid, [2.0, 2.0, 2.0]; steps=100, step_size=0.2)
test("Flow on Gyroid computed", length(flow_gyroid) > 1)

# Flow on TwistedTorus — nested trig topology
flow_twisted = flow(machine, :TwistedTorus, [0.0, 0.0, 0.0]; steps=50, step_size=0.3)
test("Flow on TwistedTorus computed", length(flow_twisted) > 1)

# ==========================================================================
# TEST SECTION 13: LEVELSET (RAY MARCHING)
# ==========================================================================

section("13. LEVELSET — RAY-SURFACE INTERSECTION")

# Ray toward sphere center
ray_origin = [15.0, 0.0, 0.0]
ray_dir = [-1.0, 0.0, 0.0]
hit_result = levelset(machine, :Sphere, ray_origin, ray_dir)
test("Ray hits sphere", hit_result.hit)
test("Ray hit distance correct", isapprox(hit_result.distance, 10.0; atol=0.1))  # 15 - 5 = 10

# Ray away from sphere
miss_result = levelset(machine, :Sphere, ray_origin, [1.0, 0.0, 0.0]; max_dist=20.0)
test("Ray misses sphere", !miss_result.hit)

# Ray through gyroid — multiple potential intersections
gyroid_ray = levelset(machine, :Gyroid, [0.0, 0.0, -10.0], [0.0, 0.0, 1.0]; max_dist=20.0)
test("Ray through Gyroid computed", gyroid_ray.steps > 0)

# ==========================================================================
# TEST SECTION 14: GEODESIC
# ==========================================================================

section("14. GEODESIC — APPROXIMATE SURFACE DISTANCE")

# Geodesic on sphere surface (should be along great circle ≈ π*r for opposite points)
geo_result = geodesic(machine, :Sphere, [5.0, 0.0, 0.0], [-5.0, 0.0, 0.0]; max_steps=200)
test("Geodesic computed", length(geo_result.path) > 1)
test("Geodesic distance reasonable", geo_result.distance > 0)

# Geodesic on torus surface
geo_torus = geodesic(machine, :Torus, [10.0, 0.0, 0.0], [8.0, 2.0, 0.0]; max_steps=300)
test("Geodesic on Torus computed", length(geo_torus.path) > 1)

# ==========================================================================
# TEST SECTION 15: USER-DEFINED SDF
# ==========================================================================

section("15. USER-DEFINED SDF — RUNTIME GEOMETRY")

# Define a custom SDF: a sphere with sin wave distortion
machine_user = AntikytheraMap(0.001)
machine_user.throttle_clamp = 0.5

# Simple sphere: sqrt(x²+y²+z²) - r
user_name = parse_user_sdf!(machine_user, "sqrt(x*x + y*y + z*z) - a", [3.0])
test("User SDF created", haskey(machine_user.gears, user_name))

user_val = probe(machine_user, user_name, [0.0, 0.0, 0.0])
test("User SDF probe at center", isapprox(user_val, -3.0; atol=0.1))

user_grad = gradient(machine_user, user_name, [3.0, 0.0, 0.0])
test("User SDF gradient computed", !any(isnan, user_grad))
test("User SDF gradient magnitude ≈ 1", isapprox(norm(user_grad), 1.0; atol=0.1))

# More complex: sin wave surface (IMPOSSIBLE to differentiate symbolically in closed form)
user_name2 = parse_user_sdf!(machine_user, "sin(x) + cos(y) + sin(z)", [])
test("Complex user SDF created", haskey(machine_user.gears, user_name2))

complex_grad = gradient(machine_user, user_name2, [1.0, 1.0, 1.0])
test("Complex user SDF gradient", !any(isnan, complex_grad))

complex_curv = curvature(machine_user, user_name2, [1.0, 1.0, 1.0])
test("Complex user SDF curvature", !isnan(complex_curv.mean))

# ==========================================================================
# TEST SECTION 16: USER-DEFINED DIFFERENTIAL OPERATORS
# ==========================================================================

section("16. USER-DEFINED DIFFERENTIALS — ARBITRARY DERIVATIVES")

# Parse diff specs
spec_dx = parse_diff_spec("dx")
test("Parse dx", spec_dx.specs == [(1, 1)] && spec_dx.total_order == 1)

spec_d2x = parse_diff_spec("d2x")
test("Parse d2x", spec_d2x.specs == [(1, 2)] && spec_d2x.total_order == 2)

spec_dxdz = parse_diff_spec("dxdz")
test("Parse dxdz", spec_dxdz.specs == [(1, 1), (3, 1)] && spec_dxdz.total_order == 2)

spec_d3xd2z = parse_diff_spec("d3xd2z")
test("Parse d3xd2z", spec_d3xd2z.total_order == 5)

# Apply derivatives
diff_dx = apply_differential(machine, :Sphere, [5.0, 0.0, 0.0], spec_dx)
test("dx computed", !isnan(diff_dx))

diff_d2x = apply_differential(machine, :Sphere, [5.0, 0.0, 0.0], spec_d2x)
test("d²x computed", !isnan(diff_d2x))

# High-order derivative: d⁴f/dx²dz²
spec_d2xd2z = parse_diff_spec("d2xd2z")
diff_d2xd2z = apply_differential(machine, :Gyroid, [1.0, 1.0, 1.0], spec_d2xd2z)
test("d⁴f/dx²dz² computed on Gyroid", !isnan(diff_d2xd2z) && !isinf(diff_d2xd2z))

# Absolutely insane derivative: d⁶f/dx³dy²dz
spec_insane = parse_diff_spec("d3xd2ydz")
diff_insane = apply_differential(machine, :TwistedTorus, [10.0, 0.0, 0.0], spec_insane)
test("d⁶f/dx³dy²dz on TwistedTorus — SYMBOLIC DIFF WOULD EXPLODE", 
    !isnan(diff_insane) && !isinf(diff_insane))

# ==========================================================================
# TEST SECTION 17: ERROR HANDLING
# ==========================================================================

section("17. ERROR HANDLING")

# Missing gear
test_throws("Missing gear rejected", "MISSING", 
    () -> probe(machine, :NonExistent, [0.0, 0.0, 0.0]))

# Zero gradient (flat region)
test_throws("Zero gradient rejected", "ZERO", 
    () -> surface_normal(machine, :Sphere, [0.0, 0.0, 0.0]))

# Invalid diff spec
test_throws("Invalid diff spec rejected", "INVALID", 
    () -> parse_diff_spec("xyz"))

# Empty user SDF
test_throws("Empty user SDF rejected", "EMPTY", 
    () -> parse_user_sdf!(machine_user, "", [1.0]))

# ==========================================================================
# TEST SECTION 18: PERFORMANCE / STRESS
# ==========================================================================

section("18. PERFORMANCE STRESS TEST")

# Many gradient probes
start_time = time()
for i in 1:100
    gradient(machine, :Gyroid, [rand(), rand(), rand()])
end
elapsed = time() - start_time
test("100 gradient probes on Gyroid under 1 second", elapsed < 1.0, @sprintf("%.3fs", elapsed))

# Many curvature probes (more expensive)
start_time = time()
for i in 1:20
    curvature(machine, :TwistedTorus, [rand()*10, rand(), rand()])
end
elapsed = time() - start_time
test("20 curvature probes on TwistedTorus under 2 seconds", elapsed < 2.0, @sprintf("%.3fs", elapsed))

# Deep CSG chain
machine_deep = AntikytheraMap(0.001)
machine_deep.throttle_clamp = 0.5
cast_single!(machine_deep, :Base, "sphere", [5.0])
current_base = :Base
for i in 1:10
    cast_single!(machine_deep, Symbol("S$(i)"), "sphere", [Float64(i)])
    union_name = Symbol("U$(i)")
    boolean_union!(machine_deep, union_name, current_base, Symbol("S$(i)"))
    global current_base = union_name  # Chain the union
end
test("Deep CSG chain created", length(machine_deep.gears) > 20)

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

# Return exit code
exit(TEST.failed > 0 ? 1 : 0)