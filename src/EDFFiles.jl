module EDFFiles

export EDFFile, Signal

using Dates

#####
##### Signals
#####

# TODO: Make the vector of samples mmappable
# Also TODO: Refactor to make signals immutable
"""
    Signal

Type representing a single signal extracted from an EDF file.
"""
mutable struct Signal
    label::String
    transducer::String
    physical_units::String
    physical_min::Int16
    physical_max::Int16
    digital_min::Int16
    digital_max::Int16
    prefilter::String
    n_samples::Int16
    samples::Vector{Int16}

    Signal() = new()
end

#struct PatientID
#    code::Union{String,Missing}
#    sex::Union{Char,Missing}
#    birthdate::Union{Date,Missing}
#    name::Union{String,Missing}
#end
#
#function PatientID(raw::String)
#    s = split(raw, ' ', keepempty=false)
#    if length(s) != 4
#        throw(ArgumentError("Expected 4 patient identifier fields, got $(length(s))"))
#    end
#    code_raw, sex_raw, dob_raw, name_raw = s
#    code = edf_unknown(code_raw)
#    if length(sex_raw) != 1
#        throw(ArgumentError("Expected 1 character sex identifier, got '$(sex_raw)'"))
#    end
#    sex = edf_unknown(first, sex_raw)
#    dob = edf_unknown(raw->Date(raw, dateformat"d-u-y"), dob_raw)
#    name = edf_unknown(name_raw)
#    return PatientID(code, sex, dob, name)
#end
#
#struct RecordingID
#    startdate::Union{Date,Missing}
#    admincode::Union{String,Missing}
#    technician::Union{String,Missing}
#    equipment::Union{String,Missing}
#end
#
#function RecordingID(raw::String)
#    s = split(raw, ' ', keepempty=false)
#    if length(s) != 5
#        throw(ArgumentError("Expected 4 recording identifier fields, got $(length(s))"))
#    end
#    _, start_raw, admin_raw, tech_raw, equip_raw = s
#    startdate = edf_unknown(raw->Date(raw, dateformat"d-u-y"), start_raw)
#    admincode = edf_unknown(admin_raw)
#    technician = edf_unknown(tech_raw)
#    equipment = edf_unknown(equip_raw)
#    return RecordingID(startdate, admincode, technician, equipment)
#end

"""
    EDFHeader

Type representing the header record for an EDF file.

## Fields

* `version` (`String`): Version of the data format
* `patient` (`PatientID`): Local patient identification
* `recording` (`RecordingID`): Local recording identification
* `start` (`Dates.DateTime`): Date and time the recording started
* `n_records` (`Int`): Number of data records
* `duration` (`Float64`): Duration of a data record in seconds
* `n_signals` (`Int`): Number of signals in a data record
"""
struct EDFHeader
    version::String
    patient::String #PatientID
    recording::String #RecordingID
    continuous::Bool
    start::DateTime
    n_records::Int
    duration::Float64
    n_signals::Int
end

"""
    EDFFile

Type representing a parsed EDF file.
All data defined in the file is accessible from this type through various mechanisms.
"""
struct EDFFile
    header::EDFHeader
    signals::Dict{String,Signal}
end

function EDFFile(file::AbstractString)
    open(file, "r") do io
        header, data = read_header(io)
        read_data!(io, data, header)
        EDFFile(header, Dict(x.label => x for x in data))
    end
end

function Base.show(io::IO, edf::EDFFile)
    print(io, "EDFFile with ", length(keys(edf.signals)), " signals")
end

#####
##### The rest
#####

include("read.jl")
include("write.jl")

end # module
