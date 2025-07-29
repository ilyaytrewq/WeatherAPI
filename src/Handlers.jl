module Handlers

using ..UserInterface
using HTTP 

function request_handler(req::HTTP.Request)
    path = req.target

    if path == "/v1.0.0/create_user"
        if req.method == "POST"
            return UserInterface.create_user(req)
        else
            return HTTP.Response(405, "Method Not Allowed")
        end
    elseif path == "/v1.0.0/change_user_data"
        if !(req.method == "GET")
            return UserInterface.change_user_data(req)
        else
            return HTTP.Response(405, "Method Not Allowed")
        end
    elseif path == "/v1.0.0/delete_user"
        if !(req.method == "GET")
            return UserInterface.delete_user(req)
        else
            return HTTP.Response(405, "Method Not Allowed")
        end
    elseif startswith(path, "/v1.0.0/get_user_data/email=")
        if req.method == "GET"
            return UserInterface.get_user_data(req)
        else
            return HTTP.Response(405, "Method Not Allowed")
        end
    else
        return HTTP.Response(404, "Unknown command")
    end
end



end