include("set_up_tests.jl")

@testset "Aqua" begin
    Aqua.test_all(EDF;
                  ambiguities=false,
                  # false positive on EDF.File?
                  unbound_args=false)
end

@testset "Just Do It" begin
    # test EDF.read(::AbstractString)
    edf = EDF.read(joinpath(DATADIR, "test.edf"))
    @test sprint(show, edf) == "EDF.File with 140 16-bit-encoded signals"
    @test edf.header.version == "0"
    @test edf.header.patient == PatientID(missing, missing, missing, missing)
    @test edf.header.recording == RecordingID(Date(2014, 4, 29), missing, missing, missing)
    @test edf.header.is_contiguous
    @test edf.header.start == DateTime(2014, 4, 29, 22, 19, 44)
    @test edf.header.record_count == 6
    @test edf.header.seconds_per_record == 1.0
    @test edf.signals isa Vector{Union{Signal{Int16},AnnotationsSignal}}
    @test length(edf.signals) == 140
    for signal in edf.signals
        if signal isa EDF.Signal
            @test length(signal.samples) ==
                  signal.header.samples_per_record * edf.header.record_count
        else
            @test length(signal.records) == edf.header.record_count
            # XXX seems like this test file actually contains nonsensical onset timestamps...
            # according to the EDF+ specification, onsets should be relative to the start time of
            # the entire file, but it seems like whoever wrote these onsets might have used values
            # that were relative to the start of the surrounding data record
            expected = [[TimestampedAnnotationList(0.0, nothing, String[""]),
                         TimestampedAnnotationList(0.0, nothing, ["start"])],
                        [TimestampedAnnotationList(1.0, nothing, String[""]),
                         TimestampedAnnotationList(0.1344, 0.256, ["type A"])],
                        [TimestampedAnnotationList(2.0, nothing, String[""]),
                         TimestampedAnnotationList(0.3904, 1.0, ["type A"])],
                        [TimestampedAnnotationList(3.0, nothing, String[""]),
                         TimestampedAnnotationList(2.0, nothing, ["type B"])],
                        [TimestampedAnnotationList(4.0, nothing, String[""]),
                         TimestampedAnnotationList(2.5, 2.5, ["type A"])],
                        [TimestampedAnnotationList(5.0, nothing, String[""])]]
            @test all(signal.records .== expected)
            @test AnnotationsSignal(signal.records).samples_per_record == 16
        end
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
    # ensure that multiple `EDF.read!` calls don't error and have no effect by
    # simply rerunning the exact same test as above
    EDF.read!(file)
    @test deep_equal(edf.signals, file.signals)

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

    @testset "EDF constructor with different signal collection (el)type (#95)" begin
        alt_signals = Tuple(file.signals)
        @test EDF.File(IOBuffer(), file.header, alt_signals) isa EDF.File{Int16}

        alt_signals = collect(Signal, filter(s -> !(s isa AnnotationsSignal), file.signals))
        @test alt_signals isa Vector{Signal}
        @test EDF.File(IOBuffer(), file.header, alt_signals) isa EDF.File{Int16}

        alt_signals = collect(AnnotationsSignal,
                              filter(s -> s isa AnnotationsSignal, file.signals))
        @test alt_signals isa Vector{AnnotationsSignal}
        @test EDF.File(IOBuffer(), file.header, alt_signals) isa EDF.File{Int16}

        # this even allows for empty EDFs ...
        @test EDF.File(IOBuffer(), file.header, []) isa EDF.File{Int16}
    end

    @test EDF._edf_repr(EDF._nearest_representable_edf_time_value(-0.0023405432)) ==
          "-0.00234"
    @test EDF._edf_repr(EDF._nearest_representable_edf_time_value(0.0023405432)) ==
          "0.002340"
    @test EDF._edf_repr(EDF._nearest_representable_edf_time_value(1.002343)) == "1.002343"
    @test EDF._edf_repr(EDF._nearest_representable_edf_time_value(1011.05432)) == "1011.054"
    @test EDF._edf_repr(EDF._nearest_representable_edf_time_value(-1011.05432)) ==
          "-1011.05"
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
    @test sprint(show, uneven) == "EDF.File with 2 16-bit-encoded signals"
    @test uneven.header.version == "0"
    @test uneven.header.patient ==
          "A 3Hz sinewave and a 0.2Hz block signal, both starting in their positive phase"
    @test uneven.header.recording == "110 seconds from 13-JUL-2000 12.05.48hr."
    @test uneven.header.is_contiguous
    @test uneven.header.start == DateTime(2000, 1, 31, 23, 0, 59)
    @test uneven.header.record_count == 11
    @test uneven.header.seconds_per_record == 10.0
    @test uneven.signals[1].header.samples_per_record !=
          uneven.signals[2].header.samples_per_record
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
    mne = map(line -> parse(Float32, line), eachline(joinpath(DATADIR, "mne_values.csv")))
    for (a, b) in zip(EDF.decode(signal), mne)
        @test a ≈ b atol=0.01
    end

    # Truncated files
    dir = mktempdir(; cleanup=true)
    for full_file in ["test.edf", "evt.bdf"]
        # note that this tests a truncated final record, not an incorrect number of records
        truncated_file = joinpath(dir, "test_truncated" * last(splitext(full_file)))
        full_edf_bytes = read(joinpath(DATADIR, full_file))
        write(truncated_file, full_edf_bytes[1:(end - 1)])
        @test_logs((:warn,
                    "Number of data records in file header does not match " *
                    "file size. Skipping 1 truncated data record(s)."),
                   EDF.read(truncated_file))
        edf = EDF.read(joinpath(DATADIR, full_file))
        truncated_edf = EDF.read(truncated_file)
        for field in fieldnames(EDF.FileHeader)
            a = getfield(edf.header, field)
            b = getfield(truncated_edf.header, field)
            if field === :record_count
                @test b == a - 1
            else
                @test a == b
            end
        end
        for i in 1:length(edf.signals)
            good = edf.signals[i]
            bad = truncated_edf.signals[i]
            if good isa EDF.Signal
                @test deep_equal(good.header, bad.header)
                @test good.samples[1:(end - good.header.samples_per_record)] == bad.samples
            else
                @test good.samples_per_record == bad.samples_per_record
            end
        end
        @test deep_equal(edf.signals[end].records[1:(edf.header.record_count - 1)],
                         truncated_edf.signals[end].records)
        # Ensure that "exotic" IO types work for truncated records if the requisite
        # methods exist
        fb = FileBuffer(Path(truncated_file))
        @test EDF._size(fb) == length(full_edf_bytes) - 1
        fb_edf = EDF.read(fb)
        @test deep_equal(truncated_edf.header, fb_edf.header)
        @test deep_equal(truncated_edf.signals, fb_edf.signals)
    end

    @test EDF._size(IOBuffer("memes")) == 5
    @test EDF._size(Base.DevNull()) == -1

    @testset "BDF Files" begin
        # The corresponding EDF file was exported by 3rd party software based on the BDF,
        # so some differences are inevitable, but we just want to check that the values
        # are Close Enough™.
        bdf = EDF.read(joinpath(DATADIR, "bdf_test.bdf"))
        comp = EDF.read(joinpath(DATADIR, "bdf_test.edf"))
        for i in 1:8
            bdf_values = EDF.decode(bdf.signals[i])
            comp_values = EDF.decode(comp.signals[i])
            @test bdf_values ≈ comp_values rtol=0.01
        end
        # Ensure that BDF files can also be round-tripped
        mktempdir() do dir
            path = joinpath(dir, "tmp.bdf")
            EDF.write(path, bdf)
            file = EDF.read(path)
            @test deep_equal(bdf, file)
        end
        @test EDF.sample_type(bdf) == EDF.Int24
        @test EDF.sample_type(comp) == Int16
        @test EDF.is_bdf(bdf)
        @test !EDF.is_bdf(comp)
        @test sprint(show, bdf) == "EDF.File with 8 24-bit-encoded signals"
    end

    @testset "FilePathsBase support" begin
        # test EDF.read(::AbstractPath)
        edf = EDF.read(Path(joinpath(DATADIR, "test.edf")))
        @test sprint(show, edf) == "EDF.File with 140 16-bit-encoded signals"

        # emulate EDF.read(::S3Path)
        io = FileBuffer(Path(joinpath(DATADIR, "test.edf")))
        edf = EDF.File(io)
        @test sprint(show, edf) == "EDF.File with 140 16-bit-encoded signals"
    end
end

@testset "BDF+ Files" begin
    # This is a `BDF+` file containing only trigger information.
    # It is similiar to a `EDF Annotations` file except that
    # The `ANNOTATIONS_SIGNAL_LABEL` is `BDF Annotations`.
    # The test data has 1081 trigger events, and
    # has 180 trials in total, and
    # The annotation `255` signifies the offset of a trial.
    # More information, contact: zhanlikan@hotmail.com
    evt = EDF.read(joinpath(DATADIR, "evt.bdf"))
    events = evt.signals[2].records
    @test length(events) == 1081
    annotations = [event[end].annotations[1] for event in events]
    @test count(==("255"), annotations) == 180
end
