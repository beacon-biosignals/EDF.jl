using EDFFiles
using Dates
using Test

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
    seekstart(io)
    h, _ = EDFFiles.read_header(io)
    for f in fieldnames(typeof(h))
        if !isdefined(edf.header, f)
            @test !isdefined(h, f)
        else
            @test getfield(edf.header, f) == getfield(h, f)
        end
    end
end
