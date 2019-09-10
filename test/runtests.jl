using EDFFiles
using Dates
using Test

const DATADIR = joinpath(@__DIR__, "data")

@testset "Just Do It" begin
    edf = EDFFile(joinpath(DATADIR, "test.edf"))
    @test sprint(show, edf) == "EDFFile with 140 signals"
    @test edf.header.version == "0"
    @test edf.header.patient == "X X X X"
    @test edf.header.recording == "Startdate 29-APR-2014 X X X"
    @test edf.header.continuous
    @test edf.header.start == DateTime(2014, 4, 29, 22, 19, 44)
    @test edf.header.n_records == 6
    @test edf.header.duration == 1.0
    @test edf.header.n_signals == 140
    @test edf.signals isa Dict{String,Signal}
    @test length(edf.signals) == edf.header.n_signals
    for (k, v) in edf.signals
        @test length(v.samples) == v.n_samples * edf.header.n_records
    end
end
