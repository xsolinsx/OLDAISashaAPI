if not config.bot_api_key then
    error('You did not set your bot token in config.lua!')
end

local fake_user_chat = { first_name = 'FAKE', last_name = 'USER CHAT', title = 'FAKE USER CHAT', id = 'FAKE ID' }

local BASE_URL = 'https://api.telegram.org/bot' .. config.bot_api_key
local PWR_URL = 'https://api.pwrtelegram.xyz/bot' .. config.bot_api_key

local curl_context = curl.easy { verbose = false }

-- *** START API FUNCTIONS ***
function performRequest(url)
    local data = { }

    -- if multithreading is made, this request must be in critical section
    local c = curl_context:setopt_url(url):setopt_writefunction(table.insert, data):perform()

    return table.concat(data), c:getinfo_response_code()
end

function sendRequest(url)
    local dat, code = performRequest(url)
    local tab = JSON.decode(dat)

    if not tab then
        print(clr.red .. 'Error while parsing JSON' .. clr.reset, code)
        print(clr.yellow .. 'Data:' .. clr.reset, dat)
        error('Incorrect response')
    end

    if code ~= 200 then

        if code == 400 then
            -- error code 400 is general: try to specify
            code = getCode(tab.description)
        end

        print(clr.red .. code, tab.description .. clr.reset)
        redis:hincrby('bot:errors', code, 1)

        if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
            --sendLog('#BadRequest\n' .. vardumptext(tab) .. '\n' .. code)
        end
        return nil, code, tab.description
    end

    if not tab.ok then
        --sendLog('Not tab.ok' .. vardumptext(tab))
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

function APIgetChat(id_or_username)
    local url = BASE_URL .. '/getChat?chat_id=' .. id_or_username
    return sendRequest(url)
end

function getChatAdministrators(chat_id)
    local url = BASE_URL .. '/getChatAdministrators?chat_id=' .. chat_id
    return sendRequest(url)
end

function getChatMembersCount(chat_id)
    local url = BASE_URL .. '/getChatMembersCount?chat_id=' .. chat_id
    return sendRequest(url)
end

function getChatMember(chat_id, user_id)
    if not string.match(user_id, '^%*%d') then
        local obj = getChat(chat_id)
        if type(obj) == 'table' then
            if obj.type ~= 'bot' and obj.type ~= 'private' and obj.type ~= 'user' then
                local url = BASE_URL .. '/getChatMember?chat_id=' .. chat_id .. '&user_id=' .. user_id
                return sendRequest(url)
            end
        else
            return sendMessage(chat_id, langs[get_lang(chat_id)].noObject)
        end
    else
        local fake_user = { first_name = 'FAKECOMMAND', username = '@FAKECOMMAND', id = user_id, type = 'fake', status = 'fake' }
        return fake_user
    end
end

function getFile(file_id)
    local url = BASE_URL ..
    '/getFile?file_id=' .. file_id
    return sendRequest(url)
end

function getCode(error)
    for k, v in pairs(config.api_errors) do
        if error:match(v) then
            return k
        end
    end
    -- error unknown
    return 7
end

function code2text(code, ln)
    -- the default error description can't be sent as output, so a translation is needed
    if code == 101 or code == 105 or code == 107 then
        return langs[ln].kick_errors[1]
    elseif code == 102 or code == 104 then
        return langs[ln].kick_errors[2]
    elseif code == 103 then
        return langs[ln].kick_errors[3]
    elseif code == 106 then
        return langs[ln].kick_errors[4]
    elseif code == 7 then
        return false
    end
    return false
end

-- never call this outside this file
function kickChatMember(user_id, chat_id)
    local url = BASE_URL .. '/kickChatMember?chat_id=' .. chat_id .. '&user_id=' .. user_id
    local dat, res = HTTPS.request(url)
    local tab = JSON.decode(dat)

    if res ~= 200 then
        -- if error, return false and the custom error code
        print(tab.description)
        return false, getCode(tab.description)
    end

    if not tab.ok then
        return false, tab.description
    end

    return tab
end

-- never call this outside this file
function unbanChatMember(user_id, chat_id)
    local url = BASE_URL .. '/unbanChatMember?chat_id=' .. chat_id .. '&user_id=' .. user_id
    -- return sendRequest(url)
    local dat, res = HTTPS.request(url)
    local tab = JSON.decode(dat)

    if res ~= 200 then
        return false, res
    end

    if not tab.ok then
        return false, tab.description
    end

    return tab
end

function leaveChat(chat_id)
    local url = BASE_URL .. '/leaveChat?chat_id=' .. chat_id
    return sendRequest(url)
end

function sendMessage(chat_id, text, use_markdown, reply_to_message_id, send_sound)
    local obj = getChat(chat_id)
    if type(obj) == 'table' then
        if text then
            if type(text) ~= 'table' then
                text = tostring(text)
                if text ~= '' then
                    text = text:gsub('[Cc][Rr][Oo][Ss][Ss][Ee][Xx][Ee][Cc] ', '')
                    local text_max = 4096
                    local text_len = string.len(text)
                    local num_msg = math.ceil(text_len / text_max)
                    local url = BASE_URL ..
                    '/sendMessage?chat_id=' .. chat_id ..
                    '&disable_web_page_preview=true'
                    local reply = false
                    if reply_to_message_id then
                        url = url .. '&reply_to_message_id=' .. reply_to_message_id
                        reply = true
                    end
                    if use_markdown then
                        url = url .. '&parse_mode=Markdown'
                    end
                    if not send_sound then
                        url = url .. '&disable_notification=true'
                        -- messages are silent by default
                    end

                    if num_msg <= 1 then
                        url = url .. '&text=' .. URL.escape(text)

                        local res, code = sendRequest(url)

                        if not res and code then
                            -- if the request failed and a code is returned (not 403 and 429)
                            if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                                savelog('send_msg', code .. '\n' .. text)
                            end
                        end
                        if print_res_msg(res) then
                            return res, code
                        else
                            local sent_msg = { from = bot, chat = obj, text = text, reply = reply }
                            print_msg(sent_msg)
                        end
                    else
                        local my_text = string.sub(text, 1, 4096)
                        local rest = string.sub(text, 4096, text_len)
                        url = url .. '&text=' .. URL.escape(my_text)

                        local res, code = sendRequest(url)

                        if not res and code then
                            -- if the request failed and a code is returned (not 403 and 429)
                            if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                                savelog('send_msg', code .. '\n' .. text)
                            end
                        end
                        if print_res_msg(res) then
                            res, code = sendMessage(chat_id, rest, use_markdown, reply_to_message_id, send_sound)
                        else
                            local sent_msg = { from = bot, chat = obj, text = my_text, reply = reply }
                            print_msg(sent_msg)
                            res, code = sendMessage(chat_id, rest, use_markdown, reply_to_message_id, send_sound)
                        end
                    end

                    return res, code
                    -- return false, and the code
                end
            end
        end
    else
        -- return sendMessage(chat_id, langs[get_lang(chat_id)].noObject)
    end
