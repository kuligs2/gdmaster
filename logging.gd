extends Node
class_name Logging


@export var logfile:String = "log.log"
@export var use_logfile:bool = true

func save_to_file(content):

	if use_logfile:
		var exe_path:String = OS.get_executable_path()
		var exe_file:String = exe_path.get_file()
		var exe_folder:String = exe_path.replace(exe_file,"")
		
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
		var format_date =  year + "." + month + "." + day + " " + hour + ":"+ minute + ":" + second + " "
		var old_content = load_from_file(exe_folder+logfile)
		#var file = FileAccess.open("user://"+logfile, FileAccess.WRITE)
		var file = FileAccess.open(exe_folder+logfile, FileAccess.WRITE)
		file.seek_end()
		file.store_string( old_content + "\n" + format_date + content)
		file.close()

func load_from_file(file_path):
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		return content
	else:
		return ""
