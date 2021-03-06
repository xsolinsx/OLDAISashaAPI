clr = require "term.colors"

last_cron = os.date('%M')
last_administrator_cron = os.date('%d')
last_redis_cron = ''
last_redis_administrator_cron = ''

tmp_msg = { }
news_table = {
    chats = { },
    spam = false,
    msg_to_update = nil,
    chat_msg_to_update = nil,
    counter = 0,
    tot_chats = 0,
    news = nil,
}
-- GLOBAL CRON TABLE
globalCronTable = {
    -- temp table to not restrict/kick/ban the same user again and again (just once per minute)
    -- kicks are tracked in the banUser and kickUser methods
    -- restrictions are tracked in the restrictUser method
    punishedTable =
    {
        -- chat_id = { user_id = false/true }
    },
    -- temp table to not invite the same user again and again (just once per minute or if (s)he is kicked)
    invitedTable =
    {
        -- chat_id = { user_id = false/true }
    },
    -- temp table to not keep answering "can't do this because of your privileges" to users
    executersTable =
    {
        -- chat_id = { user_id = false/true }
    }
}

-- Save the content of config to config.lua
function save_config()
    serialize_to_file(config, './config.lua', false)
    print(clr.white .. 'saved config into ./config.lua' .. clr.reset)
end

-- Returns the config from config.lua file.
-- If file doesn't exist, create it.
function load_config()
    local f = io.open('./config.lua', "r")
    -- If config.lua doesn't exist
    if not f then
        create_config()
        print(clr.white .. "Created new config file: config.lua" .. clr.reset)
    else
        f:close()
    end
    local config = loadfile("./config.lua")()
    for k, v in pairs(config.sudo_users) do
        print(clr.green .. "Sudo user: " .. k .. clr.reset)
    end
    return config
end

-- Create a basic config.lua file and saves it.
function create_config()
    -- A simple config with basic plugins and ourselves as privileged user
    local config = {
        bot_api_key = '',
        enabled_plugins =
        {
            'anti_spam',
            'alternatives',
            'msg_checks',
            'administrator',
            'banhammer',
            'bot',
            'check_tag',
            'database',
            'fakecommand',
            'feedback',
            'filemanager',
            'flame',
            'getsetunset',
            'goodbyewelcome',
            'group_management',
            'help',
            'info',
            'interact',
            'likecounter',
            'lua_exec',
            'me',
            'multiple_commands',
            'plugins',
            'stats',
            'strings',
            'tgcli_to_api_migration',
            'whitelist',
        },
        disabled_plugin_on_chat = { },
        sudo_users = { ["41400331"] = 41400331, },
        alternatives = { db = 'data/alternatives.json' },
        moderation = { data = 'data/moderation.json' },
        likecounter = { db = 'data/likecounterdb.json' },
        database = { db = 'data/database.json' },
        rdb = { db = 'data/rdb.json' },
        about_text = "AISashaAPI by @EricSolinas based on @GroupButler_bot and @TeleSeed supergroup branch with something taken from @DBTeam.\nThanks guys.",
        log_chat = - 1001043389864,
        vardump_chat = - 167065200,
        channel = '@AISashaChannel',
        -- channel username with the '@'
        help_group = '',
        -- group link, not username!
    }
    serialize_to_file(config, './config.lua', false)
    print(clr.white .. 'saved config into ./config.lua' .. clr.reset)
end

-- Save the content of alternatives to alternatives.lua
function save_alternatives()
    serialize_to_file(alternatives, './alternatives.lua', false)
    print(clr.white .. 'saved alternatives into ./alternatives.lua' .. clr.reset)
end

-- Returns the alternatives from alternatives.lua file.
-- If file doesn't exist, create it.
function load_alternatives()
    local f = io.open('./alternatives.lua', "r")
    -- If alternatives.lua doesn't exist
    if not f then
        create_alternatives()
        print(clr.white .. "Created new alternatives file: alternatives.lua" .. clr.reset)
    else
        f:close()
    end
    local alternatives = loadfile("./alternatives.lua")()
    return alternatives
end

-- Create a basic alternatives.lua file and saves it.
function create_alternatives()
    local alternatives = {
        ['global'] =
        {
            cmdAlt =
            {
                ['/pmblock'] = { 'sasha blocca pm' },
                ['/pmunblock'] = { 'sasha sblocca pm' },
                ['/backup'] = { 'sasha esegui backup' },
                ['/gban'] =
                {
                    'sasha superbanna',
                    'superbanna'
                },
                ['/ungban'] =
                {
                    'sasha supersbanna',
                    'supersbanna'
                },
            },
            altCmd =
            {
                ['sasha blocca pm'] = '/pmblock',
                ['sasha sblocca pm'] = '/pmunblock',
                ['sasha esegui backup'] = '/backup',
                ['sasha superbanna'] = '/gban',
                ['superbanna'] = '/gban',
                ['sasha supersbanna'] = '/ungban',
                ['supersbanna'] = '/ungban',
            },
        },
    }
    serialize_to_file(alternatives, './alternatives.lua', false)
    print(clr.white .. 'saved alternatives into ./alternatives.lua' .. clr.reset)
