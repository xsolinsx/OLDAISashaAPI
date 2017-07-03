local function enable_channel(chat_id)
    local lang = get_lang(chat_id)

    if not config.disabled_channels then
        config.disabled_channels = { }
    end

    if config.disabled_channels[chat_id] == nil then
        return langs[lang].botOn
    end

    config.disabled_channels[chat_id] = false

    save_config()
    return langs[lang].botOn
end

local function disable_channel(chat_id)
    local lang = get_lang(chat_id)

    if not config.disabled_channels then
        config.disabled_channels = { }
    end

    config.disabled_channels[chat_id] = true

    save_config()
    return langs[lang].botOff
end

local function run(msg, matches)
    if matches[1]:lower() == '/start' and msg.bot then
        sendMessage(msg.chat.id, langs[msg.lang].startMessage)
        if matches[2] then
            msg.text = '/' .. matches[2]
            if msg_valid(msg) then
                msg = pre_process_msg(msg)
                if msg then
                    match_plugins(msg)
                end
            end
        end
    end
    if msg.from.is_owner then
        if not matches[2] then
            if matches[1]:lower() == 'on' then
                mystat('/bot on')
                return enable_channel(msg.chat.id)
            end
            if matches[1]:lower() == 'off' then
                mystat('/bot off')
                return disable_channel(msg.chat.id)
            end
        elseif is_admin(msg) then
            if matches[1]:lower() == 'on' then
                mystat('/bot on <group_id>')
                return enable_channel(matches[2])
            end
            if matches[1]:lower() == 'off' then
                mystat('/bot off <group_id>')
                return disable_channel(matches[2])
            end
        else
            return langs[msg.lang].require_admin
        end
    else
        return langs[msg.lang].require_owner
    end
end

return {
    description = "BOT",
    patterns =
    {
        "^(/[Ss][Tt][Aa][Rr][Tt])$",
        "^(/[Ss][Tt][Aa][Rr][Tt]) (.*)$",
        "^(/[Ss][Tt][Aa][Rr][Tt])@[Aa][Ii][Ss][Aa][Ss][Hh][Aa][Bb][Oo][Tt]$",
        "^(/[Ss][Tt][Aa][Rr][Tt])@[Aa][Ii][Ss][Aa][Ss][Hh][Aa][Bb][Oo][Tt] (.*)$",
        "^[#!/][Bb][Oo][Tt] ([Oo][Nn])$",
        "^[#!/][Bb][Oo][Tt] ([Oo][Ff][Ff])$",
        "^[#!/][Bb][Oo][Tt] ([Oo][Nn]) (%-?%d+)$",
        "^[#!/][Bb][Oo][Tt] ([Oo][Ff][Ff]) (%-?%d+)$",
    },
    run = run,
    min_rank = 0,
    syntax =
    {
        "USER",
        "/start[@AISashaBot]",
        "OWNER",
        "#bot|sasha on|off",
        "ADMIN",
        "#bot|sasha on|off [<group_id>]",
    }
}