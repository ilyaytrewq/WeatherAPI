module DataCollector

using EasyCurl
using JSON
using OhMyCH, Dates 
using HTTP
using Base.Threads

const API_WEATHER_URL = "https://pro.openweathermap.org/data/2.5/weather?"
const API_COORDINATES_URL = "http://api.openweathermap.org/geo/1.0/direct?"
const API_WEATHER_KEY = "APPID=" * get(ENV, "API_WEATHER_KEY", "")

CITIES = Set{String}() #cities for analysis 

const client = Ref{OhMyCH.HttpClient}()

struct weather_type
    timestamp::DateTime
    city::String
    temp::Float32
    app_temp::Float32
    pressure::Int16
    wind_speed::Float32
    wind_deg::Int16
end

struct city_type
    city::String
end

function is_valid_city(city::String)::Bool
    url_string = API_COORDINATES_URL * "q=$(city)&limit=1&" * API_WEATHER_KEY
    try
        response = http_request(
            "GET", 
            url_string;
            headers = Pair{String, String}[
                "Accept" => "application/json",  
                "User-Agent" => "WeatherApp/1.0"
            ],
            read_timeout = 5,
            connect_timeout = 10,
            retry = 10
        )
        arr = JSON.parse(String(http_body(response)))
        return isa(arr, Vector) && length(arr) > 0 && isa(arr[1], Dict) && haskey(arr[1], "lat") && haskey(arr[1], "lon")
    catch e
        return false
    end
end

function get_coordinates_by_city_name(city::String)
    url_string = API_COORDINATES_URL * "q=$(city)&limit=1&" * API_WEATHER_KEY
    @info "url: $(url_string)"
    response = http_request(
        "GET", 
        url_string;
        headers = Pair{String, String}[
            "Accept" => "application/json",  
            "User-Agent" => "WeatherApp/1.0"
        ],
        read_timeout = 5,
        connect_timeout = 10,
        retry = 10
    )
    return JSON.parse(String(http_body(response)))[1]
end

function get_weather_from_api(parameters::Dict{String, String}) 

    if haskey(parameters, "city")
        parameters = get_coordinates_by_city_name(parameters["city"])
    end


    url_string = API_WEATHER_URL * "lat=$(parameters["lat"])&lon=$(parameters["lon"])&"  * API_WEATHER_KEY * "&units=metric"

    @info "url: $(url_string)"

    response = http_request(
        "GET",
        url_string;
        headers = Pair{String, String}[
            "Accept" => "application/json",  
            "User-Agent" => "WeatherApp/1.0"
        ],
        read_timeout = 5,
        connect_timeout = 10,
        retry = 10
    )

    return JSON.parse(String(http_body(response)))
end



function get_weather_responses(cities)
    responses = Vector{weather_type}()

    # for city in cities
    #     data = get_weather_from_api(Dict("city" => city))

    #     response = weather_type(
    #         Second(data["dt"]) + DateTime(1970, 1, 1),
    #         city,
    #         data["main"]["temp"],
    #         data["main"]["feels_like"],
    #         data["main"]["pressure"],
    #         data["wind"]["speed"],
    #         data["wind"]["deg"]
    #     )

    #     push!(responses, response)
    # end

    cities_vector = collect(cities)
    tasks = [@spawn get_weather_from_api(Dict("city" => city)) for city in cities_vector]
    
    for (i, task) in enumerate(tasks)
        try
            data = fetch(task)
            response = weather_type(
                Second(data["dt"]) + DateTime(1970, 1, 1),
                cities_vector[i],
                data["main"]["temp"],
                data["main"]["feels_like"],
                data["main"]["pressure"],
                data["wind"]["speed"],
                data["wind"]["deg"]
            )
            push!(responses, response)
        catch e
            @error "Failed to get weather for city $(cities_vector[i]): $(string(e))"
        end
    end

    return responses
end


