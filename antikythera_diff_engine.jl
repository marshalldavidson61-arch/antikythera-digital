# ==========================================================================
# THE ANTIKYTHERA DIFF-ENGINE (GEOM-CALC v2.0)
# ==========================================================================
# Geometric calculus via preloaded SDF fields.
# Derivative is a spatial property, not a symbolic procedure.
# GPU is foundry. Slack is tolerance. Throttle is flow gate.
# Calculus is just gears turning.
# ==========================================================================

using LinearAlgebra

# ----------------------------------------------------------
# GRUG SAY: NO SILENT OOPSIE. 
# IF ROCK BREAK, GRUG WANT TO HEAR LOUD CRUNCH.
# GRUG ALSO WANT TO KNOW WHICH ROCK AND WHY.
# ----------------------------------------------------------
struct MachineCrunch <: Exception
    message::String
    context::String  # GRUG: Which gear broke? What was happening?
    
    MachineCrunch(msg::String) = new(msg, "")
    MachineCrunch(msg::String, ctx::String) = new(msg, ctx)
end

function Base.showerror(io::IO, e::MachineCrunch)
    print(io, "⚙️  MACHINE CRUNCH: ", e.message)
    !isempty(e.context) && print(io, "\n   CONTEXT: ", e.context)
end

# ----------------------------------------------------------
# THE COG: THIS IS THE NONLINEAR GEAR.
# IT HAS "SHAPE" (SDF) AND "TEETH" (PARAMETERS).
# GRUG: Think of it like a bronze gear in the mechanism.
#        The shape is the gear profile. 
#        The teeth are what other gears push on.
# ----------------------------------------------------------
mutable struct Cog
    name::Symbol
    # GRUG: "How far is rock from gear?" logic.
    # This is the Signed Distance Field.
    # Negative = inside gear. Zero = on surface. Positive = outside.
    shape_logic::Function
    # GRUG: These are teeth. They change when other gears push them.
    # params[1] might be radius, params[2] might be twist, etc.
    teeth_params::Vector{Float64}
    # GRUG: How many directions does this gear live in?
    # 2D gear = flat. 3D gear = chunky. 
    ndims::Int
    
    function Cog(name::Symbol, logic::Function, params::AbstractVector; ndims::Int=3)
        # GRUG: Convert any vector to Float64 teeth.
        float_params = convert(Vector{Float64}, params)
        # GRUG: Ghost gear no turn. Need at least one tooth.
        if isempty(float_params)
            throw(MachineCrunch("GEAR $(name) HAS NO TEETH. CANNOT TURN.", "Cog constructor"))
        end
        # GRUG: Gear must live somewhere. No zero-dimension ghosts.
        if ndims < 2 || ndims > 3
            throw(MachineCrunch("GEAR $(name) MUST BE 2D OR 3D. GOT $(ndims)D.", "Cog constructor"))
        end
        new(name, logic, float_params, ndims)
    end
end

# ----------------------------------------------------------
# THE MAP: THE ENTIRE ANTIKYTHERA CLOCKWORK.
# IT SITS IN MEMORY DOING NOTHING UNTIL FLOW STARTS.
# GRUG: This is the whole machine. All gears, one map.
#        Valve shut = sleeping. Valve open = computing.
# ----------------------------------------------------------
mutable struct AntikytheraMap
    gears::Dict{Symbol, Cog}
    # GRUG: Water valve. 0.0 = shut, nobody home.
    # 1.0 = wide open, full electrochemical flow.
    throttle_clamp::Float64
    # GRUG: AK-47 wiggle room. Gear not need to be perfect.
    # If it rattle a little, it still work. That's compliance.
    slack::Float64
    # GRUG: How many times has machine been poked?
    query_count::Int
    
    function AntikytheraMap(wiggle::Float64=0.01)
        if wiggle <= 0.0
            throw(MachineCrunch("SLACK MUST BE POSITIVE. ZERO TOLERANCE IS BRITTLE.", "AntikytheraMap constructor"))
        end
        new(Dict{Symbol, Cog}(), 0.0, wiggle, 0)
    end
end

# ==========================================================================
# GEAR LIBRARY: STOCK SDF SHAPES
# ==========================================================================
# GRUG: These are gear templates. Like cookie cutters for geometry.
#        Traditional math chokes on most of these when you try to 
#        differentiate through them symbolically. But as SDF fields,
#        the gradient is just "poke and measure."
# ==========================================================================

# ----------------------------------------------------------
# SPHERE: Simplest gear. Just a ball.
# GRUG: Even Grug can make round rock.
# params[1] = radius
# ----------------------------------------------------------
function sdf_sphere(p::Vector{Float64}, params::Vector{Float64})
    return norm(p) - params[1]
end

# ----------------------------------------------------------
# TORUS: A donut gear. Ring with thickness.
# GRUG: Hard donut. Not for eating.
# params[1] = major radius (ring size)
# params[2] = minor radius (tube thickness)
# ----------------------------------------------------------
function sdf_torus(p::Vector{Float64}, params::Vector{Float64})
    length(p) == 3 || throw(MachineCrunch("TORUS NEEDS 3D POINT.", "sdf_torus"))
    R, r = params[1], params[2]
    q = [sqrt(p[1]^2 + p[3]^2) - R, p[2]]
    return norm(q) - r
end

# ----------------------------------------------------------
# BOX: A brick. Sharp edges.
# GRUG: Square rock. Very stable. Good for stacking.
# params[1:3] = half-extents (width, height, depth) / 2
# ----------------------------------------------------------
function sdf_box(p::Vector{Float64}, params::Vector{Float64})
    length(p) == 3 || throw(MachineCrunch("BOX NEEDS 3D POINT.", "sdf_box"))
    b = params[1:3]
    q = abs.(p) .- b
    return norm(max.(q, 0.0)) + min(maximum(q), 0.0)
end

# ----------------------------------------------------------
# CYLINDER: A tube standing up.
# GRUG: Like hollow log but math.
# params[1] = radius, params[2] = half-height
# ----------------------------------------------------------
function sdf_cylinder(p::Vector{Float64}, params::Vector{Float64})
    length(p) == 3 || throw(MachineCrunch("CYLINDER NEEDS 3D POINT.", "sdf_cylinder"))
    r, h = params[1], params[2]
    d = [norm([p[1], p[3]]) - r, abs(p[2]) - h]
    return min(max(d[1], d[2]), 0.0) + norm(max.(d, 0.0))
end

# ----------------------------------------------------------
# GYROID: Triply-periodic minimal surface.
# GRUG: This one is MAGIC ROCK. It tiles forever in all 
#        directions. Traditional math HATES this because the 
#        implicit surface has no closed-form gradient.
#        But we just poke it and measure. Easy.
# params[1] = scale (period), params[2] = thickness
# ----------------------------------------------------------
function sdf_gyroid(p::Vector{Float64}, params::Vector{Float64})
    length(p) == 3 || throw(MachineCrunch("GYROID NEEDS 3D POINT.", "sdf_gyroid"))
    s = params[1]  # scale
    t = length(params) >= 2 ? params[2] : 0.0  # thickness offset
    x, y, z = p[1] / s, p[2] / s, p[3] / s
    return (sin(x) * cos(y) + sin(y) * cos(z) + sin(z) * cos(x)) - t
end

# ----------------------------------------------------------
# SCHWARZ P: Another triply-periodic minimal surface.
# GRUG: Gyroid's cousin. Also magic. Also hates symbolic diff.
# params[1] = scale, params[2] = thickness
# ----------------------------------------------------------
function sdf_schwarz_p(p::Vector{Float64}, params::Vector{Float64})
    length(p) == 3 || throw(MachineCrunch("SCHWARZ NEEDS 3D POINT.", "sdf_schwarz_p"))
    s = params[1]
    t = length(params) >= 2 ? params[2] : 0.0
    x, y, z = p[1] / s, p[2] / s, p[3] / s
    return (cos(x) + cos(y) + cos(z)) - t
end

# ----------------------------------------------------------
# TWISTED TORUS: Torus with a helical twist.
# GRUG: Donut that somebody wrung like a towel.
#        Symbolic differentiation of this is BRUTAL.
#        Five nested trig functions. Chain rule explodes.
#        But spatial probe? Still just poke-and-measure.
# params[1] = major R, params[2] = minor r, params[3] = twist rate
# ----------------------------------------------------------
function sdf_twisted_torus(p::Vector{Float64}, params::Vector{Float64})
    length(p) == 3 || throw(MachineCrunch("TWISTED TORUS NEEDS 3D POINT.", "sdf_twisted_torus"))
    R, r, twist = params[1], params[2], params[3]
    # GRUG: First find angle around the ring
    angle = atan(p[3], p[1])
    # GRUG: Then twist the cross-section by that angle
    q_x = sqrt(p[1]^2 + p[3]^2) - R
    q_y = p[2]
    twist_angle = angle * twist
    rotated_x = q_x * cos(twist_angle) - q_y * sin(twist_angle)
    rotated_y = q_x * sin(twist_angle) + q_y * cos(twist_angle)
    return sqrt(rotated_x^2 + rotated_y^2) - r
end

# ----------------------------------------------------------
# GEAR LIBRARY REGISTRY
# GRUG: Menu of available cookie cutters.
# ----------------------------------------------------------
# ----------------------------------------------------------
# CONE: A pointy shape.
# GRUG: Like mountain but more stabby.
# params[1] = half-angle in radians, params[2] = height
# ----------------------------------------------------------
function sdf_cone(p::Vector{Float64}, params::Vector{Float64})
    length(p) == 3 || throw(MachineCrunch("CONE NEEDS 3D POINT.", "sdf_cone"))
    half_angle, h = params[1], params[2]
    q = [sqrt(p[1]^2 + p[3]^2), p[2]]
    sin_a, cos_a = sin(half_angle), cos(half_angle)
    k = dot(q, [-sin_a, cos_a])
    if k < 0.0
        return norm(q)
    end
    if k > norm(q)
        return norm(q .- [0.0, h])
    end
    return dot(q, [cos_a, sin_a])
end

