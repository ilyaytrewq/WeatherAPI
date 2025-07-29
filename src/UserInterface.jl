module UserInterface 

using Serde
using LibPQ
using HTTP

const connection = Ref{LibPQ.Connection}()

struct user
    email::String
    password::String
    telegram::String
    ways_to_send::String
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

    @info "connection to Postgres is ok: $(connection)"

    LibPQ.execute(connection[], """
        CREATE TABLE IF NOT EXISTS users (
            email VARCHAR(255) NOT NULL UNIQUE,
            password VARCHAR(255) NOT NULL,
            telegram VARCHAR(20) DEFAULT NULL,
            ways_to_send VARCHAR(10) NOT NULL
        );
    """)
end

function create_user(req::HTTP.Request)
    new_user = deser_json(user, String(req.body))

    @info "creating new user: $new_user"
    
    LibPQ.execute(
        connection[],
        "INSERT INTO users(email, password, telegram, ways_to_send) VALUES (\$1, \$2, \$3, \$4)",
        (new_user.email, new_user.password, new_user.telegram, new_user.ways_to_send)
    )
    
    @info "user created"

    return HTTP.Response(201, "user created")
end

function change_user_data(req::HTTP.Request)
    data = deser_json(Dict{String, String}, String(req.body))
    if !haskey(data, "email") || !haskey(data, "password")
        return HTTP.Response(400, "Missing required fields")
    end

    user_email = data["email"]
    delete!(data, "email")

    @info "change user's data: $user_email"

    keys = Vector{String}()
    values = Vector{String}()

    for (k, v) in data
        push!(values, v)
        push!(keys, "$k = \$$(length(values))")
    end

    push!(values, user_email)
    query = "UPDATE users SET $(join(keys, ", ")) WHERE email = \$$(length(values))"

    LibPQ.execute(
        connection[],
        query,
        values
    )

    @info "user data updated"

    return HTTP.Response(200, "Data updated successfully")
end


function delete_user(req::HTTP.Request)
    data = deser_json(Dict{String, String}, String(req.body))
    if !haskey(data, "email")
        return HTTP.Response(400, "Missing required fields")
    end

    LibPQ.execute(
        connection[],
        "DELETE FROM users where email = \$1",
        [data["email"]]
    )

    @info "user deleted successfully"

    return HTTP.Response(200, "User deleted successfully")
end

function get_user_data(req::HTTP.Request)
    user_email = split(req.target, "get_user_data/email=")[2]

    @info "user_email: $user_email"

    result = LibPQ.execute(
        connection[],
        "SELECT email, telegram, ways_to_send FROM users WHERE email = \$1",
        [user_email]
    )

    if LibPQ.num_rows(result) == 0
        return HTTP.Response(404, "User not found")
    end

    rows = Tables.rowtable(result)
    user_data = first(rows)


    data_dict = Dict(string(k) => v for (k, v) in pairs(user_data))

    response = to_json(data_dict)

    return HTTP.Response(200, ["Content-Type" => "application/json"], response)
end


end