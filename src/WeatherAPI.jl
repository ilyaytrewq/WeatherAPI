include("DataCollector.jl")
include("UserInterface.jl")
include("Handlers.jl")

using HTTP
using .Handlers
using .DataCollector
using .UserInterface

function main()
    #
    UserInterface.init_postgres_db()
    DataCollector.init_clickhouse_db()
    

    DataCollector.start_periodic_task(120)


    server = HTTP.serve!(
        Handlers.request_handler,  # Обработчик запросов
        "0.0.0.0",        # Хост (все интерфейсы)
        8080,             # Порт
        reuseaddr = true, # Разрешить переиспользование адреса
    )
    
    @info "Server started on port 8080"
    
    try
        # Бесконечный цикл ожидания
        while true
            sleep(1)
        end
    catch e
        # Обработка прерывания (Ctrl+C)
        if e isa InterruptException
            @info "Shutting down server"
        else
            @error "Unexpected error" exception=e
        end
    finally
        # Корректное завершение
        close(server)
        close(client[])
        @info "Server stopped"
    end
end


if abspath(PROGRAM_FILE) == @__FILE__
    main()
end