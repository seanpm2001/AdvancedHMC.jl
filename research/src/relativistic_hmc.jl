using AdvancedHMC
import AdvancedHMC: ∂H∂r, neg_energy, AbstractKinetic
import Random: AbstractRNG

abstract type AbstractRelativisticKinetic{T} <: AbstractKinetic end

struct RelativisticKinetic{T} <: AbstractRelativisticKinetic{T}
    "Mass"
    m::T
    "Speed of light"
    c::T
end

relativistic_mass(kinetic::RelativisticKinetic, r) = 
    kinetic.m * sqrt(dot(r, r) / (kinetic.m ^ 2 * kinetic.c ^ 2) + 1)
relativistic_energy(kinetic::RelativisticKinetic, r) = sum(
    kinetic.c ^ 2 * relativistic_mass(kinetic, r)
)

struct DimensionwiseRelativisticKinetic{T} <: AbstractRelativisticKinetic{T}
    "Mass"
    m::T
    "Speed of light"
    c::T
end

relativistic_mass(kinetic::DimensionwiseRelativisticKinetic, r) = 
    kinetic.m .* sqrt.(r .^ 2 ./ (kinetic.m .^ 2 .* kinetic.c .^ 2) .+ 1)
relativistic_energy(kinetic::DimensionwiseRelativisticKinetic, r) = sum(
    kinetic.c .^ 2 .* relativistic_mass(kinetic, r)
)

function ∂H∂r(
    h::Hamiltonian{<:UnitEuclideanMetric,<:AbstractRelativisticKinetic},
    r::AbstractVecOrMat,
)
    mass = relativistic_mass(h.kinetic, r)
    return r ./ mass
end
function ∂H∂r(
    h::Hamiltonian{<:DiagEuclideanMetric,<:AbstractRelativisticKinetic},
    r::AbstractVecOrMat,
)
    r = h.metric.sqrtM⁻¹ .* r
    mass = relativistic_mass(h.kinetic, r)
    red_term = r ./ mass # red part of (15)
    return h.metric.sqrtM⁻¹ .* red_term # (15)
end
function ∂H∂r(h::Hamiltonian{<:DenseEuclideanMetric, <:AbstractRelativisticKinetic}, r::AbstractVecOrMat)
    r = h.metric.cholM⁻¹ * r
    mass = relativistic_mass(h.kinetic, r)
    red_term = r ./ mass
    return h.metric.cholM⁻¹ * red_term
end

function neg_energy(
    h::Hamiltonian{<:UnitEuclideanMetric,<:AbstractRelativisticKinetic},
    r::T,
    θ::T,
) where {T<:AbstractVector}
    return -relativistic_energy(h.kinetic, r)
end
function neg_energy(
    h::Hamiltonian{<:DiagEuclideanMetric,<:AbstractRelativisticKinetic},
    r::T,
    θ::T,
) where {T<:AbstractVector}
    r = h.metric.sqrtM⁻¹ .* r
    return -relativistic_energy(h.kinetic, r)
end
function neg_energy(
    h::Hamiltonian{<:DenseEuclideanMetric,<:AbstractRelativisticKinetic},
    r::T,
    θ::T
) where {T<:AbstractVector}
    r = h.metric.cholM⁻¹ * r
    return -relativistic_energy(h.kinetic, r)
end

using AdaptiveRejectionSampling: RejectionSampler, run_sampler!
import AdvancedHMC: _rand

polar2carte(θ, d) = d * [cos(θ), sin(θ)]
momentum_mode(m, c) = sqrt((1 / c^2 + sqrt(1 / c^2 + 4 * m^2)) / 2) # mode of the momentum distribution

function _rand(
    rng::AbstractRNG,
    metric::UnitEuclideanMetric{T},
    kinetic::RelativisticKinetic{T},
) where {T}
    h_temp = Hamiltonian(metric, kinetic, identity, identity)
    densityfunc = x -> exp(neg_energy(h_temp, [x], [x])) * x
    mm = momentum_mode(kinetic.m, kinetic.c)
    sampler = RejectionSampler(densityfunc, (0.0, Inf), (mm / 2, mm * 2); max_segments = 5)
    sz = size(metric)
    # r = polar2carte(2 * π * rand(rng), only(run_sampler!(rng, sampler, 1)) * rand(rng, [-1, +1]))
    r = polar2carte(2 * π * rand(rng), only(run_sampler!(rng, sampler, 1))) # already taking 2π, need for random +/- 1
    # num_samples = prod(sz)
    # r_angular = 2 * π * rand(rng, num_samples)
    # r_radial = run_sampler!(rng, sampler, num_samples) # FIXME!!! this sampler assumes dimensionwise!!!
    # r = reduce(hcat, polar2carte.(r_angular, r_radial))
    r = reshape(r, sz)
    return r
end

# TODO Support AbstractVector{<:AbstractRNG}
# function _rand(
#     rng::AbstractRNG,
#     metric::UnitEuclideanMetric{T},
#     kinetic::RelativisticKinetic{T},
# ) where {T}
#     h_temp = Hamiltonian(metric, kinetic, identity, identity)
#     densityfunc = x -> exp(neg_energy(h_temp, [x], [x]))
#     sampler = RejectionSampler(densityfunc, (-Inf, Inf); max_segments = 5)
#     sz = size(metric)
#     r = run_sampler!(rng, sampler, prod(sz)) # FIXME!!! this sampler assumes dimensionwise!!!
#     r = reshape(r, sz)
#     return r
# end
# TODO Support AbstractVector{<:AbstractRNG}
function _rand(
    rng::AbstractRNG,
    metric::UnitEuclideanMetric{T},
    kinetic::DimensionwiseRelativisticKinetic{T},
) where {T}
    h_temp = Hamiltonian(metric, kinetic, identity, identity)
    densityfunc = x -> exp(neg_energy(h_temp, [x], [x]))
    sampler = RejectionSampler(densityfunc, (-Inf, Inf); max_segments = 5)
    sz = size(metric)
    r = run_sampler!(rng, sampler, prod(sz))
    r = reshape(r, sz)
    return r
end

# TODO Support AbstractVector{<:AbstractRNG}
function _rand(
    rng::AbstractRNG,
    metric::DiagEuclideanMetric{T},
    kinetic::AbstractRelativisticKinetic{T},
) where {T}
    r = _rand(rng, UnitEuclideanMetric(size(metric)), kinetic)
    # p' = A p where A = sqrtM
    r ./= metric.sqrtM⁻¹
    return r
end
# TODO Support AbstractVector{<:AbstractRNG}
function _rand(
    rng::AbstractRNG,
    metric::DenseEuclideanMetric{T},
    kinetic::AbstractRelativisticKinetic{T},
) where {T}
    r = _rand(rng, UnitEuclideanMetric(size(metric)), kinetic)
    # p' = A p where A = cholM
    ldiv!(metric.cholM⁻¹, r)
    return r
end
