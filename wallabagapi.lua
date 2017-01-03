local json = require("json")
local http = require("socket.http")
local https = require("ssl.https")
local _ = require("gettext")

local WallabagApi = {
}

function WallabagApi:init()
end

function WallabagApi:fetchAll(url, token, numArticles)
    body, code, headers, result = http.request(url .. "/api/entries.json?access_token=" .. token.."&perPage="..numArticles)
    return ok, json.decode(body)
end

function WallabagApi:modifyEntry(url, token, articleId, newStatus)
    local body = ""
    url = url.."/api/entries/"..articleId..".json"
    for k,v in pairs(newStatus)
        do body = body.."&"..k.."="..v
    end
    print("BODY= "..body)
    resp_body = WallabagApi:buildRequest("PATCH", url, token, body)
    print(json.decode(resp_body).is_starred.."\tISSTARRED")
end

function WallabagApi:deleteEntry(url, token, articleId)
    url = url.."/api/entries/"..articleId..".json"
    WallabagApi:buildRequest("DELETE", url, token)
end

function WallabagApi:getEntry(url, token, articleId)
    url = url.."/api/entries/"..articleId..".json"
    local entry_data = WallabagApi:buildRequest("GET", url, token)
    return json.decode(entry_data)
end

function WallabagApi:buildRequest(req_method, req_url, token, req_body)
    local resp_body = {}
    local req_headers = {
        ["Authorization"] = "Bearer "..token,
        ["Content-Type"]="application/x-www-form-urlencoded"
    }
    if req_body then
        req_headers["content-length"]=req_body:len()
    else
        req_body = ""
    end
    b, c, h, r = http.request{
        method = req_method,
        url = req_url,
        headers = req_headers,
        source = ltn12.source.string(req_body),
        sink = ltn12.sink.table(resp_body)
    }
    if c ~= 200 then print("There was an error sending the request to the server") end
    return(table.concat(resp_body))
end


return WallabagApi
