using Documenter
using EDF

makedocs(modules=[EDF],
         sitename="EDF.jl",
         authors="Beacon Biosignals, Inc.",
         pages=["Functionality" => "index.md"])

# Comment out until the package is open source
#deploydocs(repo="github.com/beacon-biosignals/EDF.jl.git")