end

function sendMessage_SUDOERS(text, use_markdown)
    for v, user in pairs(sudoers) do
        if user.id ~= bot.userVersion.id then
            sendMessage(user.id, text, use_markdown, false, true)
        end
    end
end

function sendReply(msg, text, markd, send_sound)
    sendMessage(msg.chat.id, text, markd, msg.message_id, send_sound)
end

function sendLog(text, markdown)
    if config.log_chat then
        sendMessage(config.log_chat, text, markdown)
    else
        sendMessage_SUDOERS(text, markdown)
    end
end

function forwardMessage(chat_id, from_chat_id, message_id)
    local obj_from = getChat(from_chat_id)
    local obj_to = getChat(chat_id)
    if type(obj_from) == 'table' and type(obj_to) == 'table' then
        local url = BASE_URL ..
        '/forwardMessage?chat_id=' .. chat_id ..
        '&from_chat_id=' .. from_chat_id ..
        '&message_id=' .. message_id
        local res, code = sendRequest(url)

        if not res and code then
            -- if the request failed and a code is returned (not 403 and 429)
            if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                savelog('forward_msg', code .. '\n' .. text)
            end
        end
        if print_res_msg(res) then
            return res, code
        else
            local sent_msg = { from = bot, chat = obj_to, text = text, forward = true }
            if obj_from.type == 'private' then
                sent_msg.forward_from = obj_from
            elseif obj_from.type == 'channel' then
                sent_msg.forward_from_chat = obj_from
            end
            print_msg(sent_msg)
        end
    else
        return sendMessage(chat_id, langs[get_lang(chat_id)].noObject)
    end
end

function forwardMessage_SUDOERS(from_chat_id, message_id)
    for v, user in pairs(sudoers) do
        if user.id ~= bot.userVersion.id then
            forwardMessage(user.id, from_chat_id, message_id)
        end
    end
end

function forwardLog(from_chat_id, message_id)
    if config.log_chat then
        forwardMessage(config.log_chat, from_chat_id, message_id)
    else
        forwardMessage_SUDOERS(from_chat_id, message_id)
    end
end

function sendKeyboard(chat_id, text, keyboard, markdown)
    local obj = getChat(chat_id)
    if type(obj) == 'table' then
        local url = BASE_URL .. '/sendMessage?chat_id=' .. chat_id
        if markdown then
            url = url .. '&parse_mode=Markdown'
        end
        text = text:gsub('[Cc][Rr][Oo][Ss][Ss][Ee][Xx][Ee][Cc] ', '')
        url = url .. '&text=' .. URL.escape(text)
        url = url .. '&disable_web_page_preview=true'
        url = url .. '&reply_markup=' .. JSON.encode(keyboard)
        local res, code = sendRequest(url)

        if not res and code then
            -- if the request failed and a code is returned (not 403 and 429)
            if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                savelog('send_msg', code .. '\n' .. text)
            end
        end
        if print_res_msg(res) then
            return res, code
        else
            local sent_msg = { from = bot, chat = obj, text = text, cb = true }
            print_msg(sent_msg)
        end
        -- return false, and the code
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
    if print_res_msg(res) then
        return res, code
    else
        local sent_msg = { from = bot, chat = fake_user_chat, text = text, cb = true }
        print_msg(sent_msg)
    end
end

function editMessageText(chat_id, message_id, text, keyboard, markdown)
    local obj = getChat(chat_id)
    if type(obj) == 'table' then
        local url = BASE_URL ..
        '/editMessageText?chat_id=' .. chat_id ..
        '&message_id=' .. message_id ..
        '&text=' .. URL.escape(text)
        if markdown then
            url = url .. '&parse_mode=Markdown'
        end
        url = url .. '&disable_web_page_preview=true'
        if keyboard then
            url = url .. '&reply_markup=' .. JSON.encode(keyboard)
        end
        local res, code = sendRequest(url)

        if not res and code then
            -- if the request failed and a code is returned (not 403 and 429)
            if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                savelog('send_msg', code .. '\n' .. text)
            end
        end
        if print_res_msg(res) then
            return res, code
        else
            local sent_msg = { from = fake_user_chat, chat = obj, text = text, edited = true }
            print_msg(sent_msg)
        end
        -- return false, and the code
    else
        return sendMessage(chat_id, langs[get_lang(chat_id)].noObject)
    end
end

function sendChatAction(chat_id, action)
    -- Support actions are typing, upload_photo, record_video, upload_video, record_audio, upload_audio, upload_document, find_location
    local url = BASE_URL ..
    '/sendChatAction?chat_id=' .. chat_id ..
    '&action=' .. action
    return sendRequest(url)
end

function deleteMessage(chat_id, message_id)
    local url = BASE_URL ..
    '/deleteMessage?chat_id=' .. chat_id ..
    '&message_id=' .. message_id
    local res, code = sendRequest(url)

    if not res and code then
        -- if the request failed and a code is returned (not 403 and 429)
        if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
            savelog('delete_message', code)
        end
    end
end

----------------------------By Id-----------------------------------------

function sendPhotoId(chat_id, file_id, caption, reply_to_message_id)
    local obj = getChat(chat_id)
    if type(obj) == 'table' then
        local url = BASE_URL ..
        '/sendPhoto?chat_id=' .. chat_id ..
        '&photo=' .. file_id
        if caption then
            if type(caption) == 'string' or type(caption) == 'number' then
                url = url .. '&caption=' .. caption
            end
        end
        local reply = false
        if reply_to_message_id then
            url = url .. '&reply_to_message_id=' .. reply_to_message_id
            reply = true
        end
        local res, code = sendRequest(url)

        if not res and code then
            -- if the request failed and a code is returned (not 403 and 429)
            if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                savelog('send_photo', code)
            end
        end
        if print_res_msg(res) then
            return res, code
        else
            local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'photo' }
            print_msg(sent_msg)
        end
    else
        return sendMessage(chat_id, langs[get_lang(chat_id)].noObject)
    end
