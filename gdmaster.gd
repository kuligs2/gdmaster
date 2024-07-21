class_name ServerNode
extends Node

@onready var logging: Logging = $Logging

var USE_LOGFILES = false # saves all output to logfile in the same dir where app is run from. Used mainly for debugging.
var LISTEN_PORT = 27777 # port on whic the gdmaster is listening for packets
var TIME_TO_LIVE = 600.0 # seconds for server to be marked as not avaliable / deleted from list and not served to clients. Default value is 10min.
var TIME_TO_LIVE_CHALLENGE = 2 # seconds for challenge to expire

var ipv4_regex = RegEx.new() # Used to verify that the string is correct IPv4 address
var server_udp := UDPServer.new() # gdmaster main server
var peers = {} # Temp location for connected peers that could send response
var challenges = [] # Temp location to keep challenges for verification

# Server list. During runtime this is where servers live.
var server_ip_list = []

var GAME_POLICY_NAME:Array = [] # Leave blank to accept all gamenames. If defined then all other games will be rejected.
var GAME_POLICY_NAME_REJECT:Array = [] # If defined then these will be rejected and all other will be accepted.
var GAME_POLICY_PROTOCOL:Array = [] # Leave blank to accept all protocol numbers. This is used to further more filter games based on the same name.

const GAME_PROPERTIES:Array = ["gamename","sv_maxclients","clients","protocol","challenge","public"] # InfoResponse must have these.

var GAME_CUSTOM_PROPERTIES:Array = [] # Leave blank to accept any prop. Otherwise if defined, gdmster will recect any InfoResponse that does not contain these props.

const CHALLENGE_MAX_LENGTH = 12  # Define as appropriate. Following dpmaster convention.
const CHALLENGE_MIN_LENGTH = 9   # Define as appropriate. Following dpmaster convention.
const MAX_SERVER_RETURN_ARRAY_SIZE = 193 # Don't touch. Used to limit the ammount of servers to be sent to client. Following dpmaster convention.
const MAX_PACKET_SIZE_OUT = 1400 # Bad touch. Used to limit the ammount of servers to be sent to client. Following dpmaster convention.

var cmd_thread : Thread
var master_thread: Thread
var server_is_listening:bool = false

var export_config = ConfigFile.new()
var export_config_path = "res://export_presets.cfg"

func _ready():
	print_rich("\n [color=yellow]> Gdmaster launching..  [/color]\n")
	# Load config file
	var config_error = export_config.load(export_config_path)
	if config_error == OK:
		# Print version
		pass
	# Initialize with args
	var args = parse_cmd_args()
	if args:
		apply_cmd_args(args)
	print_server_config()
	# Launch server
	var ok = server_udp.listen(LISTEN_PORT)
	if ok == OK:
		print_rich("\n [color=yellow]> Gdmaster started on [/color][color=green]Port [/color][color=orange]" + str(LISTEN_PORT) + " [/color][color=green]Successfully![/color]")
		logging.save_to_file(str("\n > Gdmaster started on Port " + str(LISTEN_PORT) + " Successfully!"))
		server_is_listening = true
	else:
		print_rich("\n [color=red]>> Failed to bind to [/color][color=green]Port [/color][color=orange]" + str(LISTEN_PORT) + " [/color]")
		logging.save_to_file(str("\n >> Failed to bind to Port: " + str(LISTEN_PORT)))
	print_rich("\n[color=yellow]Enter [/color][color=green]help[/color][color=yellow] for help or [/color][color=green]quit[/color][color=yellow] to quit: \n")
	ipv4_regex.compile("^((25[0-5]|(2[0-4]|1[0-9]|[1-9]|)[0-9])(\\.(?!$)|$)){4}$")
	cmd_thread = Thread.new()
	cmd_thread.start(_stdin_thread)
	master_thread = Thread.new()
	master_thread.start(poll_server, Thread.PRIORITY_HIGH)
	pass

