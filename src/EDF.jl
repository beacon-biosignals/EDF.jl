module EDF

using BitIntegers, Compat, Dates, Printf

include("types.jl")
include("read.jl")
include("write.jl")

@compat public File,
               FileHeader,
               SignalHeader,
               Signal,
               AnnotationsSignal,
               TimestampedAnnotationList,
               PatientID,
               RecordingID,
               sample_type,
               is_bdf,
               read,
               read!,
               decode,
               write

end # module
