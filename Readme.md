# Gdmaster - Open masterlist server written in Godot's gdscript. 

This is a conceptual work. Not tested in production.

## Description

This is a simple, opensource masterlist server, written in Godot's gdscript. Server keeps a list of 
IP's (IPv4) and ports and other additional game info in memory and when player clients ask for a 
serverlist it sends IP lists, based on the requested game information. This is used for games that 
have server browsers, to retrieve all game servers from masterlist.
You can use it with any game that you can develop and implement a simple UDP packet sender 
and receiver.

This application is heavily inspired by Dark Places Master Server (dpmaster) with the help of 
Xonotic community members help.

Why does this exist when we already have dpmaster? 
Because Godot's high-level multiplayer networking API does allow for sending (you can send) but not 
receiving (you can't receive) packets from hosted game's port (game port). Dpmaster requires 
client's (servers) to send, information about server, from the same port that the game is hosted on. 
And this IP:PORT combination will be added to masterlist. 

Example your game run on port 27800. Players use this port number to connect to the game and join 
the game server. The game server needs to send "heartbeat" to dpmaster and await "getinfo" response 
from dpmaster with a "challenge" that is needed for sending back "infoResponse" with game 
parameters. These parameters along with sender's IP and PORT from which the packet has been received 
on dpmaster are added to the masterlist.

As you can see this is not doable (as far as i know in Godot 4.3) in Godot, when you use high level 
multiplayer API to host game server.

For this exact reason, I wrote this application, to allow game servers to add additional information 
in "inforResponse" such as "host" and "port" properties. These will be parsed and then set in the 
masterlist.

## Configuration

You can configure the app by passing in launch arguments. Application runs in --headless mode by 
default. You can add additional arguments if need be.

- Save all output to logfile. Logfile "log.log" is generated next to the executable. By default, it 
is not enabled.
	
	--log 
	
- GDmaster listen port. Defined as UDP port. By default, it runs on 27777 port.
	
	--port integer

- Games that are allowed/rejected to send heartbeats to the gdmaster. Only one option "accept" or 
"reject" can be specified. By default, all games are accepted and none are rejected.
	
	--game-policy accept game1-no-space Game2-case-sensitive ..
	or
	--game-policy reject game3 game4 ..

- Game protocol to filter games more precisely. By default, all protocols are accepted.

	--protocol integer1 integer2

- Custom game properties. By default, no custom properties are defined.

	--game-properties gametype boobs team modded ..

## Running application

To run this application, either build it from source or use pre-built binaries.

Windows Example:
	
1. Create a "run.bat" file and add the name of the gdmaster executable and various options/arguments 
if you want:
	
	```batch
	gdmaster.exe --log --port 27777 --protocol 4522
	```
2. Save it and run the "run.bat" file.

Linux Example:

1. Create a "run.sh" file and add the name of the gdmaster executable and various options/arguments 
if you want:
	
	```sh
	#!/bin/bash
	
	./gdmaster.x86_64 --log --port 27777 --protocol 4522
	```
	
2. Make it executable:
	
	```
	chmod u+x run.sh
	```
	
3. Run it:
	
	```
	./run.sh
	```
Android/ARM/iOS/MAC Example:
	
1. Please don’t

Note:
	You will have to handle the server crashes and reboots yourself.
	In these example we didn't specify any game policy so all games will be accepted that uses this
	specific protocol - 4522.

## Usage during runtime

You have little bit of control once the gdmaster is runing. Here is a list of available commands:
	
- To show this list of available commands, enter:
	
	`help`
	
- To getservers, enter:
	
	`getservers gamename protocol empty full property=value property2=value2`

	Note:
		<gamename> and <protocol> are mandatory, <empty>, <full>, <property=value> are optional:

- To list current servers in memory, enter:

	`list-servers`
	
	Note:
		This command will display all current servers in memory.

- To save server list to json file, enter:

	`save-servers <filename-no-extension>`
	
	Note:
		Enter <filename-no-extension> without extension or leave blank. File will be saved next to 
		executable.

- To load servers from json file, enter:

	`load-servers file.json`
	
	Note:
		File.json has to be located next to executable.
		
- To clear server list, enter:

	`clear-servers`
		
- To enable logfile, enter:
	
	`log-enable`

- To disable logfile, enter:

	`log-disable`

- To list PacketPeerUDP peers, enter:

	`list-peers`

- To quit application, enter:

	`quit`

## Technical information

Every communication with gdmaster must contain a header. Header consists of four bytes of fluff 
followed by message string. Packets that do not contain this header will be rejected.
Examples below are written in C like fashion. In other words "xFF" and "x0A" are "[255]" and "[10]" 
in Godot's PackedByteArray lingo or you could say "String.chr(255)" and "String.chr(10)".

- heartbeat <--- client

	Heartbeat is sent by the server when it wants to be noticed by a gdmaster. Server should send 
	heartbeat once ever 8min (default gdmaster time_to_live is 10min), otherwise the server will be 
	marked as unavailable and removed from master list. Server also should send heartbeat when 
	it becomes full or empty.
	
	Example:
		"\xFF\xFF\xFF\xFFheartbeat DarkPlaces\x0A"
		
	Note:
		Heartbeat must contain "DarkPlaces" string otherwise it will not work. Following the 
		dpmaster standard.
		
- getinfo ---> client

	Getinfo is sent by gdmaster to the server that sent heartbeat as a response to that request. The 
	getinfo response contains challenge that must be sent along with infoResponse.
	
	Example:
		"\xFF\xFF\xFF\xFFgetinfo A_ch4Lleng3"

- infoResponse <--- client

	Inforesponse is sent by the server as a reply to gdmaster's getinfo request. This response has
	to contain "must have" properties - "gamename","sv_maxclients","clients","protocol","challenge",
	"public". The message type is followed by a line feed character and the server's infostring. An 
	infostring is a series of keys and values separated by '\'s. "sv_maxclients" (the maximum number 
	of clients allowed on the server) must not be 0 or lower than "clients" value. "protocol" must 
	be an integer number. "public" is either 1 or 0. By default "public" property must be 1, this 
	ensures that the server is served to public, if you want to disable server visibility in 
	"getservers" requests then you need to set "public" to 0.
	
	Example:
		"\xFF\xFF\xFF\xFFinfoResponse\x0A\\sv_maxclients\\8\\clients\\0\\.."
		
	Note:
		There are also special properties that can be used - "host", "port". For changing server IP 
		you can use "host" property. You can specify FQDN and gdmaster will try to resolve the IPv4. 
		If resolve fails, then the packet sender IP will be used. You can specify game port if 
		you are not sending infoResponse from game port using "port" property. If "port" property is 
		not specified, then packet sender port will be used. There are also forbidden properties - 
		"time", "available". Packets that contain these will be rejected.
	
