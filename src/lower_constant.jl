function lower_zero!(
    q::Expr, op::Operation, vectorized::Symbol, W::Symbol, unrolled::Symbol, U::Int,
    suffix::Union{Nothing,Int}, typeT::Symbol
)
    mvar = variable_name(op, suffix)
    if vectorized ∈ loopdependencies(op) || vectorized ∈ reducedchildren(op) || vectorized ∈ reduceddependencies(op)
        call = Expr(:call, lv(:vzero), W, typeT)
    else
        call = Expr(:call, :zero, typeT)
    end
    if unrolled ∈ loopdependencies(op) || unrolled ∈ reducedchildren(op) || unrolled ∈ reduceddependencies(op)
        for u ∈ 0:U-1
            push!(q.args, Expr(:(=), Symbol(mvar, u), call))
        end
    else
        push!(q.args, Expr(:(=), mvar, call))
    end
    nothing    
end
function lower_constant!(
    q::Expr, op::Operation, vectorized::Symbol, W::Symbol, unrolled::Symbol, U::Int,
    suffix::Union{Nothing,Int}
)
    instruction = op.instruction
    mvar = variable_name(op, suffix)
    constsym = instruction.instr
    if vectorized ∈ loopdependencies(op) || vectorized ∈ reducedchildren(op) || vectorized ∈ reduceddependencies(op)
        call = Expr(:call, lv(:vbroadcast), W, constsym)
        if unrolled ∈ loopdependencies(op) || unrolled ∈ reducedchildren(op) || unrolled ∈ reduceddependencies(op)
            for u ∈ 0:U-1
                push!(q.args, Expr(:(=), Symbol(mvar, u), call))
            end
        else
            push!(q.args, Expr(:(=), mvar, call))
        end
    else
        if unrolled ∈ loopdependencies(op) || unrolled ∈ reducedchildren(op) || unrolled ∈ reduceddependencies(op)
            for u ∈ 0:U-1
                push!(q.args, Expr(:(=), Symbol(mvar, u), constsym))
            end
        else
            push!(q.args, Expr(:(=), mvar, constsym))
        end
    end
    nothing
end

function setop!(ls, op, val)
    if instruction(op) === LOOPCONSTANT# && mangledvar(op) !== val
        pushpreamble!(ls, Expr(:(=), mangledvar(op), val))
    else
        pushpreamble!(ls, Expr(:(=), instruction(op).instr, val))
    end
    nothing
end
function setconstantop!(ls, op, val)
    if instruction(op) === LOOPCONSTANT# && mangledvar(op) !== val
        pushpreamble!(ls, Expr(:(=), mangledvar(op), val))
    end
    nothing
end


function lower_licm_constants!(ls::LoopSet)
    ops = operations(ls)
    for (id, sym) ∈ ls.preamble_symsym
        setconstantop!(ls, ops[id], sym)
    end
    for (id,intval) ∈ ls.preamble_symint
        setop!(ls, ops[id], Expr(:call, lv(:sizeequivalentint), ls.T, intval))
    end
    for (id,floatval) ∈ ls.preamble_symfloat
        setop!(ls, ops[id], Expr(:call, lv(:sizeequivalentfloat), ls.T, intval))
    end
    for id ∈ ls.preamble_zeros
        setconstantop!(ls, ops[id], Expr(:call, :zero, ls.T))
    end
    for id ∈ ls.preamble_ones
        setop!(ls, ops[id], Expr(:call, :one, ls.T))
    end
end



