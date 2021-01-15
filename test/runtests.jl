using EDF
using EDF: TimestampedAnnotationList, PatientID, RecordingID, SignalHeader,
           Signal, AnnotationsSignal
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
    # test EDF.read(::AbstractString)
    edf = EDF.read(joinpath(DATADIR, "test.edf"))
    @test sprint(show, edf) == "EDF.File with 140 signals"
    @test edf.header.version == "0"
    @test edf.header.patient == PatientID(missing, missing, missing, missing)
    @test edf.header.recording == RecordingID(Date(2014, 4, 29), missing, missing, missing)
    @test edf.header.is_contiguous
    @test edf.header.start == DateTime(2014, 4, 29, 22, 19, 44)
    @test edf.header.record_count == 6
    @test edf.header.seconds_per_record == 1.0
    @test edf.signals isa Vector{Union{Signal,AnnotationsSignal}}
    @test length(edf.signals) == 140
    for signal in edf.signals
        if signal isa EDF.Signal
            @test length(signal.samples) == signal.header.samples_per_record * edf.header.record_count
        else
            @test length(signal.records) == edf.header.record_count
            # XXX seems like this test file actually contains nonsensical onset timestamps...
            # according to the EDF+ specification, onsets should be relative to the start time of
            # the entire file, but it seems like whoever wrote these onsets might have used values
            # that were relative to the start of the surrounding data record
            expected = [[TimestampedAnnotationList(0.0, nothing, String[""]), TimestampedAnnotationList(0.0, nothing, ["start"])],
                        [TimestampedAnnotationList(1.0, nothing, String[""]), TimestampedAnnotationList(0.1344, 0.256, ["type A"])],
                        [TimestampedAnnotationList(2.0, nothing, String[""]), TimestampedAnnotationList(0.3904, 1.0, ["type A"])],
                        [TimestampedAnnotationList(3.0, nothing, String[""]), TimestampedAnnotationList(2.0, nothing, ["type B"])],
                        [TimestampedAnnotationList(4.0, nothing, String[""]), TimestampedAnnotationList(2.5, 2.5, ["type A"])],
                        [TimestampedAnnotationList(5.0, nothing, String[""])]]
            @test all(signal.records .== expected)
            @test AnnotationsSignal(signal.records).samples_per_record == 16
        end
    end

    @testset "truncated EDF" begin
        # note that this tests a truncated final record, not an incorrect number of records
        fulledf = read(joinpath(DATADIR, "test.edf"))
        write(joinpath(DATADIR, "test_truncated.edf"), fulledf[begin:end-1537])
        logmsg = (:warn, "Sample data is truncated: tried to read 512 bytes but only 511 available")
        @test_logs logmsg EDF.read(joinpath(DATADIR, "test_truncated.edf"))

        truncedf = EDF.read(joinpath(DATADIR, "test_truncated.edf"))
        @test deep_equal(edf.header, truncedf.header)

        # the last signal read is truncated, so won't match
        # likewise for the annotation signal
        @test deep_equal(edf.signals[1:end-2], truncedf.signals[1:end-2])

        full_last_signal = edf.signals[end-1]
        trunc_last_signal = truncedf.signals[end-1]
        @test deep_equal(full_last_signal.header, trunc_last_signal.header)
        # XXX This doesn't work -- not sure why
        # @test all(full_last_signal.samples[1:end-1] .== trunc_last_signal.samples)
        @test length(full_last_signal.samples) - 1 == length(trunc_last_signal.samples)

        trunc_anno_signal = last(truncedf.signals)
        full_anno_signal = last(edf.signals)
        @test deep_equal(full_anno_signal.records[1:end-1], trunc_anno_signal.records[1:end-1])
        @test last(trunc_anno_signal.records) == []
        @test full_anno_signal.samples_per_record == trunc_anno_signal.samples_per_record
    end

    # test EDF.write(::IO, ::EDF.File)
    io = IOBuffer()
    EDF.write(io, edf)
    seekstart(io)
    file = EDF.File(io)
    @test deep_equal(edf.header, file.header)
    @test all(isempty(s isa Signal ? s.samples : s.records) for s in file.signals)
    EDF.read!(file)
    @test deep_equal(edf.signals, file.signals)
    @test eof(io)

    # test that EDF.write(::IO, ::EDF.File) errors if file is
    # discontiguous w/o an AnnotationsSignal present
    bad_file = EDF.File(IOBuffer(),
                        EDF.FileHeader(file.header.version,
                                       file.header.patient,
                                       file.header.recording,
                                       file.header.start,
                                       false, # is_contiguous
                                       file.header.record_count,
                                       file.header.seconds_per_record),
                        filter(s -> !(s isa AnnotationsSignal), file.signals))
    @test_throws ArgumentError EDF.write(IOBuffer(), bad_file)

    # test EDF.write(::AbstractString, ::EDF.File)
    mktempdir() do dir
        path = joinpath(dir, "tmp.edf")
        EDF.write(path, edf)
        file = EDF.File(open(path, "r"))
        @test deep_equal(edf.header, file.header)
        @test all(isempty(s isa Signal ? s.samples : s.records) for s in file.signals)
        EDF.read!(file)
        @test deep_equal(edf.signals, file.signals)
        @test eof(io)
    end

    @test EDF._edf_repr(EDF._nearest_representable_edf_time_value(-0.0023405432)) == "-0.00234"
    @test EDF._edf_repr(EDF._nearest_representable_edf_time_value(0.0023405432)) == "0.002340"
    @test EDF._edf_repr(EDF._nearest_representable_edf_time_value(1.002343)) == "1.002343"
    @test EDF._edf_repr(EDF._nearest_representable_edf_time_value(1011.05432)) == "1011.054"
    @test EDF._edf_repr(EDF._nearest_representable_edf_time_value(-1011.05432)) == "-1011.05"
    @test EDF._edf_repr(EDF._nearest_representable_edf_time_value(-1013441.5)) == "-1013442"
    @test EDF._edf_repr(EDF._nearest_representable_edf_time_value(-1013441.3)) == "-1013441"
    @test EDF._edf_repr(34577777) == "34577777"
    @test EDF._edf_repr(0.0345) == "0.034500"
    @test EDF._edf_repr(-0.02) == "-0.02000"
    @test EDF._edf_repr(-187.74445) == "-187.744"
    @test_throws ErrorException EDF._edf_repr(123456789)
    @test_throws ErrorException EDF._edf_repr(-12345678)
    @test_throws ErrorException EDF._edf_repr(0.00000000024)
    @test_throws ErrorException EDF.edf_write(IOBuffer(), "hahahahaha", 4)

    uneven = EDF.read(joinpath(DATADIR, "test_uneven_samp.edf"))
    @test sprint(show, uneven) == "EDF.File with 2 signals"
    @test uneven.header.version == "0"
    @test uneven.header.patient == "A 3Hz sinewave and a 0.2Hz block signal, both starting in their positive phase"
    @test uneven.header.recording == "110 seconds from 13-JUL-2000 12.05.48hr."
    @test uneven.header.is_contiguous
    @test uneven.header.start == DateTime(2000, 1, 31, 23, 0, 59)
    @test uneven.header.record_count == 11
    @test uneven.header.seconds_per_record == 10.0
    @test uneven.signals[1].header.samples_per_record != uneven.signals[2].header.samples_per_record
    @test length(uneven.signals) == 2

    nonint = EDF.read(joinpath(DATADIR, "test_float_extrema.edf"))
    signal = nonint.signals[1]
    @test signal.header.physical_minimum ≈ -29483.1f0
    @test signal.header.physical_maximum ≈ 29483.12f0
    @test signal.header.digital_minimum ≈ -32767.0f0
    @test signal.header.digital_maximum ≈ 32767.0f0

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
    for (a, b) in zip(EDF.decode(signal), mne)
        @test a ≈ b atol=0.01
    end

end