# ----------------------------------------------------------
# CAPSULE: A pill shape. Cylinder with hemispherical caps.
# GRUG: Like fat ant. Or medicine pill.
# params[1] = radius, params[2] = half-height of cylinder
# ----------------------------------------------------------
function sdf_capsule(p::Vector{Float64}, params::Vector{Float64})
    length(p) == 3 || throw(MachineCrunch("CAPSULE NEEDS 3D POINT.", "sdf_capsule"))
    r, h = params[1], params[2]
    q = [norm([p[1], p[3]]), p[2]]
    q[2] -= clamp(q[2], -h, h)
    return norm(q) - r
end

# ----------------------------------------------------------
# PLANE: An infinite flat surface.
# GRUG: Like world before Grug dug first hole.
# params[1:3] = normal direction, params[4] = offset
# ----------------------------------------------------------
function sdf_plane(p::Vector{Float64}, params::Vector{Float64})
    length(p) == 3 || throw(MachineCrunch("PLANE NEEDS 3D POINT.", "sdf_plane"))
    n = params[1:3]
    n_norm = norm(n)
    n_norm < 1e-12 && throw(MachineCrunch("PLANE NORMAL CANNOT BE ZERO.", "sdf_plane"))
    return dot(p, n ./ n_norm) - params[4]
end

# ----------------------------------------------------------
# ELLIPSOID: A stretched ball.
# GRUG: Like sphere that ate too much in one direction.
# params[1:3] = semi-axes (a, b, c)
# ----------------------------------------------------------
function sdf_ellipsoid(p::Vector{Float64}, params::Vector{Float64})
    length(p) == 3 || throw(MachineCrunch("ELLIPSOID NEEDS 3D POINT.", "sdf_ellipsoid"))
    a, b, c = params[1], params[2], params[3]
    k0 = norm([p[1]/a, p[2]/b, p[3]/c])
    k1 = norm([p[1]/(a*a), p[2]/(b*b), p[3]/(c*c)])
    k0 < 1e-12 && return -min(a, b, c)
    return k0 * (k0 - 1.0) / k1
end

# ----------------------------------------------------------
# GEAR LIBRARY REGISTRY
# GRUG: Menu of available cookie cutters.
# ----------------------------------------------------------
const GEAR_LIBRARY = Dict{String, Tuple{Function, Vector{Float64}, Int, String}}(
    "sphere"        => (sdf_sphere,        [5.0],                3, "Round rock. params: [radius]"),
    "torus"         => (sdf_torus,         [8.0, 2.0],           3, "Donut. params: [major_R, minor_r]"),
    "box"           => (sdf_box,           [3.0, 4.0, 5.0],      3, "Brick. params: [half_w, half_h, half_d]"),
    "cylinder"      => (sdf_cylinder,      [3.0, 5.0],           3, "Tube. params: [radius, half_height]"),
    "gyroid"        => (sdf_gyroid,        [6.28, 0.0],          3, "Magic tiling surface. params: [scale, thickness]"),
    "schwarz"       => (sdf_schwarz_p,     [6.28, 0.0],          3, "Schwarz P surface. params: [scale, thickness]"),
    "twisted_torus" => (sdf_twisted_torus, [8.0, 2.0, 1.5],      3, "Wrung donut. params: [major_R, minor_r, twist]"),
    "cone"          => (sdf_cone,          [0.4, 5.0],           3, "Pointy rock. params: [half_angle_rad, height]"),
    "capsule"       => (sdf_capsule,       [2.0, 4.0],           3, "Pill shape. params: [radius, half_height]"),
    "plane"         => (sdf_plane,         [0.0, 1.0, 0.0, 0.0], 3, "Infinite flat. params: [nx, ny, nz, offset]"),
    "ellipsoid"     => (sdf_ellipsoid,     [4.0, 2.0, 3.0],      3, "Stretched ball. params: [a, b, c semi-axes]"),
)

# ==========================================================================
# JIT CASTING: GPU FOUNDRY
# ==========================================================================
# GRUG: Use shiny light-box to make gears. Once made, light-box sleeps.
#        You can cast from library or bring your own shape.
# ==========================================================================

function jit_cast_gears!(am::AntikytheraMap; preset::String="default")
    # GRUG: "default" = load the standard gear set for demo
    if preset == "default"
        am.gears[:Sphere]       = Cog(:Sphere,       sdf_sphere,        [5.0])
        am.gears[:Torus]        = Cog(:Torus,         sdf_torus,         [8.0, 2.0])
        am.gears[:Gyroid]       = Cog(:Gyroid,        sdf_gyroid,        [6.28, 0.0])
        am.gears[:TwistedTorus] = Cog(:TwistedTorus,  sdf_twisted_torus, [8.0, 2.0, 1.5])
        println("⚙️  GRUG: Foundry cast 4 default gears. Light-box is now off.")
    elseif preset == "all"
        for (name, (fn, params, nd, _)) in GEAR_LIBRARY
            sym = Symbol(uppercasefirst(name))
            am.gears[sym] = Cog(sym, fn, copy(params); ndims=nd)
        end
        println("⚙️  GRUG: Foundry cast $(length(GEAR_LIBRARY)) gears (full library). Light-box is now off.")
    else
        throw(MachineCrunch("UNKNOWN PRESET: $(preset)", "jit_cast_gears!"))
    end
end

function cast_single!(am::AntikytheraMap, gear_name::Symbol, shape_key::String, params::Vector{Float64})
    # GRUG: Cast one gear from library with custom params.
    if !haskey(GEAR_LIBRARY, shape_key)
        throw(MachineCrunch("NO SUCH SHAPE IN LIBRARY: $(shape_key)", "cast_single!"))
    end
    fn, _, nd, _ = GEAR_LIBRARY[shape_key]
    am.gears[gear_name] = Cog(gear_name, fn, params; ndims=nd)
    println("⚙️  GRUG: Cast gear :$(gear_name) as $(shape_key) with params=$(params)")
end

# ==========================================================================
# CORE GEOMETRIC OPERATIONS
# ==========================================================================
# GRUG: These are the things you can DO to gears.
#        Traditional math dies on most of these for complex shapes.
#        We just poke the field and measure what happens.
# ==========================================================================

# ----------------------------------------------------------
# VALIDATION HELPERS
# GRUG: Check everything before turning any gear.
# ----------------------------------------------------------
function _require_flow!(am::AntikytheraMap)
    if am.throttle_clamp < 0.01
        throw(MachineCrunch("THROTTLE SHUT. MACHINE IDLE. NO FLOW.", "throttle_check"))
    end
end

function _require_gear(am::AntikytheraMap, name::Symbol)::Cog
    !haskey(am.gears, name) && throw(MachineCrunch("GEAR :$(name) IS MISSING!", "gear_lookup"))
    return am.gears[name]
end

function _require_point(point::Vector{Float64}, gear::Cog)
    if length(point) != gear.ndims
        throw(MachineCrunch(
            "POINT IS $(length(point))D BUT GEAR :$(gear.name) IS $(gear.ndims)D.",
            "dimension_check"
        ))
    end
end

# GRUG: Make a poke vector. All zeros except position `dim` which gets value `val`.
function _basis(ndims::Int, dim::Int, val::Float64)::Vector{Float64}
    v = zeros(ndims)
    v[dim] = val
    return v
end

# ----------------------------------------------------------
# /probe — RAW SDF EVALUATION
# GRUG: "How far is this spot from the gear surface?"
#        Negative = inside. Zero = on surface. Positive = outside.
# ----------------------------------------------------------
function probe(am::AntikytheraMap, gear_name::Symbol, point::Vector{Float64})::Float64
    _require_flow!(am)
    gear = _require_gear(am, gear_name)
    _require_point(point, gear)
    am.query_count += 1
    return gear.shape_logic(point, gear.teeth_params)
end

# ----------------------------------------------------------
# /gradient — SPATIAL DIFFERENTIATION (THE CORE OPERATION)
# GRUG: "Which way does the gear surface tilt at this spot?"
#        We don't calculate. We poke and measure.
#        This is what traditional d/dx does symbolically,
#        but we do it spatially on the preloaded field.
# ----------------------------------------------------------
function gradient(am::AntikytheraMap, gear_name::Symbol, point::Vector{Float64})::Vector{Float64}
    _require_flow!(am)
    gear = _require_gear(am, gear_name)
    _require_point(point, gear)
    am.query_count += 1
    
    f = gear.shape_logic
    p = gear.teeth_params
    h = am.slack  # AK-47 rattle = finite difference step
    nd = gear.ndims
    
    grad = zeros(nd)
    try
        for dim in 1:nd
            fwd = f(point .+ _basis(nd, dim, h), p)
            bwd = f(point .- _basis(nd, dim, h), p)
            grad[dim] = (fwd - bwd) / (2 * h)
        end
    catch err
        throw(MachineCrunch(
            "GEAR CRUNCHED IN :$(gear_name) DURING GRADIENT.",
            sprint(showerror, err)
        ))
    end
    
    # GRUG: If math go crazy, stop machine. No silent fail!
    if any(isnan, grad) || any(isinf, grad)
        throw(MachineCrunch("GEAR JAMMED IN :$(gear_name). GRADIENT IS BROKEN.", "NaN/Inf detected"))
    end
    
    return grad
end

# ----------------------------------------------------------
# /normal — UNIT SURFACE NORMAL
# GRUG: "Which way does the surface FACE at this spot?"
#        Just the gradient, but normalized to length 1.
#        Needed for lighting, reflection, collision, everything.
#
# GRUG NOTE: If point has zero gradient (e.g. dead centre of torus tube,
#             sphere origin), we auto-project to nearest surface and warn.
#             No silent failures. GRUG SHOUT WHEN ROCK MOVES.
# ----------------------------------------------------------
function surface_normal(am::AntikytheraMap, gear_name::Symbol, point::Vector{Float64})::Vector{Float64}
    g = gradient(am, gear_name, point)
    n = norm(g)
    if n < 1e-12
        # GRUG: Zero gradient = degenerate point (symmetry axis, tube centre, etc.)
        # Project to nearest surface and retry. Warn loudly - no silent failures.
        projected = _project_to_surface(am, gear_name, point)
        dist_moved = norm(projected .- point)
        println("  WARNING: Zero gradient at $(point). Auto-projected to surface.")
        println("           Projected: $(projected)  (moved $(round(dist_moved, digits=4)))")
        g = gradient(am, gear_name, projected)
        n = norm(g)
        if n < 1e-12
            throw(MachineCrunch("GRADIENT IS ZERO AT THIS POINT. NO SURFACE HERE.", "surface_normal"))
        end
        return g ./ n
    end
    return g ./ n