- getservers <--- client
	
	Getservers request is sent by server or any other client of gdmaster that wants to retrieve 
	server list. The client will receive getserversResponse with a list of IP and Ports that the 
	requested games are hosted on. After that it is up to a client to make connections with these 
	IPs to get other game data. Each argument cannot contain spaces. The syntax is as follows: 
	"getservers <GameName> <Protocol> empty full <property=value>". "GameName" must be the first 
	property, followed by a "protocol", the rest are optional. "Empty" option will return empty 
	servers and "full" option will return full servers. 
	
	Example:
		"\xFF\xFF\xFF\xFFgetservers MyGame 1337 empty full gametype=dm someprop=value"
	
- getserversResponse ---> client

	GetserversResponse is sent by the gdmaster as a reply to server's getservers request. The list 
	of servers is composed of IPv4 addresses and ports. Each server is stored on 4 bytes for the IP 
	address and 2 bytes for the port number, and a "\" to separate it from the next server. All 
	numbers are big-endian oriented (most significant bytes first). For instance, a server hosted at 
	address 1.2.3.4 on port 2048 will be sent as: "\x01\x02\x03\x04\x08\x00". In Godot's 
	PackedByteArray it would look like [1,2,3,4,8,0,92]. Note that the "92" is "\"
	
	If the list is too big to fit into one single network packet (by default no bigger than 1.4kb or 
	that roughly translates to 193 server addresses and ports.), dpmaster will create as many 
	getserversResponses as necessary to send all the matching servers. The last message contains a 
	fake server at the end of the list, which is the 6-byte string "EOT\0\0\0", to tell the client 
	that the master has finished to send the server list (EOT stands for "End Of Transmission"). In 
	Godot's PackedByteArray it would look like [69, 79, 84, 0, 0, 0].

	Example:
		 "\xFF\xFF\xFF\xFFgetserversResponse\\[...]\\EOT\0\0\0"