func _stdin_thread() -> void:
	var _input_str = ""
	while _input_str != "quit" or _input_str != "q":
		_input_str = OS.read_string_from_stdin().strip_edges()
		var input_arr = _input_str.split(" ")
		if _input_str:
			match input_arr[0]:
				"--help","help","-h","h","?":
					print_rich("[color=yellow]> Selected: help:[/color]")
					print_rich("\n[color=yellow]# ---------------------------------------------- [/color] \n")
					print_rich("[color=yellow]> To show this help, enter either one of:[/color]")
					print_rich("\t[color=green]h --help help -h ?[/color]")
					print_rich("[color=yellow]> To getservers, enter:[/color]")
					print_rich("[color=yellow]> <gamename> and <protocol> are mandatory, <empty>, <full>, <property=value> are optional:[/color]")
					print_rich("\t[color=green]getservers[/color] [color=orange]gamename protocol empty full property=value property2=value2[/color]")
					print_rich("[color=yellow]> To list current servers in memory, enter:[/color]")
					print_rich("\t[color=green]list-servers[/color]")
					print_rich("[color=yellow]> To save server list to json file, enter:[/color]")
					print_rich("[color=yellow]> <filename> without extension or leave blank:[/color]")
					print_rich("\t[color=green]save-servers [/color] [color=orange]<filename-no-extension>[/color]")
					print_rich("[color=yellow]> To load servers from json file, enter:[/color]")
					print_rich("\t[color=green]load-servers[/color] [color=orange]file.json[/color]")
					print_rich("[color=yellow]> To clear server list, enter:[/color]")
					print_rich("\t[color=green]clear-servers[/color]")
					print_rich("[color=yellow]> To enable logfile, enter:[/color]")
					print_rich("\t[color=green]log-enable[/color]")
					print_rich("[color=yellow]> To disable logfile, enter:[/color]")
					print_rich("\t[color=green]log-disable[/color]")
					print_rich("[color=yellow]> To list PacketPeerUDP peers, enter:[/color]")
					print_rich("\t[color=green]list-peers[/color]")
					print_rich("[color=yellow]> To quit application, enter:[/color]")
					print_rich("\t[color=green]quit[/color]")
					print_rich("\n[color=yellow]# ---------------------------------------------- [/color] \n")
				"quit","q":
					print_rich("[color=yellow]> Quitting application. BYE![/color]")
					logging.save_to_file("Quitting application. BYE!")
					server_is_listening = false
					call_deferred_thread_group("stop_threads")
					get_tree().quit()
					break
				"list-servers":
					print_rich("[color=yellow]> Selected: list-servers:[/color] \n")
					if server_ip_list.size()>0:
						print_rich("[color=yellow]> Current server list contains: ([/color][color=orange]%s[/color][color=yellow])[/color] \n" % server_ip_list.size())
						print_rich("[color=yellow]> ---------------------------------------------- [/color]\n")
						print_rich("[color=orange]"+str(JSON.stringify(server_ip_list, "\t")),"[/color] \n")
						print_rich("[color=yellow]> ---------------------------------------------- [/color]\n")
					else:
						print_rich("[color=yellow]> Current server list contains: ([/color][color=orange]%s[/color][color=yellow])[/color] \n" % server_ip_list.size())
						print_rich("[color=yellow]> Nothing to list[/color]")
				"save-servers":
					print_rich("[color=yellow]> Selected: save-servers: [/color]\n")
					if server_ip_list.size()>0:
						print_rich("[color=yellow]> Saving server list: ([/color][color=orange]%s[/color][color=yellow])[/color] \n" % server_ip_list.size())
						var path = ""
						if input_arr.size() >1 and input_arr[1] != "":
							path = save_server_list_to_json(server_ip_list,input_arr[1])
						else:
							path = save_server_list_to_json(server_ip_list)
						print_rich("[color=yellow]> Saved to: [/color][color=green]%s[/color]\n" % path)
						print_rich("[color=yellow]> ---------------------------------------------- [/color]\n")
					else:
						print_rich("[color=yellow]> Current server list contains: ([/color][color=orange]%s[/color][color=yellow])[/color] \n" % server_ip_list.size())
						print_rich("[color=yellow]> Nothing to save[/color]")
				"load-servers":
					print_rich("[color=yellow]> Selected: load-servers: [/color]\n")
					if input_arr.size()>1 and input_arr[1]:
						var path = 	input_arr[1]
						var loaded_list = load_server_list_from_json(path)
						if loaded_list and loaded_list.size() >0:
							print_rich("[color=yellow]> Loaded: ([/color][color=orange]%s[/color][color=yellow]) servers[/color]\n" % loaded_list.size())
							merge_loaded_servers(loaded_list)
							print_rich("[color=yellow]> Current server list contains: ([/color][color=orange]%s[/color][color=yellow])[/color] \n" % server_ip_list.size())
						else:
							print_rich("[color=red]> Error![/color] [color=yellow]Didn'd load anything[/color] \n")							
						print_rich("[color=yellow]> ---------------------------------------------- [/color]\n")
					else:
						print_rich("[color=red]> Error![/color] [color=yellow] No filepath was specified: [/color]\n")
				"clear-servers":
					print_rich("[color=yellow]> Selected: clear-servers: [/color]\n")
					if server_ip_list.size() > 0:
						var server_count = server_ip_list.size()
						server_ip_list.clear()
						print_rich("[color=yellow]> Current server list contains: ([/color][color=orange]%s[/color][color=yellow]) servers[/color]\n" % server_ip_list.size())
						print_rich("[color=yellow]> Cleared: ([/color][color=orange]%s[/color][color=yellow]) servers[/color]\n" % server_count)
					else:
						print_rich("[color=yellow]> There are no servers to clear [/color]\n")
				"getservers":
					var serv_props:Dictionary = get_props_from_get_servers(_input_str)
					var string_bytes = input_arr.slice(1)
					if not  string_bytes.size() < 2:
						var game_name = string_bytes[0].trim_prefix(" ").trim_suffix(" ")
						var game_protocol = string_bytes[1].trim_prefix(" ").trim_suffix(" ")
						var other_filters = string_bytes.slice(2)
						var empty_servers = other_filters.has("empty")
						var full_servers = other_filters.has("full")
						var custom_props = {}
						for i in other_filters:
							if "=" in i:
								var arr = i.split("=")
								var key = arr[0].trim_prefix(" ").trim_suffix(" ")
								var val = arr[1].trim_prefix(" ").trim_suffix(" ")
								custom_props[key]=val
						var serv_arr_available = filter_servers(game_name,game_protocol,custom_props,empty_servers,full_servers)
						print_rich("\n[color=yellow]> Selected: getservers with parameters: [/color]\n")
						print_rich("[color=yellow]> ---------------------------------------------- [/color]\n")
						print_rich("[color=orange]"+str(JSON.stringify(serv_props, "\t")),"[/color] \n")
						print_rich("[color=yellow]> ---------------------------------------------- [/color]\n")
						print_rich("[color=yellow]> Filtered servers: ( [/color][color=orange]%s[/color][color=yellow]/[/color][color=orange]%s [/color][color=yellow])[/color] \n" % [serv_arr_available.size(), server_ip_list.size()])
						if serv_arr_available.size()>0:
							print_rich("[color=yellow]> ---------------------------------------------- [/color]\n")
							print_rich("[color=orange]"+str(JSON.stringify(serv_arr_available, "\t")),"[/color] \n")
							print_rich("[color=yellow]> ---------------------------------------------- [/color]\n")
					else:
						print_rich("\n[color=red]> Error![/color] [color=yellow]Missing one or more getserver parameters: [color=orange]gamename protocol [/color] \n")
				"log-enable":
					USE_LOGFILES = true
					logging.use_logfile = USE_LOGFILES
					print_rich("\n[color=yellow]> Selected: log-enable: [/color]\n")
					print_rich("[color=yellow]> Logging is [/color] [color=green]enabled![/color] \n")
					print_rich("[color=yellow]> ---------------------------------------------- [/color]\n")
				"log-disable":
					USE_LOGFILES = false
					logging.use_logfile = USE_LOGFILES
					print_rich("\n[color=yellow]> Selected: log-disable: [/color]\n")
					print_rich("[color=yellow]> Logging is [/color] [color=red]disabled![/color] \n")
					print_rich("[color=yellow]> ---------------------------------------------- [/color]\n")
				"list-peers":
					print_rich("\n[color=yellow]> Selected: list-peers: [/color]\n")
					print_rich("[color=yellow]> Peer count: [/color] [color=green]%s[/color] \n" % peers.size())
					print_rich("[color=yellow]> Peers: [/color] [color=green]%s[/color] \n" % peers)
				_:
					print_rich("[color=red]> Error![/color] [color=yellow]Command \"[/color] [color=orange]%s[/color] [color=yellow]\" not recognized[/color] \n" % _input_str)

func _exit_tree():
	server_is_listening = false
	if cmd_thread != null and (cmd_thread.is_alive() or cmd_thread.is_started()):
		cmd_thread.wait_to_finish()
	if master_thread != null and (master_thread.is_alive() or master_thread.is_started()):
		master_thread.wait_to_finish()

func stop_threads():
	if cmd_thread != null and (cmd_thread.is_alive() or cmd_thread.is_started()):
		cmd_thread.wait_to_finish()
	if master_thread != null and (master_thread.is_alive() or master_thread.is_started()):
		master_thread.wait_to_finish()

