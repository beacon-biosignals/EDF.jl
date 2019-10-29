using EDF
using EDF: AnnotationsList, PatientID, RecordAnnotation, RecordingID, Signal
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
    edf = EDF.read(joinpath(DATADIR, "test.edf"))
    @test sprint(show, edf) == "EDF.File with 139 signals"
    @test edf.header.version == "0"
    @test edf.header.patient == PatientID(missing, missing, missing, missing)
    @test edf.header.recording == RecordingID(Date(2014, 4, 29), missing, missing, missing)
    @test edf.header.continuous
    @test edf.header.start == DateTime(2014, 4, 29, 22, 19, 44)
    @test edf.header.n_records == 6
    @test edf.header.duration == 1.0
    @test edf.header.n_signals == 139
    @test edf.signals isa Vector{Signal}
    @test length(edf.signals) == edf.header.n_signals
    for s in edf.signals
        @test length(s.samples) == s.n_samples * edf.header.n_records
    end
    expected = [
        RecordAnnotation(0.0, String[], [AnnotationsList(0.0, nothing, ["start"])], 1024),
        RecordAnnotation(1.0, String[], [AnnotationsList(0.1344, 0.256, ["type A"])], 1024),
        RecordAnnotation(2.0, String[], [AnnotationsList(0.3904, 1.0, ["type A"])], 1024),
        RecordAnnotation(3.0, String[], [AnnotationsList(2.0, nothing, ["type B"])], 1024),
        RecordAnnotation(4.0, String[], [AnnotationsList(2.5, 2.5, ["type A"])], 1024),
        RecordAnnotation(5.0, String[], AnnotationsList[], 1024),
    ]
    @test deep_equal(edf.annotations, expected)

    io = IOBuffer()
    nb = EDF.write_header(io, edf)
    @test nb == edf.header.nb_header
    EDF.write_data(io, edf)
    seekstart(io)
    h, d, i = EDF.read_header(io)
    @test deep_equal(edf.header, h)
    d, a = EDF.read_data!(io, d, h, i)
    @test eof(io)
    @test deep_equal(edf.signals, d)
    @test deep_equal(edf.annotations, a)

    mktempdir() do dir
        file = joinpath(dir, "test2.edf")
        EDF.write(file, edf)
        edf2 = EDF.read(file)
        @test deep_equal(edf, edf2)
    end

    uneven = EDF.read(joinpath(DATADIR, "test_uneven_samp.edf"))
    @test sprint(show, uneven) == "EDF.File with 2 signals"
    @test uneven.header.version == "0"
    @test uneven.header.patient == "A 3Hz sinewave and a 0.2Hz block signal, both starting in their positive phase"
    @test uneven.header.recording == "110 seconds from 13-JUL-2000 12.05.48hr."
    @test uneven.header.continuous
    @test uneven.header.start == DateTime(2000, 7, 13, 12, 5, 48)
    @test uneven.header.n_records == 11
    @test uneven.header.duration == 10.0
    @test uneven.header.n_signals == 2
    @test uneven.signals[1].n_samples != uneven.signals[2].n_samples
    @test uneven.annotations === nothing

    nonint = EDF.read(joinpath(DATADIR, "test_float_extrema.edf"))
    s = first(nonint.signals)
    @test s.physical_min ≈ -29483.1f0
    @test s.physical_max ≈ 29483.12f0
    @test s.digital_min ≈ -32767.0f0
    @test s.digital_max ≈ 32767.0f0

    # Python code for generating the comparison values used here:
    # ```
    # import mne
    # edf = mne.io.read_raw_edf("test/data/test_float_extrema.edf")
    # signal = edf.get_data()[0] * 1e6  # The 1e6 converts volts back to microvolts
    # with open("test/data/mne_values.csv", "w") as f:
    #     for x in signal:
    #         f.write("%s\n" % x)
    # ```
    mne = map(line->parse(Float32, line), eachline(joinpath(DATADIR, "mne_values.csv")))
    for (a, b) in zip(EDF.decode(s), mne)
        @test a ≈ b atol=0.01
    end
end
