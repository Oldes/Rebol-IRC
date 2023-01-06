REBOL [
    Title:  "IRC Bot Test script"
    author: @Oldes
    file:    https://raw.githubusercontent.com/Oldes/Rebol-IRC/master/irc-test.r3
    needs:   3.10.2
]
system/options/quiet: false
system/options/log/irc: 4

irc: import %irc.reb

;- Common IRC connection options                                               
options: object [
	user: "RebolCI"
	real: "https://github.com/Oldes/Rebol-IRC"
]

;- Common IRC input handlers                                                   
my-commands: make map! reduce/no-set [
	PRIVMSG: function/with [ircp cmd][
		print ["PRIVMSG:" mold cmd]

		;; decide if response to a channel or to an user privately
		recipient: either cmd/args/1/1 = #"#" [cmd/args/1][cmd/nick]

		any [
			;-- Actions which are send to me in private and only by my master...
			if all [
				cmd/host = "freenode/user/oldes"
				cmd/args/1 = ircp/spec/user
			][
				parse cmd/args/2 [
					"verbose" some space set val: some numeric to end (
						print [as-yellow "Changing verosity to:" val]
						system/options/log/irc: to integer! val
					)
				]
			]
			;-- Any recognized action sent by anyone...                         
			parse cmd/args/2 [
				"How are you?" (
					recycle recycle
					append ircp ajoin ["PRIVMSG " recipient " :I'm fine, thank you!"]
					append ircp ajoin ["PRIVMSG " recipient " :My memory usage is: " stats]
				)
				|
				"stats" (
					recycle recycle
					try [delete %.stats]
					echo %.stats
					stats/show
					echo none
					foreach line read/lines %.stats [
						append ircp ajoin ["PRIVMSG " recipient " :" line]
					]
				)
			]
		]
	] :system/catalog/bitsets

	PONG: func[ircp cmd][
		;; This is just an example how to do a custom action and still keep the default one.
		try [print [format-date-time now "hh:mm:ss pong:" (stats/timer - to time! cmd/args/2)]]
		;; Return FALSE so also the default action will be called,
		;; which is ok, because the default action is used to catch server response timeouts.
		false
	]
	JOIN:  func[ircp cmd][
		append ircp ajoin ["WHOIS " cmd/nick]
		if all [
			cmd/host = "freenode/user/oldes"
			cmd/args/1 = "#rebol"
		][
			append ircp ajoin ["MODE " cmd/args/1 " +o " cmd/nick]
		]
	]
]

freenode.irc: make port! [
	scheme:   'irc
	user:     :options/user
	real:     :options/real
	host:     "chat.freenode.net"
	commands: :my-commands
]
libera.irc: make port! [
	scheme:   'irc
	user:     :options/user
	real:     :options/real
	host:     "irc.eu.libera.chat"
	commands: :my-commands
]
oftc.irc: make port! [
	scheme:   'irc
	user:     :options/user
	real:     :options/real
	host:     "irc.oftc.net"
	port:      6667
	commands: :my-commands
]

do-connect: function [
	"Connect to given IRC port or ports."
	ircs [port! block!]
	/shutdown date [date!]
][
	ircs: either block? ircs [reduce ircs][reduce [ircs]]
	ports: copy [30]
	forall ircs [
		unless port? port: ircs/1 [remove ircs continue]
		print [as-yellow "Opening connection:" as-green port/spec/host now/utc]
		either error? try [open port][
			print as-purpe "*** Failed to connect!"
		][
			;print "Port opened!"
			append ports port
		]
	]
	if empty? ports [
		print as-purpe "*** No IRC ports to process!"
		return false
	]
	forever [
		try/except [
			port: wait :ports
			if all [shutdown now >= date] [
				;; The life time expired...
				;; This code is evaluated for each closed port!
				either none? done? [
					;; For the first time, send the QUIT message to server
					print as-yellow "Shutdown all connections!"
					done?: true
					foreach port next ports [
						if all [open? port port/state <> 'QUIT] [
							done?: false
							write port "QUIT :My life time ended!"
							port/state: 'QUIT
						]
					]
				][
					print "Testing if all ports are closed..."
					done?: true
					foreach port next ports [
						if open? port [
							print "Not yet!"
							done?: false ;; there is still opened port, so keep waiting...
							break        ;; no need to try other ports
						]
					]
				]
				either done? [break][continue]
			]
			;; If there is no action on any port, timeout may also awake...
			if none? port [ ;; on timeout
				foreach port next ports [
					if port? port [
						either open? port [
							;; Try to send PING to each condition to keep the connection alive.
							write port 'PING
						][
							;; Try to reopen the connection if it was lost.
							print [as-yellow "Re-opening connection:" as-green port/spec/ref now/utc]
							try [open port]
						]
					]
				]
			]
		][
			print system/state/last-error
			if any [not shutdown date > now + 0:0:5][
				print [now/utc "Will try to reconnect all not opened ports..."]
				wait 0:0:5
				foreach port next ports [ try [open port] ]
			]
		]
	]
]

print as-green "IRC TEST START"
;; Open connection to multiple IRC servers simultaneously
do-connect/shutdown [
	freenode.irc
	libera.irc
	oftc.irc
] now + 0:1:0 ;; shutdown all connections after 1 minute

print as-green "IRC TEST DONE"