end

function sendStickerId(chat_id, file_id, reply_to_message_id)
    local obj = getChat(chat_id)
    if type(obj) == 'table' then
        local url = BASE_URL ..
        '/sendSticker?chat_id=' .. chat_id ..
        '&sticker=' .. file_id
        local reply = false
        if reply_to_message_id then
            url = url .. '&reply_to_message_id=' .. reply_to_message_id
            reply = true
        end
        local res, code = sendRequest(url)

        if not res and code then
            -- if the request failed and a code is returned (not 403 and 429)
            if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                savelog('send_sticker', code)
            end
        end
        if print_res_msg(res) then
            return res, code
        else
            local sent_msg = { from = bot, chat = obj, reply = reply, media = true, media_type = 'sticker' }
            print_msg(sent_msg)
        end
    else
        return sendMessage(chat_id, langs[get_lang(chat_id)].noObject)
    end
end

function sendVoiceId(chat_id, file_id, caption, reply_to_message_id)
    local obj = getChat(chat_id)
    if type(obj) == 'table' then
        local url = BASE_URL ..
        '/sendVoice?chat_id=' .. chat_id ..
        '&voice=' .. file_id
        if caption then
            if type(caption) == 'string' or type(caption) == 'number' then
                url = url .. '&caption=' .. caption
            end
        end
        local reply = false
        if reply_to_message_id then
            url = url .. '&reply_to_message_id=' .. reply_to_message_id
            reply = true
        end
        local res, code = sendRequest(url)

        if not res and code then
            -- if the request failed and a code is returned (not 403 and 429)
            if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                savelog('send_voice', code)
            end
        end
        if print_res_msg(res) then
            return res, code
        else
            local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'voice_note' }
            print_msg(sent_msg)
        end
    else
        return sendMessage(chat_id, langs[get_lang(chat_id)].noObject)
    end
end

function sendAudioId(chat_id, file_id, caption, reply_to_message_id)
    local obj = getChat(chat_id)
    if type(obj) == 'table' then
        local url = BASE_URL ..
        '/sendAudio?chat_id=' .. chat_id ..
        '&audio=' .. file_id
        if caption then
            if type(caption) == 'string' or type(caption) == 'number' then
                url = url .. '&caption=' .. caption
            end
        end
        local reply = false
        if reply_to_message_id then
            url = url .. '&reply_to_message_id=' .. reply_to_message_id
            reply = true
        end
        local res, code = sendRequest(url)

        if not res and code then
            -- if the request failed and a code is returned (not 403 and 429)
            if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                savelog('send_audio', code)
            end
        end
        if print_res_msg(res) then
            return res, code
        else
            local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'audio' }
            print_msg(sent_msg)
        end
    else
        return sendMessage(chat_id, langs[get_lang(chat_id)].noObject)
    end
end

function sendVideoNoteId(chat_id, file_id, reply_to_message_id)
    local obj = getChat(chat_id)
    if type(obj) == 'table' then
        local url = BASE_URL ..
        '/sendVideoNote?chat_id=' .. chat_id ..
        '&video_note=' .. file_id
        local reply = false
        if reply_to_message_id then
            url = url .. '&reply_to_message_id=' .. reply_to_message_id
            reply = true
        end
        local res, code = sendRequest(url)

        if not res and code then
            -- if the request failed and a code is returned (not 403 and 429)
            if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                savelog('send_video_note', code)
            end
        end
        if print_res_msg(res) then
            return res, code
        else
            local sent_msg = { from = bot, chat = obj, reply = reply, media = true, media_type = 'video_note' }
            print_msg(sent_msg)
        end
    else
        return sendMessage(chat_id, langs[get_lang(chat_id)].noObject)
    end
end

function sendVideoId(chat_id, file_id, caption, reply_to_message_id)
    local obj = getChat(chat_id)
    if type(obj) == 'table' then
        local url = BASE_URL ..
        '/sendVideo?chat_id=' .. chat_id ..
        '&video=' .. file_id
        if caption then
            if type(caption) == 'string' or type(caption) == 'number' then
                url = url .. '&caption=' .. caption
            end
        end
        local reply = false
        if reply_to_message_id then
            url = url .. '&reply_to_message_id=' .. reply_to_message_id
            reply = true
        end
        local res, code = sendRequest(url)

        if not res and code then
            -- if the request failed and a code is returned (not 403 and 429)
            if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                savelog('send_video', code)
            end
        end
        if print_res_msg(res) then
            return res, code
        else
            local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'video' }
            print_msg(sent_msg)
        end
    else
        return sendMessage(chat_id, langs[get_lang(chat_id)].noObject)
    end
end

function sendDocumentId(chat_id, file_id, caption, reply_to_message_id)
    local obj = getChat(chat_id)
    if type(obj) == 'table' then
        local url = BASE_URL ..
        '/sendDocument?chat_id=' .. chat_id ..
        '&document=' .. file_id
        if caption then
            if type(caption) == 'string' or type(caption) == 'number' then
                url = url .. '&caption=' .. caption
            end
        end
        local reply = false
        if reply_to_message_id then
            url = url .. '&reply_to_message_id=' .. reply_to_message_id
            reply = true
        end
        local res, code = sendRequest(url)

        if not res and code then
            -- if the request failed and a code is returned (not 403 and 429)
            if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                savelog('send_document', code)
            end
        end
        if print_res_msg(res) then
            return res, code
        else
            local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'document' }
            print_msg(sent_msg)
        end
    else
        return sendMessage(chat_id, langs[get_lang(chat_id)].noObject)
    end
end

----------------------------To curl--------------------------------------------

function curlRequest(curl_command)
    -- Use at your own risk. Will not check for success.
    io.popen(curl_command)
end

function sendPhoto(chat_id, photo, caption, reply_to_message_id)
    local obj = getChat(chat_id)
    if type(obj) == 'table' then
        local url = BASE_URL .. '/sendPhoto'
        local curl_command = 'curl "' .. url .. '" -F "chat_id=' .. chat_id .. '" -F "photo=@' .. photo .. '"'
        local reply = false
        if reply_to_message_id then
            curl_command = curl_command .. ' -F "reply_to_message_id=' .. reply_to_message_id .. '"'
            reply = true
        end
        if caption then
            curl_command = curl_command .. ' -F "caption=' .. caption .. '"'
        end
        local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'photo' }
        print_msg(sent_msg)
        return curlRequest(curl_command)
    else
        return sendMessage(chat_id, langs[get_lang(chat_id)].noObject)
    end
