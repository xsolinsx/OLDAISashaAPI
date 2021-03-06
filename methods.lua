if not config.bot_api_key then
    error('You did not set your bot token in config.lua!')
end

local fake_user_chat = { first_name = 'FAKE', last_name = 'USER CHAT', print_name = 'FAKE USER CHAT', title = 'FAKE USER CHAT', username = 'USERNAME', id = 'FAKE ID' }
local unknown_user = { first_name = 'UNKNOWN', last_name = 'USER', username = 'USERNAME', id = 'UNKNOWN ID' }

local BASE_URL = 'https://api.telegram.org/bot' .. config.bot_api_key

local curl_context = curl.easy { verbose = false }
local api_errors = {
    [101] = 'not enough rights to kick/unban chat member',
    -- SUPERGROUP: bot is not admin
    [102] = 'user_admin_invalid',
    -- SUPERGROUP: trying to kick an admin
    [103] = 'method is available for supergroup chats only',
    -- NORMAL: trying to unban
    [104] = 'only creator of the group can kick administrators from the group',
    -- NORMAL: trying to kick an admin
    [105] = 'need to be inviter of the user to kick it from the group',
    -- NORMAL: bot is not an admin or everyone is an admin
    [106] = 'user_not_participant',
    -- NORMAL: trying to kick an user that is not in the group
    [107] = 'chat_admin_required',
    -- NORMAL: bot is not an admin or everyone is an admin
    [108] = 'there is no administrators in the private chat',
    -- something asked in a private chat with the api methods 2.1
    [109] = 'wrong url host',
    -- hyperlink not valid
    [110] = 'peer_id_invalid',
    -- user never started the bot
    [111] = 'message is not modified',
    -- the edit message method hasn't modified the message
    [112] = 'can\'t parse message text: can\'t find end of the entity starting at byte offset %d+',
    -- the markdown is wrong and breaks the delivery
    [113] = 'group chat is migrated to a supergroup chat',
    -- group updated to supergroup
    [114] = 'message can\'t be forwarded',
    -- unknown
    [115] = 'message text is empty',
    -- empty message
    [116] = 'message not found',
    -- message id invalid, I guess
    [117] = 'chat not found',
    -- I don't know
    [118] = 'message is too long',
    -- over 4096 char
    [119] = 'user not found',
    -- unknown user_id
    [120] = 'can\'t parse reply keyboard markup json object',
    -- keyboard table invalid
    [121] = 'field \\\"inline_keyboard\\\" of the inlinekeyboardmarkup should be an array of arrays',
    -- inline keyboard is not an array of array
    [122] = 'can\'t parse inline keyboard button: inlinekeyboardbutton should be an object',
    [123] = 'bad Request: object expected as reply markup',
    -- empty inline keyboard table
    [124] = 'query_id_invalid',
    -- callback query id invalid
    [125] = 'channel_private',
    -- I don't know
    [126] = 'message_too_long',
    -- text of an inline callback answer is too long
    [127] = 'wrong user_id specified',
    -- invalid user_id
    [128] = 'too big total timeout [%d%.]+',
    -- something about spam an inline keyboards
    [129] = 'button_data_invalid',
    -- callback_data string invalid
    [130] = 'type of file to send mismatch',
    -- trying to send a media with the wrong method
    [131] = 'message_id_invalid',
    -- I don't know. Probably passing a string as message id
    [132] = 'can\'t parse inline keyboard button: can\'t find field "text"',
    -- the text of a button could be nil
    [133] = 'can\'t parse inline keyboard button: field "text" must be of type String',
    [134] = 'user_id_invalid',
    [135] = 'chat_invalid',
    [136] = 'user_deactivated',
    -- deleted account, probably
    [137] = 'can\'t parse inline keyboard button: text buttons are unallowed in the inline keyboard',
    [138] = 'message was not forwarded',
    [139] = 'can\'t parse inline keyboard button: field \\\"text\\\" must be of type string',
    -- "text" field in a button object is not a string
    [140] = 'channel invalid',
    -- /shrug
    [141] = 'wrong message entity: unsupproted url protocol',
    -- username in an inline link [word](@username) (only?)
    [142] = 'wrong message entity: url host is empty',
    -- inline link without link [word]()
    [143] = 'there is no photo in the request',
    [144] = 'can\'t parse message text: unsupported start tag "%w+" at byte offset %d+',
    [145] = 'can\'t parse message text: expected end tag at byte offset %d+',
    [146] = 'button_url_invalid',
    -- invalid url (inline buttons)
    [147] = 'message must be non%-empty',
    -- example: ```   ```
    [148] = 'can\'t parse message text: unmatched end tag at byte offset',
    [149] = 'reply_markup_invalid',
    -- returned while trying to send an url button without text and with an invalid url
    [150] = 'message text must be encoded in utf%-8',
    [151] = 'url host is empty',
    [152] = 'requested data is unaccessible',
    -- the request involves a private channel and the bot is not admin there
    [153] = 'unsupported url protocol',
    [154] = 'can\'t parse message text: unexpected end tag at byte offset %d+',
    [155] = 'message to edit not found',
    [156] = 'group chat was migrated to a supergroup chat',
    [157] = 'message to forward not found',
    [403] = 'bot was blocked by the user',
    -- user blocked the bot
    [429] = 'Too many requests: retry later',
    -- the bot is hitting api limits
    [430] = 'Too big total timeout',
    -- too many callback_data requests
}

-- *** START API FUNCTIONS ***
function performRequest(url)
    local data = { }

    -- if multithreading is made, this request must be in critical section
    local c = nil
    local ok, err = pcall( function()
        c = curl_context:setopt_url(url):setopt_writefunction(table.insert, data):perform()
    end )

    if ok then
        return table.concat(data), c:getinfo_response_code()
    end
end

function sendRequest(url, no_log)
    local method = url:match(BASE_URL .. '/(.*)%?')
    if method ~= 'sendChatAction' and method ~= 'getUpdates' then
        savelog('requests', method)
    end
    local dat, code = performRequest(url)
    local tab = nil
    if dat then
        tab = json:decode(dat)
    end

    if not tab then
        print(clr.red .. 'Error while parsing JSON' .. clr.reset, code)
        print(clr.yellow .. 'Data:' .. clr.reset, dat)
        return
    end

    if code ~= 200 then
        if code == 400 then
            -- error code 400 is general: try to specify
            code = getCode(tab.description)
        end

        print(clr.red .. code, tab.description .. clr.reset)
        redis_hincr('bot:errors', code, 1)

        local retry_after
        if code == 429 then
            retry_after = tab.parameters.retry_after
            print(('%sRate limited for %d seconds%s'):format(clr.yellow, retry_after, clr.reset))
        end

        if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 and code ~= 502 then
            if not no_log then
                sendLog('#BadRequest\n' .. vardumptext(tab) .. '\n' .. code, false, false, true)
            end
        end
        return nil, code, tab.description, retry_after
    end

    if not tab.ok then
        sendLog('Not tab.ok' .. vardumptext(tab))
        return false, tab.description
    end

    return tab
end

function getMe()
    local url = BASE_URL .. '/getMe'
    return sendRequest(url)
end

function getUpdates(offset)
    local url = BASE_URL .. '/getUpdates?timeout=20'
    if offset then
        url = url .. '&offset=' .. offset
    end
    return sendRequest(url)
end

function APIgetChat(id_or_username, no_log)
    id_or_username = tostring(id_or_username):gsub(' ', '')
    local url = BASE_URL .. '/getChat?chat_id=' .. id_or_username
    return sendRequest(url, no_log)
end

function getChatAdministrators(chat_id)
    local url = BASE_URL .. '/getChatAdministrators?chat_id=' .. chat_id
    return sendRequest(url)
end

function getChatMembersCount(chat_id)
    local url = BASE_URL .. '/getChatMembersCount?chat_id=' .. chat_id
    return sendRequest(url)
end

function getChatMember(chat_id, user_id, no_log)
    user_id = tostring(user_id):gsub(' ', '')
    if not string.match(user_id, '^%*%d') then
        local url = BASE_URL .. '/getChatMember?chat_id=' .. chat_id .. '&user_id=' .. user_id
        return sendRequest(url, no_log)
    else
        local fake_user = { first_name = 'FAKECOMMAND', last_name = 'FAKECOMMAND', print_name = 'FAKECOMMAND', username = '@FAKECOMMAND', id = user_id, type = 'fake', status = 'fake' }
        return fake_user
    end
end

function getFile(file_id)
    local url = BASE_URL ..
    '/getFile?file_id=' .. file_id
    return sendRequest(url)
end

function getCode(error)
    for k, v in pairs(api_errors) do
        if error:match(v) then
            return k
        end
    end
    -- error unknown
    return 7
end

function code2text(code, lang)
    -- the default error description can't be sent as output, so a translation is needed
    if code == 101 or code == 105 or code == 107 then
        return langs[lang].errors[1]
    elseif code == 102 or code == 104 then
        return langs[lang].errors[2]
    elseif code == 103 then
        return langs[lang].errors[3]
    elseif code == 106 then
        return langs[lang].errors[4]
    elseif code == 7 then
        return false
    end
    return false
end

-- never call this outside this file
function kickChatMember(user_id, chat_id, until_date, no_log)
    user_id = tostring(user_id):gsub(' ', '')
    local url = BASE_URL .. '/kickChatMember?chat_id=' .. chat_id ..
    '&user_id=' .. user_id
    if until_date then
        url = url .. '&until_date=' .. os.time() + until_date
    end
    local res, code = sendRequest(url, no_log)
    return res, code
end

-- never call this outside this file
function unbanChatMember(user_id, chat_id, no_log)
    user_id = tostring(user_id):gsub(' ', '')
    local url = BASE_URL .. '/unbanChatMember?chat_id=' .. chat_id ..
    '&user_id=' .. user_id
    local res, code = sendRequest(url, no_log)
    return res, code
end

--[[permissions is a table that contains (not necessarily all of them):
    can_change_info = true,
    can_post_messages = true, -- channel
    can_edit_messages = true, -- channel
    can_delete_messages = true,
    can_invite_users = true,
    can_restrict_members = true,
    can_pin_messages = true,
    can_promote_members = true]]
function promoteChatMember(chat_id, user_id, permissions)
    user_id = tostring(user_id):gsub(' ', '')
    if sendChatAction(chat_id, 'typing', true) then
        local url = BASE_URL .. '/promoteChatMember?chat_id=' .. chat_id ..
        '&user_id=' .. user_id
        if permissions then
            for k, v in pairs(permissions) do
                url = url .. '&' .. k .. '=' .. tostring(permissions[k])
            end
        end
        local res, code = sendRequest(url)

        if not res and code then
            -- if the request failed and a code is returned (not 403 and 429)
            if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                savelog('promote_user', code)
            end
        end
        return res
    end
end

function demoteChatMember(chat_id, user_id)
    user_id = tostring(user_id):gsub(' ', '')
    local demote_table = {
        can_change_info = false,
        can_delete_messages = false,
        can_invite_users = false,
        can_restrict_members = false,
        can_pin_messages = false,
        can_promote_members = false,
    }
    return promoteChatMember(chat_id, user_id, demote_table)
end

--[[can_send_messages = true,
    can_send_media_messages = true, -- implies can_send_messages
    can_send_other_messages = true, -- implies can_send_media_messages
    can_add_web_page_previews = true -- implies can_send_media_messages]]
-- never call this outside this file
function restrictChatMember(chat_id, user_id, restrictions, until_date)
    user_id = tostring(user_id):gsub(' ', '')
    if sendChatAction(chat_id, 'typing', true) then
        local url = BASE_URL .. '/restrictChatMember?chat_id=' .. chat_id ..
        '&user_id=' .. user_id
        if until_date then
            url = url .. '&until_date=' .. os.time() + until_date
        end
        for k, v in pairs(restrictions) do
            url = url .. '&' .. k .. '=' .. tostring(restrictions[k])
        end
        local res, code = sendRequest(url)
        if not res and code then
            -- if the request failed and a code is returned (not 403 and 429)
            if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                savelog('restrict_user', code)
            end
        end
        return res
    end