end

# ----------------------------------------------------------
# /curvature — MEAN AND GAUSSIAN CURVATURE VIA HESSIAN
# GRUG: "How bendy is the gear surface at this spot?"
#        This needs SECOND derivatives. The Hessian matrix.
#        For composed SDFs, doing this symbolically is INSANE.
#        You'd need the chain rule applied to the chain rule.
#        But spatially? Just poke three times per pair of axes.
#
# GRUG NOTE: If point has zero gradient (degenerate/interior point),
#             we auto-project to nearest surface point and warn.
#             No silent failures. GRUG SHOUT WHEN ROCK MOVES.
#
# Returns: (mean_curvature, gaussian_curvature, principal_k1, principal_k2)
# ----------------------------------------------------------
function curvature(am::AntikytheraMap, gear_name::Symbol, point::Vector{Float64})
    _require_flow!(am)
    gear = _require_gear(am, gear_name)
    _require_point(point, gear)
    am.query_count += 1
    
    f = gear.shape_logic
    p = gear.teeth_params
    h = am.slack
    nd = gear.ndims
    
    # GRUG: First get the gradient (first derivatives)
    g = gradient(am, gear_name, point)
    g_norm = norm(g)
    
    # GRUG: Zero gradient = degenerate point (symmetry axis, tube centre, etc.)
    # Common causes: centre of sphere, tube axis of torus at major radius,
    # any point where the SDF has a local extremum or is exactly at an axis.
    # Auto-project to nearest surface and retry. Warn loudly - no silent failures.
    actual_point = point
    if g_norm < 1e-12
        projected = _project_to_surface(am, gear_name, point)
        dist_moved = norm(projected .- point)
        println("  WARNING: Zero gradient at $(point). Auto-projected to surface.")
        println("           Projected: $(projected)  (moved $(round(dist_moved, digits=4)))")
        actual_point = projected
        g = gradient(am, gear_name, actual_point)
        g_norm = norm(g)
        if g_norm < 1e-12
            throw(MachineCrunch("ZERO GRADIENT EVEN AFTER SURFACE PROJECTION. GEOMETRY IS DEGENERATE.", "curvature"))
        end
    end
    
    # GRUG: Now build the Hessian (second derivatives) at actual_point.
    # H[i,j] = d²f / (dxi dxj)
    # Each entry = poke twice, measure once.
    H = zeros(nd, nd)
    f0 = f(actual_point, p)
    try
        for i in 1:nd
            for j in i:nd
                if i == j
                    # GRUG: Diagonal = pure second derivative
                    fwd = f(actual_point .+ _basis(nd, i, h), p)
                    bwd = f(actual_point .- _basis(nd, i, h), p)
                    H[i, i] = (fwd - 2 * f0 + bwd) / (h * h)
                else
                    # GRUG: Off-diagonal = mixed partial
                    fpp = f(actual_point .+ _basis(nd, i, h) .+ _basis(nd, j, h), p)
                    fpm = f(actual_point .+ _basis(nd, i, h) .- _basis(nd, j, h), p)
                    fmp = f(actual_point .- _basis(nd, i, h) .+ _basis(nd, j, h), p)
                    fmm = f(actual_point .- _basis(nd, i, h) .- _basis(nd, j, h), p)
                    H[i, j] = (fpp - fpm - fmp + fmm) / (4 * h * h)
                    H[j, i] = H[i, j]  # Symmetric
                end
            end
        end
    catch err
        throw(MachineCrunch("GEAR CRUNCHED DURING HESSIAN IN :$(gear_name).", sprint(showerror, err)))
    end
    
    # GRUG: Mean curvature from divergence of unit normal
    # κ_mean = (1/|∇f|) * (Δf - (∇f' H ∇f)/|∇f|²)
    # where Δf = trace(H) = laplacian
    lapl = tr(H)
    bilinear = dot(g, H * g)
    mean_k = (g_norm^2 * lapl - bilinear) / (2 * g_norm^3)
    
    # GRUG: Gaussian curvature (3D only, needs adjugate of bordered Hessian)
    gauss_k = 0.0
    if nd == 3
        # Bordered Hessian method for implicit surfaces
        # Build the 4x4 bordered matrix, take cofactor
        # But Grug do it the direct way with the adjugate formula
        gx, gy, gz = g[1], g[2], g[3]
        
        # Adjugate of Hessian projected onto tangent plane
        # Gaussian curvature = det(shape_operator) 
        # For implicit surface: use the formula involving bordered Hessian
        B = zeros(4, 4)
        B[1:3, 1:3] .= H
        B[1:3, 4] .= g
        B[4, 1:3] .= vec(g')
        B[4, 4] = 0.0
        
        gauss_k = -det(B) / (g_norm^4)
    end
    
    # GRUG: Principal curvatures from mean and gaussian
    # κ_mean = (κ1 + κ2) / 2
    # κ_gauss = κ1 * κ2
    # So κ1, κ2 are roots of: κ² - 2*κ_mean*κ + κ_gauss = 0
    discriminant = mean_k^2 - gauss_k
    if discriminant < 0
        discriminant = 0.0  # GRUG: Numerical noise. Clamp it.
    end
    k1 = mean_k + sqrt(discriminant)
    k2 = mean_k - sqrt(discriminant)
    
    return (mean=mean_k, gaussian=gauss_k, k1=k1, k2=k2)
end

# ----------------------------------------------------------
# /laplacian — TRACE OF HESSIAN (SECOND-ORDER OPERATOR)
# GRUG: "How much does the field want to spread out here?"
#        Sum of all pure second derivatives.
#        Symbolically brutal for composed SDFs.
#        Spatially? Just three center-difference pokes.
# ----------------------------------------------------------
function laplacian(am::AntikytheraMap, gear_name::Symbol, point::Vector{Float64})::Float64
    _require_flow!(am)
    gear = _require_gear(am, gear_name)
    _require_point(point, gear)
    am.query_count += 1
    
    f = gear.shape_logic
    p = gear.teeth_params
    h = am.slack
    nd = gear.ndims
    f0 = f(point, p)
    
    result = 0.0
    try
        for dim in 1:nd
            fwd = f(point .+ _basis(nd, dim, h), p)
            bwd = f(point .- _basis(nd, dim, h), p)
            result += (fwd - 2 * f0 + bwd) / (h * h)
        end
    catch err
        throw(MachineCrunch("LAPLACIAN CRUNCH IN :$(gear_name).", sprint(showerror, err)))
    end
    
    return result
end

# ----------------------------------------------------------
# /divergence — DIVERGENCE OF GRADIENT FIELD
# GRUG: "Is the gradient field squeezing or expanding here?"
#        div(∇f) = Δf = laplacian. Same thing for scalar fields.
#        But Grug expose it separately because the CONCEPT is
#        different even though the NUMBER is the same.
# ----------------------------------------------------------
function divergence(am::AntikytheraMap, gear_name::Symbol, point::Vector{Float64})::Float64
    return laplacian(am, gear_name, point)
end

# ==========================================================================
# CSG BOOLEAN OPERATIONS: UNION / INTERSECT / SUBTRACT
# ==========================================================================
# GRUG: This is where SDF DESTROYS traditional methods.
#        Boolean ops on implicit surfaces are just min() and max().
#        But try to differentiate THROUGH a min/max junction 
#        symbolically. The derivative is DISCONTINUOUS at the seam.
#        Traditional AD/symbolic diff DIES here.
#        Spatial probe? Doesn't care. Poke both sides. Done.
# ==========================================================================

# ----------------------------------------------------------
# /boolean union — Combine two gears. Keep the outside of both.
# GRUG: Smash two rocks together. Keep the big shape.
# ----------------------------------------------------------
function boolean_union!(am::AntikytheraMap, result_name::Symbol, 
                        gear_a::Symbol, gear_b::Symbol)
    a = _require_gear(am, gear_a)
    b = _require_gear(am, gear_b)
    
    combined_logic = (p, params) -> begin
        da = a.shape_logic(p, a.teeth_params)
        db = b.shape_logic(p, b.teeth_params)
        return min(da, db)
    end
    
    am.gears[result_name] = Cog(result_name, combined_logic, [0.0]; ndims=a.ndims)
    println("⚙️  GRUG: Boolean UNION :$(gear_a) ∪ :$(gear_b) → :$(result_name)")
end

# ----------------------------------------------------------
# /boolean intersect — Keep only where both gears overlap.
# GRUG: Two rocks overlap. Keep the overlap part only.
# ----------------------------------------------------------
function boolean_intersect!(am::AntikytheraMap, result_name::Symbol,
                            gear_a::Symbol, gear_b::Symbol)
    a = _require_gear(am, gear_a)
    b = _require_gear(am, gear_b)
    
    combined_logic = (p, params) -> begin
        da = a.shape_logic(p, a.teeth_params)
        db = b.shape_logic(p, b.teeth_params)
        return max(da, db)
    end
    
    am.gears[result_name] = Cog(result_name, combined_logic, [0.0]; ndims=a.ndims)
    println("⚙️  GRUG: Boolean INTERSECT :$(gear_a) ∩ :$(gear_b) → :$(result_name)")
end

# ----------------------------------------------------------
# /boolean subtract — Cut one gear out of another.
# GRUG: Use gear B as cookie cutter on gear A.
# ----------------------------------------------------------
function boolean_subtract!(am::AntikytheraMap, result_name::Symbol,
                           gear_a::Symbol, gear_b::Symbol)
    a = _require_gear(am, gear_a)
    b = _require_gear(am, gear_b)
    
    combined_logic = (p, params) -> begin
        da = a.shape_logic(p, a.teeth_params)
        db = b.shape_logic(p, b.teeth_params)
        return max(da, -db)
    end
    
    am.gears[result_name] = Cog(result_name, combined_logic, [0.0]; ndims=a.ndims)
    println("⚙️  GRUG: Boolean SUBTRACT :$(gear_a) \\ :$(gear_b) → :$(result_name)")
end

# ==========================================================================
# SMOOTH BLEND: DIFFERENTIABLE BOOLEAN UNION
# ==========================================================================
# GRUG: Normal boolean union has a SHARP crease where gears meet.
#        The derivative is discontinuous there. Traditional methods 
#        CANNOT handle this. Smooth blend uses a polynomial fillet 
#        to round the junction. Now the derivative exists everywhere.
#        But the blend region has NO closed-form symbolic gradient.
#        You MUST probe it spatially. This is our territory.
# ==========================================================================

# ----------------------------------------------------------
# /blend — Smooth union of two gears with fillet radius k.
# params: gear_a, gear_b, blend_radius k
# Bigger k = smoother blend. k=0 = hard boolean.
# ----------------------------------------------------------
function blend!(am::AntikytheraMap, result_name::Symbol,
                gear_a::Symbol, gear_b::Symbol, k::Float64)
    a = _require_gear(am, gear_a)
    b = _require_gear(am, gear_b)
    
    if k < 0
        throw(MachineCrunch("BLEND RADIUS MUST BE >= 0.", "blend!"))
    end
    
    blended_logic = (p, params) -> begin
        da = a.shape_logic(p, a.teeth_params)
        db = b.shape_logic(p, b.teeth_params)
        if k < 1e-12
            return min(da, db)  # Degenerate: hard boolean
        end
        # GRUG: Polynomial smooth-min. The magic fillet.
        h_val = max(k - abs(da - db), 0.0) / k
        return min(da, db) - h_val * h_val * h_val * k * (1.0 / 6.0)
    end
    
    am.gears[result_name] = Cog(result_name, blended_logic, [k]; ndims=a.ndims)
    println("⚙️  GRUG: Smooth BLEND :$(gear_a) + :$(gear_b) → :$(result_name) (k=$(k))")
end

# ==========================================================================
# MORPH: PARAMETER INTERPOLATION BETWEEN GEAR STATES
# ==========================================================================
# GRUG: Take a gear and smoothly change its teeth.
#        At t=0 you have state A. At t=1 you have state B.
#        In between? The gear is in a shape that has NO NAME 
#        in traditional geometry. But the SDF still works.
#        You can still probe it. Still differentiate it.
#        Traditional parametric methods need explicit formulas 
#        for every intermediate state. We just interpolate teeth.
# ==========================================================================

function morph!(am::AntikytheraMap, gear_name::Symbol, 
                target_params::Vector{Float64}, t::Float64)
    gear = _require_gear(am, gear_name)
    
    if t < 0.0 || t > 1.0
        throw(MachineCrunch("MORPH t MUST BE IN [0, 1]. GOT $(t).", "morph!"))
    end
    if length(target_params) != length(gear.teeth_params)
        throw(MachineCrunch(
            "TARGET HAS $(length(target_params)) PARAMS BUT GEAR HAS $(length(gear.teeth_params)).",
            "morph!"
        ))
    end
    
    # GRUG: Linear interpolation of teeth. Simple but powerful.
    gear.teeth_params .= (1.0 - t) .* gear.teeth_params .+ t .* target_params
    println("⚙️  GRUG: Morphed :$(gear_name) teeth to $(gear.teeth_params) (t=$(t))")
end

# ==========================================================================
# FLOW: STREAMLINE TRACING THROUGH GRADIENT FIELD
# ==========================================================================
# GRUG: "If I drop a leaf in the river, where does it go?"
#        Follow the gradient downhill from a starting point.
#        For complex SDF compositions, the flow paths have 
#        NO analytic solution. The streamlines twist through 
#        topological features that can't be expressed in closed form.
#        But stepping along the gradient? That always works.
# ==========================================================================

function flow(am::AntikytheraMap, gear_name::Symbol, start::Vector{Float64};
              steps::Int=100, step_size::Float64=0.1, direction::Symbol=:descent)::Vector{Vector{Float64}}
    _require_flow!(am)
    gear = _require_gear(am, gear_name)
    _require_point(start, gear)
    am.query_count += 1
    
    sign_mult = direction == :descent ? -1.0 : 1.0
    
    path = Vector{Vector{Float64}}()
    push!(path, copy(start))
    current = copy(start)
    
    # GRUG: If start has zero gradient (e.g. exact centre of sphere),
    # perturb slightly so we can actually walk somewhere.
    g_check = gradient(am, gear_name, current)
    if norm(g_check) < 1e-10
        # Nudge along each axis until we find a direction
        nd = gear.ndims
        for d in 1:nd
            perturbed = copy(current)
            perturbed[d] += am.slack * 100
            gp = gradient(am, gear_name, perturbed)
            if norm(gp) > 1e-10
                current = perturbed
                push!(path, copy(current))
                break
            end
        end
    end
    
    prev_sdf = gear.shape_logic(current, gear.teeth_params)
    for i in 1:steps
        g = gradient(am, gear_name, current)
        g_norm = norm(g)
        if g_norm < 1e-10
            break
        end
        next = current .+ sign_mult .* step_size .* (g ./ g_norm)
        next_sdf = gear.shape_logic(next, gear.teeth_params)
        if prev_sdf * next_sdf < 0.0
            lo, hi = copy(current), copy(next)
            lo_sdf = prev_sdf
            for _ in 1:10
                mid = (lo .+ hi) ./ 2
                mid_sdf = gear.shape_logic(mid, gear.teeth_params)
                if abs(mid_sdf) < am.slack * 0.1
                    next = mid
                    next_sdf = mid_sdf
                    break
                end
                if lo_sdf * mid_sdf < 0.0
                    hi = mid
                else
                    lo = mid
                    lo_sdf = mid_sdf
                end
            end
            current = next
            push!(path, copy(current))
            break
        end
        current = next
        prev_sdf = next_sdf
        push!(path, copy(current))
        if abs(next_sdf) < max(am.slack * 10, step_size * 0.01)
            break
        end
    end
    
    return path
end

# ==========================================================================
# LEVELSET: FIND ZERO-CROSSING ALONG A RAY
# ==========================================================================
# GRUG: "Where does a ray hit the gear surface?"
#        March along the ray using the SDF itself as step size.
#        This is sphere tracing / ray marching.
#        Traditional ray-surface intersection for implicit surfaces 
#        requires solving f(o + td) = 0, which for complex SDFs 
#        has NO closed-form solution. Newton's method can diverge.
#        But SDF gives us a safe step distance at every point.
#        So we just walk forward, guaranteed not to overshoot.
# ==========================================================================

function levelset(am::AntikytheraMap, gear_name::Symbol,
                  origin::Vector{Float64}, direction::Vector{Float64};
                  max_steps::Int=256, max_dist::Float64=100.0)
    _require_flow!(am)
    gear = _require_gear(am, gear_name)
    _require_point(origin, gear)
    _require_point(direction, gear)
    am.query_count += 1
    
    dir_norm = norm(direction)
    if dir_norm < 1e-12
        throw(MachineCrunch("RAY DIRECTION IS ZERO.", "levelset"))
    end
    dir = direction ./ dir_norm
    
    t = 0.0
    for i in 1:max_steps
        p = origin .+ t .* dir
        d = gear.shape_logic(p, gear.teeth_params)
        
        # GRUG: Close enough to surface? Found it!
        if abs(d) < am.slack
            return (hit=true, point=p, distance=t, steps=i)
        end
        
        # GRUG: SDF tells us we can safely step |d| forward
        t += abs(d)
        
        if t > max_dist
            break
        end
    end
    
    return (hit=false, point=origin .+ t .* dir, distance=t, steps=max_steps)
end

# ==========================================================================
# GEODESIC: APPROXIMATE GEODESIC DISTANCE ON SURFACE
# ==========================================================================
# GRUG: "What's the shortest path ALONG the surface between two points?"
#        This requires solving the Eikonal equation |∇T| = 1.
#        For arbitrary implicit surfaces, this is COMPLETELY 
#        intractable analytically. Even numerical methods (fast 
#        marching) need a grid. We do it with gradient-constrained 
#        stepping: project each step onto the tangent plane.
#        It's approximate. But it converges. And it works on 
#        surfaces that don't even have names.
# ==========================================================================

function geodesic(am::AntikytheraMap, gear_name::Symbol,
                  start::Vector{Float64}, target::Vector{Float64};
                  max_steps::Int=500, step_size::Float64=0.05)
    _require_flow!(am)
    gear = _require_gear(am, gear_name)
    _require_point(start, gear)
    _require_point(target, gear)
    am.query_count += 1
    
    # GRUG: First project both points onto the surface.
    # If start/end are not on the surface (SDF != 0), project them.
    # Warn loudly if significant movement needed — no silent failures.
    current = _project_to_surface(am, gear_name, start)
    start_moved = norm(current .- start)
    if start_moved > am.slack * 10
        println("  WARNING: Start point $(start) not on surface (SDF=$(round(gear.shape_logic(start, gear.teeth_params), digits=4))).")
        println("           Projected to $(round.(current, digits=4))  (moved $(round(start_moved, digits=4)))")
    end
    
    target_proj = _project_to_surface(am, gear_name, target)
    end_moved = norm(target_proj .- target)
    if end_moved > am.slack * 10
        println("  WARNING: End point $(target) not on surface (SDF=$(round(gear.shape_logic(target, gear.teeth_params), digits=4))).")
        println("           Projected to $(round.(target_proj, digits=4))  (moved $(round(end_moved, digits=4)))")
    end
    
    total_dist = 0.0
    path = [copy(current)]
    
    for i in 1:max_steps
        # GRUG: Direction toward target
        to_target = target_proj .- current
        remaining = norm(to_target)
        
        # GRUG: Close enough? Done.
        if remaining < step_size
            total_dist += remaining
            push!(path, copy(target_proj))
            break
        end
        
        # GRUG: Project direction onto tangent plane (remove normal component)
        n = surface_normal(am, gear_name, current)
        tangent_dir = to_target .- dot(to_target, n) .* n
        td_norm = norm(tangent_dir)
        
        if td_norm < 1e-12
            # GRUG: Target is directly above/below on the normal. 
            # Need to go around. Perturb.
            tangent_dir = to_target
            td_norm = norm(tangent_dir)
        end
        
        # GRUG: Step along tangent, then project back to surface
        current = current .+ step_size .* (tangent_dir ./ td_norm)
        current = _project_to_surface(am, gear_name, current)
        total_dist += step_size
        push!(path, copy(current))
    end
    
    return (distance=total_dist, path=path, steps=length(path))
end

# GRUG: Push a point onto the nearest surface (SDF = 0).
# Walk along the gradient until we hit zero.
#
# GRUG NOTE: If the starting point has zero gradient (degenerate symmetry point
#             like the tube axis of a torus at its major radius, or sphere centre),
#             we try perturbations in each axis direction to escape the flat void,
#             then project from the best perturbed position.
#             No silent failures: if nothing works, we return best guess.
function _project_to_surface(am::AntikytheraMap, gear_name::Symbol, 
                              point::Vector{Float64}; max_iter::Int=50)::Vector{Float64}
    gear = _require_gear(am, gear_name)
    nd = gear.ndims
    f = gear.shape_logic
    p = gear.teeth_params
    h = am.slack
    
    # GRUG: Helper - gradient at an arbitrary point (no query_count increment)
    function _raw_gradient(pt::Vector{Float64})::Vector{Float64}
        g = zeros(nd)
        for dim in 1:nd
            ep = copy(pt); ep[dim] += h
            em = copy(pt); em[dim] -= h
            g[dim] = (f(ep, p) - f(em, p)) / (2 * h)
        end
        return g
    end
    
    # GRUG: Helper - project from a point that has nonzero gradient
    function _project_from(start::Vector{Float64})::Vector{Float64}
        cur = copy(start)
        for _ in 1:max_iter
            d = f(cur, p)
            if abs(d) < h * 0.1
                return cur
            end
            g = _raw_gradient(cur)
            g_norm = norm(g)
            if g_norm < 1e-12
                return cur  # stuck again
            end
            cur = cur .- d .* (g ./ (g_norm^2))
        end
        return cur
    end
    
    # GRUG: Check if starting point already has nonzero gradient
    d0 = f(point, p)
    if abs(d0) < h * 0.1
        return copy(point)  # Already on surface
    end
    
    g0 = _raw_gradient(point)
    if norm(g0) >= 1e-10
        # Normal case: gradient exists, project directly
        return _project_from(point)
    end
    
    # GRUG: Zero gradient at starting point. Try perturbations to escape.
    # Use the SDF value magnitude as perturbation scale (we're |d| from the surface).
    # Try ±|d| perturbations along each axis, pick the one with best gradient.
    perturb_scale = abs(d0) > h ? abs(d0) : h * 10
    
    best_pt = copy(point)
    best_g_norm = 0.0
    
    # Try perturbations in each axis direction (both + and -)
    for dim in 1:nd
        for sign in (+1.0, -1.0)
            perturbed = copy(point)
            perturbed[dim] += sign * perturb_scale
            gp = _raw_gradient(perturbed)
            gp_norm = norm(gp)
            if gp_norm > best_g_norm
                best_g_norm = gp_norm
                best_pt = perturbed
            end
        end
    end
    
    if best_g_norm < 1e-12
        # GRUG: Still stuck. Try larger perturbations (2x, 5x scale).
        for scale_mult in (2.0, 5.0, 10.0)
            for dim in 1:nd
                for sign in (+1.0, -1.0)
                    perturbed = copy(point)
                    perturbed[dim] += sign * perturb_scale * scale_mult
                    gp = _raw_gradient(perturbed)
                    gp_norm = norm(gp)
                    if gp_norm > best_g_norm
                        best_g_norm = gp_norm
                        best_pt = perturbed
                    end
                end
            end
            if best_g_norm >= 1e-10
                break
            end
        end
    end
    
    if best_g_norm < 1e-12
        # GRUG: Completely stuck. Geometry is degenerate everywhere nearby.
        # Return original point. Caller should handle this.
        return copy(point)
    end
    
    # GRUG: Project from the best perturbed position
    return _project_from(best_pt)
end

# ==========================================================================
# USER-DEFINED SDF PARSING
# ==========================================================================
# GRUG: User bring own rock. We turn it into gear.
#        User types math expression. We make it callable.
#        This is where the machine becomes UNIVERSAL.
# ==========================================================================

const USER_GEAR_COUNTER = Ref(0)

function parse_user_sdf!(am::AntikytheraMap, expr_str::String, params::AbstractVector; 
                         name::Union{Symbol,Nothing}=nothing, ndims::Int=3)
    # GRUG: Turn string into Julia function.
    # "sin(x)*cos(y) + sqrt(z)" → (p, params) -> sin(p[1])*cos(p[2]) + sqrt(p[3])
    
    # Sanitize: only allow safe characters
    safe_expr = replace(expr_str, r"[^0-9+\-*\/\.\(\)\^\s\w]" => "")
    
    if isempty(safe_expr)
        throw(MachineCrunch("EMPTY EXPRESSION AFTER SANITIZATION.", "parse_user_sdf!"))
    end
    
    # GRUG: Build the function body.
    # Replace x,y,z with p[1],p[2],p[3] etc.
    body = lowercase(safe_expr)
    
    # Coordinate substitution: x,y,z → p[1],p[2],p[3], etc.
    # Use word boundaries to avoid replacing inside words like "sqrt" or "exp"
    coord_map = Dict(
        'x' => "p[1]", 'y' => "p[2]", 'z' => "p[3]",
        'r' => "sqrt(p[1]^2+p[2]^2+p[3]^2)",  # radial distance
        't' => "atan(p[2],p[1])",              # theta (azimuthal)
        'u' => "atan(p[3],sqrt(p[1]^2+p[2]^2))" # phi (polar)
    )
    
    for (c, sub) in coord_map
        # Use regex with word boundaries to match standalone letters only
        body = replace(body, Regex("\\b$(string(c))\\b") => sub)
    end
    
    # GRUG: params[i] accessible as a,b,c,... or p0,p1,p2,...
    for i in 1:min(length(params), 26)
        # Use word boundary for single-letter parameter names
        body = replace(body, Regex("\\b$(string('a' + i - 1))\\b") => "params[$i]")
        body = replace(body, "p$(i)" => "params[$i]")
    end
    
    # Build full function string
    func_str = "(p, params) -> begin $body end"
    
    # GRUG: Try to compile it.
    try
        func = eval(Meta.parse(func_str))
        
        # Generate name if not provided
        if name === nothing
            USER_GEAR_COUNTER[] += 1
            name = Symbol("UserGear_", USER_GEAR_COUNTER[])
        end
        
        # Validate: try calling it once using invokelatest to handle world age
        test_p = zeros(ndims)
        test_result = Base.invokelatest(func, test_p, params)
        
        if !isa(test_result, Number)
            throw(MachineCrunch("EXPRESSION DOES NOT RETURN A NUMBER.", "parse_user_sdf!"))
        end
        
        # GRUG: If no params, use dummy param so gear can turn.
        # User SDFs without parameters are still valid geometries.
        gear_params = isempty(params) ? [0.0] : copy(params)
        
        # Create the gear
        am.gears[name] = Cog(name, func, gear_params; ndims=ndims)
        println("⚙️  GRUG: Cast user-defined gear :$(name)")
        println("   Expression: $(strip(expr_str))")
        println("   Params: $(params)")
        return name
        
    catch err
        throw(MachineCrunch(
            "FAILED TO PARSE USER EXPRESSION: $(strip(expr_str))",
            sprint(showerror, err)
        ))
    end
end

# ==========================================================================
# USER-DEFINED DIFFERENTIAL OPERATORS
# ==========================================================================
# GRUG: User say "poke the gear HERE, in THIS direction, with THIS order."
#        We build the stencil dynamically. No pre-baked limits.
# ==========================================================================

struct DifferentialSpec
    # Vector of (dim, order) pairs: [(1,1), (3,2)] = d³f/dx dz²
    specs::Vector{Tuple{Int, Int}}
    total_order::Int
end

function parse_diff_spec(spec_str::String)::DifferentialSpec
    # GRUG: Parse strings like:
    # "dx" → [(1,1)]
    # "dxdz" or "dxdz" → [(1,1), (3,1)]
    # "d2xdz" or "d²x dz" → [(1,2), (3,1)]
    # "d3x" → [(1,3)]
    
    specs = Tuple{Int, Int}[]
    total = 0
    
    # Pattern: optional number + d + optional number + x/y/z
    pattern = r"(?:d(?:(\d+))?([xyz]))+"
    
    remaining = lowercase(replace(spec_str, r"\s+" => ""))
    
    while !isempty(remaining)
        m = match(r"^d(?:(\d+))?([xyz])", remaining)
        if m === nothing
            throw(MachineCrunch("INVALID DIFF SPEC NEAR: '$(remaining)'", "parse_diff_spec"))
        end
        
        order = m.captures[1] === nothing ? 1 : parse(Int, m.captures[1])
        dim_char = m.captures[2][1]
        dim = dim_char == 'x' ? 1 : dim_char == 'y' ? 2 : 3
        
        push!(specs, (dim, order))
        total += order
        
        remaining = remaining[length(m.match)+1:end]
    end
    
    if isempty(specs)
        throw(MachineCrunch("EMPTY DIFFERENTIAL SPEC.", "parse_diff_spec"))
    end
    
    return DifferentialSpec(specs, total)
end

function apply_differential(am::AntikytheraMap, gear_name::Symbol, point::Vector{Float64}, 
                            diff_spec::DifferentialSpec)
    # GRUG: Apply the user-defined differential operator.
    # Uses finite difference stencil with central differences.
    # Higher order = more pokes. d³f/dx³ needs 4 pokes minimum.
    
    _require_flow!(am)
    gear = _require_gear(am, gear_name)
    _require_point(point, gear)
    am.query_count += 1
    
    f = gear.shape_logic
    p = gear.teeth_params
    h = am.slack
    nd = gear.ndims
    
    # GRUG: Build stencil coefficients for central difference.
    # For order k, we need coefficients at positions ±h, ±2h, ... ±kh
    # Central difference: f^(k)(x) ≈ Σ c_i * f(x + i*h) / h^k
    
    function compute_stencil(order::Int)
        # Central difference coefficients for derivative of given order
        # f^(k)(x) ≈ Σ_{i=-n}^{n} c_i f(x + i*h)
        # where n = ceil(k/2) and c_i are the coefficients
        
        n = ceil(Int, order / 2)
        
        # Build Vandermonde system for central difference
        # Solve for coefficients that give exact derivative for polynomials
        m = 2 * n + 1
        
        # Vandermonde matrix: A[i,j] = j^i where j = -n, ..., n
        A = zeros(m, m)
        b = zeros(m)
        
        for i in 0:(m-1)
            for j in -n:n
                A[i+1, j+n+1] = j^i
            end
        end
        b[order+1] = factorial(order)
        
        # Solve for coefficients
        coeffs = A \ b
        return Dict((i-n-1) => coeffs[i] for i in 1:m)
    end
    
    # GRUG: Build the stencil point-weight map.
    # result_grid maps (evaluation_point → accumulated_weight).
    # Start with weight=1.0 at the base point.
    # For each (dim, order) spec, expand the current set of points
    # by applying the 1D stencil in that dimension.
    # At the end: result = Σ weight * f(point) / h^total_order
    
    result_grid = Dict{Vector{Float64}, Float64}()
    result_grid[copy(point)] = 1.0  # weight, not value!
    
    for (dim, order) in diff_spec.specs
        stencil = compute_stencil(order)
        
        new_grid = Dict{Vector{Float64}, Float64}()
        
        for (pt, weight) in result_grid
            for (offset, coeff) in stencil
                new_pt = copy(pt)
                new_pt[dim] += offset * h
                new_grid[new_pt] = get(new_grid, new_pt, 0.0) + weight * coeff
            end
        end
        
        result_grid = new_grid
    end
    
    # Evaluate: Σ weight * f(point) / h^total_order
    numerator = 0.0
    for (pt, weight) in result_grid
        numerator += weight * f(pt, p)
    end
    
    denominator = h ^ diff_spec.total_order
    
    return numerator / denominator
end

# ==========================================================================
# CLI KEEPALIVE REPL
# ==========================================================================
# GRUG: This is the FRONT DOOR. User types commands. Machine does geometry.
#        Machine stays alive between commands. Gears stay loaded.
#        Throttle stays where you set it. Slack stays calibrated.
#        This is the keepalive loop. The machine BREATHES here.
# ==========================================================================

function print_banner()
    println("""
    
    ╔══════════════════════════════════════════════════════════════╗
    ║        ⚙️  THE ANTIKYTHERA DIFF-ENGINE  ⚙️                  ║
    ║              GEOM-CALC v2.0                                 ║
    ║                                                             ║
    ║  "Calculus is just gears turning."                          ║
    ║                                                             ║
    ║  Geometric operations on preloaded SDF fields.              ║
    ║  Derivative is spatial, not symbolic.                       ║
    ║  GPU is foundry. Slack is tolerance. Throttle is flow.      ║
    ╚══════════════════════════════════════════════════════════════╝
    
    Type /help for commands. Type /quit to shut down.
    """)
end

function print_help()
    println("""
    ═══════════════════════════════════════════════════════════════
    ⚙️  ANTIKYTHERA DIFF-ENGINE — COMMAND REFERENCE
    ═══════════════════════════════════════════════════════════════
    
    MACHINE CONTROL
    ───────────────
      /cast [preset]       Cast gears from foundry. 
                           preset = "default" | "all"
      /cast! <name> <shape> [p1 p2 ...]
      /gear  <name> <shape> [p1 p2 ...]   (same as /cast!)
                           Cast single gear with custom params.
                           Shapes: sphere, torus, box, cylinder, 
                                   gyroid, schwarz, twisted_torus,
                                   cone, capsule, plane, ellipsoid
      /throttle <0.0-1.0>  Set flow level. 0 = idle. 1 = max.
      /slack <value>        Set tolerance band (ε). Default 0.01.
      /gears               List all loaded gears.
      /status              Machine state: throttle, slack, queries.
      /library             Show available gear shapes.
    
    GEOMETRIC OPERATIONS (require throttle > 0)
    ─────────────────────────────────────────────
      /probe <gear> <x y z>
          Raw SDF value. How far is this point from the surface?
    
      /gradient <gear> <x y z>
          Spatial derivative. Which way does the surface tilt?
          (Intractable symbolically for composed/boolean SDFs)
    
      /normal <gear> <x y z>
          Unit surface normal. The gradient, normalized.
    
      /curvature <gear> <x y z>
          Mean + Gaussian curvature via spatial Hessian.
          (Intractable: requires d²/dx² on nested SDFs)
    
      /laplacian <gear> <x y z>
          Trace of Hessian. Field spreading tendency.
          (Intractable: sum of second derivatives on composed fields)
    
      /divergence <gear> <x y z>
          Divergence of gradient field (= laplacian for scalar SDF).
    
      /flow <gear> <x y z> [steps] [step_size] [ascent|descent]
          Trace streamline through gradient field.
          (Intractable: no analytic solution for complex topology)
    
      /levelset <gear> <ox oy oz> <dx dy dz> [max_steps]
          Ray-march to find where ray hits gear surface.
          (Intractable: f(o+td)=0 has no closed form for complex SDFs)
    
      /geodesic <gear> <x1 y1 z1> <x2 y2 z2> [max_steps]
          Approximate shortest path along the surface.
          (Intractable: requires solving Eikonal equation |∇T|=1)
    
    CSG / COMBINATION OPERATIONS
    ─────────────────────────────
      /boolean union <result> <gear_a> <gear_b>
          Combine two gears. Keep the hull.
          (Derivative is discontinuous at junction — 
           symbolic diff DIES at min() boundary)
    
      /boolean intersect <result> <gear_a> <gear_b>
          Keep only the overlap region.
    
      /boolean subtract <result> <gear_a> <gear_b>
          Cut gear_b out of gear_a.
    
      /blend <result> <gear_a> <gear_b> <radius>
          Smooth union with polynomial fillet.
          (Blend region has NO closed-form gradient.
           Must be probed spatially.)
    
    USER-DEFINED GEOMETRY
    ─────────────────────
      /sdf <expression> [p1 p2 ...]
          Define a custom SDF from a math expression.
          Coordinates: x,y,z = p[1],p[2],p[3]
                       r = radial distance, t = theta, u = phi
          Parameters: a,b,c,... or p1,p2,p3 = params[1],params[2],...
          Example: /sdf "sin(x)*cos(y)+sqrt(z)-a" 2.0
                   Creates UserGear_N with params=[2.0]
          (User-defined SDFs have no closed-form gradient.
           Symbolic differentiation is impossible. Spatial probe works.)
    
      /diff <gear> <spec> <x y z>
          Apply arbitrary differential operator.
          Spec format: dx, dy, dz, d2x, dxdz, d3xd2y, etc.
          Example: /diff MyGear d2xdz 1.0 2.0 3.0
                   Computes d³f/dx²dz at the given point.
          (User-defined differential orders are built from
           finite difference stencils. No symbolic limits.)
    
    DEFORMATION
    ───────────
      /morph <gear> <t> <p1 p2 ...>
          Interpolate gear teeth toward target params at ratio t.
          (Intermediate shapes have no name in traditional geometry.
           SDF doesn't care. Probe still works.)
    
    SYSTEM
    ──────
      /help                This scroll.
      /quit                Shut down the machine.
    ═══════════════════════════════════════════════════════════════
    """)
end

# ----------------------------------------------------------
# PARSER HELPERS
# GRUG: Turn user words into numbers. Carefully.
# ----------------------------------------------------------
function _parse_floats(tokens::Vector{SubString{String}}, start::Int, count::Int)::Vector{Float64}
    if start + count - 1 > length(tokens)
        throw(MachineCrunch(
            "NEED $(count) NUMBERS STARTING AT POSITION $(start). GOT $(length(tokens) - start + 1).",
            "parser"
        ))
    end
    result = Float64[]
    for i in start:(start + count - 1)
        try
            push!(result, parse(Float64, tokens[i]))
        catch
            throw(MachineCrunch("'$(tokens[i])' IS NOT A NUMBER.", "parser"))
        end
    end
    return result
end

function _parse_symbol(tokens::Vector{SubString{String}}, pos::Int)::Symbol
    if pos > length(tokens)
        throw(MachineCrunch("EXPECTED GEAR NAME AT POSITION $(pos).", "parser"))
    end
    return Symbol(tokens[pos])
end

# ----------------------------------------------------------
# THE KEEPALIVE LOOP
# GRUG: This is where the machine breathes.
#        It sits here between commands, all gears loaded,
#        throttle set, slack calibrated, waiting for input.
#        The field is always present. The machine is always warm.
# ----------------------------------------------------------
function keepalive!(am::AntikytheraMap)
    print_banner()
    
    while true
        print("\n⚙️  AK> ")
        line = ""
        try
            line = readline()
        catch e
            # GRUG: EOF or broken pipe. Shut down clean.
            if isa(e, InterruptException)
                println("\n⚙️  GRUG: Machine interrupted. Shutting down.")
            end
            break
        end
        
        line = strip(line)
        isempty(line) && continue
        
        tokens = split(line)
        cmd = lowercase(String(tokens[1]))
        
        try
            # ── SYSTEM COMMANDS ──
            if cmd == "/quit" || cmd == "/exit"
                println("⚙️  GRUG: Shutting down. Gears stop. Valve closes. Goodnight.")
                break
                
            elseif cmd == "/help"
                print_help()
                
            elseif cmd == "/status"
                println("  ⚙️  ANTIKYTHERA STATUS")
                println("  ─────────────────────")
                println("  Throttle:  $(am.throttle_clamp)")
                println("  Slack:     $(am.slack)")
                println("  Gears:     $(length(am.gears))")
                println("  Queries:   $(am.query_count)")
                for (name, gear) in am.gears
                    println("    :$(name) — $(gear.ndims)D, params=$(gear.teeth_params)")
                end
                
            elseif cmd == "/gears"
                if isempty(am.gears)
                    println("  No gears loaded. Use /cast to load from foundry.")
                else
                    println("  ⚙️  LOADED GEARS:")
                    for (name, gear) in am.gears
                        println("    :$(name) — $(gear.ndims)D, teeth=$(gear.teeth_params)")
                    end
                end
                
            elseif cmd == "/library"
                println("  ⚙️  GEAR LIBRARY:")
                for (name, (_, params, nd, desc)) in sort(collect(GEAR_LIBRARY))
                    println("    $(name) — $(desc) [$(nd)D, default=$(params)]")
                end
                
            # ── MACHINE CONTROL ──
            elseif cmd == "/cast"
                preset = length(tokens) >= 2 ? String(tokens[2]) : "default"
                jit_cast_gears!(am; preset=preset)
                
            elseif cmd == "/cast!" || cmd == "/gear"
                # /cast! GearName shape p1 p2 p3 ...
                # /gear  GearName shape p1 p2 p3 ...  (alias)
                if length(tokens) < 3
                    println("  Usage: /cast! <name> <shape> [p1 p2 ...]")
                    println("  Alias:  /gear <name> <shape> [p1 p2 ...]")
                    shape_list = join(sort(collect(keys(GEAR_LIBRARY))), ", ")
                    println("  Shapes: $(shape_list)")
                else
                    name = _parse_symbol(tokens, 2)
                    shape = lowercase(String(tokens[3]))
                    params = length(tokens) >= 4 ? _parse_floats(tokens, 4, length(tokens) - 3) : 
                             haskey(GEAR_LIBRARY, shape) ? copy(GEAR_LIBRARY[shape][2]) : Float64[]
                    cast_single!(am, name, shape, params)
                end
                
            elseif cmd == "/throttle"
                if length(tokens) < 2
                    println("  Throttle is currently: $(am.throttle_clamp)")
                else
                    val = parse(Float64, tokens[2])
                    am.throttle_clamp = clamp(val, 0.0, 1.0)
                    if am.throttle_clamp < 0.01
                        println("⚙️  GRUG: Valve SHUT. Machine idle. No flow.")
                    else
                        println("⚙️  GRUG: Throttle set to $(am.throttle_clamp). Flow is on.")
                    end
                end
                
            elseif cmd == "/slack"
                if length(tokens) < 2
                    println("  Slack is currently: $(am.slack)")
                else
                    val = parse(Float64, tokens[2])
                    if val <= 0.0
                        println("  ⚠️  GRUG: Slack must be positive. Zero tolerance is brittle.")
                    else
                        am.slack = val
                        println("⚙️  GRUG: Slack set to $(am.slack). Tolerance band adjusted.")
                    end
                end
                
            # ── GEOMETRIC OPERATIONS ──
            elseif cmd == "/probe"
                gear = _parse_symbol(tokens, 2)
                pt = _parse_floats(tokens, 3, 3)
                val = probe(am, gear, pt)
                println("  SDF(:$(gear), $(pt)) = $(val)")
                println("  $(val < 0 ? "INSIDE" : val > 0 ? "OUTSIDE" : "ON SURFACE")")
                
            elseif cmd == "/gradient"
                gear = _parse_symbol(tokens, 2)
                pt = _parse_floats(tokens, 3, 3)
                g = gradient(am, gear, pt)
                println("  ∇f(:$(gear), $(pt)) = $(g)")
                println("  |∇f| = $(norm(g))")
                
            elseif cmd == "/normal"
                gear = _parse_symbol(tokens, 2)
                pt = _parse_floats(tokens, 3, 3)
                n = surface_normal(am, gear, pt)
                println("  n̂(:$(gear), $(pt)) = $(n)")
                
            elseif cmd == "/curvature"
                gear = _parse_symbol(tokens, 2)
                pt = _parse_floats(tokens, 3, 3)
                c = curvature(am, gear, pt)
                println("  Curvature at :$(gear) $(pt):")
                println("    Mean (κ_H):     $(round(c.mean, digits=6))")
                println("    Gaussian (κ_G): $(round(c.gaussian, digits=6))")
                println("    Principal κ₁:   $(round(c.k1, digits=6))")
                println("    Principal κ₂:   $(round(c.k2, digits=6))")
                
            elseif cmd == "/laplacian"
                gear = _parse_symbol(tokens, 2)
                pt = _parse_floats(tokens, 3, 3)
                val = laplacian(am, gear, pt)
                println("  Δf(:$(gear), $(pt)) = $(val)")
                
            elseif cmd == "/divergence"
                gear = _parse_symbol(tokens, 2)
                pt = _parse_floats(tokens, 3, 3)
                val = divergence(am, gear, pt)
                println("  div(∇f)(:$(gear), $(pt)) = $(val)")
                
            elseif cmd == "/flow"
                gear = _parse_symbol(tokens, 2)
                pt = _parse_floats(tokens, 3, 3)
                steps = length(tokens) >= 6 ? parse(Int, tokens[6]) : 100
                ss = length(tokens) >= 7 ? parse(Float64, tokens[7]) : 0.1
                dir = length(tokens) >= 8 && String(tokens[8]) == "ascent" ? :ascent : :descent
                path = flow(am, gear, pt; steps=steps, step_size=ss, direction=dir)
                println("  Flow $(dir) from $(pt): $(length(path)) steps")
                println("  Start: $(path[1])")
                println("  End:   $(path[end])")
                if length(path) > 2
                    mid = div(length(path), 2)
                    println("  Mid:   $(path[mid])")
                end
                
            elseif cmd == "/levelset"
                gear = _parse_symbol(tokens, 2)
                origin = _parse_floats(tokens, 3, 3)
                dir = _parse_floats(tokens, 6, 3)
                ms = length(tokens) >= 9 ? parse(Int, tokens[9]) : 256
                result = levelset(am, gear, origin, dir; max_steps=ms)
                if result.hit
                    println("  ✓ HIT at $(result.point)")
                    println("    Distance: $(result.distance), Steps: $(result.steps)")
                else
                    println("  ✗ MISS. Ray traveled $(result.distance) in $(result.steps) steps.")
                end
                
            elseif cmd == "/geodesic"
                gear = _parse_symbol(tokens, 2)
                p1 = _parse_floats(tokens, 3, 3)
                p2 = _parse_floats(tokens, 6, 3)
                ms = length(tokens) >= 9 ? parse(Int, tokens[9]) : 500
                result = geodesic(am, gear, p1, p2; max_steps=ms)
                println("  Geodesic on :$(gear):")
                println("    Distance: ≈$(round(result.distance, digits=4))")
                println("    Path steps: $(result.steps)")
                println("    Start: $(result.path[1])")
                println("    End:   $(result.path[end])")
                
            # ── CSG / COMBINATION ──
            elseif cmd == "/boolean"
                if length(tokens) < 5
                    println("  Usage: /boolean <union|intersect|subtract> <result> <gear_a> <gear_b>")
                else
                    op = lowercase(String(tokens[2]))
                    result_name = _parse_symbol(tokens, 3)
                    ga = _parse_symbol(tokens, 4)
                    gb = _parse_symbol(tokens, 5)
                    if op == "union"
                        boolean_union!(am, result_name, ga, gb)
                    elseif op == "intersect"
                        boolean_intersect!(am, result_name, ga, gb)
                    elseif op == "subtract"
                        boolean_subtract!(am, result_name, ga, gb)
                    else
                        println("  Unknown boolean op: $(op). Use union, intersect, subtract.")
                    end
                end
                
            elseif cmd == "/blend"
                if length(tokens) < 5
                    println("  Usage: /blend <result> <gear_a> <gear_b> <radius>")
                else
                    result_name = _parse_symbol(tokens, 2)
                    ga = _parse_symbol(tokens, 3)
                    gb = _parse_symbol(tokens, 4)
                    k = parse(Float64, tokens[5])
                    blend!(am, result_name, ga, gb, k)
                end
                
            elseif cmd == "/morph"
                if length(tokens) < 4
                    println("  Usage: /morph <gear> <t> <p1 p2 ...>")
                else
                    gear = _parse_symbol(tokens, 2)
                    t = parse(Float64, tokens[3])
                    target = _parse_floats(tokens, 4, length(tokens) - 3)
                    morph!(am, gear, target, t)
                end
                
            # ── USER-DEFINED GEOMETRY ──
            elseif cmd == "/sdf"
                if length(tokens) < 2
                    println("  Usage: /sdf \"expression\" [p1 p2 ...]")
                    println("  Example: /sdf \"sin(x)*cos(y)-sqrt(z)-a\" 2.0")
                else
                    # Find the quoted expression using match with offset
                    expr_match = match(r"\"([^\"]+)\"", line)
                    if expr_match === nothing
                        println("  ⚠️  Expression must be in quotes.")
                    else
                        expr_str = expr_match.captures[1]
                        # Extract everything after the closing quote for params
                        # expr_match.offset = start of match, length of match tells us where closing quote is
                        close_quote_pos = expr_match.offset + length(expr_match.match) - 1
                        after_expr = close_quote_pos < length(line) ? strip(line[close_quote_pos+1:end]) : ""
                        param_tokens = filter(!isempty, split(after_expr))
                        params = Float64[]
                        parse_ok = true
                        for tok in param_tokens
                            v = tryparse(Float64, tok)
                            if v === nothing
                                parse_ok = false
                                println("  ⚠️  '$(tok)' is not a number. Ignored.")
                            else
                                push!(params, v)
                            end
                        end
                        name = parse_user_sdf!(am, expr_str, params)
                    end
                end
                
            elseif cmd == "/diff"
                if length(tokens) < 5
                    println("  Usage: /diff <gear> <spec> <x y z>")
                    println("  Spec: dx, dy, dz, d2x, dxdz, d3xd2y, etc.")
                    println("  Example: /diff MyGear d2xdz 1.0 2.0 3.0")
                else
                    gear = _parse_symbol(tokens, 2)
                    spec_str = String(tokens[3])
                    pt = _parse_floats(tokens, 4, 3)
                    spec = parse_diff_spec(spec_str)
                    result = apply_differential(am, gear, pt, spec)
                    println("  $(spec_str)(:$(gear), $(pt)) = $(result)")
                    println("  Total derivative order: $(spec.total_order)")
                end
                
            else
                println("  ⚠️  GRUG: Unknown command '$(cmd)'. Type /help.")
            end
            
        catch e
            if isa(e, MachineCrunch)
                println("  ⚠️  $(e.message)")
                !isempty(e.context) && println("     CONTEXT: $(e.context)")
            else
                println("  ⚠️  UNEXPECTED ERROR: $(sprint(showerror, e))")
            end
        end
    end
end

# ==========================================================================
# MAIN ENTRY POINT
# ==========================================================================
# GRUG: Boot the machine. Cast default gears. Open the valve.
#        Enter the keepalive loop. Machine breathes until /quit.
# ==========================================================================

function main()
    # 1. Build the machine with default slack
    machine = AntikytheraMap(0.001)
    
    # 2. Cast default gear set from foundry
    jit_cast_gears!(machine)
    
    # 3. Set throttle to working level
    machine.throttle_clamp = 0.5
    
    # 4. Enter the keepalive loop
    keepalive!(machine)
end

# GRUG: If running as script, boot the machine.
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

# ==========================================================================
# ACADEMIC EXPLANATION BLOCK
# ==========================================================================
#=
THE ANTIKYTHERA DIFF-ENGINE — GEOM-CALC v2.0
Geometric Calculus via Preloaded Signed Distance Fields

────────────────────────────────────────────────────────────────

1. SPATIAL DIFFERENTIATION (vs. Algorithmic/Symbolic Differentiation)

   Standard approach: Apply the Chain Rule as a temporal sequence of
   operations. For a function f(g(h(x))), the derivative requires
   mechanically unwinding the composition: f'(g(h(x))) · g'(h(x)) · h'(x).
   For deeply nested or procedurally generated functions — especially 
   those involving min/max (CSG), trigonometric compositions (gyroids),
   or parametric deformations (twists) — this chain becomes 
   combinatorially explosive. Automatic Differentiation (AD) engines
   handle the bookkeeping, but the computational graph itself grows
   without bound for complex geometric compositions.

   This architecture: Preload the function as a Signed Distance Field.
   The derivative becomes a spatial property — the surface gradient —
   extracted by finite probing of the pre-existing field. The cost is
   O(2d) evaluations of the SDF for a d-dimensional gradient, regardless
   of the internal compositional complexity of the field. A boolean
   intersection of 100 gyroids costs the same gradient probe as a 
   single sphere.

   The key insight: the derivative is not computed FROM the function.
   It is MEASURED ON the field. This is the difference between asking
   "what is the symbolic rate of change?" and asking "how much does
   the field value change when I poke it?"

────────────────────────────────────────────────────────────────

2. JIT-BAKED MANIFOLDS (GPU as Foundry, not Workhorse)

   The GPU (or any high-throughput co-processor) is utilized as a 
   "Foundry" to instantiate the topological map. Once the JIT casting 
   phase completes, the manifold exists in memory as a pre-aligned 
   field. The GPU returns to idle. Subsequent queries probe the 
   resident field at O(1) marginal cost.

   This inverts the standard GPU utilization model where the 
   accelerator is continuously active during inference. Here, the 
   accelerator performs a burst of setup work, then sleeps. The 
   analogy is a bronze foundry that casts gears once, then the 
   mechanism runs without returning to the forge.

────────────────────────────────────────────────────────────────

3. ELECTROCHEMICAL THROTTLING (Flow-Gated Activation)

   The system maintains a "near-zero flow" idle state that preserves 
   the field topology without active computation. The throttle_clamp 
   parameter [0.0, 1.0] controls the activation gate. At 0.0, the 
   field exists but no queries are permitted — the machine is 
   topologically present but computationally silent.

   Information propagation is triggered by raising the throttle, 
   allowing queries to resolve against the pre-aligned SDF gradients. 
   This mirrors analog electrochemical systems where "calculation" 
   is potential equalization — the answer exists as a property of the 
   pre-existing field state; the throttle merely permits observation.

────────────────────────────────────────────────────────────────

4. COMPLIANCE ROBUSTNESS (AK-47 SLACK)

   The slack parameter (ε-tolerance) implements compliance-based 
   robustness rather than precision-based correctness. The finite 
   difference step size is set to the slack value, which means:

   a) The gradient resolution is bounded by the tolerance band,
      not by machine epsilon.
   b) The system naturally handles non-manifold geometries, cusps,
      and degenerate features that cause traditional differentiation
      to produce NaN or ±∞.
   c) The tolerance band acts as a low-pass filter on the gradient
      field, suppressing high-frequency numerical noise while 
      preserving the dominant geometric signal.

   This is the "reliability through compliance, not precision" 
   principle. A mechanism with precisely machined gears seizes under
   thermal stress. A mechanism with tolerance bands continues to 
   function. The slack is not imprecision — it is engineered 
   survivability.