end

function sendSticker(chat_id, sticker, reply_to_message_id)
    local obj = getChat(chat_id)
    if type(obj) == 'table' then
        local url = BASE_URL .. '/sendSticker'
        local curl_command = 'curl "' .. url .. '" -F "chat_id=' .. chat_id .. '" -F "sticker=@' .. sticker .. '"'
        local reply = false
        if reply_to_message_id then
            curl_command = curl_command .. ' -F "reply_to_message_id=' .. reply_to_message_id .. '"'
            reply = true
        end
        local sent_msg = { from = bot, chat = obj, reply = reply, media = true, media_type = 'sticker' }
        print_msg(sent_msg)
        return curlRequest(curl_command)
    else
        return sendMessage(chat_id, langs[get_lang(chat_id)].noObject)
    end
end

function sendVoice(chat_id, voice, caption, reply_to_message_id)
    local obj = getChat(chat_id)
    if type(obj) == 'table' then
        local url = BASE_URL .. '/sendVoice'
        local curl_command = 'curl "' .. url .. '" -F "chat_id=' .. chat_id .. '" -F "voice=@' .. voice .. '"'
        if caption then
            if type(caption) == 'string' or type(caption) == 'number' then
                url = url .. ' -F "caption=' .. caption .. '"'
            end
        end
        local reply = false
        if reply_to_message_id then
            curl_command = curl_command .. ' -F "reply_to_message_id=' .. reply_to_message_id .. '"'
            reply = true
        end
        if duration then
            curl_command = curl_command .. ' -F "duration=' .. duration .. '"'
        end
        local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'voice_note' }
        print_msg(sent_msg)
        return curlRequest(curl_command)
    else
        return sendMessage(chat_id, langs[get_lang(chat_id)].noObject)
    end
end

function sendAudio(chat_id, audio, caption, reply_to_message_id, duration, performer, title)
    local obj = getChat(chat_id)
    if type(obj) == 'table' then
        local url = BASE_URL .. '/sendAudio'
        local curl_command = 'curl "' .. url .. '" -F "chat_id=' .. chat_id .. '" -F "audio=@' .. audio .. '"'
        if caption then
            if type(caption) == 'string' or type(caption) == 'number' then
                url = url .. ' -F "caption=' .. caption .. '"'
            end
        end
        local reply = false
        if reply_to_message_id then
            curl_command = curl_command .. ' -F "reply_to_message_id=' .. reply_to_message_id .. '"'
            reply = true
        end
        if duration then
            curl_command = curl_command .. ' -F "duration=' .. duration .. '"'
        end
        if performer then
            curl_command = curl_command .. ' -F "performer=' .. performer .. '"'
        end
        if title then
            curl_command = curl_command .. ' -F "title=' .. title .. '"'
        end
        local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'audio' }
        print_msg(sent_msg)
        return curlRequest(curl_command)
    else
        return sendMessage(chat_id, langs[get_lang(chat_id)].noObject)
    end
end

function sendVideo(chat_id, video, reply_to_message_id, caption, duration, performer, title)
    local obj = getChat(chat_id)
    if type(obj) == 'table' then
        local url = BASE_URL .. '/sendVideo'
        local curl_command = 'curl "' .. url .. '" -F "chat_id=' .. chat_id .. '" -F "video=@' .. video .. '"'
        local reply = false
        if reply_to_message_id then
            curl_command = curl_command .. ' -F "reply_to_message_id=' .. reply_to_message_id .. '"'
            reply = true
        end
        if caption then
            curl_command = curl_command .. ' -F "caption=' .. caption .. '"'
        end
        if duration then
            curl_command = curl_command .. ' -F "duration=' .. duration .. '"'
        end
        local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'video' }
        print_msg(sent_msg)
        return curlRequest(curl_command)
    else
        return sendMessage(chat_id, langs[get_lang(chat_id)].noObject)
    end
end

function sendVideoNote(chat_id, video_note, reply_to_message_id, duration, length)
    local obj = getChat(chat_id)
    if type(obj) == 'table' then
        local url = BASE_URL .. '/sendVideoNote'
        local curl_command = 'curl "' .. url .. '" -F "chat_id=' .. chat_id .. '" -F "video_note=@' .. video_note .. '"'
        local reply = false
        if reply_to_message_id then
            curl_command = curl_command .. ' -F "reply_to_message_id=' .. reply_to_message_id .. '"'
            reply = true
        end
        if duration then
            curl_command = curl_command .. ' -F "duration=' .. duration .. '"'
        end
        if length then
            curl_command = curl_command .. ' -F "length=' .. length .. '"'
        end
        local sent_msg = { from = bot, chat = obj, reply = reply, media = true, media_type = 'video_note' }
        print_msg(sent_msg)
        return curlRequest(curl_command)
    else
        return sendMessage(chat_id, langs[get_lang(chat_id)].noObject)
    end
end

function sendDocument(chat_id, document, caption, reply_to_message_id)
    local obj = getChat(chat_id)
    if type(obj) == 'table' then
        local url = BASE_URL .. '/sendDocument'
        local curl_command = 'curl "' .. url .. '" -F "chat_id=' .. chat_id .. '" -F "document=@' .. document .. '"'
        local reply = false
        if reply_to_message_id then
            curl_command = curl_command .. ' -F "reply_to_message_id=' .. reply_to_message_id .. '"'
            reply = true
        end
        local sent_msg = { from = bot, chat = obj, caption = caption, reply = reply, media = true, media_type = 'document' }
        print_msg(sent_msg)
        return curlRequest(curl_command)
    else
        return sendMessage(chat_id, langs[get_lang(chat_id)].noObject)
    end
end

function sendLocation(chat_id, latitude, longitude, reply_to_message_id)
    local obj = getChat(chat_id)
    if type(obj) == 'table' then
        local url = BASE_URL ..
        '/sendLocation?chat_id=' .. chat_id ..
        '&latitude=' .. latitude ..
        '&longitude=' .. longitude
        local reply = false
        if reply_to_message_id then
            url = url .. '&reply_to_message_id=' .. reply_to_message_id
            reply = true
        end
        local res, code = sendRequest(url)

        if not res and code then
            -- if the request failed and a code is returned (not 403 and 429)
            if code ~= 403 and code ~= 429 and code ~= 110 and code ~= 111 then
                savelog('send_location', code)
            end
        end
        if print_res_msg(res) then
            return res, code
        else
            local sent_msg = { from = bot, chat = obj, reply = reply, media = true, media_type = 'location' }
            print_msg(sent_msg)
        end
    else
        return sendMessage(chat_id, langs[get_lang(chat_id)].noObject)
    end
