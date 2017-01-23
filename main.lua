local InputContainer = require("ui/widget/container/inputcontainer")
local DocSettings = require("docsettings")
local FileManager = require("apps/filemanager/filemanager")
local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local WallabagApi = require("wallabagapi")
local NetworkMgr = require("ui/network/manager")
local md5 = require("ffi/MD5")
local dump = require("dump")
local lfs = require("libs/libkoreader-lfs")
local json = require("json")
local http = require("socket.http")
local https = require("ssl.https")
local util = require("util")
local _ = require("gettext")

local Wallabag = InputContainer:new {
    client_id = "",
    client_secret = "",
    walla_url = "",
    walla_username = "",
    walla_password = "",
    fetch_amount = "",
}

function Wallabag:init()
    local walla_sett = Wallabag:readWallaSettings().data
    if walla_sett.wallabag then
        self.walla_url = walla_sett.wallabag.url
        self.walla_username = walla_sett.wallabag.username
        self.walla_password = walla_sett.wallabag.password
        self.client_id = walla_sett.wallabag.id
        self.client_secret = walla_sett.wallabag.secret
        self.fetch_amount = walla_sett.wallabag.amount
    end
	walla_dir = DataStorage:getDataDir().."/plugins/wallabag.koplugin/wallabag/"
	walla_image_dir = DataStorage:getDataDir().."/plugins/wallabag.koplugin/.images/"
    Wallabag:createDBDir()
    self.ui.menu:registerToMainMenu(self)
end

function Wallabag:buildImageCache()
    imageCache = {}
    for file in lfs.dir(walla_image_dir) do
        if lfs.attributes(walla_image_dir..file, "mode") == "file" then
            table.insert(imageCache, file)
        end
    end
    return imageCache
end

function Wallabag:createDBDir()
	lfs.mkdir(walla_dir)
	lfs.mkdir(walla_image_dir)
    lfs.mkdir(walla_dir.."archived")
    lfs.mkdir(walla_dir.."favorites")
end

function Wallabag:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins, {
        text = _("Wallabag"),
        sub_item_table = {
            {
                text = _("Settings"),
                callback = function() self:updateSettings() end,
            },
            {
                text = _("Sync"),
                callback = function()
                    if self.client_id ~= "" then
                        if NetworkMgr:isOnline() then
                            self.sync()
                        else
                            NetworkMgr:promptWifiOn()
                        end
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("Please set up your Wallabag \"Client ID\" and login info first"),
                        })
                    end
                end
            },
			{
				text = _("Article List"),
				callback = function()
					FileManager:showFiles(walla_dir)
				end,
			},
        },
    })
end

function Wallabag:updateSettings()
    local hint_client_id
    local text_client_id
    local hint_client_secret
    local text_client_secret
    local hint_walla_url
    local text_walla_url
    local hint_walla_username
    local text_walla_username
    local hint_walla_password
    local text_walla_password
    local text_fetch_amount
    local hint_fetch_amount
    local text_info = "You must generate \"client_id\" and \"client_secret\""..
		" keys in Wallabag's developer options. Paste them here, along with the Wallabag url and your login information."
    if self.walla_url == "" then
        hint_walla_url = _("Wallabag Url Not Set")
        text_walla_url = ""
    else
        hint_walla_url = ""
        text_walla_url = self.walla_url
    end
    if self.walla_username == "" then
        hint_walla_username = _("Wallabag Username Not Set")
        text_walla_username = ""
    else
        hint_walla_username = ""
        text_walla_username = self.walla_username
    end
    if self.walla_password == "" then
        hint_walla_password = _("Wallabag Password Not Set")
        text_walla_password = ""
    else
        hint_walla_password = ""
        text_walla_password = self.walla_password
    end
    if self.client_id == "" then
        hint_client_id = _("Client_ID Key Not Set")
        text_client_id = ""
    else
        hint_client_id = ""
        text_client_id = self.client_id
    end
    if self.client_secret == "" then
        hint_client_secret = _("Client Secret Key Not Set")
        text_client_secret = ""
    else
        hint_client_secret = ""
        text_client_secret = self.client_secret
    end
    if self.fetch_amount == "" then
        hint_fetch_amount = _("Number of articles to fetch")
        text_fetch_amount = ""
    else
        hint_fetch_amount = ""
        text_fetch_amount = self.fetch_amount
    end
    self.settings_dialog = MultiInputDialog:new {
        title = _("Login to Wallabag"),
        fields = {
            {
                text = text_walla_url,
                input_type = "string",
                hint = hint_walla_url,
            },
            {
                text = text_walla_username,
                input_type = "string",
                hint = hint_walla_username,
            },
            {
                text = text_walla_password,
                input_type = "string",
                hint = hint_walla_password,
            },
            {
                text = text_client_id,
                input_type = "string",
                hint = hint_client_id,
            },
            {
                text = text_client_secret,
                input_type = "string",
                hint = hint_client_secret,
            },
            {
                text = text_fetch_amount,
                input_type = "number",
                hint = hint_fetch_amount,
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)
                    end
                },
                {
                    text = _("Info"),
                    callback = function()
                        UIManager:show(InfoMessage:new{text = text_info })
                    end
                },
                {
                    text = _("Apply"),
                    callback = function()
                        self:saveSettings(MultiInputDialog:getFields())
                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)
                    end
                },
            },
        },
    }
    self.settings_dialog:onShowKeyboard()
    UIManager:show(self.settings_dialog)