────────────────────────────────────────────────────────────────

5. INTRACTABILITY BOUNDARIES (Why These Operations Matter)

   The following operations are intractable or severely degraded 
   under traditional symbolic/analytic methods when applied to 
   complex composed implicit surfaces. The spatial probe approach 
   handles all of them uniformly:

   a) GRADIENT through CSG junctions (min/max):
      The derivative of min(f,g) is discontinuous at f=g.
      Symbolic AD produces undefined gradients at the seam.
      Spatial probe: finite difference straddles the discontinuity,
      producing a numerically valid gradient everywhere.

   b) CURVATURE (Hessian) on composed SDFs:
      Requires second derivatives of the composition. For n composed
      fields, the symbolic Hessian has O(n²) cross-terms.
      Spatial probe: always 3d² + 1 evaluations regardless of 
      composition depth.

   c) STREAMLINE TRACING through complex topology:
      Gradient flow on implicit surfaces with genus > 0, tunnels,
      self-intersections: no analytic solution exists. The flow 
      path must be integrated numerically step-by-step.

   d) RAY-SURFACE INTERSECTION (levelset):
      Solving f(o + td) = 0 for arbitrary composed SDFs has no 
      closed-form root. Newton's method can diverge on non-convex
      geometries. Sphere tracing using the SDF as safe-step bound
      is guaranteed convergent for Lipschitz SDFs.

   e) GEODESIC DISTANCE on arbitrary implicit surfaces:
      Requires solving the Eikonal equation |∇T| = 1 on a surface
      that may have no parametric representation. The tangent-plane
      projection method converges for smooth surfaces without 
      requiring a discretized grid.

   f) SMOOTH BLEND derivative:
      The polynomial smooth-min introduces a blend region where 
      the effective SDF is a cubic function of the two input SDFs.
      This has a closed-form derivative in theory, but in practice
      the composition with complex input SDFs makes the symbolic
      expression intractable. Spatial probe handles it identically
      to any other SDF.

   g) MORPH intermediate states:
      Parameter interpolation produces shapes that have no name in
      classical geometry — a torus with radius 7.3 morphing toward
      radius 12.1 at t=0.37 is a valid geometric object that exists
      only as an SDF evaluation. The spatial probe differentiates it 
      without needing to name it.

