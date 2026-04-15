# Antikythera Digital

[![CI](https://github.com/marshalldavidson61-arch/antikythera-digital/actions/workflows/ci.yml/badge.svg)](https://github.com/marshalldavidson61-arch/antikythera-digital/actions/workflows/ci.yml)

**Geometric Computation Engine for Operations Intractable to Traditional Methods**

---

## What Is This?

Antikythera Digital is a spatial differentiation engine that treats calculus as a **measurement operation** rather than a symbolic procedure. Instead of chain-rule derivation through nested expressions, the engine preloads signed distance fields (SDFs) as geometric manifolds and probes them directly for gradients, curvature, geodesics, and arbitrary differential operators.

**The key insight**: When you embody computation in geometry, operations that are exponentially expensive symbolically become constant-time spatial queries.

---

## Why "Antikythera"?

The Antikythera mechanism (c. 100 BCE) is the oldest known analog computer—a geared device that computed astronomical positions through mechanical relationships. It didn't calculate symbolically; it **encoded knowledge in physical alignment**.

Antikythera Digital extends this philosophy:

> **Computation is alignment. Turing machines achieve it through recursive meta-instructions. We achieve it through direct geometric embedding.**

---

## Core Concepts

### Grug-Style Explanation

```
grug think: math hard when many symbols
grug discover: shape already have math inside
grug poke shape -> shape tell grug answer
no need calculate -> shape IS calculation
grug happy
```

Traditional approach:
1. Write complicated function
2. Apply chain rule many times
3. Hope no mistakes
4. Get gradient

Antikythera approach:
1. Build shape
2. Poke shape
3. Shape gives gradient
4. Done

### Academic Explanation

The engine implements **spatial differentiation** on implicit surfaces represented as signed distance fields. Rather than computing derivatives through symbolic differentiation or automatic differentiation (AD), we exploit the geometric structure of SDFs:

- **Gradient**: ∇f(x) emerges from finite differences on the preloaded field
- **Curvature**: κ(x) = ∇²f(x) / |∇f(x)| computed via Laplacian probe
- **Geodesics**: Integral curves on the manifold, computed via streamline integration
- **Arbitrary Differentials**: dⁿf/dxⁱdyʲdzᵏ constructed from Vandermonde stencil coefficients

The key advantage is that **composition complexity does not increase query cost**. A boolean union of 1000 primitives has the same gradient-probe cost as a single sphere—the geometry is preloaded, and differentiation is measurement.

---

## Features

### 23 CLI Commands

| Command | Description |
|---------|-------------|
| `/init` | Initialize the Antikythera map |
| `/gear <name> <type> [params]` | Cast an SDF gear from library |
| `/sdf "expr" [params]` | Parse user-defined SDF expression |
| `/probe <gear> <x> <y> <z>` | Probe SDF value at point |
| `/gradient <gear> <x> <y> <z>` | Compute gradient vector |
| `/normal <gear> <x> <y> <z>` | Surface normal at point |
| `/curvature <gear> <x> <y> <z>` | Mean curvature value |
| `/laplacian <gear> <x> <y> <z>` | Laplacian (divergence of gradient) |
| `/divergence <gear> <x> <y> <z>` | Vector field divergence |
| `/flow <gear> <x> <y> <z> <steps>` | Trace streamline from point |
| `/levelset <gear> <iso> <x> <y> <z>` | Project to isosurface |
| `/geodesic <gear> <start> <end> <steps>` | Compute geodesic path |
| `/union <g1> <g2> <result>` | Boolean union |
| `/intersect <g1> <g2> <result>` | Boolean intersection |
| `/subtract <g1> <g2> <result>` | Boolean difference |
| `/blend <g1> <g2> <k> <result>` | Smooth blend operation |
| `/morph <g1> <g2> <t> <result>` | Linear morph between shapes |
| `/diff <gear> <spec> <x> <y> <z>` | User-defined differential operator |
| `/list` | List all gears in machine |
| `/throttle <value>` | Set compliance slack (h value) |
| `/dump <gear>` | Export gear parameters |
| `/quit` | Exit CLI |

### Gear Library

- `sphere(radius)`
- `box(width, height, depth)`
- `torus(major_radius, minor_radius)`
- `cylinder(radius, height)`
- `gyroid(period, thickness)`
- `schwarz(period, thickness)`
- `twisted_torus(major, minor, twist)`

### CSG Operations

- Boolean union, intersection, subtraction
- Smooth blending with controllable smoothing factor
- Morphing between arbitrary SDFs

### User-Defined Operations

- Custom SDF expressions with JIT compilation
- Arbitrary differential operators: dⁿf/dxⁱdyʲdzᵏ

---

## Installation

```bash
# Clone repository
git clone https://github.com/marshalldavidson61-arch/antikythera-digital.git
cd antikythera-digital

# Run the engine (requires Julia 1.9+)
julia antikythera_diff_engine.jl
```

---

## Quick Start

```julia
# Initialize machine
/init

# Create a sphere
/gear mysphere sphere 1.0

# Probe its surface
/probe mysphere 0.5 0.0 0.0
# Output: -0.5 (inside sphere by 0.5 units)

# Get gradient
/gradient mysphere 0.5 0.0 0.0
# Output: [1.0, 0.0, 0.0]

# Create another shape and blend
/gear mybox box 1.0 1.0 1.0
/blend mysphere mybox 0.3 blended_shape

# Compute curvature on blended shape
/curvature blended_shape 0.0 0.0 0.0
```

---

## Why This Matters

### Security Implications

Operations marketed as "quantum-required" may simply be problems framed incorrectly. When you embody computation in geometry:

- Optimization landscapes become surfaces to probe
- Gradient descent becomes streamline following
- Constraint satisfaction becomes admissibility region design

### Capability Bypass

The engine demonstrates that certain computational hardness assumptions depend on **algorithmic framing**, not fundamental limits. A geometric computer doesn't "solve" NP-hard problems—it makes them irrelevant by construction.

---

## File Structure

```
antikythera-digital/
├── README.md                    # This file
├── WHITEPAPER.html              # Comprehensive technical documentation
├── antikythera_diff_engine.jl   # Main engine (1,743 lines)
├── test_antikythera.jl          # Test suite (537 lines, 83 assertions)
└── docs/
    └── images/                  # Diagrams and flowcharts
```

---

## License

MIT License - See LICENSE file for details.

---

## Author

**GrugBot420 / Bindboss**

*Listening to nature before theorizing.*

---

## Acknowledgments

- The original Antikythera mechanism builders (c. 100 BCE)
- Every craftsperson who understood that fit matters more than exactness
- Nature, for having answers without being asked