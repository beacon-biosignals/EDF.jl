function read_discontiguous!(file::File)
    file.header.is_contiguous && throw(ArgumentError("File is continguous "))
    isopen(file.io) && !eof(file.io) && read_discontiguous_signals!(file)
    return file
end

"""
    EDF.read_discontiguous(io::IO)

Return `EDF.read_discontiguous(EDF.File(io))`.

See also: [`EDF.File`](@ref), [`EDF.read_discontiguous`](@ref)
"""
read_discontiguous(io::IO) = read_discontiguous!(File(io))

"""
    EDF.read_discontiguous(path)

Return `open(EDF.read_discontiguous, path)`.
"""
read_discontiguous(path) = open(read_discontiguous, path)

function read_discontiguous_signals!(file::File)
    # XXX need to have this be slightly more constrained
    time_idx = findfirst(x -> isa(x, EDF.AnnotationsSignal), file.signals)
    time_anns = file.signals[time_idx]
    # annotations have their own timestamps
    signals = filter(x -> isa(x, Signal), file.signals)
    # XXX first we read, then we resize in memory, and finally copy around
    # not the most efficient route, but c'est la vie

    # 1. read
    EDF.read!(file)

    final_record_start = only(last(time_anns.records)).onset_in_seconds
    final_record_start = Int(final_record_start)
    for signal in signals
        # 2. resize
        sr = sampling_rate(file, signal)
        total_length = final_record_start * sr + signal.header.samples_per_record
        # prev_length = length(signal.samples)
        resize!(signal.samples, total_length)
        # # fill all the new stuff with 0s
        # samples = signal.samples
        # fill!(@view(samples[prev_length:end]), 0)
    end

    spr = file.header.seconds_per_record
    # count is used for sanity checking that we foudn the correct number of
    # discontinuities
    count = 0

    # XXX Note that this logic will probably fail for truncated final records.
    for signal in signals
        sr = sampling_rate(file, signal)
        rec_n_samples = Int(sr * spr)
        samples = signal.samples
        prev_start = only(first(time_anns.records)).onset_in_seconds
        for (tal_idx, tal) in enumerate(@view(time_anns.records[2:end]))
            start = only(tal).onset_in_seconds
            if start - spr != prev_start
                # 4. copy around
                start_idx = tal_idx * rec_n_samples + 1
                # -1 because 1-based indexing
                end_idx = start_idx + rec_n_samples - 1
                @info "" start_idx, end_idx
                slice = view(samples, start_idx:end_idx)
                @info "" slice
                post_slice = view(samples, end_idx:lastindex(samples))
                @info "" post_slice
                copyto!(post_slice, slice)
                fill!(slice, 0)
                count += 1
            end
            prev_start = start
        end
    end

    !iszero(count) || count % length(signals) == 0 ||
        error("Found an unexpected number of discontinuities")

    return file
end

function sampling_rate(file::File, signal::Signal)
    return Int(signal.header.samples_per_record / file.header.seconds_per_record)
end