────────────────────────────────────────────────────────────────

6. THE KEEPALIVE PRINCIPLE (Ambient Field Persistence)

   The CLI REPL implements the "always-on ambient field" principle 
   from the GrugBot architecture. Between commands, the machine 
   maintains:

   - All gear SDFs loaded and queryable
   - Throttle state preserved
   - Slack calibration preserved
   - Boolean compositions referencing parent gears (live links)
   - Morph history accumulated in teeth_params

   There is no cold start between operations. The field is 
   continuous. Each command is a measurement of a pre-existing 
   state, not a construction of a new computation. This is the 
   resolution latency model applied to geometric calculus:

   L_total = L_collapse = time for SDF probe to return a value

   The probe cost is independent of how the field was constructed.
   A boolean intersection of 50 blended twisted gyroids has the 
   same probe latency as a single sphere. The complexity is in 
   the construction (JIT casting). The queries are uniformly cheap.

   This is the Antikythera principle: pre-align the mechanism,
   then operate by measurement, not re-derivation.

────────────────────────────────────────────────────────────────

7. ARCHITECTURAL LINEAGE

   Antikythera Mechanism → Geometric constraint satisfaction via 
   mechanically pre-aligned gear trains with tolerance bands.

   Analog computers → Computation as potential equalization in 
   continuous fields, gated by flow control (throttle/valve).

   SDF literature (Hart 1996, Quilez 2008+) → Implicit surface 
   representation enabling boolean composition, smooth blending,
   and spatial differentiation without explicit mesh.

   GrugBot neuromorphic architecture → Ambient field persistence,
   resolution latency over transmission latency, compliance over 
   precision, pre-alignment over re-computation.

   TI800 doctrine → GPU as burst co-processor (foundry), 
   electrochemical throttle gating, AK-47 slack tolerance,
   reliability through compliance not precision.