end

-- Enable plugins in config.lua
function load_plugins()
    local index = 0
    for k, v in pairs(config.enabled_plugins) do
        index = index + 1
        print(clr.white .. "Loading plugin", v .. clr.reset)

        local ok, err = pcall( function()
            local t = loadfile("plugins/" .. v .. '.lua')()
            plugins[v] = t
        end )

        if not ok then
            print(clr.red .. 'Error loading plugin ' .. v .. clr.reset)
            print(tostring(clr.red .. io.popen("lua plugins/" .. v .. ".lua"):read('*all') .. clr.reset))
            print(clr.red .. err .. clr.reset)
        end
    end
    print(clr.white .. 'Plugins loaded: ', index .. clr.reset)
    return index
end

function reload_bot()
    print("Reloading bot")
    loadfile("./dictionaries.lua")()
    loadfile("./utils.lua")()
    loadfile("./methods.lua")()
    loadfile("./ranks.lua")()
    loadfile("./keyboards.lua")()
    loadfile("./libs/myRedis.lua")()
    langs = dofile('languages.lua')
    load_plugins()
    print("Bot reloaded")
end

function bot_init()
    config = { }
    bot = nil
    plugins = { }
    database = nil
    rdb = nil
    data = nil
    alternatives = { }

    loadfile("./dictionaries.lua")()
    loadfile("./utils.lua")()
    config = load_config()

    print(clr.white .. 'Loading rdb.json' .. clr.reset)
    rdb = load_data(config.rdb.db)

    alternatives = load_alternatives()
    local file_bot_api_key = io.open('bot_api_key.txt', "r")
    if file_bot_api_key then
        -- read all contents of file into a string
        config.bot_api_key = file_bot_api_key:read()
        file_bot_api_key:close()
    end
    if config.bot_api_key == '' then
        print(clr.red .. 'API KEY MISSING!' .. clr.reset)
        return
    end
    loadfile("./methods.lua")()
    loadfile("./ranks.lua")()
    loadfile("./keyboards.lua")()
    loadfile("./libs/myRedis.lua")()

    while not bot do
        -- Get bot info and retry if unable to connect.
        local obj = getMe()
        if obj then
            if obj.result then
                bot = obj.result
                bot.link = "t.me/" .. bot.username
            end
        end
    end
    local obj = getChat(149998353)
    if type(obj) == 'table' then
        bot.userVersion = obj
    end

    langs = dofile("languages.lua")

    local tot_plugins = load_plugins()
    print(clr.white .. 'Loading database.json' .. clr.reset)
    database = load_data(config.database.db)

    print(clr.white .. 'Loading moderation.json' .. clr.reset)
    data = load_data(config.moderation.data)

    for k, v in pairs(config.sudo_users) do
        local obj_user = getChat(k)
        if type(obj_user) == 'table' then
            config.sudo_users[tostring(k)] = obj_user
        end
    end

    print('\n' .. clr.green .. 'BOT RUNNING:\n@' .. bot.username .. '\n' .. bot.first_name .. '\n' .. bot.id .. clr.reset)
    redis_hincr('bot:general', 'starts', 1)
    sendMessage_SUDOERS(string.gsub(string.gsub(langs['en'].botStarted, 'Y', tot_plugins), 'X', os.date('On %A, %d %B %Y\nAt %X')), 'markdown')

    -- Generate a random seed and "pop" the first random number. :)
    math.randomseed(os.time())
    math.random()

    last_update = last_update or 0
    -- Set loop variables: Update offset,
    last_cron = last_cron or os.time()
    -- the time of the last cron job,
    is_started = true
    -- whether the bot should be running or not.
    start_time = os.date('%c')
end

function update_redis_cron()
    if redis:get('api:last_redis_cron') then
        if redis:get('api:last_redis_cron') ~= os.date('%M') then
            local value = os.date('%M')
            redis:set('api:last_redis_cron', value)
        end
        last_redis_cron = redis:get('api:last_redis_cron')
    else
        local value = os.date('%M')
        redis:set('api:last_redis_cron', value)
        last_redis_cron = redis:get('api:last_redis_cron')
    end

    if redis:get('api:last_redis_administrator_cron') then
        if redis:get('api:last_redis_administrator_cron') ~= os.date('%d') then
            local value = os.date('%d')
            redis:set('api:last_redis_administrator_cron', value)
        end
        last_redis_administrator_cron = redis:get('api:last_redis_administrator_cron')
    else
        local value = os.date('%d')
        redis:set('api:last_redis_administrator_cron', value)
        last_redis_administrator_cron = redis:get('api:last_redis_administrator_cron')
    end
