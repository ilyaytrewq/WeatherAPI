module UserInterface

using SHA
using Serde
using LibPQ
using HTTP
using Tables

const connection = Ref{LibPQ.Connection}()

struct UserData
    email::String
    password::String
    telegram::String
    ways_to_send::String
    cities::Vector{String}
end

function init_postgres_db()
    host     = get(ENV, "POSTGRES_HOST",     "localhost")
    port     = parse(Int, get(ENV, "POSTGRES_PORT", "5432"))
    user     = get(ENV, "POSTGRES_USER",     "postgres")
    password = get(ENV, "POSTGRES_PASSWORD", "")
    dbname   = get(ENV, "POSTGRES_NAME",     "postgres")

    connection[] = LibPQ.Connection("""
        host=$host
        user=$user
        password=$password
        dbname=$dbname
        port=$port
    """)

    LibPQ.execute(connection[], """
        CREATE TABLE IF NOT EXISTS users (
            email VARCHAR(255) NOT NULL UNIQUE,
            password VARCHAR(255) NOT NULL,
            telegram VARCHAR(20) DEFAULT NULL,
            ways_to_send VARCHAR(10) NOT NULL.
            cities TEXT[] DEFAULT '{}'
        );
        """)
end

function deser_with_exception(::Type{T}, req::HTTP.Request)::T where {T<:AbstractDict, T<:UserData}
    try
        new_user = deser_json(typeof(T), String(req.body))
    catch e
        @error "JSON parse error: $e"
        return HTTP.Response(400, "Incorrect data format $e")
    end
    return new_user
end

function create_user(req::HTTP.Request)
    
    new_user = deser_with_exception(UserData, req) #get UserData from http request
    new_user.password = bytes2hex(sha256(new_user.password)) #hash password

    @info "creating new user: $(new_user.email)"
    
    try    #insert user in db
        LibPQ.execute(
            connection[],
            "INSERT INTO users(email, password, telegram, ways_to_send, cities) VALUES (\$1, \$2, \$3, \$4, \$5)",
            (new_user.email, new_user.password, new_user.telegram, new_user.ways_to_send, new_user.cities)
        )
    catch e 
        @error "Database insert error: $e"
        
        if occursin("duplicate key value violates unique constraint", String(e))
            return HTTP.Response(409, "User with this email already exists")
        else
            return HTTP.Response(500, "Internal server error")
        end

    end
    @info "user created"

    return HTTP.Response(201, "user created")
end

function change_user_data(req::HTTP.Request)
    data = deser_with_exception(Dict{String, Any}, req)
    if !haskey(data, "email") || !haskey(data, "password")
        return HTTP.Response(400, "Missing required fields: email or password")
    end

    user_email = data["email"]
    delete!(data, "email")

    @info "change user's data: $user_email"

    data["password"] = bytes2hex(sha256(data["password"]))

    # create sql query
    keys = Vector{String}()
    values = Vector{String}()

    #add data in format (value, key = index of value)
    for (k, v) in data
        push!(values, v)
        push!(keys, "$k = \$$(length(values))")
    end

    push!(values, user_email)
    query = "UPDATE users SET $(join(keys, ", ")) WHERE email = \$$(length(values))"

    try 
        LibPQ.execute(
            connection[],
            query,
            values
        )
    catch e 
        msg = String(e)

        if occursin("column", msg) && occursin("does not exist", msg)
            @error "Invalid column name in update data: $msg"
            return HTTP.Response(400, "Invalid column name in request data")
        else
            @error "Failed to update user data: $msg"
            return HTTP.Response(500, "Internal server error")
        end
    end
    @info "user data updated"

    return HTTP.Response(200, "Data updated successfully")
end


function delete_user(req::HTTP.Request)
    data = deser_with_exception(Dict{String, String}, req)
    if !haskey(data, "email")
        return HTTP.Response(400, "Missing required fields")
    end

    try
        LibPQ.execute(
            connection[],
            "DELETE FROM users where email = \$1",
            [data["email"]]
        )
    catch e
        @error "Database delete error: $e"
        return HTTP.Response(500, "Internal server error")
    end

    @info "user deleted successfully"

    return HTTP.Response(200, "User deleted successfully")
end

function get_user_data(req::HTTP.Request)
    user_email = split(req.target, "get_user_data/email=")[2]

    @info "get user data with email: $user_email"

    try
        result = LibPQ.execute(
            connection[],
            "SELECT email, telegram, ways_to_send, cities FROM users WHERE email = \$1",
            [user_email]
        )

        if LibPQ.num_rows(result) == 0
            return HTTP.Response(404, "User not found")
        end
    catch e
        @error "Database select error: $e"
        return HTTP.Response(500, "Internal server error")
    end

    rows = Tables.rowtable(result)
    user_data = first(rows)


    data_dict = Dict(string(k) => v for (k, v) in pairs(user_data))

    response = to_json(data_dict)

    return HTTP.Response(200, ["Content-Type" => "application/json"], response)
end


end