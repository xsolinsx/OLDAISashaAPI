-- Returns true if file exists in plugins folder
local function plugin_exists(plugin_name)
    for k, v in pairs(plugins_names()) do
        if plugin_name .. '.lua' == v then
            return true
        end
    end
    return false
end

local function list_plugins_sudo()
    local text = ''
    for k, v in pairs(plugins_names()) do
        --  ✅ enabled, ☑️ disabled
        local status = '☑️'
        -- get the name
        v = string.match(v, "(.*)%.lua")
        -- Check if enabled
        if plugin_enabled(v) then
            status = '✅'
        end
        -- Check if system plugin
        if system_plugin(v) then
            status = '💻'
        end
        text = text .. k .. '. ' .. status .. ' ' .. v .. '\n'
    end
    return text
end

local function list_plugins(chat_id)
    local text = ''
    for k, v in pairs(plugins_names()) do
        --  ✅ enabled, ☑️ disabled
        local status = '☑️'
        -- get the name
        v = string.match(v, "(.*)%.lua")
        -- Check if is enabled
        if plugin_enabled(v) then
            status = '✅'
        end
        -- Check if system plugin, if not check if disabled on chat
        if system_plugin(v) then
            status = '💻'
        elseif plugin_disabled_on_chat(v, chat_id) then
            status = '🚫'
        end
        text = text .. k .. '. ' .. status .. ' ' .. v .. '\n'
    end
    return text
end

local function reload_plugins()
    plugins = { }
    load_plugins()
    return list_plugins_sudo()
end

local function enable_plugin(plugin_name, chat_id)
    local lang = get_lang(chat_id)
    -- Check if plugin is enabled
    if plugin_enabled(plugin_name) then
        return '✔️ ' .. plugin_name .. langs[lang].alreadyEnabled
    end
    -- Checks if plugin exists
    if plugin_exists(plugin_name) then
        -- Add to the config table
        table.insert(config.enabled_plugins, plugin_name)
        print(plugin_name .. ' added to config table')
        save_config()
        -- Reload the plugins
        reload_plugins()
        return '✅ ' .. plugin_name .. langs[lang].enabled
    else
        return '❔ ' .. plugin_name .. langs[lang].notExists
    end
end

local function disable_plugin(plugin_name, chat_id)
    local lang = get_lang(chat_id)
    -- Check if plugins exists
    if not plugin_exists(plugin_name) then
        return '❔ ' .. plugin_name .. langs[lang].notExists
    end
    local k = plugin_enabled(plugin_name)
    -- Check if plugin is enabled
    if not k then
        return '✖️ ' .. plugin_name .. langs[lang].alreadyDisabled
    end
    -- Disable and reload
    table.remove(config.enabled_plugins, k)
    save_config()
    reload_plugins()
    return '☑️ ' .. plugin_name .. langs[lang].disabled
end

local function disable_plugin_on_chat(plugin_name, chat_id)
    local lang = get_lang(chat_id)
    if not plugin_exists(plugin_name) then
        return '❔ ' .. plugin_name .. langs[lang].notExists
    end

    if not config.disabled_plugin_on_chat then
        config.disabled_plugin_on_chat = { }
    end

    if not config.disabled_plugin_on_chat[chat_id] then
        config.disabled_plugin_on_chat[chat_id] = { }
    end

    config.disabled_plugin_on_chat[chat_id][plugin_name] = true

    save_config()
    return '🚫 ' .. plugin_name .. langs[lang].disabledOnChat
end

local function reenable_plugin_on_chat(plugin_name, chat_id)
    local lang = get_lang(chat_id)
    if not config.disabled_plugin_on_chat then
        return langs[lang].noDisabledPlugin
    end

    if not config.disabled_plugin_on_chat[chat_id] then
        return langs[lang].noDisabledPlugin
    end

    if not config.disabled_plugin_on_chat[chat_id][plugin_name] then
        return langs[lang].pluginNotDisabled
    end

    config.disabled_plugin_on_chat[chat_id][plugin_name] = false
    save_config()
    return '✅ ' .. plugin_name .. langs[lang].pluginEnabledAgain
end

local function list_disabled_plugin_on_chat(chat_id)
    local lang = get_lang(chat_id)
    if not config.disabled_plugin_on_chat then
        return langs[lang].noDisabledPlugin
    end

    if not config.disabled_plugin_on_chat[chat_id] then
        return langs[lang].noDisabledPlugin
    end

    local status = '🚫'
    local text = ''
    for k in pairs(config.disabled_plugin_on_chat[chat_id]) do
        if config.disabled_plugin_on_chat[chat_id][k] == true then
            text = text .. status .. ' ' .. k .. '\n'
        end
    end
    return text
end

