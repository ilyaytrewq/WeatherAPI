include("Handlers.jl")
include("DataCollector.jl")

using HTTP
using .Handlers
using .DataCollector

function main()
    #
    Handlers.init_postgres_db()
    DataCollector.init_clickhouse_db()
    

    DataCollector.start_periodic_task(10)

    HTTP.serve(Handlers.request_handler, "0.0.0.0", 8080)
end


if abspath(PROGRAM_FILE) == @__FILE__
    main()
end