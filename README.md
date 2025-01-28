# EDF.jl

[![CI](https://github.com/beacon-biosignals/EDF.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/beacon-biosignals/EDF.jl/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/beacon-biosignals/EDF.jl/branch/main/graph/badge.svg?token=E8vy5nZtJF)](https://codecov.io/gh/beacon-biosignals/EDF.jl)
[![](https://img.shields.io/badge/docs-stable-blue.svg)](https://beacon-biosignals.github.io/EDF.jl/stable)
[![](https://img.shields.io/badge/docs-dev-blue.svg)](https://beacon-biosignals.github.io/EDF.jl/dev)

Read and write [European Data Format (EDF/EDF+)](https://www.edfplus.info/) and [BioSemi Data Format (BDF)](https://www.biosemi.com/faq/file_format.htm) files in Julia.

Compared to all features implied by the EDF/EDF+ specifications, this package is currently missing:

- Out-of-core data record streaming; this package (and its type representations, i.e. `EDF.Signal`) generally assumes the user is loading all of a file's sample data into memory at once.
- Specialization for discontinuous EDF+ files ("EDF+D" files).
- Validation/specialization w.r.t. ["canonical/standard EDF texts"](https://www.edfplus.info/specs/edftexts.html)
- Validation-on-write of manually constructed `EDF.File`s
- Support for [the EDF+ `longinteger`/`float` extension](https://www.edfplus.info/specs/edffloat.html)

Where practical, this package chooses field names that are as close to EDF/EDF+ specification terminology as possible.

## Breaking Changes

In 0.8 the field `samples_per_record` of `SignalHeader` was changes from `Int16` to `Int32`.