end

-- never call this outside this file
function unrestrictChatMember(chat_id, user_id)
    user_id = tostring(user_id):gsub(' ', '')
    local unrestrict_table = {
        can_send_messages = true,
        can_send_media_messages = true,
        can_send_other_messages = true,
        can_add_web_page_previews = true
    }
    return restrictChatMember(chat_id, user_id, unrestrict_table, nil)
end

function leaveChat(chat_id)
    local url = BASE_URL .. '/leaveChat?chat_id=' .. chat_id
    return sendRequest(url)
end

function sendMessage(chat_id, text, parse_mode, reply_to_message_id, send_sound, no_log)
    local max_msgs = 2
    if sendChatAction(chat_id, 'typing', true) and text and type(text) ~= 'table' then
        text = tostring(text)
        if text == '' then
            return nil
        end
        text = text:gsub('[Cc][Rr][Oo][Ss][Ss][Ee][Xx][Ee][Cc] ', '')
        if tmp_msg then
            if tmp_msg.from then
                local executer = tmp_msg.from.id
                if globalCronTable then
                    if globalCronTable.executersTable then
                        if globalCronTable.executersTable[tostring(chat_id)] then
                            if globalCronTable.executersTable[tostring(chat_id)][tostring(executer)] then
                                return nil
                            end
                        end
                    end
                end
                if get_rank(executer, chat_id, true) == 1 and(text == langs[get_lang(chat_id)].require_rank or text == langs[get_lang(chat_id)].require_mod or text == langs[get_lang(chat_id)].require_owner or text == langs[get_lang(chat_id)].require_admin or text == langs[get_lang(chat_id)].require_sudo) then
                    globalCronTable.executersTable[tostring(chat_id)][tostring(executer)] = true
                end
            end
        end
        local text_max = 4096
        local text_len = string.len(text)
        local num_msg = math.ceil(text_len / text_max)
        if parse_mode then
            max_msgs = 1
        end
        if num_msg > max_msgs then
            local path = "./data/tmp/" .. tostring(chat_id) .. tostring(tmp_msg.text or ''):gsub('/', 'forwardslash') .. ".txt"
            text = text:gsub('<code>', '')
            text = text:gsub('</code>', '')
            text = text:gsub('<b>', '')
            text = text:gsub('</b>', '')
            text = text:gsub('<pre>', '')
            text = text:gsub('</pre>', '')
            text = text:gsub('<i>', '')
            text = text:gsub('</i>', '')
            text = text:gsub('<a href="', '')
            text = text:gsub('">', '')
            text = text:gsub('</a>', '')
            local file_msg = io.open(path, "w")
            file_msg:write(text)
            file_msg:close()
            pyrogramUpload(chat_id, "document", path, reply_to_message_id, langs[get_lang(chat_id)].messageTooLong)
            return true
        else
            local url = BASE_URL ..
            '/sendMessage?chat_id=' .. chat_id ..
            '&disable_web_page_preview=true'
            local reply = false
            if reply_to_message_id then
                url = url .. '&reply_to_message_id=' .. reply_to_message_id
                reply = true
            end
            if parse_mode then
                if parse_mode:lower() == 'html' then
                    url = url .. '&parse_mode=HTML'
                elseif parse_mode:lower() == 'markdown' then
                    url = url .. '&parse_mode=Markdown'
                else
                    -- no parse_mode
                end
            end
            if not send_sound then
                url = url .. '&disable_notification=true'
                -- messages are silent by default
            end

            if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
                if num_msg <= 1 then
                    url = url .. '&text=' .. URL.escape(text)
                    local res, code = sendRequest(url, no_log)
                    if not res and code then
                        -- if the request failed and a code is returned (not 403 and 429)
                        if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                            savelog('send_msg', code .. '\n' .. text)
                        end
                    end
                    if print_res_msg(res) then
                        msgs_plus_plus(chat_id)
                    else
                        local obj = getChat(chat_id)
                        local sent_msg = { from = bot, chat = obj, text = text, reply = reply }
                        print_msg(sent_msg)
                    end
                    return res, code
                else
                    local my_text = string.sub(text, 1, 4090)
                    local rest = string.sub(text, 4090, text_len)
                    url = url .. '&text=' .. URL.escape(my_text)

                    local res, code = sendRequest(url, no_log)
                    if not res and code then
                        -- if the request failed and a code is returned (not 403 and 429)
                        if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                            savelog('send_msg', code .. '\n' .. text)
                        end
                    end
                    if print_res_msg(res) then
                        msgs_plus_plus(chat_id)
                        res, code = sendMessage(chat_id, rest, parse_mode, reply_to_message_id, send_sound)
                    else
                        local obj = getChat(chat_id)
                        local sent_msg = { from = bot, chat = obj, text = my_text, reply = reply }
                        print_msg(sent_msg)
                        msgs_plus_plus(chat_id)
                        res, code = sendMessage(chat_id, rest, parse_mode, reply_to_message_id, send_sound)
                    end
                end
                return res, code
                -- return false, and the code
            end
        end
    end
end

function sendMessage_SUDOERS(text, parse_mode)
    for k, v in pairs(config.sudo_users) do
        if k ~= bot.userVersion.id then
            sendMessage(k, text, parse_mode, false, true)
        end
    end
end

function sendReply(msg, text, parse_mode, send_sound, no_log)
    return sendMessage(msg.chat.id, text, parse_mode, msg.message_id, send_sound, no_log)
end

function sendLog(text, parse_mode, novardump, keyboard)
    if config.log_chat then
        if novardump then
            sendMessage(config.log_chat, text, parse_mode)
        else
            sendMessage(config.log_chat, text .. '\n' ..(vardumptext(tmp_msg) or ''), parse_mode)
            if keyboard then
                local obj = getChat(tmp_msg.chat.id)
                if obj then
                    sendKeyboard(config.log_chat, 'KEYBOARD OF THE CHAT IN WHICH THAT HAPPENED', get_object_info_keyboard(bot.id, obj, config.log_chat), false, false, true)
                end
            end
        end
    else
        if novardump then
            sendMessage_SUDOERS(text, parse_mode)
        else
            sendMessage_SUDOERS(text .. '\n' ..(vardumptext(tmp_msg) or ''), parse_mode)
        end
    end
end

