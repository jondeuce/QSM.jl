"""
    tkd(
        f::AbstractArray{<:AbstractFloat, N ∈ (3, 4)},
        mask::AbstractArray{Bool, 3},
        vsz::NTuple{3, Real};
        pad::NTuple{3, Integer} = (0, 0, 0),
        bdir::NTuple{3, Real} = (0, 0, 1),
        Dkernel::Symbol = :k,
        thr::Real = 0.15,
    ) -> typeof(similar(f))

Truncated k-space division (TKD) [1].

### Arguments
- `f::AbstractArray{<:AbstractFloat, N ∈ (3, 4)}`: unwrapped (multi-echo) local
    field/phase
- `mask::AbstractArray{Bool, 3}`: binary mask of region of interest
- `vsz::NTuple{3, Real}`: voxel size

### Keywords
- `pad::NTuple{3, Integer} = (0, 0, 0)`: zero padding array
    - `< 0`: no padding
    - `≥ 0`: minimum padding to fast fft size
- `bdir::NTuple{3, Real} = (0, 0, 1)`: unit vector of B field direction
- `Dkernel::Symbol = :k`: dipole kernel method
- `thr::Real = 0.15`: threshold for k-space filter

### Returns
- `typeof(similar(f))`: susceptibility map

### References
[1] Shmueli K, de Zwart JA, van Gelderen P, Li TQ, Dodd SJ, Duyn JH. Magnetic
    susceptibility mapping of brain tissue in vivo using MRI phase data.
    Magnetic Resonance in Medicine: An Official Journal of the International
    Society for Magnetic Resonance in Medicine. 2009 Dec;62(6):1510-22.
"""
function tkd(
    f::AbstractArray{<:AbstractFloat, N},
    mask::AbstractArray{Bool, 3},
    vsz::NTuple{3, Real};
    pad::NTuple{3, Integer} = (0, 0, 0),
    bdir::NTuple{3, Real} = (0, 0, 1),
    Dkernel::Symbol = :k,
    thr::Real = 0.15,
) where {N}
    N ∈ (3, 4) || throw(ArgumentError("arrays must be 3d or 4d, got $(N)d"))
    return _kdiv!(tzero(f), f, mask, vsz, pad, bdir, Dkernel, thr, nothing, :tkd)
end


"""
    tsvd(
        f::AbstractArray{<:AbstractFloat, N ∈ (3, 4)},
        mask::AbstractArray{Bool, 3},
        vsz::NTuple{3, Real};
        pad::NTuple{3, Integer} = (0, 0, 0),
        bdir::NTuple{3, Real} = (0, 0, 1),
        Dkernel::Symbol = :k,
        thr::Real = 0.15,
    ) -> typeof(similar(f))

Truncated singular value decomposition (TSVD) [1].

### Arguments
- `f::AbstractArray{<:AbstractFloat, N ∈ (3, 4)}`: unwrapped (multi-echo) local
    field/phase
- `mask::AbstractArray{Bool, 3}`: binary mask of region of interest
- `vsz::NTuple{3, Real}`: voxel size

### Keywords
- `pad::NTuple{3, Integer} = (0, 0, 0)`: zero padding array
    - `< 0`: no padding
    - `≥ 0`: minimum padding to fast fft size
- `bdir::NTuple{3, Real} = (0, 0, 1)`: unit vector of B field direction
- `Dkernel::Symbol = :k`: dipole kernel method
- `thr::Real = 0.15`: threshold for k-space filter

### Returns
- `typeof(similar(f))`: susceptibility map

### References
[1] Wharton S, Schäfer A, Bowtell R. Susceptibility mapping in the human brain
    using threshold‐based k‐space division. Magnetic resonance in medicine.
    2010 May;63(5):1292-304.
"""
function tsvd(
    f::AbstractArray{<:AbstractFloat, N},
    mask::AbstractArray{Bool, 3},
    vsz::NTuple{3, Real};
    pad::NTuple{3, Integer} = (0, 0, 0),
    bdir::NTuple{3, Real} = (0, 0, 1),
    Dkernel::Symbol = :k,
    thr::Real = 0.15,
) where {N}
    N ∈ (3, 4) || throw(ArgumentError("arrays must be 3d or 4d, got $(N)d"))
    return _kdiv!(tzero(f), f, mask, vsz, pad, bdir, Dkernel, thr, nothing, :tsvd)
end