────────────────────────────────────────────────────────────────

8. USER-DEFINED GEOMETRY AND DIFFERENTIAL OPERATORS

   The /sdf command allows users to define custom Signed Distance 
   Fields at runtime via string expressions. The expression is 
   JIT-parsed into a Julia anonymous function and wrapped as a Cog.
   
   Coordinate substitutions:
     x,y,z → p[1],p[2],p[3] (Cartesian)
     r → sqrt(p[1]²+p[2]²+p[3]²) (radial distance)
     t → atan(p[2],p[1]) (azimuthal angle)
     u → atan(p[3],sqrt(p[1]²+p[2]²)) (polar angle)
   
   Parameter substitutions:
     a,b,c,... or p1,p2,p3,... → params[1],params[2],...
   
   Example: /sdf "sin(x)*cos(y)+sqrt(z)-a" 2.0
   
   This creates a gear whose SDF is sin(p[1])*cos(p[2])+sqrt(p[3])-params[1]
   with params=[2.0]. The user can then apply /gradient, /curvature, /diff
   etc. to this completely novel geometry. Symbolic differentiation of 
   user-defined expressions at runtime is impossible without AD infrastructure.
   Spatial probing works immediately.

   The /diff command allows users to specify arbitrary mixed partial 
   derivatives via a specification string:
   
     dx    → ∂f/∂x (first order)
     d2x   → ∂²f/∂x² (second order)
     dxdz  → ∂²f/∂x∂z (mixed partial)
     d3xdz → ∂⁴f/∂x³∂z (fourth order mixed)
   
   The finite difference stencil is constructed dynamically using 
   central difference coefficients derived from the Vandermonde system.
   For a derivative of order k, the stencil spans ±⌈k/2⌉ points.
   
   This permits exploration of differential operators that have no 
   standard name and no pre-existing implementation. The user can 
   ask "what is d⁵f/dx²dydz² at this point?" and receive an answer 
   without any symbolic preprocessing.

=#