using EDFFiles
using Dates
using Test

#####
##### Testing utilities
#####

function deep_equal(a::T, b::T) where T
    nfields = fieldcount(T)
    if nfields == 0
        return isequal(a, b)  # Use `isequal` instead of `==` to handle `missing`
    else
        for i = 1:nfields
            isdefined(a, i) || return !isdefined(b, i)  # Call two undefs equal
            deep_equal(getfield(a, i), getfield(b, i)) || return false
        end
    end
    return true
end

function deep_equal(a::T, b::T) where T<:AbstractArray
    length(a) == length(b) || return false
    for (x, y) in zip(a, b)
        deep_equal(x, y) || return false
    end
    return true
end

deep_equal(a::T, b::S) where {T,S} = false

#####
##### Actual tests
#####

const DATADIR = joinpath(@__DIR__, "data")

@testset "Just Do It" begin
    edf = EDFFile(joinpath(DATADIR, "test.edf"))
    @test sprint(show, edf) == "EDFFile with 140 signals"
    @test edf.header.version == "0"
    @test edf.header.patient == PatientID(missing, missing, missing, missing)
    @test edf.header.recording == RecordingID(Date(2014, 4, 29), missing, missing, missing)
    @test edf.header.continuous
    @test edf.header.start == DateTime(2014, 4, 29, 22, 19, 44)
    @test edf.header.n_records == 6
    @test edf.header.duration == 1.0
    @test edf.header.n_signals == 140
    @test edf.signals isa Vector{Signal}
    @test length(edf.signals) == edf.header.n_signals
    for s in edf.signals
        @test length(s.samples) == s.n_samples * edf.header.n_records
    end

    io = IOBuffer()
    nb = EDFFiles.write_header(io, edf)
    @test nb == edf.header.nb_header
    EDFFiles.write_data(io, edf)
    seekstart(io)
    h, d = EDFFiles.read_header(io)
    @test deep_equal(edf.header, h)
    EDFFiles.read_data!(io, d, h)
    @test eof(io)
    @test deep_equal(edf.signals, d)

    mktempdir() do dir
        file = joinpath(dir, "test2.edf")
        write_edf(file, edf)
        edf2 = EDFFile(file)
        @test deep_equal(edf, edf2)
    end
end