"""
    tikh(
        f::AbstractArray{<:AbstractFloat, N ∈ (3, 4)},
        mask::AbstractArray{Bool, 3},
        vsz::NTuple{3, Real};
        pad::NTuple{3, Integer} = (0, 0, 0),
        bdir::NTuple{3, Real} = (0, 0, 1),
        Dkernel::Symbol = :k,
        lambda::Real = 1e-2,
        reg::Symbol = :gradient
    ) -> typeof(similar(f))

Tikhonov regularization [1].

```math
    argmin_x ||Dx - f||_2^2 + \\frac{λ}{2}||Γx||_2^2
```

### Arguments
- `f::AbstractArray{<:AbstractFloat, N ∈ (3, 4)}`: unwrapped (multi-echo) local
    field/phase
- `mask::AbstractArray{Bool, 3}`: binary mask of region of interest
- `vsz::NTuple{3, Real}`: voxel size

### Keywords
- `pad::NTuple{3, Integer} = (0, 0, 0)`: zero padding array
    - `< 0`: no padding
    - `≥ 0`: minimum padding to fast fft size
- `bdir::NTuple{3, Real} = (0, 0, 1)`: unit vector of B field direction
- `Dkernel::Symbol = :k`: dipole kernel method
- `lambda::Real = 1e-2`: regularization parameter
- `reg::Symbol = :identity`: regularization matrix Γ
    (`:identity`, `:gradient`, `:laplacian`)

### Returns
- `typeof(similar(f))`: susceptibility map

### References
[1] Bilgic B, Chatnuntawech I, Fan AP, Setsompop K, Cauley SF, Wald LL,
    Adalsteinsson E. Fast image reconstruction with L2‐regularization. Journal
    of magnetic resonance imaging. 2014 Jul;40(1):181-91.
"""
function tikh(
    f::AbstractArray{<:AbstractFloat, N},
    mask::AbstractArray{Bool, 3},
    vsz::NTuple{3, Real};
    pad::NTuple{3, Integer} = (0, 0, 0),
    bdir::NTuple{3, Real} = (0, 0, 1),
    Dkernel::Symbol = :k,
    lambda::Real = 1e-2,
    reg::Symbol = :identity,
) where {N}
    N ∈ (3, 4) || throw(ArgumentError("arrays must be 3d or 4d, got $(N)d"))
    return _kdiv!(tzero(f), f, mask, vsz, pad, bdir, Dkernel, lambda, reg, :tikh)
end


#####
##### k-space division
#####

function _kdiv!(
    x::AbstractArray{<:AbstractFloat, N},
    f::AbstractArray{T, N},
    mask::AbstractArray{Bool, 3},
    vsz::NTuple{3, Real},
    pad::NTuple{3, Integer},
    bdir::NTuple{3, Real},
    Dkernel::Symbol,
    lambda::Real,
    reg::Union{Nothing, Symbol},
    method::Symbol,
) where {T<:AbstractFloat, N}
    N ∈ (3, 4) || throw(ArgumentError("arrays must be 3d or 4d, got $(N)d"))

    checkshape(x, f, (:x, :f))
    checkshape(axes(mask), axes(f)[1:3])

    checkopts(Dkernel, (:k, :kspace, :i, :ispace), :Dkernel)
    checkopts(method, (:tkd, :tsvd, :tikh), :method)
    method == :tikh && checkopts(reg, (:identity, :gradient, :laplacian), :reg)

    # pad to fast fft size
    fp = padfastfft(@view(f[:,:,:,1]), pad, rfft=true)
    m = padfastfft(mask, pad, rfft=true)

    # init fft plans and vars
    sz0 = size(mask)
    sz = size(m)
    sz_ = (sz[1]>>1 + 1, sz[2], sz[3])

    D = Array{T, 3}(undef, sz_)
    F̂ = Array{complex(T), 3}(undef, sz_)

    FFTW.set_num_threads(FFTW_NTHREADS[])
    P = plan_rfft(fp)
    iP = inv(P)

    # get dipole kernel
    D = _dipole_kernel!(D, F̂, fp, sz0, vsz, bdir, P, Dkernel, :rfft)

    # inverse k-space kernel
    iD = _kdiv_ikernel!(D, F̂, fp, vsz, P, lambda, reg, method)

    for t in axes(f, 4)
        fp = padarray!(fp, @view(f[:,:,:,t]))

        F̂ = mul!(F̂, P, fp)
        @bfor F̂[I] *= iD[I]

        fp = mul!(fp, iP, F̂)
        @bfor fp[I] *= m[I]

        unpadarray!(@view(x[:,:,:,t]), fp)
    end

    return x
end


function _kdiv_ikernel!(
    D::AbstractArray{T, N},
    F::AbstractArray{Complex{T}, N},
    f::AbstractArray{T, N},
    vsz::NTuple{3, Real},
    P::Union{FFTW.rFFTWPlan{T, -1}, FFTW.cFFTWPlan{Complex{T}, -1, false}},
    lambda::Real,
    reg::Union{Nothing, Symbol},
    method::Symbol
) where {T, N}
    zeroT = zero(T)

    if iszero(lambda)
        @bfor D[I] = ifelse(iszero(D[I]), zeroT, inv(D[I]))
        return D
    end

    if method == :tkd
        δ = convert(T, lambda)
        iδ = inv(δ)

        @bfor D[I] = ifelse(abs(D[I]) ≤ δ, copysign(iδ, D[I]), inv(D[I]))

    elseif method == :tsvd
        δ = convert(T, lambda)

        @bfor D[I] = ifelse(abs(D[I]) ≤ δ, zeroT, inv(D[I]))

    elseif method == :tikh
        λ = convert(T, lambda)

        if reg == :identity
            @bfor D[I] = inv(D[I]*D[I] + λ)*D[I]

        else
            Γ = similar(D)

            if reg == :gradient
                Γ = _laplace_kernel!(Γ, F, f, vsz, P, negative=true)

            elseif reg == :laplacian
                Γ = _laplace_kernel!(Γ, F, f, vsz, P)
                Γ = tmap!(abs2, Γ)
            end

            @bfor begin
                num  = D[I]
                den  = D[I]*D[I] + λ*Γ[I]
                D[I] = ifelse(iszero(den), zeroT, inv(den)*num)
            end
        end
    end

    return D
end
