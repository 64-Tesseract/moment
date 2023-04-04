# Moment
A collaborative editing Neovim plugin that isn't:
- A buggy mess (at least not when you use it normally)
- 5000 lines long
- Harder to set up than FTPD

_Everyone's asking for it, so why didn't anyone make it yet? It only took me a week._

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

### Other commands
`MomentStatus`  
Shows a list of users connected and shared buffers.

## Example usage
```
Server                | Client
MomentHost 1234       |
MomentShare project   | MomentJoin 192.168.0.5 1234
                      | MomentOpen project
```
Simple as that. All users should be able to immediately see each other's changes - no mucking around with "sessions" or "single" instance nonsense.

## Caveats
- Undo history is shared.
- Edits are made lines at a time, so don't edit the same line as someone else or you'll overwrite each other.
- Remote cursors are only visible if the same window is selected.
  This could be fixed by checking tabpages, but it didn't work the first time I tried so it's a feature now.
- Remote cursors are not accurate if lines wrap.
- Only the server can share new buffers.  
  To share and edit a file on the client side, you can `MomentOpen` in the file you want to share, then undo to restore the old text.
- Completely insecure, any and all clients are accepted and data is sent to them.  
  You might like to use SSH and connect to localhost, at the cost of lag in the editor.
- Changes to any file are sent to all clients, even if they don't have that buffer open.  
  Might cause lag to all clients if you're pasting 10k lines at a time. If you are, it'd be best to open a new Neovim instance and host another server.
- Don't know how to quit? That makes 2 of us! Just close the Neovim instance to send EOF to all sockets and disconnect.