func parse_cmd_args(): 
	var args = OS.get_cmdline_args()
	if args.size() < 1:return
	print_rich("[color=yellow]> Launch arguments detected. Parsing.. ( [/color][color=orange]%s[/color][color=yellow] )[/color]" % [args.size()])
	print_rich("[color=yellow]> ( [/color][color=orange]%s[/color][color=yellow] )[/color]" % [args])
	var index = 0
	var arr = []
	var dic = {}
	var dic_arr =[]
	var key = ""
	while index < args.size():
		var arg = args[index]
		if arg.begins_with("-") and arg.length() > 1:
			if index < 1:
				key = arg.substr(2)
			if index > 0:
				dic[key] = arr.duplicate()
				dic_arr.append(dic.duplicate())
				arr.clear()
				dic.clear()
				key = arg.substr(2)
		else:
			arr.append(arg)
		index += 1
	dic[key] = arr
	dic_arr.append(dic.duplicate())
	var clean_dic = {}
	for key_d:Dictionary in dic_arr:
		var key_n = key_d.keys()[0]
		match key_n:
			"log":
				if clean_dic.has("log"):
					print_rich("[color=red]> Error![/color] [color=yellow] In cmd args. [/color][color=green]log[/color][color=yellow] already defined. Ignoring[/color][color=orange] %s[/color]" % [key_d.values()[0]])
				else:
					clean_dic["log"] = true
			"port":
				if clean_dic.has("port"):
					print_rich("[color=red]> Error![/color] [color=yellow] In cmd args. [/color][color=green]port[/color][color=yellow] already defined. Ignoring[/color][color=orange] %s[/color]" % [key_d.values()[0]])
				else:
					clean_dic["port"] = key_d.values()[0]
			"game-policy":
				if clean_dic.has("game-policy"):
					print_rich("[color=red]> Error![/color] [color=yellow] In cmd args. [/color][color=green]game-policy[/color][color=yellow] already defined. Ignoring[/color][color=orange] %s[/color]" % [key_d.values()[0]])
				else:
					clean_dic["game-policy"] = key_d.values()[0]
			"protocol":
				if clean_dic.has("protocol"):
					print_rich("[color=red]> Error![/color] [color=yellow] In cmd args. [/color][color=green]protocol[/color][color=yellow] already defined. Ignoring[/color][color=orange] %s[/color]" % [key_d.values()[0]])
				else:
					clean_dic["protocol"] = key_d.values()[0]
			"game-properties":
				if clean_dic.has("game-properties"):
					print_rich("[color=red]> Error![/color] [color=yellow] In cmd args. [/color][color=green]game-properties[/color][color=yellow] already defined. Ignoring[/color][color=orange] %s[/color]" % [key_d.values()[0]])
				else:
					clean_dic["game-properties"] = key_d.values()[0]
	if clean_dic.has("port") and clean_dic["port"].size() == 1 and clean_dic["port"][0].to_int():
		print_rich("[color=yellow]> Argument \"[/color][color=green]port[/color][color=yellow]\" is correct. Using [/color][color=orange]", str(clean_dic["port"][0]),"[/color]")
	else:
		if clean_dic.has("port"):
			print_rich("[color=red]> Error![/color] [color=yellow] Argument \"[/color][color=green]port[/color][color=yellow]\" is not correct or not defined. Using default [/color][color=orange]", str(LISTEN_PORT),"[/color]")
			clean_dic.erase("port")
	if clean_dic.has("log") and clean_dic["log"]:
		print_rich("[color=yellow]> Argument \"[/color][color=green]log[/color][color=yellow]\" is correct. Using [/color][color=orange]logfile[/color]")
	else:
		if clean_dic.has("log"):
			print_rich("[color=red]> Error![/color] [color=yellow] Argument \"[/color][color=green]log[/color][color=yellow]\" is not correct or not defined. Using default [/color][color=orange]", str(USE_LOGFILES),"[/color]")
			clean_dic.erase("log")
	if clean_dic.has("game-policy") and ("accept" in clean_dic["game-policy"][0] or "reject" in clean_dic["game-policy"][0]) and clean_dic["game-policy"].size()>1:
		print_rich("[color=yellow]> Argument \"[/color][color=green]game-policy[/color][color=yellow]\" is correct. Using [/color][color=orange]"+str(clean_dic["game-policy"])+"[/color]")
	else:
		if clean_dic.has("game-policy"):
			print_rich("[color=red]> Error![/color] [color=yellow] Argument \"[/color][color=green]game-policy[/color][color=yellow]\" is not correct or not defined. Using default [/color][color=orange]accept [/color][color=green]all[/color][color=yellow], [/color][color=orange]reject [/color][color=green]none[/color]")
			clean_dic.erase("game-policy")
	if clean_dic.has("protocol") and clean_dic["protocol"].size()>0:
		print_rich("[color=yellow]> Argument \"[/color][color=green]protocol[/color][color=yellow]\" is correct. Using [/color][color=orange]"+str(clean_dic["protocol"])+"[/color]")
	else:
		if clean_dic.has("protocol"):
			print_rich("[color=red]> Error![/color] [color=yellow] Argument \"[/color][color=green]protocol[/color][color=yellow]\" is not correct or not defined. Using default [/color][color=orange]",GAME_POLICY_PROTOCOL,"[/color]")
			clean_dic.erase("protocol")
	if clean_dic.has("game-properties") and clean_dic["game-properties"].size()>0:
		print_rich("[color=yellow]> Argument \"[/color][color=green]game-properties[/color][color=yellow]\" is correct. Using [/color][color=orange]"+str(clean_dic["game-properties"])+"[/color]")
	else:
		if clean_dic.has("game-properties"):
			print_rich("[color=red]> Error![/color] [color=yellow] Argument \"[/color][color=green]game-properties[/color][color=yellow]\" is not correct or not defined. Using default [/color][color=orange]accept [/color][color=green]any property[/color]")
			clean_dic.erase("game-properties")
	return clean_dic

func print_server_config():
	print_rich("\n [color=yellow]> Server config: [/color]\n")
	if USE_LOGFILES:
		print_rich("[color=yellow]> Logfile:[/color] [color=green]",str(USE_LOGFILES),"[/color]")
	else:
		print_rich("[color=yellow]> Logfile:[/color] [color=red]",str(USE_LOGFILES),"[/color]")
	print_rich("[color=yellow]> Gdmaster Listen [/color] [color=green]port: [/color] [color=orange]",str(LISTEN_PORT),"[/color]")
	print_rich("[color=yellow]> Game policy [/color] [color=green]ACCEPT: [/color] [color=orange]",str(GAME_POLICY_NAME),"[/color]")
	print_rich("[color=yellow]> Game policy [/color] [color=green]REJECT: [/color] [color=orange]",str(GAME_POLICY_NAME_REJECT),"[/color]")
	print_rich("[color=yellow]> Game policy [/color] [color=green]protocol: [/color] [color=orange]",str(GAME_POLICY_PROTOCOL),"[/color]")
	print_rich("[color=yellow]> Game custom [/color] [color=green]properties: [/color] [color=orange]",str(GAME_CUSTOM_PROPERTIES),"[/color]")
	logging.save_to_file(str("\n > Server config: \n"))
	logging.save_to_file(str("> Logfile: ",str(USE_LOGFILES)))
	logging.save_to_file(str("> Gdmaster Listen port: ",str(LISTEN_PORT)))
	logging.save_to_file(str("> Game policy ACCEPT: ",str(GAME_POLICY_NAME)))
	logging.save_to_file(str("> Game policy REJECT: ",str(GAME_POLICY_NAME_REJECT)))
	logging.save_to_file(str("> Game policy protocol: ",str(GAME_POLICY_PROTOCOL)))
	logging.save_to_file(str("> Game custom properties: ",str(GAME_CUSTOM_PROPERTIES)))
	pass

func apply_cmd_args(cmd_arg_dic:Dictionary):
	var keys = cmd_arg_dic.keys()
	for key in keys:
		match key:
			"log":
				USE_LOGFILES = true
			"port":
				if cmd_arg_dic[key][0].to_int() or null:
					LISTEN_PORT = cmd_arg_dic[key][0].to_int()
			"game-policy":
				var game_accept_type = cmd_arg_dic[key][0]
				match game_accept_type:
					"accept":
						GAME_POLICY_NAME = cmd_arg_dic[key].slice(1)
					"reject":
						GAME_POLICY_NAME_REJECT = cmd_arg_dic[key].slice(1)
			"protocol":
				GAME_POLICY_PROTOCOL = cmd_arg_dic[key]
			"game-properties":
				GAME_CUSTOM_PROPERTIES = cmd_arg_dic[key]
	pass

func poll_server():
	while server_is_listening:
		server_udp.poll() # Important!
		# Get new connection from clients (servers)
		if server_udp.is_connection_available():
			var peer: PacketPeerUDP = server_udp.take_connection()
			var packet = peer.get_packet()
			add_peer(peer)
			# Parse the packet
			parse_gdmaster_reply(packet,peer)
		for key in peers:
			var p:PacketPeerUDP = peers[key]
			if p.get_available_packet_count() > 0:
				var bytes = p.get_packet()
				# Parse the packet
				parse_gdmaster_reply(bytes, p)
	pass

func _process(_delta):
		pass 