function WriteDataToTable()
    @info "start write data"
    
    # responses = get_weather_responses(CITIES)
    # @info "data is ready"
    # if !isempty(responses)
    #     OhMyCH.insert(
    #         client[],
    #         "INSERT INTO weather_metrics (timestamp, city, temp, app_temp, pressure, wind_speed, wind_deg)",
    #         responses
    #     )
    # end
    # @info "data is written"

    # Новый асинхронный код
    data_task = @spawn get_weather_responses(CITIES)
    
    responses = try
        fetch(data_task)
        @info "data is ready"
    catch e
        @error "Failed to get weather data: $(string(e))"
        throw(e)
    end

    if !isempty(responses)
        @async begin
            try
                OhMyCH.insert(
                    client[],
                    "INSERT INTO weather_metrics (timestamp, city, temp, app_temp, pressure, wind_speed, wind_deg)",
                    responses
                )
                @info "data is written"
            catch e
                @error "Failed to write data to ClickHouse: $(string(e))"
                throw(e)
            end
        end
    end
end

function add_cities(cities::Vector{String})
    # new_cities = Vector{String}()
    # new_cities_structure = Vector{city_type}()
    # for city in cities
    #     if !in(city, CITIES)
    #         push!(new_cities, city)
    #         push!(new_cities_structure, city_type(city))
    #     end 
    # end
    # union!(CITIES, new_cities)
    # OhMyCH.insert(
    #     client[],
    #     "INSERT INTO cities (city)",
    #     new_cities_structure
    # )
    # @info "cities are added"
    # @info "Added cities: $new_cities. Total: $(length(CITIES))"
    # return HTTP.Response(200, "Cities updated successfully\n")

    @async begin
        try
            new_cities = Vector{String}()
            new_cities_structure = Vector{city_type}()

            for city in cities
                if !in(city, CITIES)
                    push!(new_cities, city)
                    push!(new_cities_structure, city_type(city))
                end 
            end

            if !isempty(new_cities)
                union!(CITIES, new_cities)

                OhMyCH.insert(
                    client[],
                    "INSERT INTO cities (city)",
                    new_cities_structure
                )

                @info "cities are added"
                @info "Added cities: $new_cities. Total: $(length(CITIES))"
            end
        catch e
            @error "Failed to add cities: $(string(e))"
            throw(e)
        end

        @info "cities are added"
    end
    
    return HTTP.Response(200, "Cities updated successfully")    
end


function start_periodic_task(interval_seconds)
    @info "start_periodic_task"
    @async begin
        while true
            WriteDataToTable()
            sleep(interval_seconds)
        end
    end
end


function init_clickhouse_db()
    host     = get(ENV, "CLICKHOUSE_HOST",     "localhost")
    port     = parse(Int, get(ENV, "CLICKHOUSE_PORT", "8123"))
    user     = get(ENV, "CLICKHOUSE_USER",     "default")
    password = get(ENV, "CLICKHOUSE_PASSWORD", "")
    dbname   = get(ENV, "CLICKHOUSE_DB",       "default")
    
    base_url = "http://$(host):$(port)/"

    @info "Connecting to ClickHouse" host=host port=port user=user db=dbname
    
    client[] = ohmych_connect(
        base_url,
        dbname,
        user,
        password
    )

    @info "connection to ClickHouse is ok: $(client)"

    OhMyCH.execute(client[],
        """
        CREATE TABLE IF NOT EXISTS weather_metrics ( 
            timestamp Datetime, 
            city String,
            temp Float32,
            app_temp Float32,
            pressure Int16,
            wind_speed Float32,
            wind_deg Int16
        ) ENGINE = MergeTree()
        PARTITION BY toYYYYMM(timestamp)
        ORDER BY timestamp
        """
    )

    OhMyCH.execute(client[],
        """
        CREATE TABLE IF NOT EXISTS cities (
            city String
        ) ENGINE = MergeTree()
        ORDER BY city
        """
    )

    data = OhMyCH.query(
        client[], 
        "SELECT city FROM cities"
    )

    for item in collect(data)
        push!(CITIES, item.city)
    end

end



end

# TABLE weather_metrics
# CREATE TABLE IF NOT EXISTS weather_metrics ( 
#     timestamp Datetime, 
#     city String,
#     temp Float32,
#     app_temp Float32,
#     pressure Int16,
#     wind_speed Float32,
#     wind_deg Int16
# ) ENGINE = MergeTree()
# PARTITION BY toYYYYMM(timestamp)
# ORDER BY timestamp


# TABLE cities
# CREATE TABLE IF NOT EXISTS cities (
#     city String
# )
# ENGINE = MergeTree()
# ORDER BY city