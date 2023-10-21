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
    # @info "" time_anns
    # record_stop = 1
    # for record_index in 1:(file.header.record_count), (signal_idx, signal) in enumerate(file.signals)
    #     if signal_idx != time_idx
    #         record_stop += record_index * signal.header.samples_per_record - 1
    #         continue
    #     end
    #     seek(file.io, record_stop)
    #     read_signal_record!(file, signal, record_index)
    #     break
    # end
    # # not quite right because of headers
    # seekstart(file.io)
    EDF.read!(file)
    # gonna read and then resize in memory and then copy around
    # not the most efficient route, but c'est la vie
    # specific logic for discontinuous signals
    final_record_start = only(last(time_anns.records)).onset_in_seconds
    final_record_start = Int(final_record_start)
    for signal in signals
        sr = sampling_rate(file, signal)
        total_length = final_record_start * sr + signal.header.samples_per_record
        prev_length = length(signal.samples)
        resize!(signal.samples, total_length)
        # fill all the new stuff with 0s
        samples = signal.samples
        fill!(@view(samples[prev_length:end]), 0)
    end

    spr = file.header.seconds_per_record
    count = 0

    for signal in signals
        prev_start = only(first(time_anns.records)).onset_in_seconds
        for tal in @view(time_anns.records[2:end])
            start = only(tal).onset_in_seconds
            if start - spr == prev_start
                prev_start = start
                continue
            else
                prev_start = start
                # TODO copy around and fill source areas with 0s

                count += 1
            end
        end
    end

    count % length(signals) == 0 ||
        error("Found an unexpected number of discontinuities")

    return file
end

function sampling_rate(file::File, signal::Signal)
    return Int(signal.header.samples_per_record / file.header.seconds_per_record)
end
