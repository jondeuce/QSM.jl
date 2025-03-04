include("fd.jl")
include("fsl.jl")
include("kernels.jl")
include("lsmr.jl")
include("multi_echo.jl")
include("poisson_solver/poisson_solver.jl")


#####
##### FFT helpers
#####

const FAST_FFT_FACTORS = (2, 3, 5, 7)

nextfastfft(n::Real) = nextprod(FAST_FFT_FACTORS, n)
nextfastfft(ns) = nextfastfft.(ns)

"""
    fastfftsize(
        sz::NTuple{N, Integer},
        ksz::NTuple{M, Integer} = ntuple(_ -> 0, Val(N));
        rfft::Bool = false
    ) -> NTuple{N, Integer}

Next fast fft size greater than or equal to `sz` for convolution with a
kernel of size `ksz`.

### Arguments
- `x::AbstractArray{T, N}`: array to pad
- `ksz::NTuple{M, Integer} = ntuple(_ -> 0, Val(N))`: convolution kernel size
    - `ksz[n] < 0`: no padding for dimension n

### Keywords
- `rfft::Bool = false`: force first dimension to be even (`true`)

### Returns
- `NTuple{N, Integer}`: fast fft size
"""
function fastfftsize(
    sz::NTuple{N, Integer},
    ksz::NTuple{M, Integer} = ntuple(_ -> 0, Val(N));
    rfft::Bool = false
) where {N, M}
    i1 = findfirst(>(-1), ksz)

    if i1 === nothing
        return sz
    end

    szp = ntuple(Val(N)) do i
        if i > M || ksz[i] < 0
            sz[i]

        # FFTW's rfft strongly prefers even numbers in the first dimension
        elseif i == i1 && rfft
            s0 = nextfastfft(sz[i] + max(ksz[i], 1) - 1)
            s = s0
            for _ in 1:3
                iseven(s) && break
                s = nextfastfft(s+1)
            end
            s = isodd(s) ? s0 + 1 : s

        else
            nextfastfft(sz[i] + max(ksz[i], 1) - 1)
        end
    end

    return szp
end


#####
##### Padding
#####

"""
    padfastfft(
        x::AbstractArray{T, N},
        ksz::NTuple{M, Integer} = ntuple(_ -> 0, Val(N));
        pad::Symbol = :fill,
        val::Number = zero(T),
        rfft::Bool = false,
    ) -> typeof(similar(x, szp))

Pad array `x` to a fast fft size for convolution with a kernel of size `ksz`,
keeping the array centered at `n÷2+1`.

### Arguments
- `x::AbstractArray{T, N}`: array to pad
- `ksz::NTuple{M, Integer} = ntuple(_ -> 0, Val(N))`: convolution kernel size
    - `ksz[n] < 0`: no padding for dimension n

### Keywords
- `pad::Symbol = :fill`: padding method
    - `:fill`
    - `:circular`
    - `:replicate`
    - `:symmetric`
    - `:reflect`
- `val::Number = 0`: pads array with `val` if `pad = :fill`
- `rfft::Bool = false`: force first dimension to be even (`true`)

### Returns
- `typeof(similar(x, szp))`: padded array
"""
function padfastfft(
    x::AbstractArray{T, N},
    ksz::NTuple{M, Integer} = ntuple(_ -> 0, Val(N));
    pad::Symbol = :fill,
    val::Number = zero(T),
    rfft::Bool = false,
) where {N, M, T}
    sz = size(x)
    szp = fastfftsize(sz, ksz, rfft=rfft)
    return sz == szp ? tcopy(x) : padarray!(similar(x, szp), x, pad, val)
end


