# Moment
_Everyone's looking for it, so why didn't anyone make it yet?_

A collaborative editing Neovim plugin that isn't:
- 5000 lines long
- Harder to set up than an FTP server
- Older than Neovim itself
- ~~A buggy mess~~  
  _Ok it's definitely a little buggy, but at least it doesn't throw indecipherable errors every 5 seconds_

## Features
- Buffers update immediately in all clients
- Multiple buffers can be hosted per server, which clients can choose to follow
- Remote cursors display what line users are on

## Installation
With Plug, in your `init.nvim`:
```
call Plug#begin()
plug '64-Tesseract/moment'
call Plug#end()
```

Or put `moment.lua` in `~/.config/nvim/lua`, and in your `init.nvim`:
```
lua require('moment')
```

You can also set your username by putting the following in your `init.nvim`, *before* you load the plugin:
```
let g:moment_username = 'YourUsernameHere'
lua require('moment')
```

## Commands
### Server commands
`MomentHost <port>`  
Host a websocket that clients may connect to. No buffers are shared yet.

`MomentShare <name>`  
Provide a buffer to share to remote clients, identified by `name`. Changes made to it by either server or client will be forwarded to all other users.

### Client commands
`MomentJoin <ip> <port>`  
Connects to a server's websocket, receiving information about it like users connected and available shared buffers.

`MomentOpen <name>`  
Loads a buffer shared by the server and binds it to the currently opened buffer, applying changes from the server and sending local edits.  
Make sure not to open a remote buffer in a buffer with data already in it - you'll be able to undo to get back the original text, but it will replace everyone else's buffer as well - unless that's your intent.

### Mutual commands
`MomentStatus`  
Shows a list of connected users and shared buffers.

## Example usage
```
Server                | Client
MomentHost 1234       |
MomentShare project   | MomentJoin 127.0.0.1 1234
                      | MomentOpen project
```
Simple as that. All users should be able to immediately see each other's changes - no mucking around with "sessions" or "single" instance nonsense.

## Caveats
- I don't know how to make async requests.  
  Some requests will probably get doubled up and returned to clients, even though I specifically told it not to do that.  
  Best to use SSH and connect to `127.0.0.1` to eliminate desyncs "rubber-banding" while trying to type.
- Undo history is shared.
- Edits are made lines at a time, so don't edit the same line as someone else or you'll overwrite each other.
- Multiline edits (from the end of one line to the start of the other) cause line duplication, don't do it.
- Remote cursors are only visible if the same window is selected.  
  This could be fixed by checking tabpages, but it didn't work the first time I tried so it's a feature now.
- Remote cursors are not accurate if lines wrap.
- Only the server can share new buffers.  
  ~~To share and edit a file on the client side, you can `MomentOpen` in the file you want to share, then undo to restore the old text.~~  
  _Sending lots of data could be bad, try to avoid it..._
- Completely insecure, any and all clients are accepted and data is sent to them.
- Changes to any file are sent to all clients, even if they don't have that buffer open.  
  Might cause lag to all clients if you're pasting 10k lines at a time. If you are, it'd be best to open a new Neovim instance and host another server.
- Don't know how to quit? That makes 2 of us! Just close the Neovim instance to send EOF to all sockets and disconnect.
