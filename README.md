[![rebol-irc](https://github.com/user-attachments/assets/58ea3d37-478d-4b1c-ba5f-62533a300a05)](https://github.com/Oldes/Rebol-IRC)

[![Rebol-IRC CI](https://github.com/Oldes/Rebol-IRC/actions/workflows/main.yml/badge.svg)](https://github.com/Oldes/Rebol-IRC/actions/workflows/main.yml)
[![Gitter](https://badges.gitter.im/rebol3/community.svg)](https://app.gitter.im/#/room/#Rebol3:gitter.im)
[![Zulip](https://img.shields.io/badge/zulip-join_chat-brightgreen.svg)](https://rebol.zulipchat.com/)

# Rebol/IRC

Rebol IRC scheme for [Rebol3](https://github.com/Oldes/Rebol3).

## Basic usage example
This is minimal code, which does not handles reconnection and has almost no command handlers.
```rebol
import %irc.reb
port: make port! [
    scheme:  'irc
    user:    "MyReBot"
    real:    "My Full Name"
    host:    "irc.libera.chat"
    commands: make map! reduce/no-set [
        PRIVMSG: func[ircp cmd][ print ["PRIVMSG:" mold cmd] ]
        001      func[ircp cmd][ print "You are connected now!" ]
    ]
]
open port                     ;; Initialize the connection
forever [
    res: wait [port 30]       ;; Wakeup after every 30 seconds
    unless open? port [break] ;; Connection was lost, so exit the loop
    unless res [
        write port 'PING      ;; Send PING to server
    ]
]
```

For more complex example see: [irc-test.r3](https://github.com/Oldes/Rebol-IRC/blob/master/irc-test.r3)