end

function adjust_user(tab)
    if tab.is_bot then
        tab.type = 'bot'
    else
        tab.type = 'private'
    end
    tab.print_name = tab.first_name
    if tab.last_name then
        tab.print_name = tab.print_name .. ' ' .. tab.last_name
    end
    return tab
end

function adjust_group(tab)
    tab.type = 'group'
    tab.print_name = tab.title
    return tab
end

function adjust_supergroup(tab)
    tab.type = 'supergroup'
    tab.print_name = tab.title
    return tab
end

function adjust_channel(tab)
    tab.type = 'channel'
    tab.print_name = tab.title
    return tab
end

-- adjust message for cli plugins
-- recursive to simplify code
function adjust_msg(msg)
    -- sender print_name
    msg.from = adjust_user(msg.from)
    if msg.adder then
        msg.adder = adjust_user(msg.adder)
    end
    if msg.added then
        for k, v in pairs(msg.added) do
            msg.added[k] = adjust_user(v)
        end
    end
    if msg.remover then
        msg.remover = adjust_user(msg.remover)
    end
    if msg.removed then
        msg.removed = adjust_user(msg.removed)
    end
    if msg.entities then
        for k, v in pairs(msg.entities) do
            if msg.entities[k].user then
                adjust_user(msg.entities[k].user)
            end
        end
    end

    if msg.chat.type then
        if msg.chat.type == 'private' then
            -- private chat
            msg.bot = adjust_user(bot)
            msg.chat = adjust_user(msg.chat)
        elseif msg.chat.type == 'group' then
            -- group
            msg.chat = adjust_group(msg.chat)
        elseif msg.chat.type == 'supergroup' then
            -- supergroup
            msg.chat = adjust_supergroup(msg.chat)
        elseif msg.chat.type == 'channel' then
            -- channel
            msg.chat = adjust_channel(msg.chat)
        end
    end

    -- if forward adjust forward
    if msg.forward then
        if msg.forward_from then
            msg.forward_from = adjust_user(msg.forward_from)
        elseif msg.forward_from_chat then
            msg.forward_from_chat = adjust_channel(msg.forward_from_chat)
        end
    end

    -- if reply adjust reply
    if msg.reply then
        msg.reply_to_message = adjust_msg(msg.reply_to_message)
    end

    -- group language
    msg.lang = get_lang(msg.chat.id)
    return msg
end

local function collect_stats(msg)
    -- count the number of messages
    redis_hincr('bot:general', 'messages', 1)

    -- for resolve username
    saveUsername(msg.from, msg.chat.id)
    saveUsername(msg.chat)
    saveUsername(msg.reply_to_message, msg.chat.id)
    if msg.added then
        for k, v in pairs(msg.added) do
            saveUsername(v, msg.chat.id)
        end
    end
    saveUsername(msg.adder, msg.chat.id)
    saveUsername(msg.removed, msg.chat.id)
    saveUsername(msg.remover, msg.chat.id)
    saveUsername(msg.forward_from)
    saveUsername(msg.forward_from_chat)

    -- group stats
    if not(msg.chat.type == 'private') then
        -- user in the group stats
        if msg.from.id then
            redis_hset_something('chat:' .. msg.chat.id .. ':userlast', msg.from.id, os.time())
            -- last message for each user
            redis_hincr('chat:' .. msg.chat.id .. ':userstats', msg.from.id, 1)
            -- number of messages for each user
            if msg.media then
                redis_hincr('chat:' .. msg.chat.id .. ':usermedia', msg.from.id, 1)
            end
        end
        redis_incr('chat:' .. msg.chat.id .. ':totalmsgs', 1)
        -- total number of messages of the group
    end

    -- user stats
    if msg.from then
        redis_hincr('user:' .. msg.from.id, 'msgs', 1)
        if msg.media then
            redis_hincr('user:' .. msg.from.id, 'media', 1)
        end
    end

    if msg.cb and msg.from and msg.chat then
        redis_hincr('chat:' .. msg.chat.id .. ':cb', msg.from.id, 1)
    end
end

local function update_sudoers(msg)
    if config.sudo_users[tostring(msg.from.id)] then
        config.sudo_users[tostring(msg.from.id)] = clone_table(msg.from)
    end
end

function pre_process_reply(msg)
    if msg.reply_to_message then
        msg.reply = true
    end
    return msg
end

function pre_process_callback(msg)
    if msg.cb_id then
        msg.cb = true
        msg.text = "###cb" .. msg.data
    end
    if msg.reply then
        msg.reply_to_message = pre_process_callback(msg.reply_to_message)
    end
    return msg