local function run(msg, matches)
    if msg.cb then
        if matches[2] == 'DELETE' then
            if not deleteMessage(msg.chat.id, msg.message_id, true) then
                editMessageText(msg.chat.id, msg.message_id, langs[msg.lang].stop)
            end
        elseif matches[2] == 'PAGES' then
            answerCallbackQuery(msg.cb_id, langs[msg.lang].uselessButton, false)
        elseif matches[2] == 'BACK' then
            answerCallbackQuery(msg.cb_id, langs[msg.lang].keyboardUpdated, false)
            if matches[4] then
                if is_owner2(msg.from.id, matches[4]) then
                    editMessageReplyMarkup(msg.chat.id, msg.message_id, keyboard_plugins_pages(msg.from.id, false, matches[3] or 1, tonumber(matches[4]), matches[5] or false))
                else
                    editMessageText(msg.chat.id, msg.message_id, langs[msg.lang].require_owner)
                end
            else
                if is_sudo(msg) then
                    editMessageReplyMarkup(msg.chat.id, msg.message_id, keyboard_plugins_pages(msg.from.id, true, matches[3] or 1))
                else
                    editMessageText(msg.chat.id, msg.message_id, langs[msg.lang].require_sudo)
                end
            end
        elseif matches[2]:gsub('%d', '') == 'PAGEMINUS' then
            answerCallbackQuery(msg.cb_id, langs[msg.lang].turningPage)
            if matches[4] then
                if is_owner2(msg.from.id, matches[4]) then
                    editMessageReplyMarkup(msg.chat.id, msg.message_id, keyboard_plugins_pages(msg.from.id, false, tonumber(matches[3] or(tonumber(matches[2]:match('%d')) + 1)) - tonumber(matches[2]:match('%d')), tonumber(matches[4]), matches[5] or false))
                else
                    editMessageText(msg.chat.id, msg.message_id, langs[msg.lang].require_owner)
                end
            else
                if is_sudo(msg) then
                    editMessageReplyMarkup(msg.chat.id, msg.message_id, keyboard_plugins_pages(msg.from.id, true, tonumber(matches[3] or(tonumber(matches[2]:match('%d')) + 1)) - tonumber(matches[2]:match('%d'))))
                else
                    editMessageText(msg.chat.id, msg.message_id, langs[msg.lang].require_sudo)
                end
            end
        elseif matches[2]:gsub('%d', '') == 'PAGEPLUS' then
            answerCallbackQuery(msg.cb_id, langs[msg.lang].turningPage)
            if matches[4] then
                if is_owner2(msg.from.id, matches[4]) then
                    editMessageReplyMarkup(msg.chat.id, msg.message_id, keyboard_plugins_pages(msg.from.id, false, tonumber(matches[3] or(tonumber(matches[2]:match('%d')) -1)) + tonumber(matches[2]:match('%d')), tonumber(matches[4]), matches[5] or false))
                else
                    editMessageText(msg.chat.id, msg.message_id, langs[msg.lang].require_owner)
                end
            else
                if is_sudo(msg) then
                    editMessageReplyMarkup(msg.chat.id, msg.message_id, keyboard_plugins_pages(msg.from.id, true, tonumber(matches[3] or(tonumber(matches[2]:match('%d')) -1)) + tonumber(matches[2]:match('%d'))))
                else
                    editMessageText(msg.chat.id, msg.message_id, langs[msg.lang].require_sudo)
                end
            end
        elseif matches[5] then
            -- Enable/Disable a plugin for this chat
            if is_owner2(msg.from.id, matches[5]) then
                if matches[2] == 'ENABLE' then
                    answerCallbackQuery(msg.cb_id, reenable_plugin_on_chat(matches[3], tonumber(matches[5])), false)
                    editMessageReplyMarkup(msg.chat.id, msg.message_id, keyboard_plugins_pages(msg.from.id, false, matches[4] or 1, tonumber(matches[5]), matches[6] or false))
                elseif matches[2] == 'DISABLE' then
                    if not system_plugin(matches[3]) then
                        answerCallbackQuery(msg.cb_id, disable_plugin_on_chat(matches[3], tonumber(matches[5])), false)
                        editMessageReplyMarkup(msg.chat.id, msg.message_id, keyboard_plugins_pages(msg.from.id, false, matches[4] or 1, tonumber(matches[5]), matches[6] or false))
                    else
                        answerCallbackQuery(msg.cb_id, langs[msg.lang].systemPlugin, false)
                    end
                end
                mystat(matches[1] .. matches[2] .. matches[3] .. matches[5])
            else
                return editMessageText(msg.chat.id, msg.message_id, langs[msg.lang].require_owner)
            end
        else
            -- Enable/Disable a plugin
            if is_sudo(msg) then
                if matches[2] == 'ENABLE' then
                    answerCallbackQuery(msg.cb_id, enable_plugin(matches[3], msg.chat.id), false)
                    editMessageReplyMarkup(msg.chat.id, msg.message_id, keyboard_plugins_pages(msg.from.id, true, matches[4] or 1))
                elseif matches[2] == 'DISABLE' then
                    if not system_plugin(matches[3]) then
                        answerCallbackQuery(msg.cb_id, disable_plugin(matches[3], msg.chat.id), false)
                        editMessageReplyMarkup(msg.chat.id, msg.message_id, keyboard_plugins_pages(msg.from.id, true, matches[4] or 1))
                    else
                        answerCallbackQuery(msg.cb_id, langs[msg.lang].systemPlugin, false)
                    end
                end
                mystat(matches[1] .. matches[2] .. matches[3])
            else
                editMessageText(msg.chat.id, msg.message_id, langs[msg.lang].require_sudo)
            end
        end
        return
    end

    if matches[1]:lower() == 'plugins' then
        if msg.from.is_owner then
            local chat_plugins = false
            if matches[2] then
                chat_plugins = true
            elseif not is_sudo(msg) then
                chat_plugins = true
            end
            if chat_plugins then
                if data[tostring(msg.chat.id)] then
                    mystat('/plugins chat')
                    if sendKeyboard(msg.from.id, langs[msg.lang].pluginsIntro .. '\n\n' .. langs[msg.lang].pluginsList .. msg.chat.id, keyboard_plugins_pages(msg.from.id, false, 1, msg.chat.id)) then
                        if msg.chat.type ~= 'private' then
                            local message_id = getMessageId(sendReply(msg, langs[msg.lang].sendPluginsPvt, 'html'))
                            io.popen('lua timework.lua "deletemessage" "60" "' .. msg.chat.id .. '" "' .. msg.message_id .. ',' ..(message_id or '') .. '"')
                            return
                        end
                    else
                        return sendKeyboard(msg.chat.id, langs[msg.lang].cantSendPvt, { inline_keyboard = { { { text = "/start", url = bot.link } } } }, false, msg.message_id)
                    end
                else
                    return langs[msg.lang].useYourGroups
                end
            else
                mystat('/plugins')
                if sendKeyboard(msg.from.id, langs[msg.lang].pluginsIntro, keyboard_plugins_pages(msg.from.id, true)) then
                    if msg.chat.type ~= 'private' then
                        local message_id = getMessageId(sendReply(msg, langs[msg.lang].sendPluginsPvt, 'html'))
                        io.popen('lua timework.lua "deletemessage" "60" "' .. msg.chat.id .. '" "' .. msg.message_id .. ',' ..(message_id or '') .. '"')
                        return
                    end
                else
                    return sendKeyboard(msg.chat.id, langs[msg.lang].cantSendPvt, { inline_keyboard = { { { text = "/start", url = bot.link .. "?start=plugins" } } } }, false, msg.message_id)
                end
            end
        else
            return langs[msg.lang].require_owner
        end
    end

    -- Show the available plugins
    if matches[1]:lower() == 'textualplugins' then
        if msg.from.is_owner then
            local chat_plugins = false
            if matches[2] then
                chat_plugins = true
            elseif not is_sudo(msg) then
                chat_plugins = true
            end
            if chat_plugins then
                if data[tostring(msg.chat.id)] then
                    mystat('/plugins chat')
                    return langs[msg.lang].pluginsIntro .. '\n\n' .. list_plugins(msg.chat.id)
                else
                    return langs[msg.lang].useYourGroups
                end
            else
                mystat('/plugins')
                return langs[msg.lang].pluginsIntro .. '\n\n' .. list_plugins_sudo()
            end
        else
            return langs[msg.lang].require_owner
        end
    end

    if matches[1]:lower() == 'enable' then
        if matches[3] then
            -- Re-enable a plugin for this chat
            if msg.from.is_owner then
                mystat('/enable <plugin> chat')
                print("enable " .. matches[2] .. ' on this chat')
                return reenable_plugin_on_chat(matches[2], msg.chat.id)
            else
                return langs[msg.lang].require_owner
            end
        else
            -- Enable a plugin
            if is_sudo(msg) then
                mystat('/enable <plugin>')
                print("enable: " .. matches[2])
                return enable_plugin(matches[2], msg.chat.id)
            else
                return langs[msg.lang].require_sudo
            end
        end
    end

    if matches[1]:lower() == 'disable' then
        if matches[3] then
            -- Disable a plugin for this chat
            if msg.from.is_owner then
                mystat('/disable plugin chat')
                if system_plugin(matches[2]) then
                    return langs[msg.lang].systemPlugin
                end
                print("disable " .. matches[2] .. ' on this chat')
                return disable_plugin_on_chat(matches[2], msg.chat.id)
            else
                return langs[msg.lang].require_owner
            end
        else
            -- Disable a plugin
            if is_sudo(msg) then
                mystat('/disable <plugin>')
                if system_plugin(matches[2]) then
                    return langs[msg.lang].systemPlugin
                end
                print("disable: " .. matches[2])
                return disable_plugin(matches[2], msg.chat.id)
            else
                return langs[msg.lang].require_sudo
            end
        end
    end

    -- Show on chat disabled plugin
    if matches[1]:lower() == 'disabledlist' then
        if msg.from.is_owner then
            mystat('/disabledlist')
            return list_disabled_plugin_on_chat(msg.chat.id)
        else
            return langs[msg.lang].require_owner
        end
    end

    -- Reload all the plugins and strings!
    if matches[1]:lower() == 'reload' then
        if is_sudo(msg) then
            mystat('/reload')
            print(reload_plugins())
            return langs[msg.lang].pluginsReloaded
        else
            return langs[msg.lang].require_sudo
        end
    end
