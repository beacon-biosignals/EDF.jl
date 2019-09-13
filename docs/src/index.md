# EDFFiles.jl

EDFFiles is a Julia package for working with [European Data Format (EDF)](https://edfplus.info)
files, including reading, writing, and an intermediate representation for direct access
to data.

## Package API

```@meta
CurrentModule = EDFFiles
```
### Representation of Data

EDF files consist of a header record, which contains file-level metadata, and a number
of contiguous data records, each containing a chunk of each signal.
In Julia, we represent this with an `EDFFile` type that consists of an `EDFHeader` object
and a vector of `Signal`s.

```@docs
EDFFile
EDFFiles.EDFHeader
EDFFiles.Signal
```

Per the original EDF specification, the signals are assumed to be continuous across data
records.
However, the EDF+ specification introduced the notion of discontinuous signals, denoted
with a value of "EDF+D" in one of the reserved fields.
The `EDFHeader` type notes this in a `Bool` field called `continuous`.
The signal data is always store contiguously, regardless of whether the data records are
declared to be continuous, but, given a `Signal` object, users of the package can divide
the signal by records if needed using

```julia
Iterators.partition(signal.samples, signal.n_samples)
```

This will construct a lazy iterator over non-overlapping chunks of the signal, iterating
which yields a total of `header.n_records` items.

### Reading

The `EDFFile` type constructor, mentioned above, accepts a path to a file as a string.

### Writing

```@docs
write_edf
```
