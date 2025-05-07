module EDF

using BitIntegers, Dates, Printf

include("types.jl")
include("read.jl")
include("write.jl")

@static if VERSION >= v"1.11"
    # public is parsed weirdly, so we can't just inline the statement here
    include("public.jl")
end

end # module
