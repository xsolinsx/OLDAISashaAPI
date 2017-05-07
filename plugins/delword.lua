local function get_censorships_hash(msg)
    if msg.chat.type == 'group' then
        return 'group:' .. msg.chat.id .. ':censorships'
    end
    if msg.chat.type == 'supergroup' then
        return 'supergroup:' .. msg.chat.id .. ':censorships'
    end
    return false
end

local function setunset_delword(msg, var_name)
    local hash = get_censorships_hash(msg)
    if hash then
        if redis:hget(hash, var_name) then
            redis:hdel(hash, var_name)
            return langs[msg.lang].delwordRemoved .. var_name
        else
            redis:hset(hash, var_name, true)
            return langs[msg.lang].delwordAdded .. var_name
        end
    end
end

local function list_censorships(msg)
    local hash = get_censorships_hash(msg)

    if hash then
        local names = redis:hkeys(hash)
        local text = langs[msg.lang].delwordList
        for i = 1, #names do
            text = text .. names[i] .. '\n'
        end
        return text
    end
end

local function run(msg, matches)
    if matches[1]:lower() == 'dellist' or matches[1]:lower() == 'sasha lista censure' or matches[1]:lower() == 'lista censure' then
        return list_censorships(msg)
    end
    if (matches[1]:lower() == 'delword' or matches[1]:lower() == 'sasha censura' or matches[1]:lower() == 'censura') and matches[2] then
        if msg.from.is_mod then
            return setunset_delword(msg, matches[2]:lower())
        else
            return langs[msg.lang].require_mod
        end
    end
end

local function clean_msg(msg)
    -- clean msg but returns it
    msg.cleaned = true
    if msg.text then
        msg.text = ''
    end
    if msg.media then
        if msg.caption then
            msg.caption = ''
        end
    end
    return msg
end

local function pre_process(msg)
    if msg then
        if not msg.from.is_mod then
            local found = false
            local vars = list_censorships(msg)

            if vars ~= nil then
                local t = vars:split('\n')
                for i, word in pairs(t) do
                    local temp = word:lower()
                    if msg.text then
                        if not string.match(msg.text, "^[#!/]([Dd][Ee][Ll][Ww][Oo][Rr][Dd]) (.*)$") then
                            if string.match(msg.text:lower(), temp) then
                                found = true
                            end
                        end
                    end
                    if msg.media then
                        if msg.caption then
                            if not string.match(msg.caption, "^[#!/]([Dd][Ee][Ll][Ww][Oo][Rr][Dd]) (.*)$") then
                                if string.match(msg.caption:lower(), temp) then
                                    found = true
                                end
                            end
                        end
                    end
                    if found then
                        deleteMessage(msg.chat.id, msg.message_id)
                        if msg.chat.type == 'group' then
                            banUser(bot.id, msg.from.id, msg.chat.id, langs[msg.lang].reasonCensorship)
                        end
                        msg = clean_msg(msg)
                        return nil
                    end
                end
            end
        end
        return msg
    end
end

return {
    description = "DELWORD",
    patterns =
    {
        "^[#!/]([Dd][Ee][Ll][Ww][Oo][Rr][Dd]) (.*)$",
        "^[#!/]([Dd][Ee][Ll][Ll][Ii][Ss][Tt])$",
        -- delword
        "^([Ss][Aa][Ss][Hh][Aa] [Cc][Ee][Nn][Ss][Uu][Rr][Aa]) (.*)$",
        "^([Cc][Ee][Nn][Ss][Uu][Rr][Aa]) (.*)$",
        -- dellist
        "^([Ss][Aa][Ss][Hh][Aa] [Ll][Ii][Ss][Tt][Aa] [Cc][Ee][Nn][Ss][Uu][Rr][Ee])$",
        "^([Ll][Ii][Ss][Tt][Aa] [Cc][Ee][Nn][Ss][Uu][Rr][Ee])$",
    },
    pre_process = pre_process,
    run = run,
    min_rank = 0,
    syntax =
    {
        "USER",
        "(#dellist|[sasha] lista censura)",
        "MOD",
        "(#delword|[sasha] censura) <word>|<pattern>",
    },
}