func parse_gdmaster_reply(byte_array:PackedByteArray, peer:PacketPeerUDP):
	var len_arr = byte_array.size()
	if len_arr >=5 and byte_array[0]==255 and byte_array[1]==255 and byte_array[2]==255 and byte_array[3]==255:
		var getinfo_string = clean_up_bytes(byte_array).slice(0,7).get_string_from_utf8()
		var server_ip = peer.get_packet_ip()
		var server_port = str(peer.get_packet_port())
		var clean_bytes = clean_up_bytes(byte_array)
		if not validate_headers(byte_array):
			print_rich("[color=orange]> WARNING[/color][color=yellow]: [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow] ---> %s[/color]" % [server_ip, server_port, "Rejecting packet : Header is not valid!"])
			logging.save_to_file("> WARNING: %s:%s ---> %s" % [server_ip, server_port, "Rejecting packet : Header is not valid!"])
			remove_peer(peer)	
			return
		match getinfo_string:
			"heartbe":
				# Parse heartbeat
				## DPMASTER RESPONSE
				## * 2024-05-17 17:22:08 FLE Daylight Time
				## > New packet received from 172.44.32.1:57867: "\xFF\xFF\xFF\xFFheartbeat DarkPlaces\x0A" (25 bytes)
				## > 172.44.32.1:57867 ---> heartbeat (DarkPlaces)
				## > 172.44.32.1:57867 <--- getinfo with challenge "Oa{M[?OI#p!"
				var heartbeat_string = clean_bytes.get_string_from_utf8().strip_escapes()
				print_rich("[color=yellow]> New packet from [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow]: [/color][color=cyan]%s[/color][color=yellow] ([/color][color=orange]%s[/color][color=yellow] bytes[/color])" % [server_ip, server_port, heartbeat_string, byte_array.size()])
				print_rich("[color=yellow]> [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow] ---> %s[/color]" % [server_ip, server_port, heartbeat_string])
				logging.save_to_file("> New packet from %s:%s: %s (%s bytes)" % [server_ip, server_port, heartbeat_string, byte_array.size()])
				logging.save_to_file("> %s:%s ---> %s" % [server_ip, server_port, heartbeat_string])
				if validate_heartbeat(byte_array):
					send_getinfo(peer)
				else:
					print_rich("[color=orange]> WARNING[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow] ---> %s[/color]" % [server_ip, server_port, "Rejecting heartbeat : It is not valid!"])
					logging.save_to_file("> WARNING: %s:%s ---> %s" % [server_ip, server_port, "Rejecting heartbeat : It is not valid!"])
					remove_peer(peer)
			"infoRes":
				# Parse infoResponse
				## DPMASTER RESPONSE
				## * 2024-05-17 17:12:28 FLE Daylight Time
				## > New packet received from 172.44.32.1:57867: "\xFF\xFF\xFF\xFFinfoResponse\x0A\\gamename\\RoboFlex\\sv_maxclients\\8\\clients\\1\\protocol\\4522\\challenge\\>e)+G$oMg\\greco\\yes" (105 bytes)
				## > 172.44.32.1:57867 ---> infoResponse
				## * 2024-05-18 13:45:03 FLE Daylight Time
				## > New packet received from 172.44.32.1:53443: "\xFF\xFF\xFF\xFFinfoResponse\x0A\\gamename\\RoboFlex\\sv_maxclients\\8\\clients\\1\\challenge\\HlD#h:{<\\greco\\ye\\host\\sum_host\\port\\sum_port" (117 bytes)
				## > 172.44.32.1:53443 ---> infoResponse
				## > WARNING: invalid infoResponse from 172.44.32.1:53443 (no protocol value)
				var inforesponse_string = clean_bytes.get_string_from_utf8().strip_escapes()
				print_rich("[color=yellow]> New packet from [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow]: [/color][color=cyan]%s[/color][color=yellow] ([/color][color=orange]%s[/color][color=yellow] bytes[/color])" % [server_ip, server_port, inforesponse_string, byte_array.size()])
				print_rich("[color=yellow]> [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow] ---> %s[/color]" % [server_ip, server_port, "infoResponse"])
				logging.save_to_file("> New packet from %s:%s: %s (%s bytes)" % [server_ip, server_port, inforesponse_string, byte_array.size()])
				logging.save_to_file("> %s:%s ---> %s" % [server_ip, server_port, "infoResponse"])
				var arr = inforesponse_string.split("\\")
				arr.remove_at(0)
				var is_inforesponse_valid = arr.size() % 2 == 0 # check if valid number of key/value pairs
				if not is_inforesponse_valid:
					print_rich("[color=orange]> WARNING[/color][color=yellow]: [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow] ---> %s[/color]" % [server_ip, server_port, "Rejecting infoResponse : custom properties are not valid. Key/value pair count odd."])
					logging.save_to_file("> WARNING: %s:%s ---> %s" % [server_ip, server_port, "Rejecting infoResponse : custom properties are not valid. Key/value pair count odd."])
					remove_peer(peer)
					return
				var prop_dic = {}
				prop_dic.host = server_ip
				prop_dic.port = server_port
				var challenge = ""
				var i := 0
				var iteration_len = 2
				var end := arr.size()
				while (i < end):
					var arr_slice = arr.slice(i,i+iteration_len)
					var key = arr_slice[0].trim_prefix(" ").trim_suffix(" ")
					var val = arr_slice[1].trim_prefix(" ").trim_suffix(" ")
					match key:
						"port","public":
							prop_dic[key]=val.to_int()
						"challenge":
							challenge = val
							prop_dic[key]=val
						_:
							prop_dic[key]=val	
					i += iteration_len
				# If infoResponse has illegal property - reject it
				if prop_dic.has("time") or prop_dic.has("available"):
					print_rich("[color=orange]> WARNING[/color][color=yellow]: [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow] ---> %s[/color]" % [server_ip, server_port, "Rejecting infoResponse : custom game properties cannot contain \"time\" or \"available\" keys"])
					logging.save_to_file("> WARNING: %s:%s ---> %s" % [server_ip, server_port, "Rejecting infoResponse : custom game properties cannot contain \"time\" or \"available\" keys"])
					remove_peer(peer)
					return
				prop_dic.time = Time.get_unix_time_from_system()
				prop_dic.available = true
				var is_challenge_valid = validate_challenge(challenge,server_ip,peer.get_packet_port())
				var clients:int = prop_dic["clients"].to_int()
				var max_clients:int = prop_dic["sv_maxclients"].to_int()
				# If infoResponse has more players than max players or max players == 0 - reject it
				if clients > max_clients and max_clients != 0:
					print_rich("[color=orange]> WARNING[/color][color=yellow]: [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow] ---> %s[/color]" % [server_ip, server_port, "Rejecting infoResponse : clients > sv_maxclients or sv_maxclients = 0."])
					logging.save_to_file("> WARNING: %s:%s ---> %s" % [server_ip, server_port, "Rejecting infoResponse : clients > sv_maxclients / sv_maxclients = 0."])
					remove_peer(peer)
					return
				var is_prop_dic_valid = validate_inforesponse_props(prop_dic)
				if is_challenge_valid:
					if is_prop_dic_valid:
						# Check host property
						if server_ip != prop_dic.host:
							var result = ipv4_regex.search(prop_dic.host)
							if not result:
								
								var resolved = IP.resolve_hostname(prop_dic.host,IP.TYPE_IPV4)
								if resolved != "":
									prop_dic.host = resolved
								else:
									prop_dic.host = server_ip
						update_server_list(prop_dic)
						remove_peer(peer)
					else:
						print_rich("[color=orange]> WARNING[/color][color=yellow]: Rejecting packet packet from [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow] [/color]" % [server_ip, server_port])
						logging.save_to_file("> WARNING: Rejecting packet packet from %s:%s" % [server_ip, server_port])
						remove_peer(peer)
				else:
					remove_challenge_from_list(prop_dic.challenge,server_ip,peer.get_packet_port())
					print_rich("[color=red]> Error![/color] [color=yellow] Challenge is not valid! Rejecting packet from [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow][/color]" % [server_ip,server_port] )
					logging.save_to_file("> Error! Challenge is not valid! Rejecting packet from %s:%s" % [server_ip,server_port] )
					remove_peer(peer)
			"getserv":
				# Send getserversResponse
				## DPMASTER RESPONSE
				## * 2024-05-17 17:15:57 FLE Daylight Time
				## > New packet received from 172.44.32.1:57867: "\xFF\xFF\xFF\xFFgetservers RoboFlex 4522 empty full" (39 bytes)
				## > 172.44.32.1:57867 ---> getservers (RoboFlex, 4522)
				## - Comparing server: IP:"172.44.32.1:57867", p:4522, g:"RoboFlex"
				## - Sending server 172.44.32.1:57867
				## > 172.44.32.1:57867 <--- getserversResponse (1 servers)
				var getservers_string = clean_bytes.get_string_from_utf8().strip_escapes()
				print_rich("[color=yellow]> New packet from [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow]: [/color][color=orange]%s[/color][color=yellow] ([/color][color=orange]%s[/color][color=yellow] bytes[/color])" % [server_ip, server_port, getservers_string, byte_array.size()])
				print_rich("[color=yellow]> [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow] ---> %s[/color]" % [server_ip, server_port, getservers_string])
				logging.save_to_file("> New packet from %s:%s: %s (%s bytes)" % [server_ip, server_port, getservers_string, byte_array.size()])
				logging.save_to_file("> %s:%s ---> %s" % [server_ip, server_port, getservers_string])
				var serv_proprs:Dictionary = get_props_from_get_servers(getservers_string)
				var is_header_valid = validate_getservers_header(byte_array)
				if not is_header_valid:
					print_rich("[color=red]> Error![/color] [color=yellow] Getserver header is not valid! Rejecting packet packet from [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow][/color]" % [server_ip, server_port])
					logging.save_to_file("> Error! Getserver header is not valid! Rejecting packet packet from %s:%s" % [server_ip, server_port])
				var is_props_valid = validate_getservers_props(serv_proprs)
				if is_props_valid and is_header_valid: 
					send_getserversResponse(peer,byte_array)
				else:
					print_rich("[color=red]> Error![/color] [color=yellow] Game policy and/or protocol is not valid! Rejecting packet packet from [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow][/color]" % [server_ip, server_port])
					logging.save_to_file("> Error! Game policy and/or protocol is not valid! Rejecting packet packet from %s:%s" % [server_ip, server_port])
				remove_peer(peer)
			_:
				print_rich("[color=orange]> WARNING[/color][color=yellow]: Makes no sense, invalid packet from [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow]: (%s bytes)[/color]" % [server_ip, server_port,  byte_array.size()])
				logging.save_to_file("> WARNING: Makes no sense, invalid packet from %s:%s: (%s bytes)" % [server_ip, server_port,  byte_array.size()])
				remove_peer(peer)
	pass

