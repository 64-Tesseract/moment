math.randomseed(os.time())

local username = "User"
pcall(function () username = vim.api.nvim_get_var("moment_username") end)

local buffers = {}  -- name = {window handle, buffer handle}
local connected_users = {}  -- id = {socket, name, buf, row, float}
local main_socket = false
local own_server_id = false
local last_cursor = {}
local last_scroll = 0
local ignore_buffer_updates = {}

-- Open a socket for clients
function host (port)
    if main_socket then
       notify("Already connected!")
        return
    end

    main_socket = vim.loop.new_tcp()
    own_server_id = gen_user_id()
    notify("Hosting on port " .. port)
    main_socket:bind("0.0.0.0", port)

    main_socket:listen(128, function (err)
        local sock = vim.loop.new_tcp()
        main_socket:accept(sock)

        local client_id = gen_user_id()
        connected_users[client_id] = {socket = sock}

        sock:read_start(function (err, chunk)
            if not err then
                parse_chunks(sock, chunk, client_id)
            end
        end)

        local available_buffers = {}
        local other_users = {[own_server_id] = {name = username .. " (Host)", buf = last_cursor.buf, row = last_cursor.row}}
        for buf, _ in pairs(buffers) do
            available_buffers[buf] = false
        end
        for user_id, user in pairs(connected_users) do
            if user.socket ~= sock then
                other_users[user_id] = {name = user.name}
            end
        end

        send_socket(sock, {cmd = "serverinfo", buffers = available_buffers, users = other_users})
        notify("New connection...")
    end)

    bind_cursor_send(nil)
end

-- Open a socket to a server
function join (ip, port)
    if main_socket then
        notify("Already connected!")
        return
    end

    main_socket = vim.loop.new_tcp()
    own_server_id = false
    notify("Connecting...")

    main_socket:connect(ip, port, function (err)
        if err then
            notify("Error connecting to " .. ip .. ":" .. port .. "\n" .. err)
        end
    end)

    main_socket:read_start(function (err, chunk)
        if not err then
            parse_chunks(main_socket, chunk)
        end
    end)

    bind_cursor_send(main_socket)
end

-- Sometimes JSON arrives joined together in 1 chunk, like "{...} {...}"
-- Split it and handle disconnections
function parse_chunks (sock, chunks, id)
    if not chunks then
        if own_server_id then
            forward_to_clients(sock, {
                cmd = "del_user",
                id = id
            })

            sock:close()
            del_user(id)

        else
            main_socket:close()
            main_socket = nil

            for id, _ in pairs(connected_users) do
                del_user(id)
            end
            buffers = {}

            notify("Server closed")
        end

        return
    end

    chunks = chunks:gsub("}" .. "{", "}\n{")
    for chunk in chunks:gmatch("[^\n]+") do
        parse_chunk(sock, chunk, id)
    end
end

-- Match chunk command to function
function parse_chunk (sock, chunk, id)
    local data
    err, _ = pcall(function () data = vim.json.decode(chunk) end)
    if not err then
        notify("Invalid JSON\n" .. chunk)
        return
    end

    cmd = data.cmd

    if cmd == "serverinfo" then  -- Client got connection confirmation and server info
        notify("Connected!")
        buffers = data.buffers
        connected_users = data.users
        send_socket(main_socket, {
            cmd = "new_user",
            name = username
        })

    elseif cmd == "new_user" then  -- Client/Server got username of user
        local this_id = 0

        if own_server_id then
            this_id = id

            forward_to_clients(sock, {
                cmd = "new_user",
                name = data.name,
                id = id
            })

        else
            this_id = data.id
            connected_users[this_id] = {}
        end

        connected_users[this_id].name = data.name

        notify(data.name .. " connected!")

    elseif cmd == "del_user" then  -- Client got user leaving
        del_user(data.id)

    elseif cmd == "cursor" then
        local this_id = 0

        if own_server_id then
            this_id = id

            forward_to_clients(sock, {
                cmd = "cursor",
                buf = data.buf,
                row = data.row,
                id = id
            })

        else
            this_id = data.id
        end

        set_float_cursor(connected_users[this_id], data.buf, data.row)

    elseif cmd == "new_buf" then  -- Client got notified that new buffer was created
        if buffers[data.buf] ~= nil then return end
        buffers[data.buf] = false

    elseif cmd == "get_buf" then  -- Server got requested entire buffer
        if buffers[data.buf] == nil then return end

        vim.schedule(function ()
            local lines = vim.api.nvim_buf_get_lines(buffers[data.buf].buf, 0, -1, false)
            local syntax = vim.api.nvim_buf_call(buffers[data.buf].buf, function ()
                return vim.api.nvim_exec("set syntax", {output = true})
            end):match("[^=]+$")
            send_socket(sock, {
                cmd = "set_buf",
                lines = lines,
                syntax = syntax,
                buf = data.buf
            })
        end)

    elseif cmd == "set_buf" then  -- Client got entire buffer
        if buffers[data.buf] == nil then return end

        vim.schedule(function ()
            vim.api.nvim_buf_set_lines(buffers[data.buf].buf, 0, -1, false, data.lines)
            if data.syntax then
                vim.api.nvim_exec("set syntax=" .. data.syntax, {})
            end
            vim.wait(100, function () end)
            bind_buffer_send(sock, data.buf)
        end)

    elseif cmd == "lines" then  -- Lines changed by another user
        if buffers[data.buf] then
            ignore_buffer_updates[data.buf .. "-" .. data.start_line .. "-" .. data.end_line] = true
            vim.schedule(function ()
                vim.api.nvim_buf_set_lines(buffers[data.buf].buf, data.start_line, data.end_line, false, data.lines)
            end)
        end

        if own_server_id then
            forward_to_clients(sock, data)
        end
    end