end

function Wallabag:saveSettings(fields)
    if fields then
        self.walla_url = fields[1]
        self.walla_username = fields[2]
        self.walla_password = fields[3]
        self.client_id = fields[4]
        self.client_secret = fields[5]
        self.fetch_amount = fields[6]
    end
    local settings = {
        url = self.walla_url,
        username = self.walla_username,
        password = self.walla_password,
        id = self.client_id,
        secret = self.client_secret,
        amount = self.fetch_amount,
    }
    Wallabag:saveWallaSettings(settings)
end

function Wallabag:saveWallaSettings(setting)
    if not walla_settings then walla_settings=Wallabag:readWallaSettings() end
    walla_settings:saveSetting("wallabag", setting)
    walla_settings:flush()
end

function Wallabag:readWallaSettings()
    return LuaSettings:open(DataStorage:getSettingsDir().."/wallabag.lua")
end

function Wallabag:getToken()
    local settings = Wallabag:readWallaSettings().data.wallabag
    body, code, headers, result = http.request(settings.url ..
        "/oauth/v2/token?grant_type=password&client_id=" .. settings.id ..
        "&client_secret=" .. settings.secret ..
        "&username=" .. settings.username ..
        "&password=" .. settings.password)
    if code ~= 200 then print("There was an error getting the authentication token from the server") end
    walla_token = json.decode(body).access_token
    return walla_token
end

function Wallabag:getDB(location)
    if location == "remote" then
        local settings = Wallabag:readWallaSettings().data.wallabag
        local walla_url = settings.url
        local fetch_amount = settings.amount
        ok, walla_db = WallabagApi:fetchAll(walla_url, Wallabag:getToken(), fetch_amount)
        -- if not ok then
        --     walla_db = {}
        -- end
    elseif location == "local" then
        ok, walla_db = pcall(dofile, walla_dir..".walladb.lua")
        if not ok then
            print("couldn't get local db: "..walla_db)
            walla_db = {}
        end
    end
    return walla_db
end

function Wallabag:saveDB(data)
    wallaDB = io.open(walla_dir..".walladb.lua", "w+")
    wallaDB:write("return ")
    wallaDB:write(dump(data))
    wallaDB:close()
end

