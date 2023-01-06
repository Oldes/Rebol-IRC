REBOL [
	Title:  "IRC scheme"
	type:    module
	name:    irc
	date:    6-Jan-2023
	file:    https://raw.githubusercontent.com/Oldes/Rebol-IRC/master/irc.reb
	version: 0.0.1
	author: @Oldes
	references: {
	Related IRC documentations:
	http://www.faqs.org/rfc/rfc1459.txt - "Internet Relay Chat Protocol"
	http://www.faqs.org/rfc/rfc2810.txt - "Internet Relay Chat: Architecture"
	http://www.faqs.org/rfc/rfc2811.txt - "Internet Relay Chat: Channel Management"
	http://www.faqs.org/rfc/rfc2812.txt - "Internet Relay Chat: Client Protocol"
	http://www.faqs.org/rfc/rfc2813.txt - "Internet Relay Chat: Server Protocol"
	http://www.faqs.org/rfc/rfc1413.txt - "Identification Protocol"}
	note: {
		Currently the scheme is designed to be working in an autonomous mode
		without any users interaction. All actions must be handled in provided
		`port/spec/commands` map.
	}
	needs: 3.10.2
]

system/options/log/irc: 4

;; some parse related values...
digit:         system/catalog/bitsets/numeric
letter:        system/catalog/bitsets/alpha
digit-letter:  system/catalog/bitsets/alpha-numeric
chuser:        make bitset! [not bits #{802400008000000080}] ;; any octet except NUL, CR, LF, " " and "@"
nospcrlfcl:    make bitset! [not bits #{8024000080000020}]   ;; any octet except NUL, CR, LF, " " and ":"
nosp:          make bitset! [not bits #{0000000080}]
special:       make bitset! #{00000000000000000000001F8000001C} ;"[]\`_^^{|}"
to-space:     [some nosp | end]
=nickname:    [[letter | special] 0 8 [digit-letter | special | #"-"] ahead [#"!" | #" "]]
=user:        [some chuser]
=shortname:   [some digit-letter any [digit-letter | #"-" | #"/"]] ;@@ RFC does not mention /, but freenode is using it!
=hostname:    [=shortname any [#"." =shortname]]
=command:     [some letter | 3 digit]

;; helpers...
hide-secrets: func[
	;- Replaces passwords and other secrets from the traced message
	message [string!]
	/local safe
][
	safe: append clear "" message
	parse safe [
		;; just one for now...
		"PRIVMSG NickServ :IDENTIFY "
		change to end "***secret***"
	]
	safe
]

on-line: function[
	;- Parses a single command line and processes it
	ircp [port!]
	line [binary! string!]
][
	msg: to string! line
	ctx: ircp/extra
	out: ctx/output
	cmd: ctx/command
	cmd/args: clear []

	sys/log/debug 'IRC ["Server:^[[32m" msg]

	parse msg [
		opt [
			#":" [
				copy nick: =nickname
				opt [#"!" copy user: =user]
				opt [#"@" copy host: =hostname]
				space
				|
				copy host: some nospcrlfcl space
			]
		]
		[
		  copy comm:    3 digit  (comm: to integer! comm)
		| copy comm: some letter (comm: to word! comm)
		]
		any [
		  some space #":" copy tmp: to end   (append cmd/args tmp)
		| some space      copy tmp: to-space (append cmd/args tmp)
		]
	]
	cmd/nick: nick
	cmd/user: user
	cmd/host: host
	cmd/comm: comm

	if any [
		;; user defined action first...
		not function? action: :ircp/spec/commands/:comm
		not action ircp cmd
	][	;; default action if there is no user's action or if user's action is truthy
		default-commands/:comm ircp cmd
	]
]

on-conn-awake: function [
	;- Function which is evaluated when the internal TCP port has an event
	event [event!]
][
	conn:  event/port   ;; the internal TCP/TLS port
	ircp:  conn/parent  ;; the upper level IRC port
	ctx:   ircp/extra   ;; IRC port level

	;sys/log/debug 'IRC ["Awake! State:" ircp/state "event:" event/type "ref:" event/port/spec/ref]

	ctx/timestamp: stats/timer

	wake?: switch event/type [
		error [
			sys/log/error 'IRC ctx/error: "Network error"
			close conn
			ctx/error
		]
		lookup [
			open conn
			false  ;; no awake
		]
		connect [
			append ircp ajoin ["NICK " ircp/spec/user]
			append ircp ajoin ["USER " ircp/spec/user " 0 * :" ircp/spec/real]
			sys/log/more 'IRC "Reading server's invitation..."
			flush  ircp
			false  ;; no awake
		]
		read [
			data: conn/data
			parse data [any[
				copy line: to CRLF 2 skip data: (
					on-line ircp line
				)
			]]
			;; remove already processed data but keep the rest, if there is any
			truncate data

			either any [
				not empty? conn/data       ;; if there are still some data,
				empty? out: ctx/output     ;; or there is nothing to send...
			][
				read conn                  ;; keep reading
			][
				flush ircp                 ;; else send the output (removing what is sent from the buffer)
			]
			false  ;; no awake
		]
		wrote [
			read conn
			false  ;; no awake
		]
		close [
			ctx/error: "Port closed on me"
		]
	]
	if ctx/error [ ircp/state: 'ERROR ]
	if wake? [
		insert system/ports/system make event! [type: ircp/state port: ircp]
	]
	false
	;to logic! wake?
]

sys/make-scheme [
	name: 'irc
	title: "Internet Relay Chat"
	spec: make system/standard/port-spec-net [
		port:     6667
		timeout:  30
		channel:  "rebol"
		user:     none
		real:     ""
		password: none
		commands: #()
	]
	awake: func[event /local port type err][
		port: event/port
		type: event/type
		sys/log/debug 'IRC ["IRC-Awake event:" type]
		switch/default type [
			error
			close [
				port/state: type
				if port/extra [
					err: :port/extra/error
					try [ close port/extra/connection ]
					port/extra: none
					port/state: none
					;if err [
					;	;@@ could be reported into upper level, if possible
					;	;@@ instead of just failing!
					;	do make error! :err
					;]
				]
				true ;; awakes from a wait call!
			]
		][
			;@@ Is this correct? What if the even is sent from the on-conn-awake?!
			on-conn-awake :event
		]
	]
	actor: [
		open: func [port [port!] /local ctx spec conn][
			if open? port [return port]
			port/extra: ctx: construct [
				connection:  ;; Internal TCP or TLS connection
				output:      ;; Output temporary buffer
				nick:        ;; Current user's nick (may be different than requested!)
				mode:        ;; Current user's mode
				error:       ;; Used to store an error object or message
				ping:        ;; High resolution time used as a PING cookie
				since:       ;; UTC datetime since connection started
				message:     ;; Used to collect a message of the day
				command:     ;; Current command modified for each line (parsed)
				timestamp:   ;; Timestamp of the last awake
			]
			port/data:   make binary! 500
			ctx/output:  make binary! 500
			ctx/mode:    copy ""
			ctx/command: construct [
				comm: ;; word or integer
				nick:
				user:
				host:
				args:
			]

			spec: port/spec

			conn: context [
				scheme: none
				host:   spec/host
				port:   spec/port
				ref:    none
			]
			conn/scheme: either 6697 == spec/port ['tls]['tcp]
			;; `ref` is used in logging and errors
			conn/ref: as url! ajoin [conn/scheme "://" spec/host #":" spec/port]
			spec/ref: as url! ajoin ["irc://" spec/user #"@" spec/host #":" spec/port]

			port/state: 'INIT
			port/extra/connection: conn: make port! conn

			conn/parent: port
			conn/awake: :on-conn-awake

			open conn ;-- open the actual tcp (or tls) port
			
			; return the newly created port
			port
		]

		open?: func [
			port [port!] /local conn
		][
			to logic! all [
				port/state
				port/extra
				port? conn: port/extra/connection
				open? conn
			]
		]
		
		close: func [
			port [port!]
		][
			sys/log/debug 'IRC ["Closing..." port/spec/ref "(" now/utc ")"]
			port/state: 'CLOSING
			try [ close port/extra/connection ]
			
			port/extra: none
			port/state: none
			insert system/ports/system make event! [ type: 'close port: port ]
			port
		]
		
		read: func [
			port [port!]
		][
			if all [
				;; allow `read` when we already initialized connection...
				port/state <> 'INIT
				not open? port
			][ cause-error 'Access 'not-open port/spec/ref ]

			either all [
				find [WRITING INIT] port/state
				port? wait [port port/spec/timeout]
				port/data
			][
				copy port/data
			][	none ]
		]

		write: func [
			port [port!]
			value
			/local timer
		][
			unless open? port [return false]
			if :value = 'PING [
				timer: stats/timer
				if 0:1:0 < subtract timer port/extra/timestamp [
					;; there was no reply from previous PING or any other awake,
					;; server is not responing, so close connection...
					sys/log/error 'IRC "No response from server!"
					return close port
				]
				if port/extra/ping [
					;; there is still pending previous ping...
					return false
				]
				value: ajoin ["PING :" port/extra/ping: timer]
			]
			append port value
			flush port
		]

		append: func [
			port  [port!]
			value 
		][
			sys/log/more 'IRC ["Client:^[[32m" hide-secrets value]
			append append port/extra/output value CRLF
		]
		
		flush: func[
			port [port!]
			/local bytes out
		][
			all [
				;; flush only when there are no data on the input...
				empty? port/extra/connection/data
				;; and when there are some output data ready to be sent
				0 < bytes: length? out: port/extra/output
				sys/log/debug 'IRC ["Sending" bytes "bytes."]
				write port/extra/connection take/part out bytes
			]
		]
	]
]

default-commands: make map! reduce/no-set [
	PING: func[ircp cmd][append ircp ajoin ["PONG " cmd/args]]
	PONG: func[ircp cmd][ircp/extra/ping: none]
	MODE: func[ircp cmd /local mode][
		if cmd/args/1 = ircp/spec/user [
			parse cmd/args/2 [
				  #"+" copy mode: some letter (ircp/extra/mode: union/case   ircp/extra/mode mode)
				| #"-" copy mode: some letter (ircp/extra/mode: exclude/case ircp/extra/mode mode)
			]
			sys/log/info 'IRC ["Current user modes:" ircp/extra/mode]
		]
	]
	PRIVMSG: func[ircp cmd][print cmd/args]
	NOTICE:  func[ircp cmd][
		print [as-red "NOTICE:" cmd/args/2]
		if all [
			cmd/nick == "NickServ"
			ircp/spec/password
		][
			parse cmd/args/2 [
				"This nickname is registered" to end (
					append ircp ajoin ["PRIVMSG NickServ :IDENTIFY " ircp/spec/password]
				)
			]
		]
	]

	001 func[ircp cmd][
		ircp/state: 'CONNECTED
		ircp/extra/since: now/utc/precise
		append ircp "JOIN #rebol"
	]
	375 func[ircp cmd][ ircp/extra/message: make block! 10 ]
	372 func[ircp cmd][ append ircp/extra/message cmd/args/2 ]
	376 func[ircp cmd][ foreach line ircp/extra/message [print as-cyan line] ]
]
