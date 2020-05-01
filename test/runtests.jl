using EDF
using EDF: AnnotationList, PatientID, RecordAnnotation, TimestampAnnotation, RecordingID, SignalHeader
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
            typeof(getfield(a, i)) <: IO && continue # Two different files will have different IO sources
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
    @test edf.signals isa Vector{Pair{SignalHeader,Vector{Int16}}}
    @test length(edf.signals) == 139
    for (signal, samples) in edf.signals
        @test length(samples) == signal.n_samples * edf.header.n_records
    end
    expected = [
        (RecordAnnotation(0.0, nothing) => [TimestampAnnotation(0.0, nothing, ["start"])]),
        (RecordAnnotation(1.0, nothing) => [TimestampAnnotation(0.1344, 0.256, ["type A"])]),
        (RecordAnnotation(2.0, nothing) => [TimestampAnnotation(0.3904, 1.0, ["type A"])]),
        (RecordAnnotation(3.0, nothing) => [TimestampAnnotation(2.0, nothing, ["type B"])]),
        (RecordAnnotation(4.0, nothing) => [TimestampAnnotation(2.5, 2.5, ["type A"])]),
        (RecordAnnotation(5.0, nothing) => nothing),
    ]
    @test deep_equal(edf.annotations.records, expected)

    io = IOBuffer()
    nb = EDF.write_header(io, edf)
    has_annotations = edf.annotations !== nothing
    @test nb == 256 * (length(edf.signals) + has_annotations + 1)
    EDF.write_data(io, edf)
    seekstart(io)
    file_header, signal_headers = EDF.read_file_and_signal_headers(io)
    @test deep_equal(edf.header, file_header)
    annotations = EDF.extract_annotation_header!(signal_headers)
    signals = [header => Vector{Int16}() for header in signal_headers]
    EDF.read_signals!(EDF.File(io, file_header, signals, annotations))
    @test eof(io)
    @test deep_equal(edf.signals, signals)
    @test deep_equal(edf.annotations, annotations)

    mktempdir() do dir
        file = joinpath(dir, "test2.edf")
        EDF.write(file, edf)
        edf2 = EDF.read(file)
        @test deep_equal(edf, edf2)
        edf3 = EDF.File(open(file, "r"))
        @test !eof(edf3.io)
        @test isopen(edf3.io)
        @test edf.header == edf3.header
        for (signal_1, signal_2) in zip(edf.signals, edf3.signals)
            @test first(signal_1) == first(signal_2)
        end
        for (signal, samples) in edf3.signals
            @test isempty(samples)
        end
        @test edf.annotations.header == edf.annotations.header
        EDF.read!(edf3)
        @test !isopen(edf.io)
        @test eof(edf3.io)
        @test deep_equal(edf3, edf)
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
    @test uneven.signals[1].first.n_samples != uneven.signals[2].first.n_samples
    @test uneven.annotations === nothing
    @test length(uneven.signals) == 2

    nonint = EDF.read(joinpath(DATADIR, "test_float_extrema.edf"))
    s = first(nonint.signals)
    h = first(s)
    @test h.physical_min ≈ -29483.1f0
    @test h.physical_max ≈ 29483.12f0
    @test h.digital_min ≈ -32767.0f0
    @test h.digital_max ≈ 32767.0f0

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