function Wallabag:buildLocalDB(remoteDB)
    local localDB = {}

	local num_articles = util.tableSize(remoteDB._embedded.items)
	for index, remote_article in pairs(remoteDB._embedded.items) do

        local article_url = remote_article.url
        local article_id = remote_article.id
        local article_content = remote_article.content
        local article_title = remote_article.title

		article_title = string.gsub(article_title, "[^%w%s]", " ")
		article_title = article_title:gsub("%s+", " ")
		article_title = article_title:gsub("^%s", "")
		article_title = article_title:gsub("%s$", "")

        local remote_status = {}
        if remote_article.is_starred == 1 and remote_article.is_archived == 1 then
            remote_status["rating"] = 5
            remote_status["status"] = "complete"
            article_filename = walla_dir.."favorites/"..article_id.."-"..article_title..".html"
        elseif remote_article.is_starred == 0 and remote_article.is_archived == 1 then
            remote_status["rating"] = 0
            remote_status["status"] = "complete"
            article_filename = walla_dir.."archived/"..article_id.."-"..article_title..".html"
        else
            remote_status["rating"] = 0
            remote_status["status"] = "reading"
            article_filename = walla_dir..article_id.."-"..article_title..".html"
        end
		-- print("filename: "..article_filename)

		article_content = Wallabag:downloadImages(article_content, article_id, index, num_articles)

		local contentFile = io.open(article_filename, "w")
		contentFile:write("<h1 style=\"text-align:center;\">"..article_title.."</h1>\n"..
			"<h2 style=\"font-size:70%;text-align:center;\">"..article_url.."</h2>\n"..
			article_content)
		contentFile:close()

        localDB[article_id] = {
            ["title"] = article_title,
            ["url"] = article_url,
            ["filename"] = article_filename,
            ["content"] = article_content,
        }
        local article_settings = DocSettings:open(article_filename)
        article_settings:saveSetting("summary", remote_status)
        article_settings:close()
    end
    Wallabag:saveDB(localDB)
end

function Wallabag:CompareTimes(remoteDB_time, localDB_time)
    print(remoteDB_time)
    -- Adapted from http://stackoverflow.com/a/4600967
    local date_pattern="(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)+%d+"
    local year, month, day, hour, min, sec = remoteDB_time:match(date_pattern)
    local offset = os.time()-os.time(os.date("!*t"))
    remoteDB_time = os.time({day=day,month=month,year=year,hour=hour,min=min,sec=sec})+offset

    date_pattern="(%d+)-(%d+)-(%d+)"
    year, month, day = localDB_time:match(date_pattern)
    -- Koreader only stores date modified, not time, so make the last modified time
    --  the end of the modified day to make changes in koreader take precedence over Wallabag
    localDB_time = os.time({day=day,month=month,year=year,hour="23",min="59",sec="59"})

    print("offset: "..offset)
    print("remote_time "..os.date("!%c", remoteDB_time)..",  local time "..os.date("!%c", localDB_time))
    time_difference = localDB_time - remoteDB_time
    print("time difference: "..time_difference)

    if time_difference > 0 then
        return "local"
    else
        return "remote"
    end
end

function Wallabag:sync()
    -- delete local db and files
    -- fetch new data
    local token = Wallabag:getToken()
    local settings = Wallabag:readWallaSettings().data.wallabag
    local walla_url = settings.url

    local localDB = Wallabag:getDB("local")

    walla_image_matched = {}
    walla_image_cache = Wallabag:buildImageCache()

    syncInfoMsg = InfoMessage:new{text = _("Syncing...")}
    UIManager:show(syncInfoMsg)
    UIManager:forceRePaint()

    for index, local_article in pairs(localDB) do
        local article_id = index
        local article_filename = local_article.filename

        article_settings = DocSettings:open(article_filename)
        article_summary = article_settings:readSetting("summary")
        if not article_summary or not article_summary.modified or article_summary == "" then
            -- No changes have been made, don't attempt to propagate
        else
            local_article.updated_at = article_summary.modified

            local remote_article = WallabagApi:getEntry(walla_url, token, article_id)
            
            local newer = ""

            if remote_article.updated_at then --do better checking of remote article return here
                newer = Wallabag:CompareTimes(remote_article.updated_at, local_article.updated_at)
            else
                newer = "remote article has been deleted"
            end

            print("newer: "..newer)
            if newer == "local" then
                print(article_summary.rating and "rating: "..article_summary.rating or "rating: none")
                print(article_summary.status and "status: "..article_summary.status or "status: none")
                local newStatus = {}
                if article_summary.status == "abandoned" then
                    WallabagApi:deleteEntry(walla_url, token, article_id)
                    print("TO REMOVE: "..article_filename.."\n")
                else
                    if article_summary.rating == 5 then
                        newStatus["starred"]="1"
                    else
                        newStatus["starred"]="0"
                    end
                    if article_summary.status == "complete" then
                        newStatus["archive"]="1"
                    else
                        newStatus["archive"]="0"
                    end
                    WallabagApi:modifyEntry(walla_url, token, article_id, newStatus)
                end
            end
        end
    end
    os.execute('rm -rd "'..walla_dir..'"')

    local remoteDB = Wallabag:getDB("remote")
    Wallabag:createDBDir()
    Wallabag:buildLocalDB(remoteDB)
    if syncInfoMsg then UIManager:close(syncInfoMsg) end
    for i,filename in pairs(walla_image_cache) do
        print("removing: "..i,filename)
        os.execute('rm -vf "'..walla_image_dir..filename..'"')
    end
    os.execute("cp -v "..DataStorage:getDataDir().."/plugins/wallabag.koplugin/".."blank.jpg "..walla_image_dir..md5.sum("blank")..".jpg")
    FileManager:showFiles(walla_dir)