end

-- recursive to simplify code
function pre_process_forward(msg)
    if msg.forward_from or msg.forward_from_chat then
        msg.forward = true
        if msg.text then
            msg.text = "FORWARDED " .. msg.text
        end
    end
    if msg.reply then
        msg.reply_to_message = pre_process_forward(msg.reply_to_message)
    end
    return msg
end

-- recursive to simplify code
function pre_process_media_msg(msg)
    msg.media = false
    if msg.caption_entities then
        msg.entities = clone_table(msg.caption_entities)
        msg.caption_entities = nil
    end

    if msg.animation then
        msg.media = true
        -- msg.text = "%[gif%]"
        msg.media_type = 'gif'
    elseif msg.audio then
        msg.media = true
        -- msg.text = "%[audio%]"
        msg.media_type = 'audio'
    elseif msg.contact then
        msg.media = true
        -- msg.text = "%[contact%]"
        msg.media_type = 'contact'
    elseif msg.document then
        msg.media = true
        -- msg.text = "%[document%]"
        msg.media_type = 'document'
    elseif msg.location then
        msg.media = true
        -- msg.text = "%[location%]"
        msg.media_type = 'location'
    elseif msg.photo then
        msg.media = true
        -- msg.text = "%[photo%]"
        msg.media_type = 'photo'
    elseif msg.sticker then
        msg.media = true
        -- msg.text = "%[sticker%]"
        msg.media_type = 'sticker'
    elseif msg.video then
        msg.media = true
        -- msg.text = "%[video%]"
        msg.media_type = 'video'
    elseif msg.video_note then
        msg.media = true
        -- msg.text = "%[video_note%]"
        msg.media_type = 'video_note'
    elseif msg.voice then
        msg.media = true
        -- msg.text = "%[voice_note%]"
        msg.media_type = 'voice_note'
    end
    if msg.caption then
        msg.text = msg.caption
        msg.caption = nil
    elseif msg.media then
        msg.text = ""
    end
    if msg.reply then
        pre_process_media_msg(msg.reply_to_message)
    end
    return msg
end

function migrate_to_supergroup(msg)
    local old = msg.migrate_from_chat_id
    local new = msg.chat.id
    if not old or not new then
        print('A group id is missing')
        return false
    end

    data[tostring(new)] = clone_table(data[tostring(old)])
    data[tostring(old)] = nil
    data['groups'][tostring(new)] = tonumber(new)
    data['groups'][tostring(old)] = nil
    data[tostring(new)].type = 'SuperGroup'
    save_data(config.moderation.data, data)

    -- migrate get
    local vars = redis_get_something('group:' .. old .. ':variables')
    for key, value in pairs(vars) do
        redis_hset_something('supergroup:' .. new .. ':variables', key, value)
        redis_hdelsrem_something('group:' .. old .. ':variables', key)
    end

    -- migrate ban
    -- FIX THIS SHIT IT CAN CAUSE FLOOD_WAITS
    local banned = redis_get_something('banned:' .. old)
    if next(banned) then
        for i = 1, #banned do
            banUser(bot.id, banned[i], new)
        end
    end

    -- migrate likes from likecounterdb.json
    local likedata = load_data(config.likecounter.db)
    if likedata then
        for id_string in pairs(likedata) do
            -- if there are any groups check for everyone of them to find the one requesting migration, if found migrate
            if id_string == tostring(old) then
                likedata[tostring(new)] = likedata[id_string]
                likedata[id_string] = nil
            end
        end
    end
    save_data(config.likecounter.db, likedata)

    -- migrate database from database.json
    if database then
        for id_string in pairs(database) do
            -- if there are any groups move their data from cli to api db
            if id_string == tostring(old) then
                database[tostring(new)] = clone_table(database[tostring(old)])
                database[tostring(new)].old_usernames = 'NOUSER'
                database[tostring(new)].username = 'NOUSER'
                database[tostring(old)] = nil
            end
        end
    end
    save_data(config.database.db, database, true)
    sendMessage(new, langs[get_lang(old)].groupToSupergroup)
end