func send_getinfo(peer:PacketPeerUDP):
	# "\xFF\xFF\xFF\xFFgetinfo A_ch4Lleng3"
	var server_ip = peer.get_packet_ip()
	var server_port = peer.get_packet_port()
	var packet_array : PackedByteArray
	var challenge = build_challenge()
	add_challenge_to_list(challenge,server_ip,server_port)
	var sent_string = "getinfo " + challenge
	packet_array = add_fluff_bytes(sent_string.to_utf8_buffer())
	var error = peer.put_packet(packet_array)
	if error != OK:
		print_rich("[color=red]> Error![/color] [color=yellow] send_getinfo: [/color][color=orange]", error_string(error) ,"[/color]")
		logging.save_to_file(str("> Error send_getinfo: ", error_string(error) ))
	else:
		print_rich("[color=yellow]> [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow] <--- getinfo with challenge \"[/color][color=cyan]%s[/color][color=yellow]\" ([/color][color=orange]%s[/color][color=yellow] bytes)[/color]" % [server_ip, server_port, challenge, packet_array.size()])
		logging.save_to_file("> %s:%s <--- getinfo with challenge \"%s\" (%s bytes)" % [server_ip, server_port, challenge, packet_array.size()])
	remove_peer(peer)
	pass

func send_getserversResponse(peer:PacketPeerUDP, bytes:PackedByteArray):
	#"\xFF\xFF\xFF\xFFgetservers Nexuiz 3 empty full gametype=dm public=1"          (DP running Nexuiz)
	# "\xFF\xFF\xFF\xFFgetserversResponse\\[...]\\EOT\0\0\0"
	var server_ip = peer.get_packet_ip()
	var server_port = peer.get_packet_port()
	var string_bytes = clean_up_bytes(bytes).get_string_from_utf8().strip_escapes().split(" ")
	if not string_bytes[0] == "getservers":
		print_rich("[color=red]> Error![/color] [color=yellow] send_getserversResponse: Invalid request: [color=orange]%s[/color]" % string_bytes[0])
		logging.save_to_file(str("> Error send_getserversResponse: Invalid request: %s" % string_bytes[0]))
		print_rich("[color=red]> Error![/color] [color=yellow] Rejecting packet packet from [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow][/color]" % [server_ip, server_port])
		logging.save_to_file("> Error! Rejecting packet packet from %s:%s" % [server_ip, server_port])
		return
	string_bytes=string_bytes.slice(1)
	if string_bytes.size() < 2:
		print_rich("[color=red]> Error![/color] [color=yellow] send_getserversResponse: Missing one or more getserver parameters: [color=orange]gamename protocol [/color]")
		logging.save_to_file(str("> Error send_getserversResponse: Missing one or more getserver parameters: gamename protocol"))
		print_rich("[color=red]> Error![/color] [color=yellow] Rejecting packet packet from [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow][/color]" % [server_ip, server_port])
		logging.save_to_file("> Error! Rejecting packet packet from %s:%s" % [server_ip, server_port])
		return
	var game_name = string_bytes[0].trim_prefix(" ").trim_suffix(" ")
	var game_protocol = string_bytes[1].trim_prefix(" ").trim_suffix(" ")
	if game_name == "" or game_protocol == "":
		print_rich("[color=red]> Error![/color] [color=yellow] send_getserversResponse: One or more getserver parameters are empty: [color=orange]gamename protocol [/color]")
		logging.save_to_file(str("> Error send_getserversResponse: One or more getserver parameters are empty: gamename protocol"))
		print_rich("[color=red]> Error![/color] [color=yellow] Rejecting packet packet from [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow][/color]" % [server_ip, server_port])
		logging.save_to_file("> Error! Rejecting packet packet from %s:%s" % [server_ip, server_port])
		return
	var other_filters = string_bytes.slice(2)
	var empty_servers = other_filters.has("empty")
	var full_servers = other_filters.has("full")
	var custom_props = {}
	for i in other_filters:
		if "=" in i:
			var arr = i.split("=")
			var key = arr[0].trim_prefix(" ").trim_suffix(" ")
			var val = arr[1].trim_prefix(" ").trim_suffix(" ")
			custom_props[key]=val
	var serv_arr_available = filter_servers(game_name,game_protocol,custom_props,empty_servers,full_servers)
	var index := 0
	var end := serv_arr_available.size()
	while (index < end):
		var addres_slice = []
		for i in range(index, min(index + MAX_SERVER_RETURN_ARRAY_SIZE, serv_arr_available.size())):
			addres_slice.append(serv_arr_available[i])
		#do stuff here
		index += MAX_SERVER_RETURN_ARRAY_SIZE
		var packet_array : PackedByteArray
		var sent_string = "getserversResponse"
		packet_array = add_fluff_bytes(sent_string.to_utf8_buffer())
		if index < end:
			addres_slice = format_servers_bytes(addres_slice)
		else:
			addres_slice = format_servers_bytes(addres_slice,true)
		packet_array.append_array(addres_slice)
		var error = peer.put_packet(packet_array)
		if error != OK:
			print_rich("[color=red]> Error![/color] [color=yellow] send_getserversResponse: [/color][color=orange]", error_string(error) ,"[/color]")
			logging.save_to_file(str("> Error send_getserversResponse: ", error_string(error) ))
		else:
			print_rich("[color=yellow]> [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow] <--- getserversResponse ( [/color][color=orange]%s[/color][color=yellow] filtered) ( [/color][color=orange]%s[/color][color=yellow] total) servers ([/color][color=orange]%s[/color][color=yellow] bytes)[/color]" % [server_ip, server_port,serv_arr_available.size(), server_ip_list.size(),packet_array.size()])
			logging.save_to_file("> %s:%s <--- getserversResponse ( %s filtered) ( %s total) servers (%s bytes)" % [server_ip, server_port,serv_arr_available.size(), server_ip_list.size(),packet_array.size()])
	if end ==0 and index==0:
		var packet_array : PackedByteArray
		var sent_string = "getserversResponse"
		var addres_slice = format_servers_bytes([],true)
		packet_array = add_fluff_bytes(sent_string.to_utf8_buffer())
		packet_array.append_array(addres_slice)
		var error = peer.put_packet(packet_array)
		if error != OK:
			print_rich("[color=red]> Error![/color] [color=yellow] send_getserversResponse: [/color][color=orange]", error_string(error) ,"[/color]")
			logging.save_to_file(str("> Error send_getserversResponse: ", error_string(error) ))
		else:
			print_rich("[color=yellow]> [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow] <--- getserversResponse ( [/color][color=orange]%s[/color][color=yellow] filtered) ( [/color][color=orange]%s[/color][color=yellow] total) servers ([/color][color=orange]%s[/color][color=yellow] bytes)[/color]" % [server_ip, server_port, serv_arr_available.size(), server_ip_list.size(),packet_array.size()])
			logging.save_to_file("> %s:%s <--- getserversResponse ( %s filtered) ( %s total) servers (%s bytes)" % [server_ip, server_port, serv_arr_available.size(), server_ip_list.size(),packet_array.size()])
	pass