end

function sendDocument_SUDOERS(document)
    for v, user in pairs(sudoers) do
        if user.id ~= bot.userVersion.id then
            sendDocument(user.id, document)
        end
    end
end

----------------------------From url functions---------------------------------
function getHttpFileName(url, headers)
    -- Eg: foo.var
    local file_name = url:match("[^%w]+([%.%w]+)$")
    -- Any delimited alphanumeric on the url
    file_name = file_name or url:match("[^%w]+(%w+)[^%w]+$")
    -- Random name, hope content-type works
    file_name = file_name or str:random(5)

    local content_type = headers["content-type"]

    local extension = nil
    if content_type then
        extension = mimetype.get_mime_extension(content_type)
    end
    if extension then
        file_name = file_name .. "." .. extension
    end

    local disposition = headers["content-disposition"]
    if disposition then
        -- attachment; filename=CodeCogsEqn.png
        file_name = disposition:match('filename=([^;]+)') or file_name
    end

    return file_name
end

-- Callback to remove a file
function removeTempFile(file_path)
    if file_path ~= nil then
        os.remove(file_path)
        print("Deleted: " .. file_path)
    end
end

--  Saves file to /tmp/. If file_name isn't provided,
-- will get the text after the last "/" for filename
-- and content-type for extension
function tempDownloadFile(url, file_name)
    print("url to download: " .. url)

    local respbody = { }
    local options = {
        url = url,
        sink = ltn12.sink.table(respbody),
        redirect = true
    }

    -- nil, code, headers, status
    local response = nil

    if url:starts('https') then
        options.redirect = false
        response = { HTTPS.request(options) }
    else
        response = { http.request(options) }
    end

    local code = response[2]
    local headers = response[3]
    local status = response[4]

    if code ~= 200 then
        return
    end

    file_name = file_name or getHttpFileName(url, headers)

    local file_path = "data/tmp/" .. file_name
    print("Saved to: " .. file_path)

    file = io.open(file_path, "w+")
    file:write(table.concat(respbody))
    file:close()

    return file_path
end

-- Download the image and send to receiver, it will be deleted.
-- cb_function and extra are optionals callback
function sendPhotoFromUrl(chat_id, url_to_download, caption, reply_to_message_id)
    local file_path = tempDownloadFile(url_to_download, false)
    if not file_path then
        -- Error
        return langs[get_lang(chat_id)].errorFileDownload
    else
        print("File path: " .. file_path)
        return sendPhoto(chat_id, file_path, caption, reply_to_message_id)
    end
end

-- Download the document and send to receiver, it will be deleted.
-- cb_function and extra are optionals callback
function sendDocumentFromUrl(chat_id, url_to_download, reply_to_message_id)
    local file_path = tempDownloadFile(url_to_download, false)
    if not file_path then
        -- Error
        return langs[get_lang(chat_id)].errorFileDownload
    else
        print("File path: " .. file_path)
        sendDocument(chat_id, file_path, reply_to_message_id)
    end
end
-- *** END API FUNCTIONS ***

-- *** START PWRTELEGRAM API FUNCTIONS ***
function resolveChat(id_or_username)
    local url = PWR_URL .. '/getChat?chat_id=' .. id_or_username
    local dat, code = HTTPS.request(url)

    if not dat then
        return false, code
    end

    local tab = JSON.decode(dat)

    if code ~= 200 then
        if not tab then
            return false
        else
            sendLog('#BadRequest PWRTelegram API\n' .. vardumptext(tab) .. '\n' .. code)
            return false
        end
    end

    return tab
end
-- *** END PWRTELEGRAM API FUNCTIONS ***

function saveUsername(obj, chat_id)
    if obj then
        if type(obj) == 'table' then
            if obj.username then
                redis:hset('bot:usernames', '@' .. obj.username:lower(), obj.id)
                if obj.type ~= 'bot' and obj.type ~= 'private' and obj.type ~= 'user' then
                    if chat_id then
                        redis:hset('bot:usernames:' .. chat_id, '@' .. obj.username:lower(), obj.id)
                    end
                end
            end
        end
    end
end

-- call this to get the chat
function getChat(id_or_username)
    if not string.match(id_or_username, '^%*%d') then
        if tostring(id_or_username) ~= '@' then
            local obj = nil
            local ok = false
            -- API
            if not ok then
                obj = APIgetChat(id_or_username)
                if type(obj) == 'table' then
                    if obj.result then
                        obj = obj.result
                        ok = true
                    end
                end
            end
            -- redis db then API
            if not ok then
                local hash = 'bot:usernames'
                local stored = nil
                if type(id_or_username) == 'string' then
                    stored = redis:hget(hash, id_or_username:lower())
                else
                    stored = redis:hget(hash, id_or_username)
                end
                if stored then
                    obj = APIgetChat(stored)
                    if type(obj) == 'table' then
                        if obj.result then
                            obj = obj.result
                            ok = true
                            saveUsername(obj)
                        end
                    end
                end
            end
            --[[
            -- PWR API
            if not ok then
                obj = resolveChat(id_or_username)
                if type(obj) == 'table' then
                    if obj.result then
                        obj = obj.result
                        ok = true
                        saveUsername(obj)
                    end
                end
            end
            ]]
            if ok then
                return obj
            end
        end
        return nil
    else
        local fake_user = { first_name = 'FAKECOMMAND', username = '@FAKECOMMAND', id = id_or_username, type = 'fake' }
        return fake_user
    end
end

function getChatParticipants(chat_id)
    local obj = resolveChat(chat_id)
    if type(obj) == 'table' then
        if obj.result then
            obj = obj.result
            if obj.participants then
                return obj.participants
            end
        end
    end
end

function sudoInChat(chat_id)
    for v, user in pairs(sudoers) do
        if user.id ~= bot.userVersion.id then
            local member = getChatMember(chat_id, user.id)
            if type(member) == 'table' then
                if member.ok and member.result then
                    if member.result.status == 'creator' or member.result.status == 'administrator' or member.result.status == 'member' then
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
            if member.result.status == 'creator' or member.result.status == 'administrator' or member.result.status == 'member' then
                return true, member.result.status
            end
        end
    end
    return false