-- recursive to simplify code
function pre_process_service_msg(msg)
    msg.service = false
    if msg.group_chat_created then
        msg.service = true
        msg.text = '!!tgservice chat_created ' ..(msg.text or '')
        msg.service_type = 'chat_created'
    elseif msg.new_chat_members then
        msg.adder = clone_table(msg.from)
        msg.added = { }
        for k, v in pairs(msg.new_chat_members) do
            if msg.from.id == v.id then
                msg.added[k] = clone_table(msg.from)
            else
                msg.added[k] = clone_table(v)
            end
        end
    elseif msg.new_chat_member then
        msg.adder = clone_table(msg.from)
        msg.added = { }
        if msg.from.id == msg.new_chat_member.id then
            msg.added[1] = clone_table(msg.from)
        else
            msg.added[1] = clone_table(msg.new_chat_member)
        end
    elseif msg.left_chat_member then
        msg.remover = clone_table(msg.from)
        if msg.from.id == msg.left_chat_member.id then
            msg.removed = clone_table(msg.from)
        else
            msg.removed = clone_table(msg.left_chat_member)
        end
    elseif msg.migrate_from_chat_id then
        msg.service = true
        msg.text = '!!tgservice migrated_from ' ..(msg.text or '')
        msg.service_type = 'migrated_from'
        if data[tostring(msg.migrate_from_chat_id)] then
            migrate_to_supergroup(msg)
        end
    elseif msg.pinned_message then
        msg.service = true
        msg.text = '!!tgservice pinned_message ' ..(msg.text or '')
        msg.service_type = 'pinned_message'
    elseif msg.delete_chat_photo then
        msg.service = true
        msg.text = '!!tgservice delete_chat_photo ' ..(msg.text or '')
        msg.service_type = 'delete_chat_photo'
    elseif msg.new_chat_photo then
        msg.service = true
        msg.text = '!!tgservice chat_change_photo ' ..(msg.text or '')
        msg.service_type = 'chat_change_photo'
    elseif msg.new_chat_title then
        msg.service = true
        msg.text = '!!tgservice chat_rename ' ..(msg.text or '')
        msg.service_type = 'chat_rename'
    end
    if msg.adder and msg.added then
        msg.service = true
        -- add_user
        if #msg.new_chat_members == 1 then
            if msg.adder.id == msg.added[1].id then
                msg.text = '!!tgservice chat_add_user_link ' ..(msg.text or '')
                msg.service_type = 'chat_add_user_link'
            else
                msg.text = '!!tgservice chat_add_user ' ..(msg.text or '')
                msg.service_type = 'chat_add_user'
            end
        else
            msg.text = '!!tgservice chat_add_users ' ..(msg.text or '')
            msg.service_type = 'chat_add_users'
        end
        msg.new_chat_member = nil
        msg.new_chat_members = nil
        msg.new_chat_participant = nil
    end
    if msg.remover and msg.removed then
        msg.service = true
        -- del_user
        if msg.remover.id == msg.removed.id then
            msg.text = '!!tgservice chat_del_user_leave ' ..(msg.text or '')
            msg.service_type = 'chat_del_user_leave'
        else
            msg.text = '!!tgservice chat_del_user ' ..(msg.text or '')
            msg.service_type = 'chat_del_user'
        end
        msg.left_chat_member = nil
        msg.left_chat_participant = nil
    end
    if msg.reply then
        pre_process_service_msg(msg.reply_to_message)
    end
    return msg
end