function forwardMessage(chat_id, from_chat_id, message_id, send_sound)
    if sendChatAction(chat_id, 'typing', true) and sendChatAction(from_chat_id, 'typing', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL ..
            '/forwardMessage?chat_id=' .. chat_id ..
            '&from_chat_id=' .. from_chat_id ..
            '&message_id=' .. message_id
            if not send_sound then
                url = url .. '&disable_notification=true'
                -- messages are silent by default
            end
            local res, code = sendRequest(url)

            if not res and code then
                -- if the request failed and a code is returned (not 403 and 429)
                if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                    savelog('forward_msg', code)
                end
            end
            if print_res_msg(res) then
                msgs_plus_plus(chat_id)
            else
                local obj_from = getChat(from_chat_id)
                local obj_to = getChat(chat_id)
                local sent_msg = { from = bot, chat = obj_to, text = text, forward = true }
                if obj_from.type == 'private' then
                    sent_msg.forward_from = obj_from
                elseif obj_from.type == 'channel' then
                    sent_msg.forward_from_chat = obj_from
                end
                print_msg(sent_msg)
            end
            return res, code
        end
    else
        return sendMessage(chat_id, langs[get_lang(chat_id)].noObject)
    end
end

function forwardMessage_SUDOERS(from_chat_id, message_id)
    for k, v in pairs(config.sudo_users) do
        if k ~= bot.userVersion.id then
            forwardMessage(k, from_chat_id, message_id, true)
        end
    end
end

function forwardLog(from_chat_id, message_id)
    if config.log_chat then
        forwardMessage(config.log_chat, from_chat_id, message_id, true)
    else
        forwardMessage_SUDOERS(from_chat_id, message_id, true)
    end
end

function sendKeyboard(chat_id, text, keyboard, parse_mode, reply_to_message_id, send_sound, no_log)
    if sendChatAction(chat_id, 'typing', true) then
        local url = BASE_URL .. '/sendMessage?chat_id=' .. chat_id
        if parse_mode then
            if parse_mode:lower() == 'html' then
                url = url .. '&parse_mode=HTML'
            elseif parse_mode:lower() == 'markdown' then
                url = url .. '&parse_mode=Markdown'
            else
                -- no parse_mode
            end
        end
        text = text:gsub('[Cc][Rr][Oo][Ss][Ss][Ee][Xx][Ee][Cc] ', '')
        url = url ..
        '&text=' .. URL.escape(text) ..
        '&disable_web_page_preview=true' ..
        '&reply_markup=' .. URL.escape(json:encode(keyboard))
        local reply = false
        if reply_to_message_id then
            url = url .. '&reply_to_message_id=' .. reply_to_message_id
            reply = true
        end
        if not send_sound then
            url = url .. '&disable_notification=true'
            -- messages are silent by default
        end
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local res, code = sendRequest(url, no_log)
            if not res and code then
                -- if the request failed and a code is returned (not 403 and 429)
                if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                    savelog('send_msg', code .. '\n' .. text)
                end
            end
            if print_res_msg(res) then
                msgs_plus_plus(chat_id)
            else
                local obj = getChat(chat_id)
                local sent_msg = { from = bot, chat = obj, text = text, cb = true, reply = reply }
                print_msg(sent_msg)
            end
            return res, code
            -- return false, and the code
        end
    else
        return sendMessage(chat_id, langs[get_lang(chat_id)].noObject)
    end
end

function answerCallbackQuery(callback_query_id, text, show_alert)
    local url = BASE_URL ..
    '/answerCallbackQuery?callback_query_id=' .. callback_query_id ..
    '&text=' .. URL.escape(text)
    if show_alert then
        url = url .. '&show_alert=true'
    end
    local res, code = sendRequest(url)
    if not print_res_msg(res) then
        local sent_msg = { from = bot, chat = fake_user_chat, text = text, cb = true }
        print_msg(sent_msg)
    end
    return res, code
end

function editMessageText(chat_id, message_id, text, keyboard, parse_mode)
    if sendChatAction(chat_id, 'typing', true) then
        local url = BASE_URL ..
        '/editMessageText?chat_id=' .. chat_id ..
        '&message_id=' .. message_id ..
        '&text=' .. URL.escape(text)
        if parse_mode then
            if parse_mode:lower() == 'html' then
                url = url .. '&parse_mode=HTML'
            elseif parse_mode:lower() == 'markdown' then
                url = url .. '&parse_mode=Markdown'
            else
                -- no parse_mode
            end
        end
        url = url .. '&disable_web_page_preview=true'
        if keyboard then
            url = url .. '&reply_markup=' .. URL.escape(json:encode(keyboard))
        end
        local res, code = sendRequest(url)

        if not res and code then
            -- if the request failed and a code is returned (not 403 and 429)
            if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                savelog('edit_msg', code .. '\n' .. text)
            end
            if code == 429 then
                printvardump(tab)
            end
        end
        if not print_res_msg(res) then
            local obj = getChat(chat_id)
            local sent_msg = { from = fake_user_chat, chat = obj, text = text, edited = true }
            print_msg(sent_msg)
        end
        return res, code
        -- return false, and the code
    end
end

function editMessageCaption(chat_id, message_id, caption, keyboard, parse_mode)
    if sendChatAction(chat_id, 'typing', true) then
        local url = BASE_URL ..
        '/editMessageCaption?chat_id=' .. chat_id ..
        '&message_id=' .. message_id ..
        '&caption=' .. URL.escape(caption)
        if parse_mode then
            if parse_mode:lower() == 'html' then
                url = url .. '&parse_mode=HTML'
            elseif parse_mode:lower() == 'markdown' then
                url = url .. '&parse_mode=Markdown'
            else
                -- no parse_mode
            end
        end
        url = url .. '&disable_web_page_preview=true'
        if keyboard then
            url = url .. '&reply_markup=' .. URL.escape(json:encode(keyboard))
        end
        local res, code = sendRequest(url)

        if not res and code then
            -- if the request failed and a code is returned (not 403 and 429)
            if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                savelog('edit_msg', code .. '\n' .. caption)
            end
            if code == 429 then
                printvardump(tab)
            end
        end
        if not print_res_msg(res) then
            local obj = getChat(chat_id)
            local sent_msg = { from = fake_user_chat, chat = obj, media = true, caption = caption, edited = true }
            print_msg(sent_msg)
        end
        return res, code
        -- return false, and the code
    end
end

function editMessageReplyMarkup(chat_id, message_id, reply_markup)
    if sendChatAction(chat_id, 'typing', true) then
        local url = BASE_URL .. '/editMessageReplyMarkup?chat_id=' .. chat_id ..
        '&message_id=' .. message_id ..
        '&reply_markup=' .. URL.escape(json:encode(reply_markup or empty_keyboard))
        local res, code = sendRequest(url)

        if not res and code then
            -- if the request failed and a code is returned (not 403 and 429)
            if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                savelog('edit_markup', code .. '\n' .. text)
            end
            if code == 429 then
                printvardump(tab)
            end
        end
        if not print_res_msg(res) then
            local obj = getChat(chat_id)
            local sent_msg = { from = fake_user_chat, chat = obj, text = text, edited = true }
            print_msg(sent_msg)
        end
        return res, code
        -- return false, and the code
    end
end

function sendChatAction(chat_id, action, no_log)
    -- Support actions are typing, upload_photo, record_video, upload_video, record_audio, upload_audio, upload_document, find_location, record_video_note, upload_video_note
    local url = BASE_URL ..
    '/sendChatAction?chat_id=' .. chat_id ..
    '&action=' .. action
    return sendRequest(url, no_log)
end

function deleteMessage(chat_id, message_id, no_log)
    if sendChatAction(chat_id, 'typing', true) then
        local url = BASE_URL ..
        '/deleteMessage?chat_id=' .. chat_id ..
        '&message_id=' .. message_id
        local res, code = sendRequest(url, no_log)

        if not res and code then
            -- if the request failed and a code is returned (not 403 and 429)
            if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                savelog('delete_message', code)
            end
        end
        return res, code
    end
end

function pinChatMessage(chat_id, message_id, send_sound)
    if sendChatAction(chat_id, 'typing', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL ..
            '/pinChatMessage?chat_id=' .. chat_id ..
            '&message_id=' .. message_id
            if not send_sound then
                url = url .. '&disable_notification=true'
                -- messages are silent by default
            end
            local res, code = sendRequest(url)

            if not res and code then
                -- if the request failed and a code is returned (not 403 and 429)
                if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                    savelog('pin_message', code)
                end
            end
            msgs_plus_plus(chat_id)
            return res
        end
    end
end

function unpinChatMessage(chat_id)
    if sendChatAction(chat_id, 'typing', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL ..
            '/unpinChatMessage?chat_id=' .. chat_id
            local res, code = sendRequest(url)

            if not res and code then
                -- if the request failed and a code is returned (not 403 and 429)
                if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                    savelog('unpin_message', code)
                end
            end
            msgs_plus_plus(chat_id)
            return res
        end
    end
end

function exportChatInviteLink(chat_id, no_log)
    if sendChatAction(chat_id, 'typing', true) then
        local url = BASE_URL .. '/exportChatInviteLink?chat_id=' .. chat_id
        local obj_link = sendRequest(url, no_log)
        if type(obj_link) == 'table' then
            if obj_link.result then
                obj_link = obj_link.result
                return obj_link
            end
        end
    end
end

function setChatTitle(chat_id, title)
    if sendChatAction(chat_id, 'typing', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL .. '/setChatTitle?chat_id=' .. chat_id ..
            '&title=' .. title
            local res, code = sendRequest(url)

            if not res and code then
                -- if the request failed and a code is returned (not 403 and 429)
                if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                    savelog('set_title', code)
                end
            end
            data[tostring(chat_id)].name = title
            save_data(config.moderation.data, data)
            msgs_plus_plus(chat_id)
            return res
        end
    end
end

-- supergroups/channels only
function setChatDescription(chat_id, description)
    if sendChatAction(chat_id, 'typing', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL .. '/setChatDescription?chat_id=' .. chat_id ..
            '&description=' .. description
            local res, code = sendRequest(url)

            if not res and code then
                -- if the request failed and a code is returned (not 403 and 429)
                if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                    savelog('set_description', code)
                end
            end
            msgs_plus_plus(chat_id)
            return res
        end
    end
end

function deleteChatPhoto(chat_id)
    if sendChatAction(chat_id, 'typing', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL .. '/deleteChatPhoto?chat_id=' .. chat_id
            local res, code = sendRequest(url)

            if not res and code then
                -- if the request failed and a code is returned (not 403 and 429)
                if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                    savelog('delete_photo', code)
                end
            end
            msgs_plus_plus(chat_id)
            return res
        end
    end
end

----------------------------By Id-----------------------------------------

function setChatPhotoId(chat_id, file_id)
    if sendChatAction(chat_id, 'upload_photo', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            if file_id then
                local download_link = getFile(file_id)
                if download_link.result then
                    download_link = download_link.result
                    download_link = 'https://api.telegram.org/file/bot' .. config.bot_api_key .. '/' .. download_link.file_path
                    local file_path = download_to_file(download_link, '/home/pi/AISashaAPI/data/tmp/' .. download_link:match('.*/(.*)'))
                    data[tostring(chat_id)].photo = file_id
                    save_data(config.moderation.data, data)
                    msgs_plus_plus(chat_id)
                    return setChatPhoto(chat_id, file_path)
                end
            else
                deleteChatPhoto(chat_id)
            end
        end
    end
end

function sendPhotoId(chat_id, file_id, caption, reply_to_message_id, send_sound)
    if sendChatAction(chat_id, 'upload_photo', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL ..
            '/sendPhoto?chat_id=' .. chat_id ..
            '&photo=' .. file_id
            if caption then
                if type(caption) == 'string' or type(caption) == 'number' then
                    caption = tostring(caption)
                    local caption_max = 200
                    local caption_len = string.len(caption)
                    local num_msg = math.ceil(caption_len / caption_max)
                    if num_msg > 1 then
                        sendMessage(chat_id, caption)
                    else
                        url = url .. '&caption=' .. URL.escape(caption)
                    end
                end
            end
            local reply = false
            if reply_to_message_id then
                url = url .. '&reply_to_message_id=' .. reply_to_message_id
                reply = true
            end
            if not send_sound then
                url = url .. '&disable_notification=true'
                -- messages are silent by default
            end
            local res, code = sendRequest(url)
            if not res and code then
                -- if the request failed and a code is returned (not 403 and 429)
                if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                    savelog('send_photo', code)
                end
            end
            if print_res_msg(res) then
                msgs_plus_plus(chat_id)
            else
                local obj = getChat(chat_id)
                local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'photo' }
                print_msg(sent_msg)
            end
            return res, code
        end
    end
end

function sendStickerId(chat_id, file_id, reply_to_message_id, send_sound)
    if sendChatAction(chat_id, 'typing', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL ..
            '/sendSticker?chat_id=' .. chat_id ..
            '&sticker=' .. file_id
            local reply = false
            if reply_to_message_id then
                url = url .. '&reply_to_message_id=' .. reply_to_message_id
                reply = true
            end
            if not send_sound then
                url = url .. '&disable_notification=true'
                -- messages are silent by default
            end
            local res, code = sendRequest(url)
            if not res and code then
                -- if the request failed and a code is returned (not 403 and 429)
                if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                    savelog('send_sticker', code)
                end
            end
            if print_res_msg(res) then
                msgs_plus_plus(chat_id)
            else
                local obj = getChat(chat_id)
                local sent_msg = { from = bot, chat = obj, reply = reply, media = true, media_type = 'sticker' }
                print_msg(sent_msg)
            end
            return res, code
        end
    end
end

function sendVoiceId(chat_id, file_id, caption, reply_to_message_id, send_sound)
    if sendChatAction(chat_id, 'record_audio', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL ..
            '/sendVoice?chat_id=' .. chat_id ..
            '&voice=' .. file_id
            if caption then
                if type(caption) == 'string' or type(caption) == 'number' then
                    caption = tostring(caption)
                    local caption_max = 200
                    local caption_len = string.len(caption)
                    local num_msg = math.ceil(caption_len / caption_max)
                    if num_msg > 1 then
                        sendMessage(chat_id, caption)
                    else
                        url = url .. '&caption=' .. URL.escape(caption)
                    end
                end
            end
            local reply = false
            if reply_to_message_id then
                url = url .. '&reply_to_message_id=' .. reply_to_message_id
                reply = true
            end
            if not send_sound then
                url = url .. '&disable_notification=true'
                -- messages are silent by default
            end
            local res, code = sendRequest(url)
            if not res and code then
                -- if the request failed and a code is returned (not 403 and 429)
                if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                    savelog('send_voice', code)
                end
            end
            if print_res_msg(res) then
                msgs_plus_plus(chat_id)
            else
                local obj = getChat(chat_id)
                local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'voice_note' }
                print_msg(sent_msg)
            end
            return res, code
        end
    end
end

function sendAudioId(chat_id, file_id, caption, reply_to_message_id, send_sound)
    if sendChatAction(chat_id, 'upload_audio', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL ..
            '/sendAudio?chat_id=' .. chat_id ..
            '&audio=' .. file_id
            if caption then
                if type(caption) == 'string' or type(caption) == 'number' then
                    caption = tostring(caption)
                    local caption_max = 200
                    local caption_len = string.len(caption)
                    local num_msg = math.ceil(caption_len / caption_max)
                    if num_msg > 1 then
                        sendMessage(chat_id, caption)
                    else
                        url = url .. '&caption=' .. URL.escape(caption)
                    end
                end
            end
            local reply = false
            if reply_to_message_id then
                url = url .. '&reply_to_message_id=' .. reply_to_message_id
                reply = true
            end
            if not send_sound then
                url = url .. '&disable_notification=true'
                -- messages are silent by default
            end
            local res, code = sendRequest(url)
            if not res and code then
                -- if the request failed and a code is returned (not 403 and 429)
                if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                    savelog('send_audio', code)
                end
            end
            if print_res_msg(res) then
                msgs_plus_plus(chat_id)
            else
                local obj = getChat(chat_id)
                local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'audio' }
                print_msg(sent_msg)
            end
            return res, code
        end
    end
end

function sendVideoNoteId(chat_id, file_id, reply_to_message_id, send_sound)
    if sendChatAction(chat_id, 'record_video_note', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL ..
            '/sendVideoNote?chat_id=' .. chat_id ..
            '&video_note=' .. file_id
            local reply = false
            if reply_to_message_id then
                url = url .. '&reply_to_message_id=' .. reply_to_message_id
                reply = true
            end
            if not send_sound then
                url = url .. '&disable_notification=true'
                -- messages are silent by default
            end
            local res, code = sendRequest(url)
            if not res and code then
                -- if the request failed and a code is returned (not 403 and 429)
                if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                    savelog('send_video_note', code)
                end
            end
            if print_res_msg(res) then
                msgs_plus_plus(chat_id)
            else
                local obj = getChat(chat_id)
                local sent_msg = { from = bot, chat = obj, reply = reply, media = true, media_type = 'video_note' }
                print_msg(sent_msg)
            end
            return res, code
        end
    end
end

function sendVideoId(chat_id, file_id, caption, reply_to_message_id, send_sound)
    if sendChatAction(chat_id, 'upload_video', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL ..
            '/sendVideo?chat_id=' .. chat_id ..
            '&video=' .. file_id
            if caption then
                if type(caption) == 'string' or type(caption) == 'number' then
                    caption = tostring(caption)
                    local caption_max = 200
                    local caption_len = string.len(caption)
                    local num_msg = math.ceil(caption_len / caption_max)
                    if num_msg > 1 then
                        sendMessage(chat_id, caption)
                    else
                        url = url .. '&caption=' .. URL.escape(caption)
                    end
                end
            end
            local reply = false
            if reply_to_message_id then
                url = url .. '&reply_to_message_id=' .. reply_to_message_id
                reply = true
            end
            if not send_sound then
                url = url .. '&disable_notification=true'
                -- messages are silent by default
            end
            local res, code = sendRequest(url)
            if not res and code then
                -- if the request failed and a code is returned (not 403 and 429)
                if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                    savelog('send_video', code)
                end
            end
            if print_res_msg(res) then
                msgs_plus_plus(chat_id)
            else
                local obj = getChat(chat_id)
                local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'video' }
                print_msg(sent_msg)
            end
            return res, code
        end
    end
end

function sendDocumentId(chat_id, file_id, caption, reply_to_message_id, send_sound)
    if sendChatAction(chat_id, 'upload_document', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL ..
            '/sendDocument?chat_id=' .. chat_id ..
            '&document=' .. file_id
            if caption then
                if type(caption) == 'string' or type(caption) == 'number' then
                    caption = tostring(caption)
                    local caption_max = 200
                    local caption_len = string.len(caption)
                    local num_msg = math.ceil(caption_len / caption_max)
                    if num_msg > 1 then
                        sendMessage(chat_id, caption)
                    else
                        url = url .. '&caption=' .. URL.escape(caption)
                    end
                end
            end
            local reply = false
            if reply_to_message_id then
                url = url .. '&reply_to_message_id=' .. reply_to_message_id
                reply = true
            end
            if not send_sound then
                url = url .. '&disable_notification=true'
                -- messages are silent by default
            end
            local res, code = sendRequest(url)
            if not res and code then
                -- if the request failed and a code is returned (not 403 and 429)
                if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                    savelog('send_document', code)
                end
            end
            if print_res_msg(res) then
                msgs_plus_plus(chat_id)
            else
                local obj = getChat(chat_id)
                local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'document' }
                print_msg(sent_msg)
            end
            return res, code
        end
    end
end

function sendAnimationId(chat_id, file_id, caption, reply_to_message_id, send_sound)
    if sendChatAction(chat_id, 'upload_document', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL ..
            '/sendAnimation?chat_id=' .. chat_id ..
            '&animation=' .. file_id
            if caption then
                if type(caption) == 'string' or type(caption) == 'number' then
                    caption = tostring(caption)
                    local caption_max = 200
                    local caption_len = string.len(caption)
                    local num_msg = math.ceil(caption_len / caption_max)
                    if num_msg > 1 then
                        sendMessage(chat_id, caption)
                    else
                        url = url .. '&caption=' .. URL.escape(caption)
                    end
                end
            end
            local reply = false
            if reply_to_message_id then
                url = url .. '&reply_to_message_id=' .. reply_to_message_id
                reply = true
            end
            if not send_sound then
                url = url .. '&disable_notification=true'
                -- messages are silent by default
            end
            local res, code = sendRequest(url)
            if not res and code then
                -- if the request failed and a code is returned (not 403 and 429)
                if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                    savelog('send_animation', code)
                end
            end
            if print_res_msg(res) then
                msgs_plus_plus(chat_id)
            else
                local obj = getChat(chat_id)
                local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'gif' }
                print_msg(sent_msg)
            end
            return res, code
        end
    end
end

----------------------------To curl--------------------------------------------

function setChatPhoto(chat_id, photo)
    if sendChatAction(chat_id, 'upload_photo', true) then
        local url = BASE_URL .. '/setChatPhoto'
        curl_context:setopt_url(url)
        local form = curl.form()
        form:add_content("chat_id", chat_id)
        form:add_file("photo", photo)
        local data = { }
        local c = curl_context:setopt_writefunction(table.insert, data):setopt_httppost(form):perform():reset()
        local obj = getChat(chat_id)
        local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'photo' }
        print_msg(sent_msg)
        return table.concat(data), c:getinfo_response_code()
    end
end

function sendDocument_SUDOERS(document)
    for k, v in pairs(config.sudo_users) do
        if k ~= bot.userVersion.id then
            pyrogramUpload(k, "document", document)
        end
    end
end

-- should be updated with live_period and stoplivelocation and editlivelocation
function sendLocation(chat_id, latitude, longitude, reply_to_message_id, send_sound)
    if sendChatAction(chat_id, 'find_location', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL ..
            '/sendLocation?chat_id=' .. chat_id ..
            '&latitude=' .. latitude ..
            '&longitude=' .. longitude
            local reply = false
            if reply_to_message_id then
                url = url .. '&reply_to_message_id=' .. reply_to_message_id
                reply = true
            end
            if not send_sound then
                url = url .. '&disable_notification=true'
                -- messages are silent by default
            end
            local res, code = sendRequest(url)

            if not res and code then
                -- if the request failed and a code is returned (not 403 and 429)
                if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                    savelog('send_location', code)
                end
            end
            if print_res_msg(res) then
                msgs_plus_plus(chat_id)
            else
                local obj = getChat(chat_id)
                local sent_msg = { from = bot, chat = obj, reply = reply, media = true, media_type = 'location' }
                print_msg(sent_msg)
            end
            return res, code
        end
    end
end
-- *** END API FUNCTIONS ***

-- *** START CURL FUNCTIONS ***
function sendPhoto(chat_id, photo, caption, reply_to_message_id, send_sound)
    if sendChatAction(chat_id, 'upload_photo', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL .. '/sendPhoto'
            curl_context:setopt_url(url)
            local form = curl.form()
            form:add_content("chat_id", chat_id)
            form:add_file("photo", photo)
            local reply = false
            if reply_to_message_id then
                form:add_content("reply_to_message_id", reply_to_message_id)
                reply = true
            end
            if caption then
                form:add_content("caption", caption)
            end
            if not send_sound then
                form:add_content("disable_notification", "true")
                -- messages are silent by default
            end
            local data = { }
            local c = curl_context:setopt_writefunction(table.insert, data):setopt_httppost(form):perform():reset()
            local obj = getChat(chat_id)
            local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'photo' }
            print_msg(sent_msg)
            msgs_plus_plus(chat_id)
            return table.concat(data), c:getinfo_response_code()
        end
    end
end

function sendSticker(chat_id, sticker, reply_to_message_id, send_sound)
    if sendChatAction(chat_id, 'typing', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL .. '/sendSticker'
            curl_context:setopt_url(url)
            local form = curl.form()
            form:add_content("chat_id", chat_id)
            form:add_file("sticker", sticker)
            local reply = false
            if reply_to_message_id then
                form:add_content("reply_to_message_id", reply_to_message_id)
                reply = true
            end
            if not send_sound then
                form:add_content("disable_notification", "true")
                -- messages are silent by default
            end
            local data = { }
            local c = curl_context:setopt_writefunction(table.insert, data):setopt_httppost(form):perform():reset()
            local obj = getChat(chat_id)
            local sent_msg = { from = bot, chat = obj, reply = reply, media = true, media_type = 'sticker' }
            print_msg(sent_msg)
            msgs_plus_plus(chat_id)
            return table.concat(data), c:getinfo_response_code()
        end
    end
end

function sendVoice(chat_id, voice, caption, reply_to_message_id, duration, send_sound)
    if sendChatAction(chat_id, 'record_audio', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL .. '/sendVoice'
            curl_context:setopt_url(url)
            local form = curl.form()
            form:add_content("chat_id", chat_id)
            form:add_file("voice", voice)
            local reply = false
            if reply_to_message_id then
                form:add_content("reply_to_message_id", reply_to_message_id)
                reply = true
            end
            if caption then
                form:add_content("caption", caption)
            end
            if duration then
                form:add_content("duration", duration)
            end
            if not send_sound then
                form:add_content("disable_notification", "true")
                -- messages are silent by default
            end
            local data = { }
            local c = curl_context:setopt_writefunction(table.insert, data):setopt_httppost(form):perform():reset()
            local obj = getChat(chat_id)
            local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'voice_note' }
            print_msg(sent_msg)
            msgs_plus_plus(chat_id)
            return table.concat(data), c:getinfo_response_code()
        end
    end
end

function sendAudio(chat_id, audio, caption, reply_to_message_id, duration, performer, title, send_sound)
    if sendChatAction(chat_id, 'upload_audio', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL .. '/sendAudio'
            curl_context:setopt_url(url)
            local form = curl.form()
            form:add_content("chat_id", chat_id)
            form:add_file("audio", audio)
            local reply = false
            if reply_to_message_id then
                form:add_content("reply_to_message_id", reply_to_message_id)
                reply = true
            end
            if caption then
                form:add_content("caption", caption)
            end
            if duration then
                form:add_content("duration", duration)
            end
            if performer then
                form:add_content("performer", performer)
            end
            if title then
                form:add_content("title", title)
            end
            if not send_sound then
                form:add_content("disable_notification", "true")
                -- messages are silent by default
            end
            local data = { }
            local c = curl_context:setopt_writefunction(table.insert, data):setopt_httppost(form):perform():reset()
            local obj = getChat(chat_id)
            local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'audio' }
            print_msg(sent_msg)
            msgs_plus_plus(chat_id)
            return table.concat(data), c:getinfo_response_code()
        end
    end
end

function sendVideo(chat_id, video, reply_to_message_id, caption, duration, performer, title, send_sound)
    if sendChatAction(chat_id, 'upload_video', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL .. '/sendVideo'
            curl_context:setopt_url(url)
            local form = curl.form()
            form:add_content("chat_id", chat_id)
            form:add_file("video", video)
            local reply = false
            if reply_to_message_id then
                form:add_content("reply_to_message_id", reply_to_message_id)
                reply = true
            end
            if caption then
                form:add_content("caption", caption)
            end
            if duration then
                form:add_content("duration", duration)
            end
            if performer then
                form:add_content("performer", performer)
            end
            if title then
                form:add_content("title", title)
            end
            if not send_sound then
                form:add_content("disable_notification", "true")
                -- messages are silent by default
            end
            local data = { }
            local c = curl_context:setopt_writefunction(table.insert, data):setopt_httppost(form):perform():reset()
            local obj = getChat(chat_id)
            local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'video' }
            print_msg(sent_msg)
            msgs_plus_plus(chat_id)
            return table.concat(data), c:getinfo_response_code()
        end
    end
end

function sendVideoNote(chat_id, video_note, reply_to_message_id, duration, length, send_sound)
    if sendChatAction(chat_id, 'record_video_note', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL .. '/sendVideoNote'
            curl_context:setopt_url(url)
            local form = curl.form()
            form:add_content("chat_id", chat_id)
            form:add_file("video_note", video_note)
            local reply = false
            if reply_to_message_id then
                form:add_content("reply_to_message_id", reply_to_message_id)
                reply = true
            end
            if duration then
                form:add_content("duration", duration)
            end
            if length then
                form:add_content("length", length)
            end
            if not send_sound then
                form:add_content("disable_notification", "true")
                -- messages are silent by default
            end
            local data = { }
            local c = curl_context:setopt_writefunction(table.insert, data):setopt_httppost(form):perform():reset()
            local obj = getChat(chat_id)
            local sent_msg = { from = bot, chat = obj, reply = reply, media = true, media_type = 'video_note' }
            print_msg(sent_msg)
            msgs_plus_plus(chat_id)
            return table.concat(data), c:getinfo_response_code()
        end
    end
end

function sendDocument(chat_id, document, caption, reply_to_message_id, send_sound)
    if sendChatAction(chat_id, 'upload_document', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL .. '/sendDocument'
            curl_context:setopt_url(url)
            local form = curl.form()
            form:add_content("chat_id", chat_id)
            form:add_file("document", document)
            local reply = false
            if reply_to_message_id then
                form:add_content("reply_to_message_id", reply_to_message_id)
                reply = true
            end
            if caption then
                form:add_content("caption", caption)
            end
            if not send_sound then
                form:add_content("disable_notification", "true")
                -- messages are silent by default
            end
            local data = { }
            local c = curl_context:setopt_writefunction(table.insert, data):setopt_httppost(form):perform():reset()
            local obj = getChat(chat_id)
            local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'document' }
            print_msg(sent_msg)
            msgs_plus_plus(chat_id)
            return table.concat(data), c:getinfo_response_code()
        end
    end
end

function sendAnimation(chat_id, animation, caption, reply_to_message_id, send_sound)
    if sendChatAction(chat_id, 'upload_document', true) then
        if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
            local url = BASE_URL .. '/sendAnimation'
            curl_context:setopt_url(url)
            local form = curl.form()
            form:add_content("chat_id", chat_id)
            form:add_file("animation", animation)
            local reply = false
            if reply_to_message_id then
                form:add_content("reply_to_message_id", reply_to_message_id)
                reply = true
            end
            if caption then
                form:add_content("caption", caption)
            end
            if not send_sound then
                form:add_content("disable_notification", "true")
                -- messages are silent by default
            end
            local data = { }
            local c = curl_context:setopt_writefunction(table.insert, data):setopt_httppost(form):perform():reset()
            local obj = getChat(chat_id)
            local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'document' }
            print_msg(sent_msg)
            msgs_plus_plus(chat_id)
            return table.concat(data), c:getinfo_response_code()
        end
    end
end
-- *** END CURL FUNCTIONS ***

-- *** START PYROGRAM FUNCTIONS ***
function pyrogramDownload(chat_id, file_id, file_name)
    print(chat_id, file_id, file_name)
    -- async, if you want it sync => os.execute("blabla")
    io.popen('python3.7 pyrogramThings.py DOWNLOAD ' ..
    chat_id .. ' ' ..
    file_id .. ' "' ..
    (file_name or("/data/tmp/" .. file_id)):gsub('"', '\\"') .. '" "' ..
    langs[get_lang(chat_id)].fileDownloadedTo .. tostring(file_name or("/data/tmp/" .. file_id)):gsub('"', '\\"') .. '"')
    msgs_plus_plus(chat_id)
end

function pyrogramUpload(chat_id, media_type, file_path, reply_to_message_id, caption)
    if check_chat_msgs(chat_id) <= 19 and check_total_msgs() <= 29 then
        print(chat_id, media_type, file_path, reply_to_message_id, caption)
        msgs_plus_plus(chat_id)
        -- async, if you want it sync => os.execute("blabla")
        io.popen('python3.7 pyrogramThings.py UPLOAD ' ..
        chat_id .. ' ' ..
        media_type .. ' "' ..
        file_path:gsub('"', '\\"') .. '" "' ..
        (reply_to_message_id or "") .. '" "' ..
        (caption or ""):gsub('"', '\\"') .. '" "' ..
        langs[get_lang(chat_id)].cantSendAs .. '"')
    end
end
-- *** END PYROGRAM FUNCTIONS ***

function saveUsername(obj, chat_id)
    if obj then
        if type(obj) == 'table' then
            if obj.username then
                redis_hset_something('bot:usernames', '@' .. obj.username:lower(), obj.id)
                if obj.type ~= 'bot' and obj.type ~= 'private' and obj.type ~= 'user' then
                    if chat_id then
                        redis_hset_something('bot:usernames:' .. chat_id, '@' .. obj.username:lower(), obj.id)
                    end
                end
            end
        end
    end
end

-- call this to get the chat
function getChat(id_or_username, no_log)
    if not id_or_username or tostring(id_or_username) == '' then
        return
    end
    id_or_username = tostring(id_or_username):gsub(' ', '')
    if not(string.match(id_or_username, '^%-?%d') or string.match(id_or_username, '^%*%d')) then
        id_or_username = '@' .. id_or_username:gsub('@', '')
    end
    if not string.match(id_or_username, '^%*%d') then
        local obj = nil
        local ok = false
        -- API
        if not ok then
            if not tostring(id_or_username):match('^@') then
                -- getChat if not a username
                obj = APIgetChat(id_or_username, true)
                if type(obj) == 'table' then
                    if obj.result then
                        obj = obj.result
                        ok = true
                        saveUsername(obj)
                    end
                end
            end
        end
        -- redis db then API
        if not ok then
            local hash = 'bot:usernames'
            local stored = nil
            if type(id_or_username) == 'string' then
                stored = redis_hget_something(hash, id_or_username:lower())
            else
                stored = redis_hget_something(hash, id_or_username)
            end
            if stored then
                -- check API
                obj = APIgetChat(stored, no_log)
                if type(obj) == 'table' then
                    if obj.result then
                        obj = obj.result
                        ok = true
                        saveUsername(obj)
                    end
                end
            else
                -- check API if not in redis db, it could be a channel username that was not checked before
                obj = APIgetChat(id_or_username, no_log)
                if type(obj) == 'table' then
                    if obj.result then
                        obj = obj.result
                        ok = true
                        saveUsername(obj)
                    end
                end
            end
        end
        if ok then
            if obj.type == 'private' then
                return adjust_user(obj)
            elseif obj.type == 'group' then
                return adjust_group(obj)
            elseif obj.type == 'supergroup' then
                return adjust_supergroup(obj)
            elseif obj.type == 'channel' then
                return adjust_channel(obj)
            end
        end
        return nil
    else
        local fake_user = { first_name = 'FAKECOMMAND', last_name = 'FAKECOMMAND', print_name = 'FAKECOMMAND', username = '@FAKECOMMAND', id = id_or_username, type = 'fake' }
        return fake_user
    end
end

function sudoInChat(chat_id)
    for k, v in pairs(config.sudo_users) do
        if k ~= bot.userVersion.id then
            local member = getChatMember(chat_id, k)
            if type(member) == 'table' then
                if member.ok and member.result then
                    if member.result.status == 'creator' or member.result.status == 'administrator' or member.result.status == 'member' or member.status == 'restricted' then
                        return true
                    end
                end
            end
        end
    end
    return false
end

function userVersionInChat(chat_id)
    local member = getChatMember(chat_id, bot.userVersion.id)
    if type(member) == 'table' then
        if member.ok and member.result then
            if member.result.status == 'creator' or member.result.status == 'administrator' or member.result.status == 'member' or member.status == 'restricted' then
                return true, member.result.status
            end
        end
    end
    return false
end

function userInChat(chat_id, user_id, no_log)
    user_id = tostring(user_id):gsub(' ', '')
    local member = getChatMember(chat_id, user_id, no_log)
    if type(member) == 'table' then
        if member.ok and member.result then
            if member.result.status == 'creator' or member.result.status == 'administrator' or member.result.status == 'member' or member.status == 'restricted' then
                return true
            end
        end
    end
end

function getUserStatus(chat_id, user_id, no_log)
    user_id = tostring(user_id):gsub(' ', '')
    local res = getChatMember(chat_id, user_id, no_log)
    if type(res) == 'table' then
        if res.ok and res.result then
            return res.result.status
        end
    end
end

-- call this to restrict
function restrictUser(executer, target, chat_id, restrictions, until_date, no_notice)
    local unrestrict = true
    for key, var in pairs(restrictions) do
        if not restrictions[key] then
            unrestrict = false
        end
    end

    if unrestrict then
        return unrestrictUser(executer, target, chat_id, no_notice)
    else
        if sendChatAction(chat_id, 'typing', true) then
            local lang = get_lang(chat_id)
            if isWhitelisted(chat_id, target) then
                savelog(chat_id, "[" .. executer .. "] tried to restrict user " .. target .. " that is whitelisted")
                return langs[lang].cantRestrictWhitelisted
            end
            if compare_ranks(executer, target, chat_id, false, true) then
                if restrictChatMember(chat_id, target, restrictions, until_date) then
                    -- if the user has been restricted, then...
                    globalCronTable.punishedTable[tostring(chat_id)] = globalCronTable.punishedTable[tostring(chat_id)] or { }
                    globalCronTable.punishedTable[tostring(chat_id)][tostring(target)] = true
                    local all = true
                    local text = ''
                    for k, v in pairs(restrictions) do
                        if not restrictions[k] then
                            text = text .. reverseRestrictionsDictionary[k:lower()] .. ' '
                        else
                            all = false
                        end
                    end
                    savelog(chat_id, "[" .. executer .. "] restricted user " .. target .. ' ' .. text)
                    if arePMNoticesEnabled(target, chat_id) and not no_notice then
                        sendMessage(target, langs[lang].youHaveBeenRestrictedUnrestricted .. database[tostring(chat_id)].print_name .. '\n' .. langs[lang].restrictions ..
                        langs[lang].restrictionSendMessages .. tostring(restrictions.can_send_messages) ..
                        langs[lang].restrictionSendMediaMessages .. tostring(restrictions.can_send_media_messages) ..
                        langs[lang].restrictionSendOtherMessages .. tostring(restrictions.can_send_other_messages) ..
                        langs[lang].restrictionAddWebPagePreviews .. tostring(restrictions.can_add_web_page_previews))
                    end
                    if all then
                        text = langs[get_lang(chat_id)].allRestrictionsApplied
                    end
                    text = '\n' .. text
                    local temprestrict = false
                    if until_date then
                        if os.time() + until_date >= 30 or os.time() + until_date <= 31622400 then
                            temprestrict = true
                        end
                    end
                    if temprestrict then
                        return langs[get_lang(chat_id)].user .. target .. langs[get_lang(chat_id)].restricted .. text ..
                        '\n#chat' .. tostring(chat_id):gsub("-", "") .. ' #user' .. target .. ' #executer' .. executer .. ' #temprestrict ' .. langs[get_lang(chat_id)].untilWord .. ' ' .. os.date('%Y-%m-%d %H:%M:%S', os.time() + until_date)
                    else
                        return langs[get_lang(chat_id)].user .. target .. langs[get_lang(chat_id)].restricted .. text ..
                        '\n#chat' .. tostring(chat_id):gsub("-", "") .. ' #user' .. target .. ' #executer' .. executer .. ' #restrict'
                    end
                else
                    return langs[lang].checkMyPermissions
                end
            else
                savelog(chat_id, "[" .. executer .. "] tried to restrict user " .. target .. " require higher rank")
                return langs[get_lang(chat_id)].require_rank
            end
        end
    end
end

-- call this to unrestrict
function unrestrictUser(executer, target, chat_id, no_notice)
    if sendChatAction(chat_id, 'typing', true) then
        local lang = get_lang(chat_id)
        if compare_ranks(executer, target, chat_id, false, true) then
            if unrestrictChatMember(chat_id, target) then
                savelog(chat_id, "[" .. executer .. "] unrestricted user " .. target)
                if arePMNoticesEnabled(target, chat_id) and not no_notice then
                    sendMessage(target, langs[lang].youHaveBeenRestrictedUnrestricted .. database[tostring(chat_id)].print_name .. '\n' .. langs[lang].restrictions ..
                    langs[lang].restrictionSendMessages .. tostring(true) ..
                    langs[lang].restrictionSendMediaMessages .. tostring(true) ..
                    langs[lang].restrictionSendOtherMessages .. tostring(true) ..
                    langs[lang].restrictionAddWebPagePreviews .. tostring(true))
                end
                return langs[get_lang(chat_id)].user .. target .. langs[get_lang(chat_id)].unrestricted ..
                '\n#chat' .. tostring(chat_id):gsub("-", "") .. ' #user' .. target .. ' #executer' .. executer .. ' #unrestrict'
            else
                return langs[lang].checkMyPermissions
            end
        else
            savelog(chat_id, "[" .. executer .. "] tried to unrestrict user " .. target .. " require higher rank")
            return langs[get_lang(chat_id)].require_rank
        end
    end
end

-- call this to kick
function kickUser(executer, target, chat_id, reason, no_notice)
    target = tostring(target):gsub(' ', '')
    if sendChatAction(chat_id, 'typing', true) then
        if isWhitelisted(chat_id, target) then
            savelog(chat_id, "[" .. executer .. "] tried to kick user " .. target .. " that is whitelisted")
            return langs[get_lang(chat_id)].cantKickWhitelisted
        end
        if compare_ranks(executer, target, chat_id, false, true) then
            -- try to kick
            local res, code = kickChatMember(target, chat_id, 45, true)

            if res then
                -- if the user has been kicked, then...
                globalCronTable.punishedTable[tostring(chat_id)] = globalCronTable.punishedTable[tostring(chat_id)] or { }
                globalCronTable.punishedTable[tostring(chat_id)][tostring(target)] = true
                savelog(chat_id, "[" .. executer .. "] kicked user " .. target)
                redis_hincr('bot:general', 'kick', 1)
                local obj_chat = getChat(chat_id, true)
                local obj_remover = getChat(executer, true)
                local obj_removed = getChat(target, true)
                local sent_msg = { from = bot, chat = obj_chat, remover = obj_remover or unknown_user, removed = obj_removed or unknown_user, text = text, service = true, service_type = 'chat_del_user' }
                print_msg(sent_msg)
                if arePMNoticesEnabled(target, chat_id) and not no_notice then
                    local text = langs[get_lang(target)].youHaveBeenKicked .. obj_chat.title
                    if reason then
                        if reason:gsub(' ', '') ~= '' then
                            text = text .. '\n' .. langs[get_lang(target)].reason .. reason
                        end
                    end
                    sendMessage(target, text)
                end
                return langs.phrases.banhammer[math.random(#langs.phrases.banhammer)] ..
                '\n#chat' .. tostring(chat_id):gsub("-", "") .. ' #user' .. target .. ' #executer' .. executer .. ' #kick ' ..(reason or '')
            else
                return code2text(code, get_lang(chat_id))
            end
        else
            savelog(chat_id, "[" .. executer .. "] tried to kick user " .. target .. " require higher rank")
            return langs[get_lang(chat_id)].require_rank
        end
    end
end

function preBanUser(executer, target, chat_id, reason)
    target = tostring(target):gsub(' ', '')
    if isWhitelisted(chat_id, target) then
        savelog(chat_id, "[" .. executer .. "] tried to ban user " .. target .. " that is whitelisted")
        return langs[get_lang(chat_id)].cantKickWhitelisted
    end
    if compare_ranks(executer, target, chat_id, true, true) then
        -- try to kick. "code" is already specific
        savelog(chat_id, "[" .. executer .. "] banned user " .. target)
        redis_hincr('bot:general', 'ban', 1)
        -- general: save how many kicks
        local hash = 'banned:' .. chat_id
        redis_hset_something(hash, tostring(target), tostring(target))
        return langs[get_lang(chat_id)].user .. target .. langs[get_lang(chat_id)].banned ..
        '\n' .. langs.phrases.banhammer[math.random(#langs.phrases.banhammer)] ..
        '\n#chat' .. tostring(chat_id):gsub("-", "") .. ' #user' .. target .. ' #executer' .. executer .. ' #preban #ban ' ..(reason or '')
    else
        savelog(chat_id, "[" .. executer .. "] tried to ban user " .. target .. " require higher rank")
        return langs[get_lang(chat_id)].require_rank
    end
end

-- call this to ban
function banUser(executer, target, chat_id, reason, until_date, no_notice)
    target = tostring(target):gsub(' ', '')
    if sendChatAction(chat_id, 'typing', true) then
        if isWhitelisted(chat_id, target) then
            savelog(chat_id, "[" .. executer .. "] tried to ban user " .. target .. " that is whitelisted")
            return langs[get_lang(chat_id)].cantKickWhitelisted
        end
        if compare_ranks(executer, target, chat_id, false, true) then
            -- try to kick. "code" is already specific
            local res, code = kickChatMember(target, chat_id, until_date, true)
            if res then
                -- if the user has been banned, then...
                globalCronTable.punishedTable[tostring(chat_id)] = globalCronTable.punishedTable[tostring(chat_id)] or { }
                globalCronTable.punishedTable[tostring(chat_id)][tostring(target)] = true
                if not tostring(chat_id):starts('-100') then
                    local hash = 'banned:' .. chat_id
                    redis_hset_something(hash, tostring(target), tostring(target))
                end
                savelog(chat_id, "[" .. executer .. "] banned user " .. target)
                redis_hincr('bot:general', 'ban', 1)
                -- general: save how many kicks
                local obj_chat = getChat(chat_id, true)
                local obj_remover = getChat(executer, true)
                local obj_removed = getChat(target, true)
                local sent_msg = { from = bot, chat = obj_chat, remover = obj_remover or unknown_user, removed = obj_removed or unknown_user, text = text, service = true, service_type = 'chat_del_user' }
                print_msg(sent_msg)
                if arePMNoticesEnabled(target, chat_id) and not no_notice then
                    local text = langs[get_lang(target)].youHaveBeenBanned .. obj_chat.title
                    if reason then
                        if reason:gsub(' ', '') ~= '' then
                            text = text .. '\n' .. langs[get_lang(target)].reason .. reason
                        end
                    end
                    sendMessage(target, text)
                end
                local tempban = false
                if until_date then
                    if os.time() + until_date >= 30 or os.time() + until_date <= 31622400 then
                        tempban = true
                    end
                end
                if tempban then
                    return langs[get_lang(chat_id)].user .. target .. langs[get_lang(chat_id)].banned ..
                    '\n' .. langs.phrases.banhammer[math.random(#langs.phrases.banhammer)] ..
                    '\n#chat' .. tostring(chat_id):gsub("-", "") .. ' #user' .. target .. ' #executer' .. executer .. ' #tempban ' .. langs[get_lang(chat_id)].untilWord .. ' ' .. os.date('%Y-%m-%d %H:%M:%S', os.time() + until_date) ..(reason or '')
                else
                    return langs[get_lang(chat_id)].user .. target .. langs[get_lang(chat_id)].banned ..
                    '\n' .. langs.phrases.banhammer[math.random(#langs.phrases.banhammer)] ..
                    '\n#chat' .. tostring(chat_id):gsub("-", "") .. ' #user' .. target .. ' #executer' .. executer .. ' #ban ' ..(reason or '')
                end
            else
                return preBanUser(executer, target, chat_id, reason)
            end
        else
            savelog(chat_id, "[" .. executer .. "] tried to ban user " .. target .. " require higher rank")
            return langs[get_lang(chat_id)].require_rank
        end
    end
end

-- call this to unban
function unbanUser(executer, target, chat_id, reason, no_notice)
    target = tostring(target):gsub(' ', '')
    if compare_ranks(executer, target, chat_id, false, true) then
        savelog(chat_id, "[" .. target .. "] unbanned")
        -- remove from the local banlist
        local hash = 'banned:' .. chat_id
        redis_hdelsrem_something(hash, tostring(target))
        if getChat(target, true) and not is_super_group( { chat = { id = chat_id } }) then
            local res, code = unbanChatMember(target, chat_id)
        end
        if arePMNoticesEnabled(target, chat_id) and not no_notice then
            local text = langs[get_lang(target)].youHaveBeenUnbanned .. database[tostring(chat_id)].print_name
            if reason then
                if reason:gsub(' ', '') ~= '' then
                    text = text .. '\n' .. langs[get_lang(target)].reason .. reason
                end
            end
            sendMessage(target, text)
        end
        return langs[get_lang(chat_id)].user .. target .. langs[get_lang(chat_id)].unbanned ..
        '\n#chat' .. tostring(chat_id):gsub("-", "") .. ' #user' .. target .. ' #executer' .. executer .. ' #unban ' ..(reason or '')
    else
        savelog(chat_id, "[" .. executer .. "] tried to unban user " .. target .. " require higher rank")
        return langs[get_lang(chat_id)].require_rank
    end
end

-- Check if user_id is banned in chat_id or not
function isBanned(user_id, chat_id)
    user_id = tostring(user_id):gsub(' ', '')
    -- Save on redis
    local hash = 'banned:' .. chat_id
    local banned = redis_sis_stored(hash, tostring(user_id))
    return banned or false
end

-- Returns chat_id ban list
function banList(chat_id)
    local hash = 'banned:' .. chat_id
    local list = redis_get_something(hash) or { }
    local text = langs[get_lang(chat_id)].banListStart
    for k, v in pairs(list) do
        local user_info = redis_get_something('user:' .. v)
        if user_info and user_info.print_name then
            local print_name = string.gsub(user_info.print_name, "_", " ")
            local print_name = string.gsub(print_name, "?", "")
            text = text .. k .. " - " .. print_name .. " [" .. v .. "]\n"
        else
            text = text .. k .. " - " .. v .. "\n"
        end
    end
    return text
end

-- Global ban
function gbanUser(user_id, no_log, no_notice)
    local lang = get_lang(user_id)
    user_id = tostring(user_id):gsub(' ', '')
    if tonumber(user_id) == tonumber(bot.id) then
        -- Ignore bot
        return ''
    end
    if is_admin2(user_id) then
        -- Ignore admins
        return ''
    end
    -- Save to redis
    local hash = 'gbanned'
    redis_hset_something(hash, user_id, user_id)
    if not no_log then
        sendLog(langs[lang].user .. user_id .. langs[lang].gbannedFrom .. tmp_msg.chat.id, false, true)
    end
    if not no_notice then
        sendMessage(user_id, langs[lang].youHaveBeenGbanned)
    end
    return langs[lang].user .. user_id .. langs[lang].gbanned
end

-- Global unban
function ungbanUser(user_id, no_notice)
    local lang = get_lang(user_id)
    user_id = tostring(user_id):gsub(' ', '')
    -- Save on redis
    local hash = 'gbanned'
    redis_hdelsrem_something(hash, user_id)
    if not no_notice then
        sendMessage(user_id, langs[lang].youHaveBeenUngbanned)
    end
    return langs[lang].user .. user_id .. langs[lang].ungbanned
end

-- Check if user_id is globally banned or not
function isGbanned(user_id)
    user_id = tostring(user_id):gsub(' ', '')
    -- Save on redis
    local hash = 'gbanned'
    local gbanned = redis_sis_stored(hash, user_id)
    return gbanned or false
end

function blockUser(user_id, no_notice)
    local lang = get_lang(user_id)
    user_id = tostring(user_id):gsub(' ', '')
    if not is_admin2(user_id) then
        redis_hset_something('bot:blocked', user_id, user_id)
        if not no_notice then
            sendMessage(user_id, langs[lang].youHaveBeenBlocked)
        end
        return langs[lang].userBlocked
    else
        return langs[lang].cantBlockAdmin
    end
end

function unblockUser(user_id, no_notice)
    local lang = get_lang(user_id)
    user_id = tostring(user_id):gsub(' ', '')
    redis_hdelsrem_something('bot:blocked', user_id)
    if not no_notice then
        sendMessage(user_id, langs[lang].youHaveBeenUnblocked)
    end
    return langs[lang].userUnblocked
end

function isBlocked(user_id)
    user_id = tostring(user_id):gsub(' ', '')
    if redis_sis_stored('bot:blocked', user_id) then
        return true
    else
        return false
    end
end

-- Check if user_id is whitelisted or not
function isWhitelisted(chat_id, user_id)
    user_id = tostring(user_id):gsub(' ', '')
    if data[tostring(chat_id)] then
        return data[tostring(chat_id)].whitelist.users[tostring(user_id)]
    end
    return false
end

function whitelist_user(chat_id, user_id)
    local lang = get_lang(chat_id)
    if isWhitelisted(chat_id, user_id) then
        data[tostring(chat_id)].whitelist.users[tostring(user_id)] = nil
        save_data(config.moderation.data, data)
        return langs[lang].userBot .. user_id .. langs[lang].whitelistRemoved
    else
        data[tostring(chat_id)].whitelist.users[tostring(user_id)] = true
        save_data(config.moderation.data, data)
        return langs[lang].userBot .. user_id .. langs[lang].whitelistAdded
    end
end

-- Check if user_id is gban whitelisted or not
function isWhitelistedGban(chat_id, user_id)
    user_id = tostring(user_id):gsub(' ', '')
    if data[tostring(chat_id)] then
        return data[tostring(chat_id)].whitelist.gbanned[tostring(user_id)]
    end
    return false
end

function whitegban_user(chat_id, user_id)
    local lang = get_lang(chat_id)
    if isWhitelistedGban(chat_id, user_id) then
        data[tostring(chat_id)].whitelist.gbanned[tostring(user_id)] = nil
        save_data(config.moderation.data, data)
        return langs[lang].userBot .. user_id .. langs[lang].whitelistGbanRemoved
    else
        data[tostring(chat_id)].whitelist.gbanned[tostring(user_id)] = true
        save_data(config.moderation.data, data)
        return langs[lang].userBot .. user_id .. langs[lang].whitelistGbanAdded
    end
end

function getWarn(chat_id)
    local lang = get_lang(chat_id)
    if data[tostring(chat_id)] then
        if data[tostring(chat_id)].settings then
            return data[tostring(chat_id)].name .. '\n' .. langs[lang].warnSet .. data[tostring(chat_id)].settings.max_warns .. '\n' .. langs[lang].punishedWith .. reverse_punishments_table[data[tostring(chat_id)].settings.warns_punishment]
        end
    end
    return data[tostring(chat_id)].name .. '\n' .. langs[lang].noWarnSet
end

function getUserWarns(user_id, chat_id)
    user_id = tostring(user_id):gsub(' ', '')
    local lang = get_lang(chat_id)
    local hashonredis = redis_get_something(chat_id .. ':warn:' .. user_id) or 0
    local warn_msg = langs[lang].yourWarnings
    local warn_chat = data[tostring(chat_id)].settings.max_warns or 0
    return string.gsub(string.gsub(warn_msg, 'Y', warn_chat), 'X', tostring(hashonredis))
end

function warnUser(executer, target, chat_id, reason, no_notice)
    target = tostring(target):gsub(' ', '')
    local lang = get_lang(chat_id)
    if reason:find(langs[lang].reasonWarnMax) then
        return ''
    end
    if compare_ranks(executer, target, chat_id) then
        local warn_chat = tonumber(data[tostring(chat_id)].settings.max_warns or 0)
        redis_incr(chat_id .. ':warn:' .. target)
        local hashonredis = redis_get_something(chat_id .. ':warn:' .. target)
        if not hashonredis then
            redis_set_something(chat_id .. ':warn:' .. target, 1)
            hashonredis = 1
        end
        savelog(chat_id, "[" .. executer .. "] warned user " .. target .. " Y")
        if tonumber(warn_chat) > 0 then
            if tonumber(hashonredis) >= tonumber(warn_chat) then
                redis_get_set_something(chat_id .. ':warn:' .. target, 0)
                return punishmentAction(executer, target, chat_id, data[tostring(chat_id)].settings.warns_punishment, reason .. '\n' .. langs[lang].reasonWarnMax)
            end
            if arePMNoticesEnabled(target, chat_id) and not no_notice then
                local text = langs[get_lang(target)].youHaveBeenWarned .. database[tostring(chat_id)].print_name
                if reason then
                    if reason:gsub(' ', '') ~= '' then
                        text = text .. '\n' .. langs[get_lang(target)].reason .. reason
                    end
                end
                sendMessage(target, text)
            end
            return langs[lang].user .. target .. ' ' .. langs[lang].warned:gsub('X', tostring(hashonredis)) ..
            '\n#chat' .. tostring(chat_id):gsub("-", "") .. ' #user' .. target .. ' #executer' .. executer .. ' #warn ' ..(reason or '')
        else
            return punishmentAction(executer, target, chat_id, data[tostring(chat_id)].settings.warns_punishment, reason)
        end
    else
        savelog(chat_id, "[" .. executer .. "] warned user " .. target .. " N")
        return langs[lang].require_rank
    end
end

function unwarnUser(executer, target, chat_id, reason, no_notice)
    target = tostring(target):gsub(' ', '')
    local lang = get_lang(chat_id)
    if compare_ranks(executer, target, chat_id) then
        local warns = redis_get_something(chat_id .. ':warn:' .. target) or 0
        savelog(chat_id, "[" .. executer .. "] unwarned user " .. target .. " Y")
        if tonumber(warns) <= 0 then
            redis_set_something(chat_id .. ':warn:' .. target, 0)
            return langs[lang].user .. target .. ' ' .. langs[lang].alreadyZeroWarnings
        else
            redis_set_something(chat_id .. ':warn:' .. target, warns - 1)
            if arePMNoticesEnabled(target, chat_id) and not no_notice then
                local text = langs[get_lang(target)].youHaveBeenUnwarned .. database[tostring(chat_id)].print_name
                if reason then
                    if reason:gsub(' ', '') ~= '' then
                        text = text .. '\n' .. langs[get_lang(target)].reason .. reason
                    end
                end
                sendMessage(target, text)
            end
            return langs[lang].user .. target .. ' ' .. langs[lang].unwarned ..
            '\n#chat' .. tostring(chat_id):gsub("-", "") .. ' #user' .. target .. ' #executer' .. executer .. ' #unwarn ' ..(reason or '')
        end
    else
        savelog(chat_id, "[" .. executer .. "] unwarned user " .. target .. " N")
        return langs[lang].require_rank
    end
end

function unwarnallUser(executer, target, chat_id, reason, no_notice)
    target = tostring(target):gsub(' ', '')
    local lang = get_lang(chat_id)
    if compare_ranks(executer, target, chat_id) then
        redis_set_something(chat_id .. ':warn:' .. target, 0)
        savelog(chat_id, "[" .. executer .. "] unwarnedall user " .. target .. " Y")
        if arePMNoticesEnabled(target, chat_id) and not no_notice then
            local text = langs[get_lang(target)].youHaveBeenUnwarnedall .. database[tostring(chat_id)].print_name
            if reason then
                if reason:gsub(' ', '') ~= '' then
                    text = text .. '\n' .. langs[get_lang(target)].reason .. reason
                end
            end
            sendMessage(target, text)
        end
        return langs[lang].user .. target .. ' ' .. langs[lang].zeroWarnings ..
        '\n#chat' .. tostring(chat_id):gsub("-", "") .. ' #user' .. target .. ' #executer' .. executer .. ' #unwarnall ' ..(reason or '')
    else
        savelog(chat_id, "[" .. executer .. "] unwarnedall user " .. target .. " N")
        return langs[lang].require_rank
    end
end

-- begin LOCK/UNLOCK/MUTE/UNMUTE FUNCTIONS
function lockSetting(target, setting_type, punishment)
    local lang = get_lang(target)
    setting_type = groupDataDictionary[setting_type:lower()]
    if setting_type == 'lock_grouplink' then
        if data[tostring(target)].settings.lock_grouplink ~= nil then
            if data[tostring(target)].settings.lock_grouplink then
                return langs[lang].settingAlreadyLocked
            else
                data[tostring(target)].settings.lock_grouplink = true
                save_data(config.moderation.data, data)
                return langs[lang].settingLocked
            end
        else
            data[tostring(target)].settings.lock_grouplink = true
            save_data(config.moderation.data, data)
            return langs[lang].settingLocked
        end
    elseif setting_type == 'lock_groupname' then
        if data[tostring(target)].settings.lock_groupname ~= nil then
            if data[tostring(target)].settings.lock_groupname then
                return langs[lang].settingAlreadyLocked
            else
                data[tostring(target)].settings.lock_groupname = true
                save_data(config.moderation.data, data)
                return langs[lang].settingLocked
            end
        else
            data[tostring(target)].settings.lock_groupname = true
            save_data(config.moderation.data, data)
            return langs[lang].settingLocked
        end
    elseif setting_type == 'lock_groupphoto' then
        local obj = getChat(target)
        if type(obj) == 'table' then
            if obj.photo then
                data[tostring(target)].photo = obj.photo.big_file_id
                if data[tostring(target)].settings.lock_groupphoto ~= nil then
                    if data[tostring(target)].settings.lock_groupphoto then
                        return langs[lang].settingAlreadyLocked
                    else
                        data[tostring(target)].settings.lock_groupphoto = true
                        save_data(config.moderation.data, data)
                        return langs[lang].settingLocked
                    end
                else
                    data[tostring(target)].settings.lock_groupphoto = true
                    save_data(config.moderation.data, data)
                    return langs[lang].settingLocked
                end
            end
        end
        return langs[lang].needPhoto
    elseif setting_type == 'groupnotices' then
        if data[tostring(target)].settings.groupnotices ~= nil then
            if data[tostring(target)].settings.groupnotices then
                return langs[lang].groupnoticesEnabled
            else
                data[tostring(target)].settings.groupnotices = true
                save_data(config.moderation.data, data)
                return langs[lang].groupnoticesEnabled
            end
        else
            data[tostring(target)].settings.groupnotices = true
            save_data(config.moderation.data, data)
            return langs[lang].groupnoticesEnabled
        end
    elseif setting_type == 'pmnotices' then
        if data[tostring(target)].settings.pmnotices ~= nil then
            if data[tostring(target)].settings.pmnotices then
                return langs[lang].noticesAlreadyEnabledGroup
            else
                data[tostring(target)].settings.pmnotices = true
                save_data(config.moderation.data, data)
                return langs[lang].noticesEnabledGroup
            end
        else
            data[tostring(target)].settings.pmnotices = true
            save_data(config.moderation.data, data)
            return langs[lang].noticesEnabledGroup
        end
    elseif setting_type == 'tagalert' then
        if data[tostring(target)].settings.tagalert ~= nil then
            if data[tostring(target)].settings.tagalert then
                return langs[lang].tagalertGroupAlreadyEnabled
            else
                data[tostring(target)].settings.tagalert = true
                save_data(config.moderation.data, data)
                return langs[lang].tagalertGroupEnabled
            end
        else
            data[tostring(target)].settings.tagalert = true
            save_data(config.moderation.data, data)
            return langs[lang].tagalertGroupEnabled
        end
    elseif setting_type == 'strict' then
        if data[tostring(target)].settings.strict ~= nil then
            if data[tostring(target)].settings.strict then
                return langs[lang].settingAlreadyLocked
            else
                data[tostring(target)].settings.strict = true
                save_data(config.moderation.data, data)
                return langs[lang].settingLocked
            end
        else
            data[tostring(target)].settings.strict = true
            save_data(config.moderation.data, data)
            return langs[lang].settingLocked
        end
    end
    if type(punishments_table[punishment]) == nil then
        return langs[lang].punishmentNotFound
    end
    return setPunishment(target, setting_type, adjust_punishment(setting_type, punishments_table[punishment]))
end

function unlockSetting(target, setting_type)
    local lang = get_lang(target)
    setting_type = groupDataDictionary[setting_type:lower()]
    if setting_type == 'groupnotices' then
        data[tostring(target)].settings[tostring(setting_type)] = false
        save_data(config.moderation.data, data)
        return langs[lang].groupnoticesDisabled
    elseif setting_type == 'pmnotices' then
        data[tostring(target)].settings[tostring(setting_type)] = false
        save_data(config.moderation.data, data)
        return langs[lang].noticesDisabledGroup
    elseif setting_type == 'tagalert' then
        data[tostring(target)].settings[tostring(setting_type)] = false
        save_data(config.moderation.data, data)
        return langs[lang].tagalertGroupDisabled
    end

    if data[tostring(target)].settings[tostring(setting_type)] then
        data[tostring(target)].settings[tostring(setting_type)] = false
        save_data(config.moderation.data, data)
        return langs[lang].settingUnlocked
    else
        return setPunishment(target, setting_type, false)
    end
end

function showSettings(target, lang)
    target = tostring(target)
    if data[target] then
        local seconds, minutes, hours, days, weeks = unixToDate(data[target].settings.time_restrict)
        local time_restrict = weeks .. langs[lang].weeksWord .. days .. langs[lang].daysWord .. hours .. langs[lang].hoursWord .. minutes .. langs[lang].minutesWord .. seconds .. langs[lang].secondsWord
        seconds, minutes, hours, days, weeks = unixToDate(data[target].settings.time_ban)
        local time_ban = weeks .. langs[lang].weeksWord .. days .. langs[lang].daysWord .. hours .. langs[lang].hoursWord .. minutes .. langs[lang].minutesWord .. seconds .. langs[lang].secondsWord

        local text = langs[lang].groupSettings:gsub('X', data[target].name) ..
        langs[lang].groupnotices .. tostring(data[target].settings.groupnotices) ..
        langs[lang].pmnotices .. tostring(data[target].settings.pmnotices) ..
        langs[lang].tagalert .. tostring(data[target].tagalert) ..
        langs[lang].grouplinkLock .. tostring(data[target].settings.lock_grouplink) ..
        langs[lang].nameLock .. tostring(data[target].settings.lock_groupname) ..
        langs[lang].photoLock .. tostring(data[target].settings.lock_groupphoto) ..
        langs[lang].tempRestrictTime .. tostring(time_restrict) ..
        langs[lang].tempBanTime .. tostring(time_ban) ..
        langs[lang].warnSensibility .. tostring(data[target].settings.max_warns) ..
        langs[lang].warnPunishment .. tostring(data[target].settings.warns_punishment) ..
        langs[lang].strictrules .. tostring(data[target].settings.strict) ..
        '\n' .. langs[lang].locksWord ..
        langs[lang].arabicLock .. tostring(data[target].settings.locks.arabic) ..
        langs[lang].botsLock .. tostring(data[target].settings.locks.bots) ..
        langs[lang].censorshipsLock .. tostring(data[target].settings.locks.delword) ..
        langs[lang].floodLock .. tostring(data[target].settings.locks.flood) ..
        langs[lang].floodSensibility .. tostring(data[target].settings.max_flood) ..
        langs[lang].forwardLock .. tostring(data[target].settings.locks.forward) ..
        langs[lang].gbannedLock .. tostring(data[target].settings.locks.gbanned) ..
        langs[lang].leaveLock .. tostring(data[target].settings.locks.leave) ..
        langs[lang].linksLock .. tostring(data[target].settings.locks.links) ..
        langs[lang].membersLock .. tostring(data[target].settings.locks.members) ..
        langs[lang].rtlLock .. tostring(data[target].settings.locks.rtl) ..
        langs[lang].spamLock .. tostring(data[target].settings.locks.spam) ..
        langs[lang].usernameLock .. tostring(data[target].settings.locks.username) ..
        '\n' .. langs[lang].mutesWord ..
        langs[lang].allMute .. tostring(data[target].settings.mutes.all) ..
        langs[lang].audiosMute .. tostring(data[target].settings.mutes.audios) ..
        langs[lang].contactsMute .. tostring(data[target].settings.mutes.contacts) ..
        langs[lang].documentsMute .. tostring(data[target].settings.mutes.documents) ..
        langs[lang].gamesMute .. tostring(data[target].settings.mutes.games) ..
        langs[lang].gifsMute .. tostring(data[target].settings.mutes.gifs) ..
        langs[lang].locationsMute .. tostring(data[target].settings.mutes.locations) ..
        langs[lang].photosMute .. tostring(data[target].settings.mutes.photos) ..
        langs[lang].stickersMute .. tostring(data[target].settings.mutes.stickers) ..
        langs[lang].textMute .. tostring(data[target].settings.mutes.text) ..
        langs[lang].tgservicesMute .. tostring(data[target].settings.mutes.tgservices) ..
        langs[lang].videosMute .. tostring(data[target].settings.mutes.videos) ..
        langs[lang].videoNotesMute .. tostring(data[target].settings.mutes.video_notes) ..
        langs[lang].voiceNotesMute .. tostring(data[target].settings.mutes.voice_notes)
        return text
    end
end
-- end LOCK/UNLOCK/MUTE/UNMUTE FUNCTIONS

function muteUser(chat_id, user_id, lang, no_notice)
    user_id = tostring(user_id):gsub(' ', '')
    local hash = 'mute_user:' .. chat_id
    redis_hset_something(hash, user_id, user_id)
    if arePMNoticesEnabled(user_id, chat_id) and not no_notice then
        sendMessage(user_id, langs[get_lang(user_id)].youHaveBeenMuted .. database[tostring(chat_id)].print_name)
    end
    return user_id .. langs[lang].muteUserAdd
end

function isMutedUser(chat_id, user_id)
    user_id = tostring(user_id):gsub(' ', '')
    local hash = 'mute_user:' .. chat_id
    local muted = redis_sis_stored(hash, user_id)
    return muted or false
end

function unmuteUser(chat_id, user_id, lang, no_notice)
    user_id = tostring(user_id):gsub(' ', '')
    local hash = 'mute_user:' .. chat_id
    redis_hdelsrem_something(hash, user_id)
    if arePMNoticesEnabled(user_id, chat_id) and not no_notice then
        sendMessage(user_id, langs[get_lang(user_id)].youHaveBeenUnmuted .. database[tostring(chat_id)].print_name)
    end
    return user_id .. langs[lang].muteUserRemove
end

-- Returns chat_id user mute list
function mutedUserList(chat_id)
    local lang = get_lang(chat_id)
    local hash = 'mute_user:' .. chat_id
    local list = redis_get_something(hash) or { }
    local text = langs[lang].mutedUsersStart .. chat_id .. "\n\n"
    for k, v in pairs(list) do
        print(k, v)
        local user_info = redis_get_something('user:' .. v)
        if user_info and user_info.print_name then
            local print_name = string.gsub(user_info.print_name, "_", " ")
            local print_name = string.gsub(print_name, "?", "")
            text = text .. k .. " - " .. print_name .. " [" .. v .. "]\n"
        else
            text = text .. k .. " - [ " .. v .. " ]\n"
        end
    end
    return text
end

--[[function resolveUsername(username)
    username = '@' .. username:lower()
    local obj = resolveChat(username) -- ex resolveChannelSupergroupsUsernames
    local ok = false

    if obj then
        if obj.result then
            obj = obj.result
            if type(obj) == 'table' then
                ok = true
            end
        end
    end

    if ok then
        return obj
    else
        local hash = 'bot:usernames'
        local stored = redis_hget_something(hash, username)
        if stored then
            local obj = getChat(stored)
            if obj.result then
                obj = obj.result
                return obj
            end
        else
            return false
        end
    end
end]]

function print_res_msg(res, code)
    if res then
        if type(res) == 'table' then
            if res.result then
                local sent_msg = res.result
                if type(sent_msg) == 'table' then
                    sent_msg = pre_process_reply(sent_msg)
                    sent_msg = pre_process_forward(sent_msg)
                    sent_msg = pre_process_callback(sent_msg)
                    sent_msg = pre_process_media_msg(sent_msg)
                    sent_msg = pre_process_service_msg(sent_msg)
                    sent_msg = adjust_msg(sent_msg)
                    return print_msg(sent_msg)
                elseif sent_msg ~= true then
                    sendLog('#BadResult\n' .. vardumptext(res) .. '\n' .. vardumptext(code))
                end
            else
                sendLog('#BadResult\n' .. vardumptext(res) .. '\n' .. vardumptext(code))
            end
        else
            sendLog('#BadResult\n' .. vardumptext(res) .. '\n' .. vardumptext(code))
        end
    end
    return nil
end

function print_msg(msg, dont_print)
    if msg then
        if not msg.printed then
            msg.printed = true
            local seconds, minutes, hours = unixToDate(msg.date or os.time())
            -- IT IS UTC TIME
            local chat_name = "ERROR CHAT NAME"
            if msg.chat then
                chat_name = msg.chat.title or(msg.chat.first_name ..(msg.chat.last_name or ''))
            end
            local sender_name = "ERROR FROM NAME"
            if msg.from then
                sender_name = msg.from.title or(msg.from.first_name ..(msg.from.last_name or ''))
            end
            local print_text = clr.cyan .. 'UTC [' .. hours .. ':' .. minutes .. ':' .. seconds .. ']  ' .. chat_name .. ' ' .. clr.reset .. clr.red .. sender_name .. clr.reset .. clr.blue .. ' >>> ' .. clr.reset
            if msg.cb then
                print_text = print_text .. clr.blue .. '[inline keyboard callback] ' .. clr.reset
            end
            if msg.edited then
                print_text = print_text .. clr.blue .. '[edited] ' .. clr.reset
            end
            if msg.forward then
                local forwarder = "ERROR FORWARD NAME"
                if msg.forward_from then
                    forwarder = msg.forward_from.first_name ..(msg.forward_from.last_name or '')
                elseif msg.forward_from_chat then
                    forwarder = msg.forward_from_chat.title
                end
                print_text = print_text .. clr.blue .. '[forward from ' .. forwarder .. '] ' .. clr.reset
            end
            if msg.reply then
                print_text = print_text .. clr.blue .. '[reply] ' .. clr.reset
            end
            if msg.media then
                print_text = print_text .. clr.blue .. '[' ..(msg.media_type or 'ERROR MEDIA NOT SUPPORTED') .. '] ' .. clr.reset
                if msg.caption then
                    print_text = print_text .. clr.blue .. msg.caption .. clr.reset
                end
            end
            if msg.service then
                if msg.service_type == 'chat_del_user' then
                    print_text = print_text .. clr.red ..(msg.remover.first_name ..(msg.remover.last_name or '')) .. clr.reset .. clr.blue .. ' deleted user ' .. clr.reset .. clr.red ..((msg.removed.first_name or '$Deleted Account$') ..(msg.removed.last_name or '')) .. ' ' .. clr.reset
                elseif msg.service_type == 'chat_del_user_leave' then
                    print_text = print_text .. clr.red ..(msg.remover.first_name ..(msg.remover.last_name or '')) .. clr.reset .. clr.blue .. ' left the chat ' .. clr.reset
                elseif msg.service_type == 'chat_add_user' or msg.service_type == 'chat_add_users' then
                    for k, v in pairs(msg.added) do
                        print_text = print_text .. clr.red ..(msg.adder.first_name ..(msg.adder.last_name or '')) .. clr.reset .. clr.blue .. ' added user ' .. clr.reset .. clr.red ..(v.first_name ..(v.last_name or '')) .. ' ' .. clr.reset
                    end
                elseif msg.service_type == 'chat_add_user_link' then
                    print_text = print_text .. clr.red ..(msg.adder.first_name ..(msg.adder.last_name or '')) .. clr.reset .. clr.blue .. ' joined chat by invite link ' .. clr.reset
                else
                    print_text = print_text .. clr.blue .. '[' ..(msg.service_type or 'ERROR SERVICE NOT SUPPORTED') .. '] ' .. clr.reset
                end
            end
            if msg.text then
                print_text = print_text .. clr.blue .. msg.text .. clr.reset
            end
            if not dont_print then
                print(msg.chat.id)
                print(print_text)
            end
            return print_text
        end
    end
end