end

-- call this to kick
function kickUser(executer, target, chat_id, reason)
    local obj_chat = getChat(chat_id)
    local obj_remover = getChat(executer)
    local obj_removed = getChat(target)
    if type(obj_chat) == 'table' and type(obj_remover) == 'table' and type(obj_removed) == 'table' then
        if isWhitelisted(id_to_cli(chat_id), target) then
            savelog(chat_id, "[" .. executer .. "] tried to kick user " .. target .. " that is whitelisted")
            return langs[get_lang(chat_id)].cantKickWhitelisted
        end
        if compare_ranks(executer, target, chat_id) then
            -- try to kick
            local res, code = kickChatMember(target, chat_id)

            if res then
                -- if the user has been kicked, then...
                savelog(chat_id, "[" .. executer .. "] kicked user " .. target)
                redis:hincrby('bot:general', 'kick', 1)
                -- general: save how many kicks
                -- unban
                unbanChatMember(target, chat_id)
                local sent_msg = { from = bot, chat = obj_chat, remover = obj_remover, removed = obj_removed, text = text, service = true, service_type = 'chat_del_user' }
                print_msg(sent_msg)
                if reason then
                    -- sendMessage(target, langs[get_lang(target)].kickedFrom .. obj_chat.title .. '\n' .. langs[get_lang(target)].executer ..(obj_remover.username or(obj_remover.first_name .. ' ' ..(obj_remover.last_name or ''))) .. '\n' .. langs[get_lang(target)].reason .. reason)
                    return langs.phrases.banhammer[math.random(#langs.phrases.banhammer)] ..
                    '\n#kick' .. target .. ' ' .. reason
                else
                    -- sendMessage(target, langs[get_lang(target)].kickedFrom .. obj_chat.title .. '\n' .. langs[get_lang(target)].executer ..(obj_remover.username or(obj_remover.first_name .. ' ' ..(obj_remover.last_name or ''))))
                    return langs.phrases.banhammer[math.random(#langs.phrases.banhammer)] ..
                    '\n#kick' .. target
                end
            else
                return code2text(code, get_lang(chat_id))
            end
        else
            savelog(chat_id, "[" .. executer .. "] tried to kick user " .. target .. " require higher rank")
            return langs[get_lang(chat_id)].require_rank
        end
    else
        return langs[get_lang(chat_id)].noObject
    end
end

function preBanUser(executer, target, chat_id)
    if isWhitelisted(id_to_cli(chat_id), target) then
        savelog(chat_id, "[" .. executer .. "] tried to ban user " .. target .. " that is whitelisted")
        return langs[get_lang(chat_id)].cantKickWhitelisted
    end
    if compare_ranks(executer, target, chat_id, true) then
        -- try to kick. "code" is already specific
        savelog(chat_id, "[" .. executer .. "] banned user " .. target)
        redis:hincrby('bot:general', 'ban', 1)
        -- general: save how many kicks
        local hash = 'banned:' .. chat_id
        redis:sadd(hash, tostring(target))
        return langs[get_lang(chat_id)].user .. target .. langs[get_lang(chat_id)].banned ..
        '\n' .. langs.phrases.banhammer[math.random(#langs.phrases.banhammer)]
    else
        savelog(chat_id, "[" .. executer .. "] tried to ban user " .. target .. " require higher rank")
        return langs[get_lang(chat_id)].require_rank
    end
end

-- call this to ban
function banUser(executer, target, chat_id, reason)
    local obj_chat = getChat(chat_id)
    local obj_remover = getChat(executer)
    local obj_removed = getChat(target)
    if reason then
        if reason == '' then
            reason = nil
        end
    end
    if type(obj_chat) == 'table' and type(obj_remover) == 'table' and type(obj_removed) == 'table' then
        if isWhitelisted(id_to_cli(chat_id), target) then
            savelog(chat_id, "[" .. executer .. "] tried to ban user " .. target .. " that is whitelisted")
            return langs[get_lang(chat_id)].cantKickWhitelisted
        end
        if compare_ranks(executer, target, chat_id) then
            -- try to kick. "code" is already specific
            local res, code = kickChatMember(target, chat_id)

            if res then
                -- if the user has been kicked, then...
                savelog(chat_id, "[" .. executer .. "] banned user " .. target)
                redis:hincrby('bot:general', 'ban', 1)
                -- general: save how many kicks
                local hash = 'banned:' .. chat_id
                redis:sadd(hash, tostring(target))
                local sent_msg = { from = bot, chat = obj_chat, remover = obj_remover, removed = obj_removed, text = text, service = true, service_type = 'chat_del_user' }
                print_msg(sent_msg)
                if reason then
                    -- sendMessage(target, langs[get_lang(target)].bannedFrom .. obj_chat.title .. '\n' .. langs[get_lang(target)].executer ..(obj_remover.username or(obj_remover.first_name .. ' ' ..(obj_remover.last_name or ''))) .. '\n' .. langs[get_lang(target)].reason .. reason)
                    return langs[get_lang(chat_id)].user .. target .. langs[get_lang(chat_id)].banned ..
                    '\n' .. langs.phrases.banhammer[math.random(#langs.phrases.banhammer)] ..
                    '\n#ban' .. target .. ' ' .. reason
                else
                    -- sendMessage(target, langs[get_lang(target)].bannedFrom .. obj_chat.title .. '\n' .. langs[get_lang(target)].executer ..(obj_remover.username or(obj_remover.first_name .. ' ' ..(obj_remover.last_name or ''))))
                    return langs[get_lang(chat_id)].user .. target .. langs[get_lang(chat_id)].banned ..
                    '\n' .. langs.phrases.banhammer[math.random(#langs.phrases.banhammer)] ..
                    '\n#ban' .. target
                end
            else
                if code == 106 then
                    local hash = 'banned:' .. chat_id
                    redis:sadd(hash, tostring(target))
                end
                return code2text(code, get_lang(chat_id))
            end
        else
            savelog(chat_id, "[" .. executer .. "] tried to ban user " .. target .. " require higher rank")
            return langs[get_lang(chat_id)].require_rank
        end
    else
        return langs[get_lang(chat_id)].noObject
    end
end

-- call this to unban
function unbanUser(executer, target, chat_id, reason)
    if compare_ranks(executer, target, chat_id) then
        savelog(chat_id, "[" .. target .. "] unbanned")
        local hash = 'banned:' .. chat_id
        redis:srem(hash, tostring(target))
        -- redis:srem('chat:'..chat_id..':prevban', target) --remove from the prevban list
        local res, code = unbanChatMember(target, chat_id)
        if reason then
            return langs[get_lang(chat_id)].user .. target .. langs[get_lang(chat_id)].unbanned ..
            '\n#unban' .. target .. ' ' .. reason
        else
            return langs[get_lang(chat_id)].user .. target .. langs[get_lang(chat_id)].unbanned ..
            '\n#unban' .. target
        end
    else
        savelog(chat_id, "[" .. executer .. "] tried to unban user " .. target .. " require higher rank")
        return langs[get_lang(chat_id)].require_rank
    end
end

-- Check if user_id is banned in chat_id or not
function isBanned(user_id, chat_id)
    -- Save on redis
    local hash = 'banned:' .. chat_id
    local banned = redis:sismember(hash, tostring(user_id))
    return banned or false
end

-- Returns chat_id ban list
function banList(chat_id)
    local hash = 'banned:' .. chat_id
    local list = redis:smembers(hash)
    local text = langs[get_lang(chat_id)].banListStart
    for k, v in pairs(list) do
        local user_info = redis:hgetall('user:' .. v)
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
function gbanUser(user_id)
    if tonumber(user_id) == tonumber(bot.id) then
        -- Ignore bot
        return
    end
    if is_admin2(user_id) then
        -- Ignore admins
        return
    end
    -- Save to redis
    local hash = 'gbanned'
    redis:sadd(hash, user_id)
end

-- Global unban
function ungbanUser(user_id)
    -- Save on redis
    local hash = 'gbanned'
    redis:srem(hash, user_id)
end

-- Check if user_id is globally banned or not
function isGbanned(user_id)
    -- Save on redis
    local hash = 'gbanned'
    local gbanned = redis:sismember(hash, user_id)
    return gbanned or false
end

function blockUser(user_id, lang)
    if not is_admin2(user_id) then
        redis:sadd('bot:blocked', user_id)
        return langs[lang].userBlocked
    else
        return langs[lang].cantBlockAdmin
    end
end

function unblockUser(user_id, lang)
    redis:srem('bot:blocked', user_id)
    return langs[lang].userUnblocked
end

function isBlocked(user_id)
    if redis:sismember('bot:blocked', user_id) then
        return true
    else
        return false
    end
end

-- Check if user_id is whitelisted or not
function isWhitelisted(chat_id, user_id)
    -- Save on redis
    local hash = 'whitelist:' .. chat_id
    local whitelisted = redis:sismember(hash, user_id)
    return whitelisted or false
end

-- Check if user_id is gban whitelisted or not
function isWhitelistedGban(chat_id, user_id)
    -- Save on redis
    local hash = 'whitelist:gban:' .. chat_id
    local whitelisted = redis:sismember(hash, user_id)
    return whitelisted or false
end

function setWarn(user_id, chat_id, value)
    local lang = get_lang(chat_id)
    if tonumber(value) < 0 or tonumber(value) > 10 then
        return langs[lang].errorWarnRange
    end
    local warn_max = value
    data[tostring(chat_id)].settings.warn_max = warn_max
    save_data(config.moderation.data, data)
    savelog(chat_id, " [" .. user_id .. "] set warn to [" .. value .. "]")
    return langs[lang].warnSet .. value
end

function getWarn(chat_id)
    local lang = get_lang(chat_id)
    if data[tostring(chat_id)] then
        if data[tostring(chat_id)].settings then
            local warn_max = data[tostring(chat_id)].settings.warn_max
            if not warn_max then
                return langs[lang].noWarnSet
            end
            return langs[lang].warnSet .. warn_max
        end
    end
    return langs[lang].noWarnSet
end

function getUserWarns(user_id, chat_id)
    local lang = get_lang(chat_id)
    local hashonredis = redis:get(chat_id .. ':warn:' .. user_id)
    local warn_msg = langs[lang].yourWarnings or ''
    local warn_chat = string.match(getWarn(chat_id), "%d+") or ''

    if hashonredis then
        warn_msg = string.gsub(string.gsub(warn_msg, 'Y', warn_chat), 'X', tostring(hashonredis))
    else
        warn_msg = string.gsub(string.gsub(warn_msg, 'Y', warn_chat), 'X', '0')
    end
    return warn_msg
end

function warnUser(executer, target, chat_id, reason)
    local lang = get_lang(chat_id)
    if compare_ranks(executer, target, chat_id) then
        local warn_chat = string.match(getWarn(chat_id), "%d+")
        redis:incr(chat_id .. ':warn:' .. target)
        local hashonredis = redis:get(chat_id .. ':warn:' .. target)
        if not hashonredis then
            redis:set(chat_id .. ':warn:' .. target, 1)
            hashonredis = 1
        end
        savelog(chat_id, "[" .. executer .. "] warned user " .. target .. " Y")
        if tonumber(warn_chat) ~= 0 then
            if tonumber(hashonredis) >= tonumber(warn_chat) then
                redis:getset(chat_id .. ':warn:' .. target, 0)
                return banUser(executer, target, chat_id, langs[lang].reasonWarnMax)
            end
            if reason then
                return langs[lang].user .. target .. ' ' .. string.gsub(langs[lang].warned, 'X', tostring(hashonredis)) ..
                '\n#warn' .. target .. ' ' .. reason
            else
                return langs[lang].user .. target .. ' ' .. string.gsub(langs[lang].warned, 'X', tostring(hashonredis)) ..
                '\n#warn' .. target
            end
        else
            return banUser(executer, target, chat_id, reason)
        end
    else
        savelog(chat_id, "[" .. executer .. "] warned user " .. target .. " N")
        return langs[lang].require_rank
    end
end

function unwarnUser(executer, target, chat_id, reason)
    local lang = get_lang(chat_id)
    if compare_ranks(executer, target, chat_id) then
        local warns = redis:get(chat_id .. ':warn:' .. target)
        savelog(chat_id, "[" .. executer .. "] unwarned user " .. target .. " Y")
        if tonumber(warns) <= 0 then
            redis:set(chat_id .. ':warn:' .. target, 0)
            return langs[lang].user .. target .. ' ' .. langs[lang].alreadyZeroWarnings
        else
            redis:set(chat_id .. ':warn:' .. target, warns - 1)
            if reason then
                return langs[lang].user .. target .. ' ' .. langs[lang].unwarned ..
                '\n#unwarn' .. target .. ' ' .. reason
            else
                return langs[lang].user .. target .. ' ' .. langs[lang].unwarned ..
                '\n#unwarn' .. target
            end
        end
    else
        savelog(chat_id, "[" .. executer .. "] unwarned user " .. target .. " N")
        return langs[lang].require_rank
    end
end

function unwarnallUser(executer, target, chat_id, reason)
    local lang = get_lang(chat_id)
    if compare_ranks(executer, target, chat_id) then
        redis:set(chat_id .. ':warn:' .. target, 0)
        savelog(chat_id, "[" .. executer .. "] unwarnedall user " .. target .. " Y")
        if reason then
            return langs[lang].user .. target .. ' ' .. langs[lang].zeroWarnings ..
            '\n#unwarnall' .. target .. ' ' .. reason
        else
            return langs[lang].user .. target .. ' ' .. langs[lang].zeroWarnings ..
            '\n#unwarnall' .. target
        end
    else
        savelog(chat_id, "[" .. executer .. "] unwarnedall user " .. target .. " N")
        return langs[lang].require_rank
    end
end

function setMutes(chat_id)
    local lang = get_lang(chat_id)
    if data[tostring(chat_id)] then
        if data[tostring(chat_id)].settings then
            data[tostring(chat_id)].settings.mutes = { ["all"] = false, ["audio"] = false, ["contact"] = false, ["document"] = false, ["gif"] = false, ["location"] = false, ["photo"] = false, ["sticker"] = false, ["text"] = false, ["tgservice"] = false, ["video"] = false, ["video_note"] = false, ["voice_note"] = false }
            save_data(config.moderation.data, data)
            return langs[lang].mutesSet
        end
    end
end

function hasMutes(chat_id)
    if data[tostring(chat_id)] then
        if data[tostring(chat_id)].settings.mutes then
            return true
        end
    end
    if setMutes(chat_id) then
        return true
    else
        return false
    end
end

function isMuted(chat_id, msg_type)
    if data[tostring(chat_id)] then
        if data[tostring(chat_id)].settings then
            if hasMutes(chat_id) then
                if data[tostring(chat_id)].settings.mutes[msg_type:lower()] ~= nil then
                    return data[tostring(chat_id)].settings.mutes[msg_type:lower()]
                end
            end
        end
    end
    return false
end

function mute(chat_id, msg_type)
    local lang = get_lang(chat_id)
    if data[tostring(chat_id)] then
        if data[tostring(chat_id)].settings then
            if hasMutes(chat_id) then
                if data[tostring(chat_id)].settings.mutes[msg_type:lower()] ~= nil then
                    if data[tostring(chat_id)].settings.mutes[msg_type:lower()] then
                        return msg_type:lower() .. langs[lang].alreadyMuted
                    else
                        data[tostring(chat_id)].settings.mutes[msg_type:lower()] = true
                        save_data(config.moderation.data, data)
                        return msg_type:lower() .. langs[lang].muted
                    end
                else
                    return langs[lang].noSuchMuteType
                end
            end
        end
    end
end

function unmute(chat_id, msg_type)
    local lang = get_lang(chat_id)
    if data[tostring(chat_id)] then
        if data[tostring(chat_id)].settings then
            if hasMutes(chat_id) then
                if data[tostring(chat_id)].settings.mutes[msg_type:lower()] ~= nil then
                    if data[tostring(chat_id)].settings.mutes[msg_type:lower()] then
                        data[tostring(chat_id)].settings.mutes[msg_type:lower()] = false
                        save_data(config.moderation.data, data)
                        return msg_type:lower() .. langs[lang].unmuted
                    else
                        return msg_type:lower() .. langs[lang].alreadyUnmuted
                    end
                else
                    return langs[lang].noSuchMuteType
                end
            end
        end
    end
end

function muteUser(chat_id, user_id)
    local hash = 'mute_user:' .. chat_id
    redis:sadd(hash, user_id)
end

function isMutedUser(chat_id, user_id)
    local hash = 'mute_user:' .. chat_id
    local muted = redis:sismember(hash, user_id)
    return muted or false
end

function unmuteUser(chat_id, user_id)
    local hash = 'mute_user:' .. chat_id
    redis:srem(hash, user_id)
end

-- Returns chat_id mute list
function mutesList(chat_id)
    local lang = get_lang(chat_id)
    if data[tostring(chat_id)] then
        if data[tostring(chat_id)].settings then
            if hasMutes(chat_id) then
                local text = langs[lang].mutedTypesStart .. chat_id .. "\n\n"
                for k, v in pairsByKeys(data[tostring(chat_id)].settings.mutes) do
                    text = text .. langs[lang].mute .. k .. ': ' .. tostring(v) .. "\n"
                end
                text = text .. langs[lang].strictrules .. tostring(data[tostring(chat_id)].settings.strict)
                return text
            end
        end
    end
end

-- Returns chat_id user mute list
function mutedUserList(chat_id)
    local lang = get_lang(chat_id)
    local hash = 'mute_user:' .. chat_id
    local list = redis:smembers(hash)
    local text = langs[lang].mutedUsersStart .. chat_id .. "\n\n"
    for k, v in pairsByKeys(list) do
        local user_info = redis:hgetall('user:' .. v)
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
        local stored = redis:hget(hash, username)
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
            local hour = os.date('%H')
            local minute = os.date('%M')
            local second = os.date('%S')
            local chat_name = msg.chat.title or(msg.chat.first_name ..(msg.chat.last_name or ''))
            local sender_name = msg.from.title or(msg.from.first_name ..(msg.from.last_name or ''))
            local print_text = clr.cyan .. ' [' .. hour .. ':' .. minute .. ':' .. second .. ']  ' .. chat_name .. ' ' .. clr.reset .. clr.red .. sender_name .. clr.reset .. clr.blue .. ' >>> ' .. clr.reset
            if msg.cb then
                print_text = print_text .. clr.blue .. '[inline keyboard callback] ' .. clr.reset
            end
            if msg.edited then
                print_text = print_text .. clr.blue .. '[edited] ' .. clr.reset
            end
            if msg.forward then
                local forwarder = ''
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
                print_text = print_text .. clr.blue .. '[' ..(msg.media_type or 'unsupported media') .. '] ' .. clr.reset
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
                    print_text = print_text .. clr.blue .. '[' ..(msg.service_type or 'unsupported service') .. '] ' .. clr.reset
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