"""
    padarray!(
        xp::AbstractArray{Txp, N},
        x::AbstractArray{Tx, N},
        pad::Symbol = :fill,
        val::Number = 0
    ) -> xp

Pad array keeping it centered at `n÷2+1`.

### Arguments
- `xp::AbstractArray{Txp, N}`: padded array
- `x::AbstractArray{Tx, N}`: array to pad
- `pad::Symbol = :fill`: padding method
    - `:fill`
    - `:circular`
    - `:replicate`
    - `:symmetric`
    - `:reflect`
- `val::Number = 0`: pads array with `val` if `pad = :fill`

### Returns
- `xp`: padded array
"""
function padarray!(
    xp::AbstractArray{Txp, N},
    x::AbstractArray{Tx, N},
    pad::Symbol = :fill,
    val::Number = zero(Txp)
) where {N, Txp, Tx}
    sz = size(x)
    szp = size(xp)
    all(szp .>= sz) || throw(DimensionMismatch())

    pad ∈ (:fill, :circular, :replicate, :symmetric, :reflect) ||
        throw(ArgumentError(
            "pad must be one of :fill, :circular, :replicate, :symmetric, :reflect"
        ))

    ΔI = CartesianIndex((szp .- sz .+ 1) .>> 1)

    outer = CartesianIndices(axes(xp))
    inner = CartesianIndices(ntuple(n -> ΔI[n]+1:ΔI[n]+size(x, n), Val(N)))
    R = EdgeIterator(outer, inner)

    if pad == :fill
        valT = convert(Txp, val)
        @inbounds for I in R
            xp[I] = valT
        end

    elseif pad == :circular
        @inbounds for I in R
            Ix = I + ΔI
            xp[I] = x[ntuple(n -> mod(Ix[n], size(x, n))+1, Val(N))...]
        end

    elseif pad == :replicate
        @inbounds for I in R
            Ix = I - ΔI
            xp[I] = x[ntuple(n -> clamp(Ix[n], 1, size(x, n)), Val(N))...]
        end

    elseif pad == :symmetric
        @inbounds for I in R
            Ix = I - ΔI
            xp[I] = x[
                ntuple(Val(N)) do n
                    if Ix[n] < 1
                        1 - Ix[n]
                    elseif Ix[n] > size(x, n)
                        2*size(x, n) + 1 - Ix[n]
                    else
                        Ix[n]
                    end
                end...
            ]
        end

    elseif pad == :reflect
        @inbounds for I in R
            Ix = I - ΔI
            xp[I] = x[
                ntuple(Val(N)) do n
                    if Ix[n] < 1
                        2 - Ix[n]
                    elseif Ix[n] > size(x, n)
                        2*size(x, n) - Ix[n]
                    else
                        Ix[n]
                    end
                end...
            ]
        end
    end

    # interior
    @inbounds @batch minbatch=1024 for I in CartesianIndices(x)
        xp[I+ΔI] = x[I]
    end

    return xp
end


"""
    unpadarray(
        xp::AbstractArray{T, N},
        sz::NTuple{N, Integer}
    ) -> typeof(similar(xp, sz))

Extract array of size `sz` centered at `n÷2+1` from `xp`.
"""
function unpadarray(
    xp::AbstractArray{T, N},
    sz::NTuple{N, Integer}
) where {T, N}
    return unpadarray!(similar(xp, sz), xp)
end

"""
    unpadarray!(
        x::AbstractArray{Tx, N},
        xp::AbstractArray{Txp, N},
        sz::NTuple{N, Integer}
    ) -> x

Extract array centered at `n÷2+1` from `xp` into `x`.
"""
function unpadarray!(
    x::AbstractArray{Tx, N},
    xp::AbstractArray{Txp, N},
) where {N, Tx, Txp}
    sz = size(x)
    szp = size(xp)
    all(sz .<= szp) || throw(DimensionMismatch())

    ΔI = CartesianIndex((szp .- sz .+ 1) .>> 1)
    @inbounds @batch minbatch=1024 for I in CartesianIndices(x)
        x[I] = xp[I+ΔI]
    end

    return x
end


#####
##### Mask stuff
#####

"""
    crop_mask(
        x::AbstractArray,
        m::AbstractArray = x;
        out::Number = 0
    ) -> typeof(x[...])

Crop array to mask.

### Arguments
- `x::AbstractArray`: array to be cropped
- `m::AbstractArray`: mask

### Keywords
- `out::Number = 0`: value in `m` considered outside

### Returns
- `typeof(x[...])`: cropped array
"""
function crop_mask(
    x::AbstractArray,
    m::AbstractArray = x;
    out::Number = 0
)
    size(x) == size(m) || throw(DimensionMismatch())
    return x[crop_indices(m, out)]
end

"""
    crop_indices(x::AbstractArray, out::Number = 0) -> CartesianIndices

Indices to crop mask.

### Arguments
- `x::AbstractArray`: mask
- `out::Number = 0`: value in `x` considered outside

### Returns
- `CartesianIndices`: indices to crop mask
"""
function crop_indices(x::AbstractArray{T, N}, out::Number = zero(T)) where {T, N}
    i1 = [last.(axes(x))...]
    i2 = [first.(axes(x))...]

    v = convert(T, out)
    cmp = T <: Integer ? (!=) : (≉)

    @inbounds for I in CartesianIndices(x)
        if cmp(x[I], v)
            for n in Base.OneTo(N)
                i1[n] = ifelse(I[n] < i1[n], I[n], i1[n])
                i2[n] = ifelse(I[n] > i2[n], I[n], i2[n])
            end
        end
    end

    return CartesianIndices(ntuple(n -> i1[n]:i2[n], Val(N)))
end