end

-- Ask the server for a shared buffer, if it exists and isn't already open
function request_buffer (buf)
    if own_server_id then
        notify("Only clients can request buffers from the host")
        return
    end
    if buffers[buf] == nil then
        notify("No such remote buffer")
        return
    end
    if buffers[buf] ~= false then
        notify("Remote buffer has already been loaded in another window")
        return
    end
    for _, winbuf in pairs(buffers) do
        if winbuff and winbuf.buf == vim.api.nvim_win_get_buf(0) then
            notify("Another remote buffer is already loaded in this window")
            return
        end
    end

    buffers[buf] = {win = vim.api.nvim_tabpage_get_win(0), buf = vim.api.nvim_win_get_buf(0)}
    send_socket(main_socket, {cmd = "get_buf", buf = buf})
end

-- Create a new buffer and tell clients
function new_buffer (buf)
    if not own_server_id then
        notify("Only the host can create new buffers")
        return
    end
    if buffers[buf] ~= nil then
        notify("A remote buffer by that name already exists")
        return
    end
    for _, winbuf in pairs(buffers) do
        if winbuf.buf == vim.api.nvim_win_get_buf(0) then
            notify("Another remote buffer is already loaded to this window")
            return
        end
    end

    buffers[buf] = {win = vim.api.nvim_tabpage_get_win(0), buf = vim.api.nvim_win_get_buf(0)}
    for _, user in pairs(connected_users) do
        send_socket(user.socket, {cmd = "new_buf", buf = buf})
    end

    bind_buffer_send(nil, buf)
end

-- Listen in the buffer for changes, then send them to the server if is client or to clients if is server
function bind_buffer_send (sock, buf)
    if not buffers[buf] then return end

    vim.schedule(function ()
        vim.api.nvim_buf_attach(buffers[buf].buf, false, {
            on_lines = function (_, handle, _, start_line, end_line, end_new, _, _, _)
                if not buffers[buf] then return true end

                local buffer_update = buf .. "-" .. start_line .. "-" .. end_line
                if ignore_buffer_updates[buffer_update] then
                    ignore_buffer_updates[buffer_update] = nil
                    return
                end

                vim.schedule(function ()
                    local lines = vim.api.nvim_buf_get_lines(buffers[buf].buf, start_line, end_new, false)
                    local line_data = {
                        cmd = "lines",
                        lines = lines,
                        start_line = start_line,
                        end_line = end_line,
                        end_new = end_new,
                        buf = buf
                    }

                    if sock == nil then
                        for _, user in pairs(connected_users) do
                            send_socket(user.socket, line_data)
                        end
                    else
                        send_socket(sock, line_data)
                    end
                end)
            end
        })
    end)
end

-- Cursor position sending loop, no event to check it
function bind_cursor_send (sock)
    local cursor_timer = vim.loop.new_timer()
    cursor_timer:start(0, 200, vim.schedule_wrap(function ()
        if not main_socket then
            cursor_timer:close()
            return
        end

        for buf, winbuf in pairs(buffers) do
            if winbuf and vim.api.nvim_tabpage_get_win(0) == winbuf.win then
                local coords = vim.api.nvim_win_get_cursor(0)

                if buf ~= last_cursor.buf or coords[1] ~= last_cursor.row then
                    local cursor_data = {
                        cmd = "cursor",
                        buf = buf,
                        row = coords[1],
                        id = own_server_id
                    }

                    last_cursor.buf = buf
                    last_cursor.row = coords[1]

                    if sock == nil then
                        for _, user in pairs(connected_users) do
                            send_socket(user.socket, cursor_data)
                        end
                    else
                        send_socket(sock, cursor_data)
                    end
                end

                break
            end
        end
    end))
end

-- Send a packet to all sockets except a specified one
function forward_to_clients (sock_from, data)
    if own_server_id then
        for _, user in pairs(connected_users) do
            if user.socket ~= sock_from then
                send_socket(user.socket, data)
            end
        end
    end
end

-- Encode data & send it
function send_socket (sock, data)
    vim.schedule(function ()
        sock:write(vim.json.encode(data))
    end)
end