end

return {
    description = "PLUGINS",
    patterns =
    {
        "^(###cbplugins)(DELETE)(%u)$",
        "^(###cbplugins)(DELETE)$",
        "^(###cbplugins)(PAGES)(%u)$",
        "^(###cbplugins)(PAGES)$",
        "^(###cbplugins)(BACK)(%d+)(%-%d+)(%u)$",
        "^(###cbplugins)(BACK)(%d+)(%-%d+)$",
        "^(###cbplugins)(BACK)(%d+)$",
        "^(###cbplugins)(PAGE%dMINUS)(%d+)(%-%d+)(%u)$",
        "^(###cbplugins)(PAGE%dPLUS)(%d+)(%-%d+)(%u)$",
        "^(###cbplugins)(PAGE%dMINUS)(%d+)(%-%d+)$",
        "^(###cbplugins)(PAGE%dPLUS)(%d+)(%-%d+)$",
        "^(###cbplugins)(PAGE%dMINUS)(%d+)$",
        "^(###cbplugins)(PAGE%dPLUS)(%d+)$",
        "^(###cbplugins)(ENABLE)(.*)(%d+)(%-%d+)(%u)$",
        "^(###cbplugins)(DISABLE)(.*)(%d+)(%-%d+)(%u)$",
        "^(###cbplugins)(ENABLE)(.*)(%d+)(%-%d+)$",
        "^(###cbplugins)(DISABLE)(.*)(%d+)(%-%d+)$",
        "^(###cbplugins)(ENABLE)(.*)(%d+)$",
        "^(###cbplugins)(DISABLE)(.*)(%d+)$",

        "^[#!/]([Pp][Ll][Uu][Gg][Ii][Nn][Ss])$",
        "^[#!/]([Pp][Ll][Uu][Gg][Ii][Nn][Ss]) ([Cc][Hh][Aa][Tt])$",
        "^[#!/]([Tt][Ee][Xx][Tt][Uu][Aa][Ll][Pp][Ll][Uu][Gg][Ii][Nn][Ss])$",
        "^[#!/]([Tt][Ee][Xx][Tt][Uu][Aa][Ll][Pp][Ll][Uu][Gg][Ii][Nn][Ss]) ([Cc][Hh][Aa][Tt])$",
        "^[#!/]([Ee][Nn][Aa][Bb][Ll][Ee]) ([%w_%.%-]+)$",
        "^[#!/]([Dd][Ii][Ss][Aa][Bb][Ll][Ee]) ([%w_%.%-]+)$",
        "^[#!/]([Ee][Nn][Aa][Bb][Ll][Ee]) ([%w_%.%-]+) ([Cc][Hh][Aa][Tt])",
        "^[#!/]([Dd][Ii][Ss][Aa][Bb][Ll][Ee]) ([%w_%.%-]+) ([Cc][Hh][Aa][Tt])",
        "^[#!/]([Rr][Ee][Ll][Oo][Aa][Dd])$",
        "^[#!/]([Dd][Ii][Ss][Aa][Bb][Ll][Ee][Dd][Ll][Ii][Ss][Tt])",
    },
    run = run,
    min_rank = 3,
    syntax =
    {
        "OWNER",
        "/plugins",
        "/textualplugins",
        "/disabledlist",
        "/enable {plugin} chat",
        "/disable {plugin} chat",
        "SUDO",
        "/plugins [chat]",
        "/textualplugins [chat]",
        "/enable {plugin} [chat]",
        "/disable {plugin} [chat]",
        "/reload",
    },
}