function msg_valid(msg)
    if msg.service then
        if msg.service_type == 'chat_del_user' then
            if tostring(msg.removed.id) == tostring(bot.id) then
                sendLog('#REMOVEDFROM ' .. msg.chat.id .. ' ' .. msg.chat.title, false, true)
                if data[tostring(msg.chat.id)] then
                    if data[tostring(msg.chat.id)].owner then
                        sendMessage(data[tostring(msg.chat.id)].owner, langs[get_lang(data[tostring(msg.chat.id)].owner)].chatWillBeRemoved)
                    end
                end
                return false
            end
        elseif msg.service_type == 'chat_add_user' or msg.service_type == 'chat_add_users' then
            for k, v in pairs(msg.added) do
                if tostring(v.id) == tostring(bot.id) then
                    sendLog('#ADDEDTO ' .. msg.chat.id .. ' ' .. msg.chat.title, false, true)
                    if not is_admin(msg) and not sudoInChat(msg.chat.id) then
                        sendMessage(msg.chat.id, langs[msg.lang].notMyGroup)
                        leaveChat(msg.chat.id)
                    end
                end
            end
        end
    end
    if not msg.bot then
        if bot.userVersion then
            if msg.from.id == bot.userVersion.id then
                local crossvalid = false
                if not msg.forward then
                    if msg.text then
                        if string.match(msg.text, '^[Cc][Rr][Oo][Ss][Ss][Ee][Xx][Ee][Cc] (.*)$') then
                            crossvalid = true
                        end
                    end
                end
                if not crossvalid then
                    print(clr.yellow .. 'Not valid: my user version in a group' .. clr.reset)
                    return false
                else
                    msg.text = string.gsub(msg.text, '[Cc][Rr][Oo][Ss][Ss][Ee][Xx][Ee][Cc] ', '')
                end
            end
        end

        if not data[tostring(msg.chat.id)] then
            print(clr.white .. 'Preprocess', 'database')
            local res, err = pcall( function()
                plugins.database.pre_process(msg)
            end )
            -- if not a known group receive messages just from sudo
            local sudoMessage = false
            for k, v in pairs(config.sudo_users) do
                if tostring(msg.from.id) == tostring(k) then
                    sudoMessage = true
                end
            end
            if not sudoMessage then
                print(clr.yellow .. 'Not valid: not sudo message' .. clr.reset)
                return false
            end
        end
    end

    if msg.edited and msg.date < os.time() -20 then
        -- Edited messages sent more than 20 seconds ago
        msg = get_tg_rank(msg)
        local res, err = pcall( function()
            print(clr.white .. 'Preprocess old edited message', 'database')
            msg = plugins.database.pre_process(msg)
            print(clr.white .. 'Preprocess old edited message', 'delword')
            msg = plugins.delword.pre_process(msg)
            print(clr.white .. 'Preprocess old edited message', 'msg_checks')
            msg = plugins.msg_checks.pre_process(msg)
        end )
        print(clr.yellow .. 'Not valid: old edited msg' .. clr.reset)
        return false
    elseif msg.date < os.time() -5 then
        -- Old messages (more than 5 seconds ago)
        if msg.date > os.time() -60 then
            -- If more recent than 60 seconds ago check them
            msg = get_tg_rank(msg)
            local res, err = pcall( function()
                print(clr.white .. 'Preprocess old message', 'database')
                msg = plugins.database.pre_process(msg)
                print(clr.white .. 'Preprocess old message', 'banhammer')
                msg = plugins.banhammer.pre_process(msg)
                print(clr.white .. 'Preprocess old message', 'delword')
                msg = plugins.delword.pre_process(msg)
                print(clr.white .. 'Preprocess old message', 'msg_checks')
                msg = plugins.msg_checks.pre_process(msg)
            end )
        end
        print(clr.yellow .. 'Not valid: old msg' .. clr.reset)
        return false
    end

    if isBlocked(msg.from.id) and msg.chat.type == 'private' then
        print(clr.yellow .. 'Not valid: user blocked' .. clr.reset)
        return false
    end

    if msg.chat.id == config.vardump_chat then
        sendMessage(msg.chat.id, 'AFTER ADJUST\n' .. vardumptext(msg))
        print(clr.yellow .. 'Not valid: vardump chat' .. clr.reset)
        return false
    end

    if isChatDisabled(msg.chat.id) and not is_owner(msg, true) then
        print(clr.yellow .. 'Not valid: channel disabled' .. clr.reset)
        return false
    end

    return true
end

-- Apply plugin.pre_process function
function pre_process_msg(msg)
    local res, err = pcall( function()
        print(clr.white .. 'Preprocess', 'alternatives')
        msg = plugins.alternatives.pre_process(msg)
        print(clr.white .. 'Preprocess', 'database')
        msg = plugins.database.pre_process(msg)
        print(clr.white .. 'Preprocess', 'banhammer')
        msg = plugins.banhammer.pre_process(msg)
        print(clr.white .. 'Preprocess', 'anti_spam')
        msg = plugins.anti_spam.pre_process(msg)
        print(clr.white .. 'Preprocess', 'msg_checks')
        msg = plugins.msg_checks.pre_process(msg)
        print(clr.white .. 'Preprocess', 'group_management')
        msg = plugins.group_management.pre_process(msg)
        print(clr.white .. 'Preprocess', 'delword')
        msg = plugins.delword.pre_process(msg)
        for name, plugin in pairs(plugins) do
            if plugin.pre_process and msg then
                if plugin.description ~= 'ALTERNATIVES' and
                    plugin.description ~= 'ANTI_SPAM' and
                    plugin.description ~= 'BANHAMMER' and
                    plugin.description ~= 'DATABASE' and
                    plugin.description ~= 'DELWORD' and
                    plugin.description ~= 'GROUP_MANAGEMENT' and
                    plugin.description ~= 'MSG_CHECKS' then
                    print(clr.white .. 'Preprocess', name)
                    msg = plugin.pre_process(msg)
                end
            end
        end
    end )
    print(res, err)
    return msg
end