end

function Wallabag:downloadImages(articleContent, articleId, index, num_articles)
	local images = {}
	local counter = 0
	local prevIndexEnd = 1
	local newArticleContent = ""
	local imageFilename = ""
	local imageIndices = articleContent:gmatch("<img.-src=\"().-()\"")

	for indexStart, indexEnd in imageIndices do
		counter = counter + 1
		imageLink = articleContent:sub(indexStart, indexEnd-1)
		newArticleContent = newArticleContent..articleContent:sub(prevIndexEnd, indexStart-1)
        imageFilename = Wallabag:downloadFile(imageLink, index, num_articles)
		newArticleContent = newArticleContent.."../.images/"..imageFilename
		prevIndexEnd = indexEnd
	end
	newArticleContent = newArticleContent..articleContent:sub(prevIndexEnd)
	return newArticleContent
end

function Wallabag:downloadFile(url, index, num_articles)
    -- print("url: "..url)
    local imageFilename = md5.sum(url)
    for key, filename in pairs(walla_image_cache) do
        if filename:match(imageFilename) then
            table.insert(walla_image_matched, filename)
            table.remove(walla_image_cache, key)
            print("matched "..filename)
            return filename
        end
    end
    for key, filename in pairs(walla_image_matched) do
        if filename:match(imageFilename) then
            print("matched "..filename)
            return filename
        end
    end
    if url:match("^https.*") then
        content, status, header = https.request(url)
    else
        content, status, header = http.request(url)
    end
    if status == 200 then
        if header["content-type"] then
            if header["content-type"]:match("image/(.*);.*$") then
                imageExt = header["content-type"]:match("image/(.*);.*$")
            elseif header["content-type"]:match("image/(.*)$") then
                imageExt = header["content-type"]:match("image/(.*)$")
            else
                print(header["content-type"])
                imageExt = "unknown"
            end

            imageFilename = imageFilename.."."..imageExt

            if syncInfoMsg then
                UIManager:close(syncInfoMsg)
                syncInfoMsg = nil
            end
            local dlInfoMsg = InfoMessage:new{text = _("Downloading images:\n Article "..index.." of "..num_articles..".")}
            UIManager:show(dlInfoMsg)
            UIManager:forceRePaint()
            UIManager:close(dlInfoMsg)

            local imageFile = io.open(walla_image_dir..imageFilename, "w")
            imageFile:write(content)
            imageFile:close()
            table.insert(walla_image_matched, imageFilename)
            return imageFilename
        end
    else
        os.execute("cp -v "..DataStorage:getDataDir().."/plugins/wallabag.koplugin/".."blank.jpg "..walla_image_dir..imageFilename..".jpg")
        return imageFilename..".jpg"
    end
end

return Wallabag