# -----------------------------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------------------------
func merge_loaded_servers(loaded_servers):
	var l_hash = {}
	var e_hash = {}
	var i = 0
	var additional_server =[]
	for l_s in loaded_servers:
		var str_s = l_s.host +":"+ l_s.port
		var k = str_s.hash()
		var v = i
		l_hash[k] = v
		i+=1
	i=0
	for e_s in server_ip_list:
		var str_s = e_s.host +":"+ e_s.port
		var k = str_s.hash()
		var v = i
		e_hash[k] = v
		i+=1
	var merged_servers = server_ip_list
	i=0
	for l_h in l_hash:
		if e_hash.has(l_h):
			# check time diff
			var l_time = loaded_servers[l_hash[l_h]].time
			var e_time = server_ip_list[e_hash[l_h]].time
			if e_time < l_time:
				# keep loaded server
				server_ip_list[e_hash[l_h]] = loaded_servers[l_hash[l_h]]
		else:
			# add loaded sever
			merged_servers.append(loaded_servers[l_hash[l_h]])
			additional_server.append(loaded_servers[l_hash[l_h]])
	server_ip_list = merged_servers
	for a_server in additional_server:
		print_rich("[color=cyan]> Adding aditional server ---> [/color][color=green]%s[/color][color=cyan]:[/color][color=green]%s[/color]" % [a_server.host,a_server.port] )
		logging.save_to_file("> Adding aditional server ---> %s:%s" % [a_server.host,a_server.port] )
	if additional_server.size()>0:
		print_rich("[color=yellow]> Added ([/color][color=green]%s[/color][color=yellow]) servers[/color]" % [additional_server.size()] )
		logging.save_to_file("> Added (%s) servers" % [additional_server.size()] )	
	clean_up_serverlist()
	pass

func save_server_list_to_json(servers, filename=""): 
	var format_date = get_date_string_for_files()
	var exe_path:String = OS.get_executable_path()
	var exe_file:String = exe_path.get_file()
	var exe_folder:String = exe_path.replace(exe_file,"")
	var file
	if not filename == "":
		file = FileAccess.open(exe_folder+filename+".json", FileAccess.WRITE)
	else:
		file = FileAccess.open(exe_folder+"Server_list_"+format_date+".json", FileAccess.WRITE)
	var json_string: String = JSON.stringify(servers,"\t") 
	file.store_string(json_string)
	file.close()
	return file.get_path()
	