-- Go over enabled plugins patterns.
function match_plugins(msg)
    for name, plugin in pairs(plugins) do
        -- Go over patterns. If match then enough.
        for k, pattern in pairs(plugin.patterns) do
            local matches = match_pattern(pattern, msg.text)
            if matches then
                print(clr.magenta .. "msg matches: ", name, " => ", pattern .. clr.reset)

                local disabled = plugin_disabled_on_chat(name, msg.chat.id)
                if pattern ~= "([\216-\219][\128-\191])" and pattern ~= "!!tgservice (.*)" and not msg.media and((msg.text:match("^###.*BACK") or msg.text:match("^###.*PAGE") or msg.text:match("^###.*DELETE")) == nil) then
                    if msg.chat.type == 'private' then
                        if disabled then
                            savelog(msg.chat.id, msg.chat.print_name:gsub('_', ' ') .. ' ID: ' .. '[' .. msg.chat.id .. ']' .. '\nCommand "' .. msg.text .. '" received but plugin is disabled on chat.')
                            return
                        else
                            savelog(msg.chat.id, msg.chat.print_name:gsub('_', ' ') .. ' ID: ' .. '[' .. msg.chat.id .. ']' .. '\nCommand "' .. msg.text .. '" executed.')
                        end
                    else
                        if disabled then
                            savelog(msg.chat.id, msg.chat.print_name:gsub('_', ' ') .. ' ID: ' .. '[' .. msg.chat.id .. ']' .. ' Sender: ' .. msg.from.print_name:gsub('_', ' ') .. ' [' .. msg.from.id .. ']' .. '\nCommand "' .. msg.text .. '" received but plugin is disabled on chat.')
                            return
                        else
                            savelog(msg.chat.id, msg.chat.print_name:gsub('_', ' ') .. ' ID: ' .. '[' .. msg.chat.id .. ']' .. ' Sender: ' .. msg.from.print_name:gsub('_', ' ') .. ' [' .. msg.from.id .. ']' .. '\nCommand "' .. msg.text .. '" executed.')
                        end
                    end
                end

                -- Function exists
                if plugin.run then
                    --[[local result = plugin.run(msg, matches)
                    if result then
                        sendMessage(msg.chat.id, result)
                    end]]
                    local res, err = pcall( function()
                        local result = plugin.run(msg, matches)
                        if result then
                            if not sendReply(msg, result) then
                                sendMessage(msg.chat.id, result)
                            end
                        end
                    end )
                    if not res then
                        sendLog('An #error occurred.\n' .. tostring(err) .. '\n' .. vardumptext(msg))
                    end
                end
                -- One patterns matches
                break
            end
        end
    end
end

local function base_logging(msg)
    if msg.service then
        local text = ""
        if msg.service_type == 'pinned_message' then
            text = msg.from.print_name .. " [" .. msg.from.id .. "] pinned a message"
        elseif msg.service_type == 'chat_add_user_link' or msg.service_type == 'chat_add_users' or msg.service_type == 'chat_add_user' then
            if msg.adder.id == msg.added[1].id then
                text = msg.adder.print_name .. " [" .. msg.adder.id .. "] joined with invite link"
            else
                text = msg.adder.print_name .. " [" .. msg.adder.id .. "] added:\n"
                for k, v in pairs(msg.added) do
                    text = v.print_name .. " [" .. v.id .. "]\n"
                end
            end
        elseif msg.service_type == 'chat_del_user_leave' or msg.service_type == 'chat_del_user' then
            if msg.remover.id == msg.removed.id then
                text = msg.remover.print_name .. " [" .. msg.remover.id .. "] left the chat"
            else
                text = msg.remover.print_name .. " [" .. msg.remover.id .. "] deleted " .. msg.removed.print_name .. " [" .. msg.removed.id .. "]"
            end
        end
        savelog(msg.chat.id, text)
    end
end

-- This function is called when tg receive a msg
function on_msg_receive(msg)
    if not is_started then
        return
    end
    if not msg then
        sendMessage_SUDOERS(langs['en'].loopWithoutMessage, 'markdown')
        return
    end
    if msg.chat.id == config.vardump_chat then
        sendMessage(msg.chat.id, 'BEFORE ADJUST\n' .. vardumptext(msg))
    end
    update_sudoers(msg)
    msg = pre_process_reply(msg)
    msg = pre_process_forward(msg)
    msg = pre_process_callback(msg)
    msg = pre_process_media_msg(msg)
    msg = pre_process_service_msg(msg)
    msg = adjust_msg(msg)
    collect_stats(msg)
    if msg.text then
        if string.match(msg.text, "^@[Aa][Ii][Ss][Aa][Ss][Hh][Aa][Bb][Oo][Tt] ") then
            msg.text = msg.text:gsub("^@[Aa][Ii][Ss][Aa][Ss][Hh][Aa][Bb][Oo][Tt] ", "")
        end
        if string.match(msg.text, "^[#!/]?[%w_]+@[Aa][Ii][Ss][Aa][Ss][Hh][Aa][Bb][Oo][Tt]") then
            local tmp = string.match(msg.text, "([#!/]?[%w_]+)@[Aa][Ii][Ss][Aa][Ss][Hh][Aa][Bb][Oo][Tt]")
            msg.text = msg.text:gsub("^[#!/]?[%w_]+@[Aa][Ii][Ss][Aa][Ss][Hh][Aa][Bb][Oo][Tt]", tmp)
        end
    end
    local print_text = print_msg(msg, true)
    local chat_id = msg.chat.id
    msg = get_tg_rank(msg)
    tmp_msg = clone_table(msg)
    base_logging(msg)
    globalCronTable.punishedTable[tostring(msg.chat.id)] = globalCronTable.punishedTable[tostring(msg.chat.id)] or { }
    globalCronTable.invitedTable[tostring(msg.chat.id)] = globalCronTable.invitedTable[tostring(msg.chat.id)] or { }
    globalCronTable.executersTable[tostring(msg.chat.id)] = globalCronTable.executersTable[tostring(msg.chat.id)] or { }
    if msg.service then
        if msg.added then
            for k, v in pairs(msg.added) do
                -- if kicked users are added again, remove them from kicked list
                globalCronTable.punishedTable[tostring(msg.chat.id)][tostring(v.id)] = false
            end
        end
        if msg.removed then
            globalCronTable.invitedTable[tostring(msg.chat.id)][tostring(msg.removed.id)] = false
        end
    end
    if msg_valid(msg) then
        msg = pre_process_msg(msg)
        if msg then
            match_plugins(msg)
        end
    end
    print(chat_id)
    print(print_text)
