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
                "User-Agent" => "WeatherAPI/1.0"
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
    response = try
         http_request(
            "GET", 
            url_string;
            headers = Pair{String, String}[
                "Accept" => "application/json",  
                "User-Agent" => "WeatherAPI/1.0"
            ],
            read_timeout = 5,
            connect_timeout = 10,
            retry = 10
        )
    catch e 
        @error "Failed to get coordinates for city: $city, error: $(string(e))"
        throw(e)
    end
    return JSON.parse(String(http_body(response)))[1]
end

function get_weather_from_api(parameters::Dict{String, String}) 

    if haskey(parameters, "city")
        try
            parameters = get_coordinates_by_city_name(parameters["city"])
        catch e
            @error "Failed to get coordinates for city $(parameters["city"]): $(string(e))"
            throw(e)
        end
    end


    url_string = API_WEATHER_URL * "lat=$(parameters["lat"])&lon=$(parameters["lon"])&"  * API_WEATHER_KEY * "&units=metric"

    @info "url: $(url_string)"

    response = try
         http_request(
            "GET",
            url_string * API_WEATHER_KEY;
            headers = Pair{String, String}[
                "Accept" => "application/json",  
                "User-Agent" => "WeatherAPI/1.0"
            ],
            read_timeout = 5,
            connect_timeout = 10,
            retry = 10
        )
    catch e 
        @error "Failed to get weather for parameters: $parameters, error: $(string(e))"
        throw(e)
    end

    return JSON.parse(String(http_body(response)))
end



function get_weather_responses(cities)
    responses = Vector{weather_type}()

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
            if e isa TaskFailedException
                @error "Task failed with exception: $(e.task.exception)"
            end
        end
    end

    return responses
end


function WriteDataToTable()
    @info "start write data"
    data_task = @spawn get_weather_responses(CITIES)
    
    responses = fetch(data_task)

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

            union!(CITIES, new_cities)

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
    
    try
        client[] = ohmych_connect(
            base_url,
            dbname,
            user,
            password
        )
        @info "connection to ClickHouse is ok: $(client)"
    catch e
        @error "Failed to connect to ClickHouse: $(string(e))"
        throw(e)
    end

    try
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
        @info "weather_metrics table created/verified"
    catch e
        @error "Failed to create weather_metrics table: $(string(e))"
        throw(e)
    end

    try
        OhMyCH.execute(client[],
            """
            CREATE TABLE IF NOT EXISTS cities (
                city String
            ) ENGINE = MergeTree()
            ORDER BY city
            """
        )
        @info "cities table created/verified"
    catch e
        @error "Failed to create cities table: $(string(e))"
        throw(e)
    end

    try
        data = OhMyCH.query(
            client[], 
            "SELECT city FROM cities"
        )

        for item in collect(data)
            push!(CITIES, item.city)
        end
        @info "Loaded $(length(CITIES)) cities from database"
    catch e
        @error "Failed to load cities from database: $(string(e))"
        throw(e)
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