"""
    erode_mask(mask::AbstractArray{Bool, 3}, iter::Integer = 1) -> typeof(similar(mask))

Erode binary mask using an 18-stencil cube.

### Arguments
- `mask::AbstractArray{Bool, 3}`: binary mask
- `iter::Integer = 1`: erode `iter` times

### Returns
- `typeof(similar(mask))`: eroded binary mask
"""
erode_mask(mask::AbstractArray{Bool, 3}, iter::Integer = 1) =
    erode_mask!(tzero(mask), mask, iter)

"""
    erode_mask(
        emask::AbstractArray{Bool, 3},
        mask::AbstractArray{Bool, 3},
        iter::Integer = 1
    ) -> emask

Erode binary mask using an 18-stencil cube.

### Arguments
- `emask::AbstractArray{Bool, 3}`: eroded binary mask
- `mask::AbstractArray{Bool, 3}`: binary mask
- `iter::Integer = 1`: erode `iter` times

### Returns
- `emask`: eroded binary mask
"""
function erode_mask!(
    m1::AbstractArray{Bool, 3},
    m0::AbstractArray{Bool, 3},
    iter::Integer = 1
)
    size(m1) == size(m0) || throw(DimensionMismatch())

    if iter < 1
        return _tcopyto!(m1, m0)
    end

    if iter > 1
        m0 = tcopy(m0)
    end

    nx, ny, nz = size(m0)
    for t in 1:iter
        @inbounds @batch for k in 1+t:nz-t
            for j in 1+t:ny-t
                for i in 1+t:nx-t
                    m1[i,j,k] = __erode_kernel(m0, i, j, k)
                end
            end
        end

        if t < iter
            _tcopyto!(m0, m1)
        end
    end

    return m1
end

@generated function __erode_kernel(m0, i, j, k)
    x = :(true)
    for _k in -1:1
        for _j in -1:1
            for _i in -1:1
                _i != 0 && _j != 0 && _k != 0 && continue
                x = :($x && m0[i+$_i, j+$_j, k+$_k])
            end
        end
    end

    quote
        Base.@_inline_meta
        return @inbounds $x
    end
end


#####
##### Misc
#####

"""
    psf2otf(
        psf::AbstractArray{<:Number, N},
        sz::NTuple{N, Integer} = size(psf);
        rfft::Bool = false,
    ) -> otf

Implementation of MATLAB's `psf2otf` function.

### Arguments
- `psf::AbstractArray{T<:Number, N}`: point-spread function
- `sz::NTuple{N, Integer}`: size of output array; must not be smaller than `psf`

### Keywords
- `rfft::Bool = false`:
    - `T<:Real`: compute `fft` (`false`) or `rfft` (`true`)
    - `T<:Complex`: unused

### Returns
- `otf`: optical transfer function
"""
function psf2otf(
    k::AbstractArray{T, N},
    sz::NTuple{N, Integer} = size(k);
    rfft::Bool = false,
) where {T<:Number, N}
    szk = size(k)
    all(szk .<= sz) || throw(DimensionMismatch())

    # zero pad
    if szk == sz
        _kp = k
    else
        _kp = tzero(k, sz)
        @inbounds @batch minbatch=1024 for I in CartesianIndices(k)
            _kp[I] = k[I]
        end
    end

    # shift so center of k is at index 1
    kp = circshift!(tzero(_kp), _kp, .-szk.÷2)

    # fft
    FFTW.set_num_threads(num_cores())
    P = T <: Real && rfft ? plan_rfft(kp) : plan_fft(kp)

    K = P*kp

    # discard imaginary part if within roundoff error
    nops = length(k)*sum(log2, szk)
    if maximum(x -> abs(imag(x)), K) / maximum(abs2, K) ≤ nops*eps(T)
        _tcopyto!(real, K, K)
    end

    return K
end


#####
##### Multi-threaded Base utilities
#####

function tzero(x::AbstractArray{T}, sz::NTuple{N, Integer} = size(x)) where {T, N}
    return tfill!(similar(x, sz), zero(T))
end

function tcopy(x::AbstractArray)
    return _tcopyto!(similar(x), x)
end

function tcopy(f::Function, x::AbstractArray)
    return _tcopyto!(f, similar(x), x)
end

function tfill!(A::AbstractArray{T}, x) where {T}
    xT = convert(T, x)
    @inbounds @batch minbatch=1024 for I in eachindex(A)
        A[I] = xT
    end
    return A
end

function _tcopyto!(y, x)
    @inbounds @batch minbatch=1024 for I in eachindex(y, x)
        y[I] = x[I]
    end
    return y
end

function _tcopyto!(f::Function, y, x)
    @inbounds @batch minbatch=1024 for I in eachindex(y, x)
        y[I] = f(x[I])
    end
    return y
end