func load_server_list_from_json(filepath):
	var exe_path:String = OS.get_executable_path()
	var exe_file:String = exe_path.get_file()
	var exe_folder:String = exe_path.replace(exe_file,"")
	var file = FileAccess.open(exe_folder+filepath, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		var json_obj = JSON.parse_string(content)
		return json_obj
	return null

func get_date_string_for_files(for_filepath:bool=true)->String:
	var current_time = Time.get_unix_time_from_system()
	var d = Time.get_datetime_dict_from_unix_time(current_time)
	var year = str(d.year)
	var month = str(d.month)
	var day = str(d.day)
	var hour = str(d.hour)
	var minute = str(d.minute)
	var second = str(d.second)
	if month.length() < 2:
		month = "0"+month
	if hour.length() < 2:
		hour = "0"+hour
	if day.length() < 2:
		day = "0"+day
	if minute.length() < 2:
		minute = "0"+minute
	if second.length() < 2:
		second = "0"+second
	var format_date 
	if for_filepath:
		format_date =  year + "." + month + "." + day + "_" + hour + "."+ minute + "." + second
	else:
		format_date =  year + "." + month + "." + day + " " + hour + ":"+ minute + ":" + second + " "
	return format_date
	
func add_peer(peer:PacketPeerUDP):
	var n_ip = peer.get_packet_ip()
	var n_port = str(peer.get_packet_port())
	var str_s = n_ip + ":" + n_port
	var str_h = str_s.hash()
	peers[str_h]=peer
	print_rich("[color=yellow]> Peer [/color][color=green](+)(+)(+)[/color][color=yellow] ---> ([/color][color=orange]%s[/color][color=yellow]): Peer count ([/color][color=orange]%s[/color][color=yellow])[/color]" % [str_h,peers.size()])
	logging.save_to_file("> Peer (+)(+)(+) ---> (%s): Peer count (%s)" % [str_h,peers.size()])
	pass
	
func remove_peer(peer:PacketPeerUDP):
	var n_ip = peer.get_packet_ip()
	var n_port = str(peer.get_packet_port())
	var str_s = n_ip + ":" + n_port
	var str_h = str_s.hash()
	if peers.has(str_h):
		peers[str_h].close()
		peers.erase(str_h)
	print_rich("[color=yellow]> Peer [/color][color=red](-)(-)(-)[/color][color=yellow] ---> ([/color][color=orange]%s[/color][color=yellow]): Peer count ([/color][color=orange]%s[/color][color=yellow])[/color]" % [str_h,peers.size()])
	logging.save_to_file("> Peer (-)(-)(-) ---> (%s): Peer count (%s)" % [str_h,peers.size()])

func build_challenge() -> String:
	var challenge = ""
	var length = CHALLENGE_MIN_LENGTH - 1
	# Add a random number of characters
	length += randi() % (CHALLENGE_MAX_LENGTH - CHALLENGE_MIN_LENGTH + 1)
	for i in range(length):
		var c = ''
		while true:
			c = 33 + randi() % (126 - 33 + 1)
			var char_s = String.chr(c)
			if char_s != '\\' and char_s != ';' and char_s != '"' and char_s != '%' and char_s != '/':
				break
		challenge += String.chr(c)
	return challenge

func add_challenge_to_list(challenge:String,peer_ip:String,peer_port:int):
	var current_time = Time.get_unix_time_from_system()
	var new_challenge_item = [peer_ip,peer_port,challenge,current_time]
	var challenge_found = false
	for item in challenges:
		if item[0] == new_challenge_item[0] and item[1] == new_challenge_item[1] and item[2] == new_challenge_item[2]:
			challenge_found = true
			return
	if not challenge_found:
		#add challenge
		challenges.append(new_challenge_item)
	pass

func remove_challenge_from_list(challenge:String,peer_ip:String,peer_port:int):
	var new_challenge_item = [peer_ip,peer_port,challenge]
	var i = 0
	var challenge_found = false
	for item in challenges:
		if item[0] == new_challenge_item[0] and item[1] == new_challenge_item[1] and item[2] == new_challenge_item[2]:
			challenge_found = true
			return
		i+=1
	if challenge_found:
		challenges.remove_at(i)
	pass

func validate_challenge(challenge:String,peer_ip:String,peer_port:int):
	var current_time = Time.get_unix_time_from_system()
	var new_challenge_item = [peer_ip,peer_port,challenge,current_time]
	var valid_challenges = []
	for item in challenges:
		if current_time - item[3] < TIME_TO_LIVE_CHALLENGE:
			valid_challenges.append(item)
	challenges = valid_challenges
	for item in valid_challenges:
		if item[0] == new_challenge_item[0] and item[1] == new_challenge_item[1] and item[2] == new_challenge_item[2] and current_time - item[3] < TIME_TO_LIVE_CHALLENGE:
			return true
	return false

func validate_inforesponse_props(prop_dic:Dictionary) ->bool:
	var is_valid = true
	var custom_game_props = {}
	# Check if one must have prop is not in the dic then break.
	for gp in GAME_PROPERTIES:
		if not prop_dic.has(gp):
			is_valid = false
			print_rich("[color=red]> Error![/color] [color=yellow] Missing one or more must have properties! (%s)[/color]" % gp)
			logging.save_to_file("> Error, missing one or more must have properties! (%s)" % gp)	
			break	
	# Filter out custom props
	for p in prop_dic:
		if not  GAME_PROPERTIES.has(p):
			custom_game_props[p] = prop_dic[p]
	if GAME_CUSTOM_PROPERTIES.size()>0:
		for pp in GAME_CUSTOM_PROPERTIES:
			if not custom_game_props.has(pp):
				is_valid=false
				print_rich("[color=red]> Error![/color] [color=yellow] Missing one or more custom properties![/color]")
				logging.save_to_file("> Error, missing one or more custom properties!")
				break
	if GAME_POLICY_NAME.size()>0:
		if not GAME_POLICY_NAME.has(prop_dic["gamename"]):
			is_valid=false
			print_rich("[color=red]> Error![/color] [color=yellow] Game policy does not match ACCEPTED policies[/color]")
			logging.save_to_file("> Error, Game policy does not match ACCEPTED policies")
	if GAME_POLICY_NAME_REJECT.size()>0:
		if GAME_POLICY_NAME_REJECT.has(prop_dic["gamename"]):
			is_valid=false
			print_rich("[color=red]> Error![/color] [color=yellow] Game policy is not allowed and matches REJECTED policies[/color]")
			logging.save_to_file("> Error, Game policy is not allowed and matches REJECTED policies")
	if GAME_POLICY_PROTOCOL.size() >0:
		if not GAME_POLICY_PROTOCOL.has(prop_dic["protocol"]):
			is_valid=false
			print_rich("[color=red]> Error![/color] [color=yellow] Game protocol does not match ACCEPTED protocols[/color]")
			logging.save_to_file("> Error, Game protocol does not match ACCEPTED protocols")
	return is_valid

func get_props_from_get_servers(get_servers_string:String)-> Dictionary:
	var arr = get_servers_string.split(" ")
	var dic = {}
	var custom_props = []
	if arr[0] == "getservers" and arr.size() > 2:
		# String is valid so far
		if arr.has("empty"):
			dic["empty"]=true
		else:
			dic["empty"]=false
		if arr.has("full"):
			dic["full"]=true
		else:
			dic["full"]=false
		dic["gamename"] = arr[1].trim_prefix(" ").trim_suffix(" ")
		dic["protocol"] = arr[2].trim_prefix(" ").trim_suffix(" ")
		for p in arr:
			if "=" in p:
				custom_props.append(p)
		for c in custom_props:
			var k = c.split("=")[0].trim_prefix(" ").trim_suffix(" ")
			var v = c.split("=")[1].trim_prefix(" ").trim_suffix(" ")
			dic[k] = v
	return dic

func validate_getservers_props(prop_dic:Dictionary) ->bool:
	var is_valid = true
	var custom_game_props = {}
	# Filter out custom props
	for p in prop_dic:
		if not  GAME_PROPERTIES.has(p):
			custom_game_props[p] = prop_dic[p]
	if GAME_CUSTOM_PROPERTIES.size()>0:
		for pp in GAME_CUSTOM_PROPERTIES:
			if not custom_game_props.has(pp):
				is_valid=false
				print_rich("[color=red]> Error![/color] [color=yellow] Missing one or more custom properties![/color]")
				logging.save_to_file("> Error, missing one or more custom properties!")
				break
	if GAME_POLICY_NAME.size()>0:
		if prop_dic.has("gamename") and not GAME_POLICY_NAME.has(prop_dic["gamename"]):
			is_valid=false
			print_rich("[color=red]> Error![/color] [color=yellow] Game policy does not match ACCEPTED policies[/color]")
			logging.save_to_file("> Error, Game policy does not match ACCEPTED policies")
	if GAME_POLICY_NAME_REJECT.size()>0:
		if prop_dic.has("gamename") and GAME_POLICY_NAME_REJECT.has(prop_dic["gamename"]):
			is_valid=false
			print_rich("[color=red]> Error![/color] [color=yellow] Game policy is not allowed and matches REJECTED policies[/color]")
			logging.save_to_file("> Error, Game policy is not allowed and matches REJECTED policies")
	if GAME_POLICY_PROTOCOL.size() >0:
		if prop_dic.has("protocol") and not GAME_POLICY_PROTOCOL.has(prop_dic["protocol"]):
			is_valid=false
			print_rich("[color=red]> Error![/color] [color=yellow] Game protocol does not match ACCEPTED protocols[/color]")
			logging.save_to_file("> Error, Game protocol does not match ACCEPTED protocols")
	return is_valid

func validate_heartbeat(byte_array:PackedByteArray) ->bool:
	var is_valid = false
	if byte_array.size() ==25 and byte_array[0]==255 and byte_array[1]==255 and byte_array[2]==255 and byte_array[3]==255 and byte_array[24] == 10:
		var clean_bytes = clean_up_bytes(byte_array)
		var heartbeat_string = clean_bytes.get_string_from_utf8().strip_escapes()
		if heartbeat_string == "heartbeat DarkPlaces":
			is_valid=true
	return is_valid

func validate_getservers_header(byte_array:PackedByteArray) ->bool:
	var is_valid = false
	if byte_array.size() >13 and byte_array[0]==255 and byte_array[1]==255 and byte_array[2]==255 and byte_array[3]==255:
		var clean_bytes = clean_up_bytes(byte_array)
		var getservers_string = clean_bytes.get_string_from_utf8().strip_escapes().get_slice(" ",0)
		if getservers_string == "getservers":
			is_valid=true
	return is_valid

func validate_headers(byte_array:PackedByteArray) ->bool:
	var is_valid = false
	if byte_array.size() > 5 and byte_array[0]==255 and byte_array[1]==255 and byte_array[2]==255 and byte_array[3]==255:
		is_valid = true
	return is_valid
	
func format_servers_bytes(arr, add_fluff_end=false) -> PackedByteArray:
	var packet_array : PackedByteArray
	var fluff_end = [92, 69, 79, 84, 0, 0, 0]
	if !arr.size()>0:
		packet_array.append_array(fluff_end)
		return packet_array
	for server in arr:
		packet_array.append(92)
		var ip = server.host
		var port = server.port #.to_int()
		var ip_arr = ip.split(".")
		for e in ip_arr:
			packet_array.append(e.to_int())
		var b1 = port % 256 # Some kind of bs, but works
		var b2 = port / 256 # Some kind of bs, but works
		packet_array.append(b2)
		packet_array.append(b1)
	if add_fluff_end:
		packet_array.append_array(fluff_end)
	return packet_array

func get_available_servers() -> Array:
	var current_time = Time.get_unix_time_from_system()
	var available_servers = []
	for server in server_ip_list:
		if "available" in server and server["available"]:
			if current_time - server["time"] > TIME_TO_LIVE:
				server["available"] = false
			else:
				available_servers.append(server)
	return available_servers

func filter_servers(game_name:String, game_proto:String,custom_props:Dictionary, empty:bool = false, full:bool=false) -> Array:
	var current_time = Time.get_unix_time_from_system()
	var available_servers = []
	var filtered_all = []
	for server in server_ip_list:
		if "available" in server:
			if current_time - server["time"] > TIME_TO_LIVE:
				server["available"] = false
			else:
				available_servers.append(server)
	for server2:Dictionary in available_servers:
		var props_matched = true
		for prop in custom_props:
			var prop_val = custom_props[prop]
			match prop:
				"empty":
					pass
				"full":
					pass
				_:
					var val = server2.get(prop)
					if prop_val != val:
						props_matched = false
		if props_matched and server2["gamename"] == game_name and server2["protocol"] == game_proto:
			var clients:int = server2.get("clients").to_int()
			var max_clients:int = server2.get("sv_maxclients").to_int()
			if not empty and not full:
				if max_clients - clients > 0 and clients > 0:
					filtered_all.append(server2)
			elif empty and not full:
				if max_clients - clients > 0:
					filtered_all.append(server2)
			elif full and not empty:
				if max_clients == clients or clients > 0:
					filtered_all.append(server2)
			else:
				filtered_all.append(server2)
	return filtered_all

func update_server_list(new_server: Dictionary):
	var current_time = Time.get_unix_time_from_system()
	for server:Dictionary in server_ip_list:
		if server["host"] == new_server["host"] and server["port"] == new_server["port"]:
			server["time"] = current_time
			server["available"] = true
			if new_server["public"] == 0:
				server["available"] = false
			for k in new_server.keys():
				match k:
					"time","available":
						pass
					_:
						server[k] = new_server[k]
			print_rich("[color=yellow]> Updated existing server [/color][color=orange]%s[/color][color=yellow]:[/color][color=orange]%s[/color][color=yellow] <--- Servers ([/color][color=orange]%s[/color][color=yellow])[/color]" % [new_server.host,new_server.port,server_ip_list.size()] )
			logging.save_to_file("> Updated existing server %s:%s <--- Servers (%s)" % [new_server.host,new_server.port,server_ip_list.size()] )
			clean_up_serverlist()
			return
	if "public" in new_server:
		if new_server["public"] == 1:
			server_ip_list.append(new_server)
			print_rich("[color=yellow]> Added new server [/color][color=green]%s[/color][color=yellow]:[/color][color=green]%s[/color][color=yellow] <--- Servers ([/color][color=orange]%s[/color][color=yellow])[/color]" % [new_server.host,new_server.port,server_ip_list.size()] )
			logging.save_to_file("> Added new server %s:%s <--- Servers (%s)" % [new_server.host,new_server.port,server_ip_list.size()] )
	clean_up_serverlist()

func clean_up_serverlist():
	var current_time = Time.get_unix_time_from_system()	
	var removed_servers = []
	print_rich("[color=yellow]> Cleaning up serverlist. Servers ([/color][color=orange]%s[/color][color=yellow])[/color]" % [server_ip_list.size()] )
	logging.save_to_file("> Cleaning up serverlist. Servers (%s)" % [server_ip_list.size()] )
	for server in server_ip_list:
		if "available" in server and server["available"]:
			if current_time - server["time"] > TIME_TO_LIVE:
				server["available"] = false
		if "public" in server:
			if server["public"] == 0:
				server["available"] = false		
	var available_servers = []
	for server2 in server_ip_list:
			if server2["available"] == true:
				available_servers.append(server2)
			else:
				removed_servers.append(server2)	
	server_ip_list = available_servers
	for r_server in removed_servers:
		print_rich("[color=orange]> Removing unavailable server ---> [/color][color=green]%s[/color][color=orange]:[/color][color=green]%s[/color]" % [r_server.host,r_server.port] )
		logging.save_to_file("> Removing unavailable server ---> %s:%s" % [r_server.host,r_server.port] )
	if removed_servers.size()>0:
		print_rich("[color=yellow]> Cleaned up ([/color][color=orange]%s[/color][color=yellow]) servers[/color]" % [removed_servers.size()] )
		logging.save_to_file("> Cleaned up (%s) servers" % [removed_servers.size()] )	
	print_rich("[color=yellow]> Current server count: ([/color][color=orange]%s[/color][color=yellow])[/color]" % [server_ip_list.size()] )
	logging.save_to_file("> Current server count: (%s) servers" % [server_ip_list.size()] )	
	pass

func get_ip_port(ip_byte_array:PackedByteArray):
	# How to convert 2 bytes into an integer?
	# Short answer: Assuming unsigned bytes, multiply the first byte by 256 and add it to the second byte
	# least sig bit first here
	if ip_byte_array.size() == 6:
		if ip_byte_array[3] == 0 and ip_byte_array[4] == 0 and ip_byte_array[5] == 0: return null
		var ip: String = \
		str(ip_byte_array[0]) + "." \
		+ str(ip_byte_array[1]) + "." \
		+ str(ip_byte_array[2]) + "." \
		+ str(ip_byte_array[3]) + ":" \
		+ str((ip_byte_array[4]*256)+ip_byte_array[5])
		return ip
	else:
		return null

func add_fluff_bytes(byte_array:PackedByteArray):
	var packet_array : PackedByteArray
	packet_array.append(255)
	packet_array.append(255)
	packet_array.append(255)
	packet_array.append(255)
	packet_array.append_array(byte_array)
	return packet_array

func clean_up_bytes(byte_array:PackedByteArray, x_ammount:int =4) ->PackedByteArray:
	return byte_array.slice(x_ammount)
