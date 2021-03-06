struct ArrayReference
    array::Symbol
    ref::Vector{Union{Symbol,Int}}
    loaded::Base.RefValue{Bool}
    ptr::Symbol
end
function ArrayReference(array::Symbol, ref, loaded)
    ArrayReference(
        array, ref, loaded,
        Symbol("##vptr##_", array)
    )
end
ArrayReference(array::Symbol, ref) = ArrayReference(array, ref, Ref{Bool}(false))
function ArrayReference(
    array::Symbol,
    ref::AbstractVector
)
    ArrayReference(array, ref, Ref{Bool}(false))
end
function Base.hash(x::ArrayReference, h::UInt)
    @inbounds for n ∈ eachindex(x)
        h = hash(x.ref[n], h)
    end
    hash(x.array, h)
end
function loopdependencies(ref::ArrayReference)
    ld = Symbol[]
    for r ∈ ref.ref
        r isa Symbol && push!(ld, r)
    end
    ld
end
function Base.isequal(x::ArrayReference, y::ArrayReference)
    x.array === y.array || return false
    nrefs = length(x.ref)
    nrefs == length(y.ref) || return false
    all(n -> x.ref[n] === y.ref[n], 1:nrefs)
    # for n ∈ 1:nrefs
        # x.ref[n] === y.ref[n] || return false
    # end
    # true
end

Base.:(==)(x::ArrayReference, y::ArrayReference) = isequal(x, y)

function ref_from_expr(ex, offset1::Int = 0, offset2 = 0)
    ArrayReference( ex.args[1 + offset1], @view(ex.args[2 + offset2:end]), Ref(false) )
end
ref_from_ref(ex::Expr) = ref_from_expr(ex, 0, 0)
ref_from_getindex(ex::Expr) = ref_from_expr(ex, 1, 1)
ref_from_setindex(ex::Expr) = ref_from_expr(ex, 1, 2)
function ArrayReference(ex::Expr)
    ex.head === :ref ? ref_from_ref(ex) : ref_from_getindex(ex)
end
function Base.:(==)(x::ArrayReference, y::Expr)
    if y.head === :ref
        isequal(x, ref_from_ref(y))
    elseif y.head === :call && first(y.args) === :getindex
        isequal(x, ref_from_getindex(y))
    else
        false
    end
end
Base.:(==)(x::ArrayReference, y) = false



# Avoid memory allocations by accessing this
const NOTAREFERENCE = ArrayReference(Symbol(""), Union{Symbol,Int}[], Ref(false))

@enum OperationType begin
    constant
    memload
    compute
    memstore
end

# const ID = Threads.Atomic{UInt}(0)


# TODO: can some computations be cached in the operations?
"""
"""
struct Operation
    identifier::Int
    variable::Symbol
    elementbytes::Int
    instruction::Instruction
    node_type::OperationType
    dependencies::Vector{Symbol}
    reduced_deps::Vector{Symbol}
    parents::Vector{Operation}
    ref::ArrayReference
    mangledvariable::Symbol
    function Operation(
        identifier::Int,
        variable,
        elementbytes,
        instruction,
        node_type,
        dependencies = Symbol[],
        reduced_deps = Symbol[],
        parents = Operation[],
        ref::ArrayReference = NOTAREFERENCE
    )
        new(
            identifier, variable, elementbytes, instruction, node_type,
            convert(Vector{Symbol},dependencies),
            convert(Vector{Symbol},reduced_deps),
            convert(Vector{Operation},parents),
            ref,
            Symbol("##", variable, :_)
        )
    end
end

 # negligible save on allocations for operations that don't need these (eg, constants).
const NODEPENDENCY = Union{Symbol,Int}[]
const NOPARENTS = Operation[]

function Base.show(io::IO, op::Operation)
    if isconstant(op)
        if op.instruction === LOOPCONSTANT
            print(io, Expr(:(=), op.variable, 0))
        else
            print(io, Expr(:(=), op.variable, op.instruction.instr))
        end
    elseif isload(op)
        print(io, Expr(:(=), op.variable, Expr(:ref, op.ref.array, op.ref.ref...)))
    elseif iscompute(op)
        print(io, Expr(:(=), op.variable, Expr(op.instruction, name.(parents(op))...)))
    elseif isstore(op)
        print(io, Expr(:(=), Expr(:ref, op.ref.array, op.ref.ref...), name(first(parents(op)))))
    end
end

function isreduction(op::Operation)
    ((op.node_type == compute) || (op.node_type == memstore)) && length(op.reduced_deps) > 0
    # (op.node_type == memstore) && (length(op.symbolic_metadata) < length(op.dependencies))# && issubset(op.symbolic_metadata, op.dependencies)
end
isload(op::Operation) = op.node_type == memload
iscompute(op::Operation) = op.node_type == compute
isstore(op::Operation) = op.node_type == memstore
isconstant(op::Operation) = op.node_type == constant
accesses_memory(op::Operation) = isload(op) | isstore(op)
elsize(op::Operation) = op.elementbytes
dependson(op::Operation, sym::Symbol) = sym ∈ op.dependencies
parents(op::Operation) = op.parents
# children(op::Operation) = op.children
loopdependencies(op::Operation) = op.dependencies
reduceddependencies(op::Operation) = op.reduced_deps
identifier(op::Operation) = op.identifier + 1
name(op::Operation) = op.variable
instruction(op::Operation) = op.instruction

refname(op::Operation) = op.ref.ptr
"""
    mvar = mangledvar(op)

Returns the mangled variable name, for use in the produced expressions.
These names will be further processed if op is tiled and/or unrolled.

```julia
    if tiled ∈ loopdependencies(op) # `suffix` is tilenumber
        mvar = Symbol(op, suffix, :_)
    end
    if unrolled ∈ loopdependencies(op) # `u` is unroll number 
        mvar = Symbol(op, u)
    end
```
"""
mangledvar(op::Operation) = op.mangledvariable

"""
Returns `0` if the op is the declaration of the constant outerreduction variable.
Returns `n`, where `n` is the constant declarations's index among parents(op), if op is an outter reduction.
Returns `-1` if not an outerreduction.
"""
function isouterreduction(op::Operation)
    if isconstant(op) # equivalent to checking if length(loopdependencies(op)) == 0
        op.instruction === LOOPCONSTANT ? 0 : -1
    elseif iscompute(op)
        var = op.variable
        for (n,opp) ∈ enumerate(parents(op))
            opp.variable === var && opp.instruction === LOOPCONSTANT && return n
        end
        -1
    else
        -1
    end
end

# function hasintersection(s1::Set{T}, s2::Set{T}) where {T}
    # for x ∈ s1
        # x ∈ s2 && return true
    # end
    # false
# end

# function symposition(op::Operation, sym::Symbol)
    # findfirst(s -> s === sym, op.symbolic_metadata)
# end
# function stride(op::Operation, sym::Symbol)
    # @assert accesses_memory(op) "This operation does not access memory!"
    # # access stride info?
    # op.numerical_metadata[symposition(op,sym)]
# end