end

-- Call and postpone execution for cron plugins
-- every minute
function cron_plugins()
    if last_cron ~= last_redis_cron then
        for name, plugin in pairs(plugins) do
            if plugin.cron then
                print("CRON: ", name)
                -- Call each plugin's cron function, if it has one.
                local res, err = pcall( function() plugin.cron() end)
                if not res then
                    sendLog('An #error occurred.\n' .. err)
                end
            end
        end
        globalCronTable = {
            punishedTable = { },
            invitedTable = { },
            executersTable = { }
        }
        -- Run cron jobs every minute.
        last_cron = last_redis_cron
    end
end

-- every day
function cron_administrator()
    if last_administrator_cron ~= last_redis_administrator_cron then
        -- save database
        save_data(config.rdb.db, rdb, true)
        save_data(config.database.db, database, true)
        io.popen('lua timework.lua "backup" "0"')
        -- deletes all files in tmp folders
        print("Deleting all files in tmp folders")
        io.popen('rm -f /home/pi/AISashaAPI/data/tmp/*')
        io.popen('rm -f /home/pi/AISasha/data/tmp/*')
        -- Run cron jobs every day.
        last_administrator_cron = last_redis_administrator_cron
    end
end

---------WHEN THE BOT IS STARTED FROM THE TERMINAL, THIS IS THE FIRST FUNCTION HE FOUNDS

bot_init() -- Actually start the script. Run the bot_init function.

while is_started do
    -- Start a loop while the bot should be running.
    local res = getUpdates(last_update + 1)
    -- Get the latest updates!
    if res then
        -- printvardump(res)
        for i, msg in ipairs(res.result) do
            -- Go through every new message.
            if last_update < msg.update_id then
                last_update = msg.update_id
            end
            if msg.edited_message then
                msg.message = msg.edited_message
                msg.message.edited = true
                msg.edited_message = nil
            elseif msg.callback_query then
                local cb_msg = msg.callback_query
                if cb_msg.message then
                    cb_msg.original_date = cb_msg.message.date
                    cb_msg.message_id = cb_msg.message.message_id
                    cb_msg.chat = cb_msg.message.chat
                    cb_msg.message = nil
                end
                cb_msg.date = os.time()
                cb_msg.cb_id = cb_msg.id
                cb_msg.id = nil
                msg.message = cb_msg
                -- callback datas often ship IDs
            end
            if msg.message then
                on_msg_receive(msg.message)
            end
        end
    else
        print(clr.red .. 'Connection error' .. clr.reset)
    end
    update_redis_cron()
    cron_plugins()
    cron_administrator()
end

print(clr.white .. 'Halted.' .. clr.reset)

--[[COLORS
  black = "\27[30m",
  blink = "\27[5m",
  blue = "\27[34m",
  bright = "\27[1m",
  clear = "\27[0m",
  cyan = "\27[36m",
  default = "\27[0m",
  dim = "\27[2m",
  green = "\27[32m",
  hidden = "\27[8m",
  magenta = "\27[35m",
  onblack = "\27[40m",
  onblue = "\27[44m",
  oncyan = "\27[46m",
  ongreen = "\27[42m",
  onmagenta = "\27[45m",
  onred = "\27[41m",
  onwhite = "\27[47m",
  onyellow = "\27[43m",
  red = "\27[31m",
  reset = "\27[0m",
  reverse = "\27[7m",
  underscore = "\27[4m",
  white = "\27[37m",
  yellow = "\27[33m"
]]