-- Create a floating window
function create_float_cursor (name, win)
    local b = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, {name})
    return vim.api.nvim_open_win(b, false, {
        relative = "win", win = win, row = 0, col = 0, width = #name, height = 1, anchor = "NE", focusable = false, style = "minimal"
    })
end

-- Delete a floating window and its buffer if it exists
function delete_float_cursor (float)
    if float and vim.api.nvim_win_is_valid(float) then
        local float_buf = vim.api.nvim_win_get_buf(float)
        vim.api.nvim_win_close(float, true)
        vim.api.nvim_buf_delete(float_buf, {force = true})
        return true
    end
    return false
end

-- Sets the position of a remote cursor, or creates/deletes it based on visible windows
function set_float_cursor (user, buf, row)
    vim.schedule(function ()
        -- Float is on different buffer or buffer doesn't exist, get rid of it
        if user and user.buf ~= buf or not buffers[buf] or vim.api.nvim_tabpage_get_win(0) ~= buffers[buf].win then
            if delete_float_cursor(user.float) then
                user.float = nil
            end
        end

        -- Float is on same buffer as open buffer
        if user and buffers[buf] and vim.api.nvim_tabpage_get_win(0) == buffers[buf].win then
            if not user.float or not vim.api.nvim_win_is_valid(user.float) then
                user.float = create_float_cursor(user.name, buffers[buf].win)
            end

            -- Set position of cursor
            local scroll_top = vim.api.nvim_win_call(buffers[buf].win, function ()
                return vim.fn.line("w0")
            end)
            local scroll_bottom = vim.api.nvim_win_call(buffers[buf].win, function ()
                return vim.fn.line("w$")
            end)

            local width = vim.api.nvim_win_get_width(buffers[buf].win)
            local height = vim.api.nvim_win_get_height(buffers[buf].win)
            local display_row = row - scroll_top

            if display_row < 0 or display_row >= height then
                float_width = 1
            else
                float_width = #user.name
            end

            vim.api.nvim_win_set_config(user.float, {
                relative = "win",
                row = math.min(display_row, height - 1),
                col = width,
                width = float_width
            })
        end

        user.buf = buf
        user.row = row
    end)
end

-- Render loop for remote cursors
function render_float_cursors ()
    for _, user in pairs(connected_users) do
        if user.name then
            set_float_cursor(user, user.buf, user.row)
        end
    end
end

-- Reliable print()
function notify (text)
    vim.schedule(function ()
        vim.notify(text)
    end)
end

-- Get a unique ID for a new user
function gen_user_id ()
    while true do
        local id = tostring(math.random(65536))
        if own_server_id ~= id and connected_users[id] == nil then
            return id
        end
    end
end

-- Delete user's cursor and deregister the user himself
function del_user (id)
    vim.schedule(function ()
        if connected_users[id] then
            notify(connected_users[id].name .. " disconnected!")
            delete_float_cursor(connected_users[id].float)
            connected_users[id] = nil
        end
    end)
end

-- Command definitions
vim.api.nvim_create_user_command("MomentHost",
    function (opts)
        if opts.fargs[1] == nil then
            vim.notify("Missing arguments: MomentHost <port>")
        end
        host(opts.fargs[1])
    end,
    {nargs = "*"}
)

vim.api.nvim_create_user_command("MomentJoin",
    function (opts)
        if opts.fargs[1] == nil and opts.fargs[2] == nil then
            vim.notify("Missing arguments: MomentJoin <address> <port>")
        end
        join(opts.fargs[1], opts.fargs[2])
    end,
    {nargs = "*"}
)

vim.api.nvim_create_user_command("MomentStatus",
    function (opts)
        if not main_socket then
            notify("Not connected")
            return
        end

        local status = ""
        if own_server_id then
            status = "Host\n"
        else
            status = "Client\n"
        end

        status = status .. "Buffers:\n"
        for buf, open in pairs(buffers) do
            status = status .. "    " .. buf
            if open then
                status = status .. "*"
            end
            status = status .. "\n"
        end
        status = status .. "Users:\n"
        for id, user in pairs(connected_users) do
            status = status .. "    " .. user.name
            if user.buf and user.row then
                status = status .. " [" .. user.buf .. ":" .. user.row .. "]"
            end
            status = status .. "\n"
        end

        notify(status)
    end,
    {nargs = 0}
)

vim.api.nvim_create_user_command("MomentShare",
    function (opts)
        if not main_socket then
            notify("Not connected")
            return
        end

        if opts.fargs[1] == nil then
            vim.notify("Missing arguments: MomentNew <name>")
        end
        new_buffer(opts.fargs[1])
    end,
    {nargs = "*"}
)

vim.api.nvim_create_user_command("MomentOpen",
    function (opts)
        if not main_socket then
            notify("Not connected")
            return
        end

        if opts.fargs[1] == nil then
            vim.notify("Missing arguments: MomentOpen <name>")
        end
        request_buffer(opts.fargs[1])
    end,
    {nargs = "*"}
)


vim.loop.new_timer():start(0, 100, render_float_cursors)
